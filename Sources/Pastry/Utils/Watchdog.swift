import Foundation
import OSLog

// MARK: - 主线程看门狗
// 后台线程周期性 ping 主线程，超时无响应则自动 sample 进程并写堆栈到文件
final class MainThreadWatchdog {

    static let shared = MainThreadWatchdog()

    private let log = Logger(subsystem: "com.nekutai.pastry", category: "watchdog")
    private let pingInterval: TimeInterval = 2.0    // 每 2s 发一次 ping
    private let hangThreshold: TimeInterval = 5.0    // 5s 无响应视为卡死
    private let dumpDir: URL

    private var timer: DispatchSourceTimer?
    private var lastPong = Date.distantFuture
    private let lock = NSLock()

    private init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            fatalError("无法获取 Application Support 目录")
        }
        dumpDir = appSupport
            .appendingPathComponent("Pastry")
            .appendingPathComponent("HangReports")
        try? FileManager.default.createDirectory(at: dumpDir, withIntermediateDirectories: true)
    }

    func start() {
        guard timer == nil else { return }

        lastPong = Date()
        let queue = DispatchQueue(label: "com.nekutai.pastry.watchdog")

        timer = DispatchSource.makeTimerSource(queue: queue)
        timer?.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer?.setEventHandler { [weak self] in
            self?.tick()
        }
        timer?.resume()

        log.info("看门狗已启动 (interval: \(self.pingInterval)s, threshold: \(self.hangThreshold)s)")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - 私有

    /// 后台线程定时回调：ping 主线程，检查是否超时
    private func tick() {
        let pingTime = Date()

        // 发 ping 给主线程
        DispatchQueue.main.async { [weak self] in
            self?.lock.withLock {
                self?.lastPong = Date()
            }
        }

        // 延迟 threshold 后检查主线程是否响应
        let queue = DispatchQueue.global(qos: .utility)
        queue.asyncAfter(deadline: .now() + hangThreshold) { [weak self] in
            guard let self else { return }
            let lastResponse = self.lock.withLock { self.lastPong }
            if lastResponse < pingTime {
                self.sampleProcess(reason: "主线程 \(Int(self.hangThreshold))s 无响应")
            }
        }
    }

    /// 调用 /usr/bin/sample 采集进程堆栈，写入文件
    private func sampleProcess(reason: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeName = timestamp.replacingOccurrences(of: ":", with: "-")
        let filename = "hang_\(safeName).txt"
        let fileURL = dumpDir.appendingPathComponent(filename)

        let pid = ProcessInfo.processInfo.processIdentifier

        let task = Process()
        task.launchPath = "/usr/bin/sample"
        task.arguments = ["\(pid)", "1", "-file", fileURL.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            if FileManager.default.fileExists(atPath: fileURL.path) {
                log.error("⚠️ 看门狗：\(reason)，sample 已写入 \(fileURL.path, privacy: .public)")
            } else {
                log.error("⚠️ 看门狗：\(reason)，sample 命令执行失败")
            }
        } catch {
            log.error("看门狗 sample 启动失败: \(error.localizedDescription)")
        }
    }
}
