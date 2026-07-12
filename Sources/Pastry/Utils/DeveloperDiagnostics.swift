import Foundation
import OSLog

/// 开发诊断：本地性能计时 + 功能使用计数，共用同一开关，不上报。
enum DeveloperDiagnostics {
    private static let log = Logger(subsystem: "com.nekutai.pastry", category: "diagnostics")
    private static let queue = DispatchQueue(label: "com.nekutai.pastry.diagnostics", qos: .utility)
    private static let usageFileName = "usage.json"
    private static let perfFileName = "perf.log"
    private static let usageVersion = 1

    /// 设置开关或环境变量开启时为 true。
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.performanceLoggingEnabled)
            || ProcessInfo.processInfo.environment["PASTRY_DIAGNOSTICS"] == "1"
            || ProcessInfo.processInfo.environment["PASTRY_PERF_LOG"] == "1"
    }

    /// 功能使用计数 +1（开关关闭时 no-op）。
    static func record(_ event: String) {
        guard isEnabled, !event.isEmpty else { return }
        queue.async {
            mutateUsageCounts { counts in
                counts[event, default: 0] += 1
            }
        }
    }

    /// 写入一行性能日志（格式保持与 bench.sh 兼容）。
    static func writePerfLine(_ line: String) {
        guard isEnabled else { return }
        queue.async {
            let logDir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
            guard AppDirectories.ensureDirectory(logDir, logCategory: "diagnostics") else { return }
            let logFile = logDir.appendingPathComponent(perfFileName)
            if let handle = try? FileHandle(forWritingTo: logFile) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
            } else {
                try? (line + "\n").write(to: logFile, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Testing helpers

    /// 同步读取当前计数（测试用；会等待队列排空）。
    static func snapshotCountsForTesting() -> [String: Int] {
        queue.sync {
            loadUsageFile().counts
        }
    }

    /// 重置 usage.json（测试用）。
    static func resetUsageForTesting() {
        queue.sync {
            let url = usageFileURL()
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 指定测试目录覆盖（测试用）；传 nil 恢复默认。
    nonisolated(unsafe) static var logsDirectoryOverrideForTesting: URL?

    // MARK: - Private

    private struct UsageFile: Codable {
        var version: Int
        var updatedAt: String
        var counts: [String: Int]
    }

    private static func usageFileURL() -> URL {
        let dir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
        return dir.appendingPathComponent(usageFileName)
    }

    private static func loadUsageFile() -> UsageFile {
        let url = usageFileURL()
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(UsageFile.self, from: data)
        else {
            return UsageFile(version: usageVersion, updatedAt: isoNow(), counts: [:])
        }
        return decoded
    }

    private static func mutateUsageCounts(_ body: (inout [String: Int]) -> Void) {
        let dir = logsDirectoryOverrideForTesting ?? AppDirectories.logsDirectory()
        guard AppDirectories.ensureDirectory(dir, logCategory: "diagnostics") else { return }

        var file = loadUsageFile()
        body(&file.counts)
        file.version = usageVersion
        file.updatedAt = isoNow()

        do {
            let data = try JSONEncoder().encode(file)
            try data.write(to: usageFileURL(), options: .atomic)
        } catch {
            log.error("写入 usage.json 失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

/// 稳定事件名，避免散落字符串拼写不一致。
enum DiagnosticsEvent {
    static let overlayOpen = "overlay.open"
    static let overlayDismiss = "overlay.dismiss"

    static let pasteSingle = "paste.single"
    static let pasteMulti = "paste.multi"
    static let pasteCmdNumber = "paste.cmd_number"
    static let cardClickPaste = "card_click.paste"

    static let copy = "copy"
    static let preview = "preview"
    static let share = "share"
    static let open = "open"
    static let showInFinder = "show_in_finder"

    static let favoritePin = "favorite.pin"
    static let favoriteUnpin = "favorite.unpin"

    static let delete = "delete"
    static let deleteIncludingFavorite = "delete.including_favorite"
    static let clearAll = "clear_all"

    static let searchOpen = "search.open"
    static let searchQuery = "search.query"

    static let dragSingle = "drag.single"
    static let dragMulti = "drag.multi"

    static let tabAll = "tab.all"
    static let tabFavorites = "tab.favorites"

    static let filterClear = "filter.clear"
    static let filterApp = "filter.app"
    static let filterURL = "filter.url"
    static let filterHandoff = "filter.handoff"

    static let accessibilityDenied = "accessibility.denied"

    static func filterType(_ format: SourceFormat) -> String {
        "filter.type.\(format.rawValue)"
    }

    static func filterTime(_ filter: StoreManager.TimeFilter) -> String {
        switch filter {
        case .any: return "filter.time.any"
        case .today: return "filter.time.today"
        case .yesterday: return "filter.time.yesterday"
        case .thisWeek: return "filter.time.thisWeek"
        case .lastWeek: return "filter.time.lastWeek"
        case .last30Days: return "filter.time.last30Days"
        }
    }
}
