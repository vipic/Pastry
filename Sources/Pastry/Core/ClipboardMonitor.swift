import Cocoa
import Combine
import OSLog

// MARK: - 剪贴板监听器
// 核心策略：轮询 NSPasteboard.changeCount，检测变化后立即读取
final class ClipboardMonitor: ObservableObject {

    // MARK: 单例
    nonisolated(unsafe) static let shared = ClipboardMonitor()

    // MARK: Published
    @Published private(set) var latestItem: ClipboardItem?
    @Published private(set) var isRunning = false

    // MARK: 回调
    var onNewItem: ((ClipboardItem) -> Void)?

    // MARK: 私有状态
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let pollInterval: TimeInterval = 0.2
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "monitor")

    /// CGEvent tap：监听 ⌘C/⌘X/截图 按键，立即触发轮询（不等 timer，降低延迟）
    private var eventTap: CFMachPort?

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

        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        log.info("剪贴板监听已启动 (interval: \(self.pollInterval)s)")
    }

    /// ⌘C 事件监听：延迟到首次粘贴时才创建（避免启动时弹辅助功能授权）
    func setupEventTap() {
        guard eventTap == nil else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyUp.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyUp {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    let isCopy       = keyCode == 8  && flags.contains(.maskCommand)                           // C
                    let isCut        = keyCode == 7  && flags.contains(.maskCommand)                           // X
                    let isScreenshot = (keyCode == 20 || keyCode == 21 || keyCode == 23)                       // 3/4/5
                                        && flags.contains(.maskCommand) && flags.contains(.maskShift)
                    let isCtrlCmdA   = keyCode == 0 && flags.contains(.maskCommand) && flags.contains(.maskControl)  // A
                    if isCopy || isCut || isScreenshot || isCtrlCmdA {
                        let monitor = Unmanaged<ClipboardMonitor>
                            .fromOpaque(refcon!).takeUnretainedValue()
                        DispatchQueue.main.async {
                            monitor.poll()
                        }
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(self).toOpaque()
            )
        )
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(
                kCFAllocatorDefault, tap, 0
            )
            CFRunLoopAddSource(
                RunLoop.main.getCFRunLoop(), runLoopSource, .commonModes
            )
            CGEvent.tapEnable(tap: tap, enable: true)
            log.info("⌘C 事件监听已启动")
        } else {
            log.warning("CGEvent tap 创建失败 — 可能需要辅助功能权限")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isRunning = false
        log.info("剪贴板监听已停止")
    }

    // MARK: - 轮询

    private func poll() {
        guard !isSuspended else { return }

        let pb = NSPasteboard.general
        let currentChange = pb.changeCount

        guard currentChange != lastChangeCount else { return }
        lastChangeCount = currentChange

        // 检测到剪贴板变化 → 立即播提示音
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            Self.copySound?.play()
        }

        // 来源 = 当前前台 App
        let frontApp = NSWorkspace.shared.frontmostApplication
        let capturedApp = frontApp?.localizedName
        let capturedBundleID = frontApp?.bundleIdentifier

        DispatchQueue.main.async {
            [weak self] in
            self?.processChange(capturedApp: capturedApp, capturedBundleID: capturedBundleID)
        }
    }

    // MARK: - 处理剪贴板变化

    private func processChange(capturedApp: String?, capturedBundleID: String?) {
        let dedup = currentDedupKey
        guard dedup != lastDedupKey else { return }

        // 排除名单：密码管理器等敏感应用不保存剪贴板历史
        if let bundleID = capturedBundleID {
            let excluded = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
            if excluded.contains(bundleID) {
                lastDedupKey = dedup  // 更新去重 key，避免下次误判为变化
                return
            }
        }

        let pb = NSPasteboard.general

        guard let types = pb.types, !types.isEmpty else { return }

        // 检测 Handoff/通用剪贴板来源
        let isRemoteClipboard = types.contains(where: { $0.rawValue == "com.apple.is-remote-clipboard" })
        let effectiveApp = isRemoteClipboard ? nil : capturedApp  // Handoff 时不给 appName，之后 UI 层特殊处理

        // 文件 URL 优先：Finder 复制文件时剪贴板同时有图片数据，fileURL 更能代表用户意图
        if let item = readFileURLs(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            lastDedupKey = dedup
            DispatchQueue.main.async {
                self.latestItem = item
                self.onNewItem?(item)
            }
            return
        }

        // URL 链接：在图片之前检测，避免 http 字符串被当作纯文本
        if let item = readURL(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            lastDedupKey = dedup
            DispatchQueue.main.async {
                self.latestItem = item
                self.onNewItem?(item)
            }
            return
        }

        // 图片处理：主线程读取数据，后台队列生成缩略图并写入磁盘
        if let (image, data) = readImageData(from: pb) {
            lastDedupKey = dedup
            let appName = effectiveApp
            let isHandoff = isRemoteClipboard
            let textAnnotation = readText(from: pb, appName: nil)?.content
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                guard let savedPath = ImageCacheManager.shared.save(image: image, data: data) else {
                    self.log.error("图片缓存写入失败")
                    return
                }
                let item = ClipboardItem(content: savedPath, sourceFormat: .image, appName: appName, isHandoff: isHandoff, textAnnotation: textAnnotation)
                DispatchQueue.main.async {
                    self.latestItem = item
                    self.onNewItem?(item)
                }
            }
            return
        }

        if let item = readHTML(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard)
            ?? readRTF(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard)
            ?? readText(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {

            lastDedupKey = dedup

            DispatchQueue.main.async {
                self.latestItem = item
                self.onNewItem?(item)
            }
        }
    }

    // MARK: - 各格式读取器

    private func readText(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        // 标准纯文本
        if let text = pb.string(forType: .string), !text.isEmpty {
            let isURL = isPlainURL(text)
            return ClipboardItem(content: text, sourceFormat: .text, tags: ContentTags(isURL: isURL), appName: appName, isHandoff: isHandoff)
        }
        // 微信/QQ 自定义富文本（TencentAttributeStringType plist）
        if let text = readTencentText(from: pb), !text.isEmpty {
            let isURL = isPlainURL(text)
            return ClipboardItem(content: text, sourceFormat: .text, tags: ContentTags(isURL: isURL), appName: appName, isHandoff: isHandoff)
        }
        return nil
    }

    /// 检测纯文本是否为 URL（http/https），用于回退到 readText 时将链接归为 .url 类型
    private func isPlainURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased())
        else { return false }
        return true
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

    private func readRTF(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        guard let data = pb.data(forType: .rtf),
              let attr = try? NSAttributedString(
                  data: data,
                  options: [.documentType: NSAttributedString.DocumentType.rtf],
                  documentAttributes: nil)
        else { return nil }
        return ClipboardItem(
            content: attr.string,
            sourceFormat: .rtf,
            appName: appName,
            isHandoff: isHandoff,
            rawFormatData: data,
            rawFormatType: "public.rtf"
        )
    }

    private func readHTML(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
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
            sourceFormat: .html,
            appName: appName,
            isHandoff: isHandoff,
            segments: segments.isEmpty ? nil : segments,
            rawFormatData: data,
            rawFormatType: "public.html"
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

    private func readFileURLs(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty
        else { return nil }
        // 只保留 file:// URL，过滤掉 Handoff 同步来的 http/https 等非文件 URL
        let fileURLs = urls.filter { $0.isFileURL }
        guard !fileURLs.isEmpty else { return nil }
        let paths = fileURLs.map(\.path).joined(separator: "\n")

        // 所有文件都是图片 → 归为 .image，显示图片预览而非文件图标
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif"]
        let allImages = fileURLs.allSatisfy { imageExtensions.contains($0.pathExtension.lowercased()) }
        if allImages {
            return ClipboardItem(content: paths, sourceFormat: .image, appName: appName, isHandoff: isHandoff)
        }

        return ClipboardItem(content: paths, sourceFormat: .fileURL, appName: appName, isHandoff: isHandoff)
    }

    /// 检测剪贴板中的 URL 链接（http/https），优于纯文本捕获
    private func readURL(from pb: NSPasteboard, appName: String?, isHandoff: Bool = false) -> ClipboardItem? {
        // 先用 NSURL 类读取，只保留 http/https 的远程 URL
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty
        else { return nil }
        let webURLs = urls.filter { $0.scheme == "http" || $0.scheme == "https" }
        guard !webURLs.isEmpty else { return nil }
        let urlStrings = webURLs.map(\.absoluteString).joined(separator: "\n")
        return ClipboardItem(content: urlStrings, sourceFormat: .text, tags: ContentTags(isURL: true), appName: appName, isHandoff: isHandoff)
    }

    // MARK: - 测试入口

    /// 供单元测试使用的 TencentAttributeStringType 解析入口
    static func readTencentTextForTesting(from pb: NSPasteboard) -> String? {
        shared.readTencentText(from: pb)
    }

    static func extractOrderedSegmentsForTesting(from html: String, sourceURL: URL?) -> [ContentSegment] {
        shared.extractOrderedSegments(from: html, sourceURL: sourceURL)
    }

    static func readFileURLsForTesting(from pb: NSPasteboard) -> ClipboardItem? {
        shared.readFileURLs(from: pb, appName: "TestApp")
    }

    static func readImageDataForTesting(from pb: NSPasteboard) -> (NSImage, Data)? {
        shared.readImageData(from: pb)
    }

    /// 供单元测试：检查 bundleID 是否在排除名单中
    static func isBundleIDExcludedForTesting(_ bundleID: String) -> Bool {
        let excluded = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        return excluded.contains(bundleID)
    }

    // MARK: - 去重

    /// 用于去重的 key：内容 + 内容类型
    var currentDedupKey: String {
        let pb = NSPasteboard.general
        guard let types = pb.types, !types.isEmpty else { return "" }

        var key = ""

        // 文件 URL
        if let paths = pb.string(forType: .fileURL) ?? pb.propertyList(forType: .fileURL) as? String,
           !paths.isEmpty {
            key += "f:\(paths.hashValue)"
        }

        // 图片
        if let tiff = pb.data(forType: .tiff) {
            key += "i:\(tiff.hashValue)"
        }

        // 文本（包括 RTF 转换后的纯文本）
        if let text = pb.string(forType: .string) {
            key += "t:\(text.hashValue)"
        }

        if key.isEmpty, let first = types.first {
            key += "o:\(first.rawValue)"
        }
        return key
    }
}
