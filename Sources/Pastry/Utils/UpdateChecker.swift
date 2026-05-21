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
            // 仍缓存 release notes（供 upToDate 页显示上次更新日志）
            cacheResult(release)
            return nil
        }

        // 找 DMG asset（文件名以 .dmg 结尾）
        guard let dmg = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            log.error("Release 中没有找到 DMG 文件")
            return nil
        }

        return UpdateResult(
            currentVersion: currentVersion,
            latestVersion: Self.displayVersion(release.tag_name),
            releaseNotes: release.body ?? "",
            downloadURL: dmg.browser_download_url,
            htmlURL: release.html_url
        )
    }

    // MARK: - 缓存上次检查结果

    private let lastReleaseNotesKey = "PastryLastReleaseNotes"
    private let lastCheckedVersionKey = "PastryLastCheckedVersion"

    /// 缓存成功的检查结果（供 upToDate 页显示上次更新日志）
    private func cacheResult(_ result: ReleaseInfo) {
        UserDefaults.standard.set(result.body, forKey: lastReleaseNotesKey)
        UserDefaults.standard.set(result.tag_name, forKey: lastCheckedVersionKey)
    }

    /// 读取缓存的 release notes
    func cachedReleaseNotes() -> String? {
        UserDefaults.standard.string(forKey: lastReleaseNotesKey)
    }

    /// 下载二进制到临时目录，返回文件路径。onProgress 在主线程回调 0.0~1.0。
    func downloadBinary(from urlString: String, onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> URL {
        guard let url = URL(string: urlString) else {
            throw UpdateError.invalidURL
        }
        guard url.scheme?.lowercased() == "https" else {
            throw UpdateError.insecureURL
        }

        let delegate = ProgressDownloadDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: .main)

        let (tempURL, response) = try await session.download(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed
        }

        return tempURL
    }

    /// 应用更新：挂载 DMG → 校验签名 → 备份替换整个 .app → 重启
    func applyUpdate(dmgAt tempURL: URL) throws {
        let targetPath = Bundle.main.bundlePath

        // 将 DMG 移到稳定路径（tempURL 可能被系统清理）
        let stableDMG = URL(fileURLWithPath: NSTemporaryDirectory() + "pastry_update.dmg")
        try? FileManager.default.removeItem(at: stableDMG)
        try FileManager.default.moveItem(at: tempURL, to: stableDMG)

        // 写 helper 脚本：当前进程 terminate 后由它完成替换
        let scriptPath = NSTemporaryDirectory() + "pastry_update.sh"
        let script = """
        #!/bin/bash
        set -e
        sleep 1

        DMG="\(stableDMG.path)"
        TARGET="\(targetPath)"
        TARGET_PARENT=$(dirname "$TARGET")
        TARGET_NAME=$(basename "$TARGET")
        BACKUP="$TARGET_PARENT/.${TARGET_NAME}.update-backup-$(date +%s)"

        # 挂载 DMG
        MOUNT_OUTPUT=$(hdiutil attach -noverify -noautoopen -nobrowse "$DMG" 2>&1)
        VOLUME=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | tail -1 | awk -F'\\t' '{print $NF}')

        if [ ! -d "$VOLUME/Pastry.app" ]; then
            echo "❌ DMG 挂载失败或缺少 Pastry.app" >&2
            open "$TARGET"
            exit 1
        fi

        CANDIDATE="$VOLUME/Pastry.app"
        CANDIDATE_BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        if [ "$CANDIDATE_BUNDLE" != "com.nekutai.pastry" ]; then
            echo "❌ 更新包 Bundle ID 不匹配: $CANDIDATE_BUNDLE" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        if ! /usr/bin/codesign --verify --deep --strict "$CANDIDATE" 2>/dev/null; then
            echo "❌ 更新包签名校验失败" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        CURRENT_REQ=$(/usr/bin/codesign -dr - "$TARGET" 2>&1 | sed -n 's/^.*designated => //p')
        if [ -z "$CURRENT_REQ" ]; then
            echo "❌ 无法读取当前 App 签名要求，拒绝自动更新" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi
        if ! /usr/bin/codesign --verify --deep --strict -R="designated => $CURRENT_REQ" "$CANDIDATE" 2>/dev/null; then
            echo "❌ 更新包签名身份与当前 App 不匹配" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        # 替换整个 .app；先备份，复制失败时恢复旧版本
        mv "$TARGET" "$BACKUP"
        if ! cp -R "$CANDIDATE" "$TARGET"; then
            echo "❌ 更新包复制失败，已恢复旧版本" >&2
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi
        rm -rf "$BACKUP"

        # 卸载 DMG
        hdiutil detach "$VOLUME" -quiet

        # 清理
        rm -f "$DMG" "$0"

        open "$TARGET"
        """

        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        // 启动 helper 并退出当前进程
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = [scriptPath]
        try task.run()

        NSApp.terminate(nil)
    }

    // MARK: - 版本比较

    private func currentVersionString() -> String {
        Self.displayVersion(AppVersion.current)
    }

    /// 语义化版本比较：tag > current → true
    private func isNewer(tag: String, than current: String) -> Bool {
        let tagParts = Self.displayVersion(tag).split(separator: ".")
        let curParts = Self.displayVersion(current).split(separator: ".")

        for i in 0..<max(tagParts.count, curParts.count) {
            let t = i < tagParts.count ? (Int(tagParts[i]) ?? 0) : 0
            let c = i < curParts.count ? (Int(curParts[i]) ?? 0) : 0
            if t > c { return true }
            if t < c { return false }
        }
        return false
    }

    static func displayVersion(_ version: String) -> String {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^v+"#, with: "", options: .regularExpression)
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

    enum UpdateError: LocalizedError, Equatable {
        case invalidURL
        case insecureURL
        case downloadFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "下载链接无效"
            case .insecureURL: return "下载链接必须使用 HTTPS"
            case .downloadFailed: return "下载失败"
            }
        }
    }
}

// MARK: - 下载进度代理
private final class ProgressDownloadDelegate: NSObject, URLSessionDownloadDelegate {

    private let onProgress: (@Sendable (Double) -> Void)?

    init(onProgress: (@Sendable (Double) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // no-op — async/await 会处理
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        // no-op — async/await 会处理
    }
}
