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
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "monitor")

    // 防止同一内容重复触发
    private var lastDedupKey = ""

    /// 自定义复制提示音
    private static let copySound: NSSound? = {
        guard let path = Bundle.main.path(forResource: "Copy", ofType: "aiff") else {
            Logger(subsystem: "com.nekutai.pastry", category: "monitor").warning("找不到 Copy.aiff")
            return nil
        }
        return NSSound(contentsOfFile: path, byReference: true)
    }()

    // MARK: - 来源识别：用户主动切换 App = 上下文
    /// 最近 10 秒内用户主动切换到的 App（didActivateApplicationNotification）。
    /// 来源应该反映用户的工作上下文，而非剪贴板写入瞬间碰巧在前台的进程。
    private let contextWindow: TimeInterval = 10.0
    private var recentApps: [(name: String, time: Date)] = []
    private var appObserver: NSObjectProtocol?

    /// 上一轮轮询时的前台 App — 捕获截图软件等不激活自身的工具
    private var previousFrontApp: String?

    /// 暂停/恢复监听（仅主线程调用）
    private var suspendCount = 0
    var isSuspended: Bool { suspendCount > 0 }

    func suspend() {
        assert(Thread.isMainThread, "suspend() 必须在主线程调用")
        suspendCount += 1
    }

    func resume() {
        assert(Thread.isMainThread, "resume() 必须在主线程调用")
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

        // 追踪用户主动切换 App 的行为（真正的上下文）
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
            self.recentApps = self.recentApps.filter {
                now.timeIntervalSince($0.time) < self.contextWindow
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

        // 每轮记录当前前台 App，供截图软件等不激活自身的工具使用
        let currentFront = NSWorkspace.shared.frontmostApplication?.localizedName

        guard currentChange != lastChangeCount else {
            previousFrontApp = currentFront
            return
        }
        lastChangeCount = currentChange

        // 检测到剪贴板变化 → 立即播提示音（不等 0.1s 延迟和内容解析）
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            Self.copySound?.play()
        }

        // 来源 = 用户上下文（激活历史） > 上一轮前台 > 当前前台
        let capturedApp = bestGuessAppName(currentFront: currentFront)
        previousFrontApp = currentFront

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            [weak self] in
            self?.processChange(capturedApp: capturedApp)
        }
    }

    /// 来源优先级：用户切换到的 App（上下文）> 上轮前台 App > 当前前台 App
    private func bestGuessAppName(currentFront: String?) -> String? {
        let now = Date()
        recentApps = recentApps.filter { now.timeIntervalSince($0.time) < contextWindow }

        // Tier 1: 用户主动切换到的最近 App（真正的上下文）
        for entry in recentApps.reversed() {
            let name = entry.name
            if name == "Finder" || name == "loginwindow" { continue }
            return name
        }

        // Tier 2: 上轮前台 App（捕获不激活自身的截图工具等）
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

        // 图片处理：主线程读取数据，后台队列生成缩略图并写入磁盘
        if let (image, data) = readImageData(from: pb) {
            lastDedupKey = dedup
            let appName = capturedApp
            let textAnnotation = readText(from: pb, appName: nil)?.content
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                guard let savedPath = ImageCacheManager.shared.save(image: image, data: data) else {
                    self.log.error("图片缓存写入失败")
                    return
                }
                let item = ClipboardItem(content: savedPath, contentType: .image, appName: appName, textAnnotation: textAnnotation)
                DispatchQueue.main.async {
                    self.latestItem = item
                    self.onNewItem?(item)
                }
            }
            return
        }

        if let item = readFileURLs(from: pb, appName: capturedApp)
            ?? readHTML(from: pb, appName: capturedApp)
            ?? readRTF(from: pb, appName: capturedApp)
            ?? readText(from: pb, appName: capturedApp) {

            lastDedupKey = dedup

            DispatchQueue.main.async {
                self.latestItem = item
                self.onNewItem?(item)
            }
        }
    }

    // MARK: - 各格式读取器

    private func readText(from pb: NSPasteboard, appName: String?) -> ClipboardItem? {
        // 标准纯文本
        if let text = pb.string(forType: .string), !text.isEmpty {
            return ClipboardItem(content: text, contentType: .text, appName: appName)
        }
        // 微信/QQ 自定义富文本（TencentAttributeStringType plist）
        if let text = readTencentText(from: pb), !text.isEmpty {
            return ClipboardItem(content: text, contentType: .text, appName: appName)
        }
        return nil
    }

    /// 微信/QQ 剪贴板自定义类型：二进制 plist 数组，元素含 TencentElementType(11=文本) + TencentElementValue
    private func readTencentText(from pb: NSPasteboard) -> String? {
        let tencentType = NSPasteboard.PasteboardType("TencentAttributeStringType")
        guard let data = pb.data(forType: tencentType),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]]
        else { return nil }
        let texts = plist.compactMap { dict -> String? in
            guard let type = dict["TencentElementType"] as? Int, type == 11,
                  let value = dict["TencentElementValue"] as? String
            else { return nil }
            return value
        }
        let combined = texts.joined()
        return combined.isEmpty ? nil : combined
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

        // 提取纯文本
        var content: String
        if let attr = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html],
            documentAttributes: nil) {
            content = attr.string
        } else {
            content = html
        }

        // 提取 HTML 图文混排的有序段
        let sourceURL = readChromiumSourceURL(from: pb)
        let segments = extractOrderedSegments(from: html, sourceURL: sourceURL)

        return ClipboardItem(
            content: content,
            contentType: .html,
            appName: appName,
            segments: segments.isEmpty ? nil : segments
        )
    }

    /// 从 Chromium 剪贴板自定义字段中读取源页面 URL
    private func readChromiumSourceURL(from pb: NSPasteboard) -> URL? {
        let sourceType = NSPasteboard.PasteboardType("org.chromium.source-url")
        guard let data = pb.data(forType: sourceType),
              let urlStr = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return URL(string: urlStr)
    }

    /// 解析 HTML 为有序图文段，保留原始 DOM 顺序
    private func extractOrderedSegments(from html: String, sourceURL: URL?) -> [ContentSegment] {
        guard let imgRegex = try? NSRegularExpression(
            pattern: "<img[^>]+src=[\"']([^\"']+)[\"'][^>]*>",
            options: .caseInsensitive
        ) else { return [] }

        let nsRange = NSRange(html.startIndex..., in: html)
        let imgMatches = imgRegex.matches(in: html, range: nsRange)

        // 收集所有 <img> 位置 + 解析后的 URL，最多 5 张，去重
        var imgEntries: [(range: NSRange, url: String)] = []
        var seen = Set<String>()
        for match in imgMatches.prefix(5) {
            guard let captureRange = Range(match.range(at: 1), in: html) else { continue }
            let src = String(html[captureRange])
            guard !src.hasPrefix("data:") else { continue }

            let resolved: String
            if let source = sourceURL, let r = URL(string: src, relativeTo: source) {
                resolved = r.absoluteString
            } else if URL(string: src) != nil {
                resolved = src
            } else { continue }

            guard !seen.contains(resolved) else { continue }
            seen.insert(resolved)
            imgEntries.append((match.range, resolved))
        }

        guard !imgEntries.isEmpty else { return [] }

        // 按位置排序
        imgEntries.sort { $0.range.location < $1.range.location }

        // 在 HTML 中切分：文字段（img 之间）→ 图片段 → 文字段 → ...
        var segments: [ContentSegment] = []
        var cursor = html.startIndex

        for entry in imgEntries {
            guard let imgStart = Range(entry.range, in: html)?.lowerBound else { continue }

            // 提取 img 之前的文字
            if cursor < imgStart {
                let rawText = String(html[cursor..<imgStart])
                let clean = stripHTMLTags(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty {
                    // 与前一个文字段合并
                    if case .text(let prev) = segments.last {
                        segments[segments.count - 1] = .text(prev + clean)
                    } else {
                        segments.append(.text(clean))
                    }
                }
            }

            // 插入图片段
            segments.append(.image(url: entry.url))

            // 移动游标到 img 之后
            cursor = Range(entry.range, in: html)?.upperBound ?? cursor
        }

        // img 之后的尾部文字
        if cursor < html.endIndex {
            let rawText = String(html[cursor..<html.endIndex])
            let clean = stripHTMLTags(rawText).trimmingCharacters(in: .whitespacesAndNewlines)
            if !clean.isEmpty {
                if case .text(let prev) = segments.last {
                    segments[segments.count - 1] = .text(prev + clean)
                } else {
                    segments.append(.text(clean))
                }
            }
        }

        return segments
    }

    /// 去除 HTML 标签和实体，保留纯文本
    private func stripHTMLTags(_ html: String) -> String {
        // 先处理常见实体
        var text = html
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        // 去除标签
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else { return text }
        text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return text
    }

    /// 仅读取剪贴板图片数据和 NSImage（主线程安全，轻量操作）。
    /// 缩略图生成、编码和磁盘写入已移至后台队列。
    private func readImageData(from pb: NSPasteboard) -> (NSImage, Data)? {
        guard let data = pb.data(forType: .tiff) ?? pb.data(forType: .png),
              let image = NSImage(data: data)
        else { return nil }
        return (image, data)
    }

    private func readFileURLs(from pb: NSPasteboard, appName: String?) -> ClipboardItem? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty
        else { return nil }
        let paths = urls.map(\.path).joined(separator: "\n")
        return ClipboardItem(content: paths, contentType: .fileURL, appName: appName)
    }

    // MARK: - 测试入口

    /// 供单元测试使用的 TencentAttributeStringType 解析入口
    static func readTencentTextForTesting(from pb: NSPasteboard) -> String? {
        shared.readTencentText(from: pb)
    }

    /// 供单元测试使用的 HTML segments 解析入口
    static func extractOrderedSegmentsForTesting(from html: String, sourceURL: URL?) -> [ContentSegment] {
        shared.extractOrderedSegments(from: html, sourceURL: sourceURL)
    }

    // MARK: - 辅助

    private var currentDedupKey: String {
        let pb = NSPasteboard.general
        let change = pb.changeCount
        let types = pb.types?.map(\.rawValue).joined() ?? ""
        // 加入内容摘要，防止同格式连续复制去重失效
        let snapshot = pb.string(forType: pb.types?.first ?? .string)?.prefix(100) ?? ""
        return "\(change):\(types):\(snapshot)"
    }
}

// MARK: - 图片缓存管理器
final class ImageCacheManager {
    static let shared = ImageCacheManager()

    /// 缓存磁盘用量上限（超过触发淘汰）
    private static let maxCacheSize: Int64 = 200 * 1024 * 1024  // 200 MB
    /// 淘汰后目标磁盘用量
    private static let targetCacheSize: Int64 = 150 * 1024 * 1024  // 150 MB

    private let cacheDir: URL

    private init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        cacheDir = appSupport
            .appendingPathComponent(Constants.appName)
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
        else { return nil }
        do {
            try pngData.write(to: fileURL)
            evictIfNeeded()
            return fileURL.path
        } catch {
            return nil
        }
    }

    /// LRU 磁盘淘汰：超过 maxCacheSize 时按修改时间删除最旧文件，直到低于 targetCacheSize
    private func evictIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, modDate: Date)] = []

        for file in files {
            guard let attrs = try? file.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            ),
                  let size = attrs.fileSize.map(Int64.init)
            else { continue }
            totalSize += size
            fileInfos.append((file, size, attrs.contentModificationDate ?? Date.distantPast))
        }

        guard totalSize > Self.maxCacheSize else { return }

        // 按修改时间升序（最旧 → 最新）
        fileInfos.sort { $0.modDate < $1.modDate }

        for info in fileInfos {
            guard totalSize > Self.targetCacheSize else { break }
            do {
                try fm.removeItem(at: info.url)
                totalSize -= info.size
            } catch {
                // 无法删除的文件跳过，继续处理下一个
            }
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
