import Foundation
import OSLog

enum AppDirectories {
    private static let log = Logger(subsystem: "com.nekutai.pastry", category: "app-directories")

    static func applicationSupportDirectory() -> URL {
        if let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            return appSupport.appendingPathComponent(Constants.appName)
        }

        let fallback = FileManager.default.temporaryDirectory
            .appendingPathComponent(Constants.appName)
            .appendingPathComponent("ApplicationSupportFallback")
        log.error("无法获取 Application Support 目录，降级使用临时目录: \(fallback.path, privacy: .public)")
        return fallback
    }

    static func ensureDirectory(_ url: URL, logCategory: String) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            let logger = Logger(subsystem: "com.nekutai.pastry", category: logCategory)
            logger.error("无法创建目录: \(url.path, privacy: .public), error: \(error.localizedDescription)")
        }
    }
}
