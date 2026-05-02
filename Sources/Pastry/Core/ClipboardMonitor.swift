import Cocoa
import Combine
import OSLog

// MARK: - 剪贴板监听器
// 核心策略：轮询 NSPasteboard.changeCount，检测变化后立即读取
final class ClipboardMonitor: ObservableObject {

    // MARK: 单例
    static let shared = ClipboardMonitor()

    // MARK: Published
    @Published private(set) var latestItem: ClipboardItem?
    @Published private(set) var isRunning = false

    // MARK: 回调
    var onNewItem: ((ClipboardItem) -> Void)?

    // MARK: 私有状态
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let pollInterval: TimeInterval = 0.5
    private let sensitiveThreshold = 4
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "monitor")

    // 防止同一内容重复触发
    private var lastDedupKey = ""

    /// 暂停/恢复监听
    private var suspendCount = 0
    var isSuspended: Bool { suspendCount > 0 }

    // MARK: - App 激活历史（解决截图来源误报 Finder 问题）
    /// 最近 5 秒内的前台 App 历史 —— 即使轮询瞬间前台是 Finder，
    /// 也能从历史中捞回真正复制时所在的 App
    private let appHistoryWindow: TimeInterval = 5.0   // 5s 窗口，覆盖截图软件异步写入
    private var recentApps: [(name: String, time: Date)] = []
    private var appObserver: NSObjectProtocol?

    /// 上一轮轮询时的前台 App —— 避免截图软件（不触发 didActivate）丢失来源
    private var previousFrontApp: String?

    func suspend() {
        suspendCount += 1
    }

    func resume() {
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        if suspendCount == 0 {
            lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    /// 清空剪贴板后同步计数器，避免监听器误检
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
        lastDedupKey = currentDedupKey
    }

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true

        lastChangeCount = NSPasteboard.general.changeCount
        lastDedupKey = currentDedupKey

        // 追踪前台 App 切换
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                      as? NSRunningApplication,
                  let name = app.localizedName
            else { return }
            let now = Date()
            self.recentApps.append((name, now))
            // 过期清理
            self.recentApps = self.recentApps.filter {
                now.timeIntervalSince($0.time) < self.appHistoryWindow
            }
        }

        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        log.info("剪贴板监听已启动 (interval: \(self.pollInterval)s)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let obs = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            appObserver = nil
        }
        isRunning = false
        log.info("剪贴板监听已停止")
    }

    // MARK: - 轮询

    private func poll() {
        guard !isSuspended else { return }

        let pb = NSPasteboard.general
        let currentChange = pb.changeCount

        // 每次轮询都缓存当前前台 App（无论是否检测到变化），
        // 这样 CleanShot X 等不触发 didActivate 的截图工具也能被捕获
        let currentFront = NSWorkspace.shared.frontmostApplication?.localizedName

        guard currentChange != lastChangeCount else {
            // 无变化时只更新缓存，不做其他事
            previousFrontApp = currentFront
            return
        }
        lastChangeCount = currentChange

        // 🔒 三层兜底：激活历史 → 上一轮前台 → 当前前台
        let capturedApp = bestGuessAppName(currentFront: currentFront)
        previousFrontApp = currentFront

        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) {
            [weak self] in
            self?.processChange(capturedApp: capturedApp)
        }
    }

    /// 三层兜底选择复制来源 App：
    ///   1. 激活历史中最近的非 Finder / 非系统 App
    ///   2. 上一轮轮询时的前台 App（捕获不激活自身的截图工具）
    ///   3. 当前前台 App
    private func bestGuessAppName(currentFront: String?) -> String? {
        let now = Date()
        recentApps = recentApps.filter { now.timeIntervalSince($0.time) < appHistoryWindow }

        // Tier 1: 激活历史中的非系统 App
        for entry in recentApps.reversed() {
            let name = entry.name
            if name == "Finder" || name == "loginwindow" { continue }
            return name
        }

        // Tier 2: 上一轮的前台 App（非 Finder）
        if let prev = previousFrontApp, prev != "Finder", prev != "loginwindow" {
            return prev
        }

        // Tier 3: 当前前台
        return currentFront
    }

    // MARK: - 处理剪贴板变化

    private func processChange(capturedApp: String?) {
        let dedup = currentDedupKey
        guard dedup != lastDedupKey else { return }
        let pb = NSPasteboard.general

        guard let types = pb.types, !types.isEmpty else { return }

        if let item = readImage(from: pb, appName: capturedApp)
            ?? readFileURLs(from: pb, appName: capturedApp)
            ?? readHTML(from: pb, appName: capturedApp)
            ?? readRTF(from: pb, appName: capturedApp)
            ?? readText(from: pb, appName: capturedApp) {

            if isSensitive(item) {
                log.notice("跳过敏感内容: \(item.content.prefix(20))")
                lastDedupKey = dedup
                return
            }

            lastDedupKey = dedup

            DispatchQueue.main.async {
                self.latestItem = item
                self.onNewItem?(item)
            }
        }
    }

    // MARK: - 各格式读取器

    private func readText(from pb: NSPasteboard, appName: String?) -> ClipboardItem? {
        guard let text = pb.string(forType: .string), !text.isEmpty else { return nil }
        return ClipboardItem(content: text, contentType: .text, appName: appName)
    }

    private func readRTF(from pb: NSPasteboard, appName: String?) -> ClipboardItem? {
        guard let data = pb.data(forType: .rtf),
              let attr = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil)
        else { return nil }
        return ClipboardItem(content: attr.string, contentType: .rtf, appName: appName)
    }

    private func readHTML(from pb: NSPasteboard, appName: String?) -> ClipboardItem? {
        guard let data = pb.data(forType: .html),
              let html = String(data: data, encoding: .utf8)
        else { return nil }
        if let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil) {
            return ClipboardItem(content: attr.string, contentType: .html, appName: appName)
        }
        return ClipboardItem(content: html, contentType: .html, appName: appName)
    }

    private func readImage(from pb: NSPasteboard, appName: String?) -> ClipboardItem? {
        guard let data = pb.data(forType: .tiff) ?? pb.data(forType: .png),
              let image = NSImage(data: data)
        else { return nil }
        guard let savedPath = ImageCacheManager.shared.save(image: image, data: data) else {
            log.error("图片缓存写入失败")
            return nil
        }
        return ClipboardItem(content: savedPath, contentType: .image, appName: appName)
    }

    private func readFileURLs(from pb: NSPasteboard, appName: String?) -> ClipboardItem? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty
        else { return nil }
        let paths = urls.map(\.path).joined(separator: "\n")
        return ClipboardItem(content: paths, contentType: .fileURL, appName: appName)
    }

    // MARK: - 辅助

    private var currentDedupKey: String {
        let pb = NSPasteboard.general
        let change = pb.changeCount
        let types = pb.types?.map(\.rawValue).joined() ?? ""
        return "\(change):\(types)"
    }

    private func isSensitive(_ item: ClipboardItem) -> Bool {
        guard item.contentType == .text else { return false }
        let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count < sensitiveThreshold else { return false }
        return trimmed.allSatisfy { $0.isNumber }
    }
}

// MARK: - 图片缓存管理器
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let cacheDir: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        cacheDir = appSupport
            .appendingPathComponent("ClipboardManager")
            .appendingPathComponent("ImageCache")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    func save(image: NSImage, data: Data) -> String? {
        let filename = "\(UUID().uuidString).png"
        let fileURL = cacheDir.appendingPathComponent(filename)
        let thumb = thumbnail(from: image, maxSize: NSSize(width: 256, height: 256))
        guard let thumbData = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: thumbData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return fileURL.path }
        do {
            try pngData.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }

    private func thumbnail(from image: NSImage, maxSize: NSSize) -> NSImage {
        let ratio = min(maxSize.width / max(image.size.width, 1),
                        maxSize.height / max(image.size.height, 1))
        let newSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}
