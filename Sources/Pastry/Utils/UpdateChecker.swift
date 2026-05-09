import Foundation
import AppKit
import OSLog

// MARK: - 更新检查器
// 对接 GitHub Releases API，提供版本检查与二进制下载
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let log = Logger(subsystem: "com.nekutai.pastry", category: "update")
    private let session: URLSession
    private let lastCheckKey = "PastryLastUpdateCheck"
    private let checkInterval: TimeInterval = 86_400 // 24 小时

    /// 当前 app 是否为开发版本
    var isDevBuild: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.contains("-dev")
    }

    // MARK: - 公开发布信息

    struct ReleaseInfo: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let published_at: String
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    struct UpdateResult {
        let currentVersion: String
        let latestVersion: String
        let releaseNotes: String
        let downloadURL: String
        let htmlURL: String
    }

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    // MARK: - 公开方法

    /// 检查更新（dev 版本直接返回 nil）
    /// 距上次检查不足 24 小时且 force=false 时跳过网络请求
    func checkForUpdate(force: Bool = false) async -> UpdateResult? {
        guard !isDevBuild else {
            log.info("开发版本，跳过更新检查")
            return nil
        }

        let now = Date()
        if !force {
            let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
            if now.timeIntervalSince(lastCheck) < checkInterval {
                log.info("距上次检查不足 24 小时，跳过")
                return nil
            }
        }

        guard let release = await fetchLatestRelease() else { return nil }

        UserDefaults.standard.set(now, forKey: lastCheckKey)

        let currentVersion = currentVersionString()
        guard isNewer(tag: release.tag_name, than: currentVersion) else {
            log.info("已是最新版本: \(currentVersion)")
            return nil
        }

        // 找裸二进制 asset（文件名 "Pastry"）
        guard let binary = release.assets.first(where: { $0.name == "Pastry" }) else {
            log.error("Release 中没有找到裸二进制文件")
            return nil
        }

        return UpdateResult(
            currentVersion: currentVersion,
            latestVersion: release.tag_name,
            releaseNotes: release.body ?? "",
            downloadURL: binary.browser_download_url,
            htmlURL: release.html_url
        )
    }

    /// 下载二进制到临时目录，返回文件路径
    func downloadBinary(from urlString: String) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }

        let (tempURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed
        }

        return tempURL
    }

    /// 应用更新：替换二进制并重启
    func applyUpdate(binaryAt tempURL: URL) throws {
        guard let executablePath = Bundle.main.executablePath else {
            throw UpdateError.cannotReplace
        }

        let fileManager = FileManager.default

        // 1. 替换二进制
        let backupPath = executablePath + ".old"
        if fileManager.fileExists(atPath: backupPath) {
            try fileManager.removeItem(atPath: backupPath)
        }
        try fileManager.moveItem(atPath: executablePath, toPath: backupPath)
        try fileManager.copyItem(atPath: tempURL.path, toPath: executablePath)

        // 2. 设置可执行权限
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executablePath)

        // 3. 用已知证书重签（保持 TCC 权限不丢失）
        let appPath = Bundle.main.bundlePath
        let identity = resolveCodeSignIdentity()
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/codesign"),
                             arguments: ["--force", "--deep", "--sign", identity, appPath])

        // 4. 重启（用 bash 中间进程，避免 terminate 杀子进程）
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", "sleep 0.3; open '\(bundlePath)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - 版本比较

    private func currentVersionString() -> String {
        AppVersion.current
    }

    /// 语义化版本比较：tag > current → true
    private func isNewer(tag: String, than current: String) -> Bool {
        let tagParts = tag.replacingOccurrences(of: "v", with: "").split(separator: ".")
        let curParts = current.split(separator: ".")

        for i in 0..<max(tagParts.count, curParts.count) {
            let t = i < tagParts.count ? (Int(tagParts[i]) ?? 0) : 0
            let c = i < curParts.count ? (Int(curParts[i]) ?? 0) : 0
            if t > c { return true }
            if t < c { return false }
        }
        return false
    }

    // MARK: - 签名

    /// 解析代码签名身份：先尝 Pastry Release（TCC 持久），失败则 ad-hoc
    private func resolveCodeSignIdentity() -> String {
        let identities = ["Pastry Release", "Pastry Dev"]
        for name in identities {
            let task = Process()
            task.launchPath = "/usr/bin/security"
            task.arguments = ["find-identity", "-p", "codesigning", name]
            task.standardOutput = FileHandle.nullDevice
            task.standardError = FileHandle.nullDevice
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                log.info("使用签名身份: \(name)")
                return name
            }
        }
        log.warning("未找到固定证书，使用 ad-hoc 签名（TCC 不持久）")
        return "-"
    }

    // MARK: - 网络请求

    private func fetchLatestRelease() async -> ReleaseInfo? {
        guard let url = URL(string: "https://api.github.com/repos/vipic/Pastry/releases/latest") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Pastry/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                log.error("GitHub API 返回非 200: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
                return nil
            }
            let decoder = JSONDecoder()
            return try decoder.decode(ReleaseInfo.self, from: data)
        } catch {
            log.error("获取 Release 失败: \(error.localizedDescription)")
            return nil
        }
    }

    enum UpdateError: LocalizedError {
        case invalidURL
        case downloadFailed
        case cannotReplace

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "下载链接无效"
            case .downloadFailed: return "下载失败"
            case .cannotReplace: return "无法替换应用二进制"
            }
        }
    }
}
