import SwiftUI
import Cocoa

// MARK: - 链接预览加载器
final class LinkPreviewLoader {
    static let shared = LinkPreviewLoader()

    struct Preview {
        let title: String
        let description: String?
        let imageURL: String?
        let host: String
    }

    /// Wrapper to store Preview struct in NSCache (requires class type)
    final class PreviewWrapper {
        let preview: Preview
        init(_ preview: Preview) { self.preview = preview }
    }

    private let cache: NSCache<NSString, PreviewWrapper> = {
        let c = NSCache<NSString, PreviewWrapper>()
        c.countLimit = 200
        return c
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    private init() {}

    /// 同步查询缓存（不发起网络请求）
    func cachedPreview(for key: String) -> Preview? {
        cache.object(forKey: key as NSString)?.preview
    }

    func load(url: URL, completion: @escaping (Preview?) -> Void) {
        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached.preview)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data = data,
                  let html = String(data: data, encoding: .utf8)
            else { DispatchQueue.main.async { completion(nil) }; return }
            let title = self.extractMeta(from: html, tag: "og:title") ?? self.extractTitleTag(from: html)
            let description = self.extractMeta(from: html, tag: "og:description")
            let imageURL = self.extractMeta(from: html, tag: "og:image").flatMap { src in
                self.resolveImageURL(src: src, baseURL: url)
            } ?? self.extractMeta(from: html, tag: "twitter:image").flatMap { src in
                self.resolveImageURL(src: src, baseURL: url)
            } ?? self.extractBestImage(from: html, baseURL: url)
            let preview = Preview(
                title: title ?? "",
                description: description,
                imageURL: imageURL,
                host: url.host ?? ""
            )
            self.cache.setObject(PreviewWrapper(preview), forKey: key as NSString)
            DispatchQueue.main.async { completion(preview) }
        }.resume()
    }

    // MARK: - HTML 元数据提取

    private func extractMeta(from html: String, tag: String) -> String? {
        // 匹配 og 属性的多种写法
        let patterns = [
            "\(tag)\" content=\"",
            "\(tag)' content='",
            "property=\"\(tag)\" content=\"",
            "property='\(tag)' content='",
            "name=\"\(tag)\" content=\"",
            "name='\(tag)' content='",
        ]
        for pattern in patterns {
            guard let s = html.range(of: pattern, options: .caseInsensitive) else { continue }
            let quote = html[html.index(before: s.upperBound)] == "\"" ? "\"" : "'"
            let searchStart = s.upperBound
            guard let e = html.range(of: quote, range: searchStart..<html.endIndex) else { continue }
            let value = String(html[searchStart..<e.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func extractTitleTag(from html: String) -> String? {
        guard let s = html.range(of: "<title>", options: .caseInsensitive),
              let e = html.range(of: "</title>", options: .caseInsensitive),
              s.upperBound <= e.lowerBound
        else { return nil }
        let t = html[s.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 相对路径图片 URL 用页面 URL 解析
    private func resolveImageURL(src: String, baseURL: URL) -> String? {
        if let resolved = URL(string: src, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        return URL(string: src)?.absoluteString
    }

    /// og:image 缺失时的降级方案：语义排序选择最佳内容图片
    private func extractBestImage(from html: String, baseURL: URL) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+>",
            options: .caseInsensitive
        ) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        struct Candidate {
            let src: String
            let score: Int
        }
        var candidates: [Candidate] = []

        for match in matches.prefix(30) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])

            // 提取 src，懒加载降级到 data-src
            var src = extractSrc(from: tag)
            if src?.hasPrefix("data:") ?? true {
                if let lazy = extractAttr(from: tag, attr: "data-src"), !lazy.isEmpty {
                    src = lazy
                }
            }
            guard let src, !src.hasPrefix("data:") else { continue }

            let lower = src.lowercased()
            let lowerTag = tag.lowercased()

            // 黑名单过滤：logo / icon / favicon / gravatar / 追踪像素 / footer/header 装饰图
            if isNoiseImage(src: lower, tag: lowerTag) { continue }

            // 尺寸过滤：跳过明确的小图标
            if isSmallIcon(tag: tag) { continue }

            // 打分
            var score = 0

            // 语义关键词加分
            let semanticBoost = [
                "featured": 20, "hero": 20, "cover": 15, "wp-image": 15,
                "thumbnail": 12, "thumb": 10,
                "og-image": 18, "post-image": 15, "entry-image": 15,
                "article-image": 15, "content-image": 12,
            ]
            for (keyword, points) in semanticBoost {
                if lowerTag.contains(keyword) || lower.contains(keyword) {
                    score += points
                }
            }

            // 尺寸加分
            score += sizeScore(from: tag)

            // alt 文本非空加分（说明是内容图）
            if let alt = extractAttr(from: tag, attr: "alt"), !alt.trimmingCharacters(in: .whitespaces).isEmpty {
                let lt = alt.lowercased()
                if !lt.contains("logo") && !lt.contains("icon") && !lt.contains("home") {
                    score += 5
                }
            }

            candidates.append(Candidate(src: src, score: score))
        }

        // 按分数降序，取最佳
        candidates.sort { $0.score > $1.score }

        if let best = candidates.first {
            return resolveImageURL(src: best.src, baseURL: baseURL)
        }

        // 全部被过滤：降级取第一个非 dataURI 的 img
        for match in matches.prefix(10) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let src = extractSrc(from: tag), !src.hasPrefix("data:") else { continue }
            return resolveImageURL(src: src, baseURL: baseURL)
        }

        return nil
    }

    // MARK: - 图片语义分析辅助

    /// 从 <img> 标签提取 src 属性值
    private func extractSrc(from tag: String) -> String? {
        for quote in ["\"", "'"] {
            if let s = tag.range(of: "src=\(quote)", options: .caseInsensitive) {
                let start = s.upperBound
                guard let e = tag.range(of: quote, range: start..<tag.endIndex) else { continue }
                let val = String(tag[start..<e.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return val }
            }
        }
        return nil
    }

    /// 从标签提取指定属性值
    private func extractAttr(from tag: String, attr: String) -> String? {
        for quote in ["\"", "'"] {
            if let s = tag.range(of: "\(attr)=\(quote)", options: .caseInsensitive) {
                let start = s.upperBound
                guard let e = tag.range(of: quote, range: start..<tag.endIndex) else { continue }
                return String(tag[start..<e.lowerBound])
            }
        }
        return nil
    }

    /// 是否为噪音图片（logo / icon / 追踪像素等）
    private func isNoiseImage(src: String, tag: String) -> Bool {
        let noisePatterns = [
            "logo", "icon", "avatar", "favicon", "gravatar",
            "1x1", "pixel", "tracking", "beacon", "analytics",
            "button", "header-logo", "site-logo", "footer-logo",
            "menu-icon", "nav-icon", "social-icon",
        ]
        for pattern in noisePatterns {
            if src.contains(pattern) || tag.contains(pattern) { return true }
        }
        return false
    }

    /// 是否为明确的小图标（width/height 属性 < 100px）
    private func isSmallIcon(tag: String) -> Bool {
        if let w = extractAttr(from: tag, attr: "width"),
           let width = Int(w), width > 0, width < 100 { return true }
        if let h = extractAttr(from: tag, attr: "height"),
           let height = Int(h), height > 0, height < 100 { return true }
        return false
    }

    /// 根据标签尺寸估算得分
    private func sizeScore(from tag: String) -> Int {
        var w = 0, h = 0
        if let ws = extractAttr(from: tag, attr: "width"), let v = Int(ws) { w = v }
        if let hs = extractAttr(from: tag, attr: "height"), let v = Int(hs) { h = v }
        if w > 0 && h > 0 {
            let area = w * h
            if area >= 500_000 { return 15 }      // ≥ 1000×500
            if area >= 200_000 { return 10 }      // ≥ 500×400
            if area >= 80_000  { return 5 }       // ≥ 400×200
        }
        // 从 URL 参数推测（如 ?w=1200 或 /1200x800）
        if let wRegex = try? NSRegularExpression(pattern: "[?&/]w=(\\d{3,4})", options: .caseInsensitive) {
            let nsTag = tag as NSString
            let range = NSRange(location: 0, length: nsTag.length)
            if let m = wRegex.firstMatch(in: tag, range: range),
               let r = Range(m.range(at: 1), in: tag),
               let v = Int(tag[r]), v >= 800 { return 12 }
        }
        return 0
    }

    // MARK: — 向后兼容

    private func extractTitle(from html: String) -> String? {
        extractTitleTag(from: html) ?? extractMeta(from: html, tag: "og:title")
    }

    // MARK: — 测试入口

    static func extractMetaForTesting(from html: String, tag: String) -> String? {
        shared.extractMeta(from: html, tag: tag)
    }

    static func extractBestImageForTesting(from html: String, baseURL: URL?) -> String? {
        shared.extractBestImage(from: html, baseURL: baseURL ?? URL(string: "https://example.com")!)
    }

    static func resolveImageURLForTesting(src: String, baseURL: URL?) -> String? {
        shared.resolveImageURL(src: src, baseURL: baseURL ?? URL(string: "https://example.com")!)
    }

    static func extractTitleTagForTesting(from html: String) -> String? {
        shared.extractTitleTag(from: html)
    }
}

// MARK: - 剪贴板卡片视图
struct ClipboardCardView: View {

    let item: ClipboardItem
    let isSelected: Bool
    let onTap: (ClipboardItem) -> Void
    let onPin: (ClipboardItem) -> Void

    @State private var appIcon: NSImage?
    @State private var themeColor: Color = .accentColor
    @State private var isContextHighlighted = false
    @State private var didPaste = false

    @State private var linkPreviewTask: Task<Void, Never>?
    /// 链接预览版本号（递增触发重绘，配合计算属性从缓存读取）
    @State private var previewLoadTrigger = 0
    /// 是否已发起过预览请求（用于骨架 → 真实内容/URL 降级的状态切换）
    @State private var previewLoadAttempted = false

    private static let cardSize: CGFloat = 200
    private static let headerHeight: CGFloat = 40
    private static let appIconSize: CGFloat = 60

    /// 路径 → NSImage 缓存，避免重绘时重复创建实例导致闪烁
    private static let imageCache = NSCache<NSString, NSImage>()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            topBar
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            footerBar
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .frame(width: Self.cardSize, height: Self.cardSize)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isContextHighlighted ? Color.blue : Color.clear, lineWidth: 2.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2.5)
        )
        .animation(.easeInOut(duration: 0.12), value: isContextHighlighted)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .scaleEffect(didPaste ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: didPaste)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(didPaste ? Color.green : Color.clear, lineWidth: 2.5)
        )
        .animation(.easeOut(duration: 0.5), value: didPaste)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            didPaste = true
            onTap(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { didPaste = false }
        }
        .overlay(
            RightClickInterceptor(
                onWillShow: { isContextHighlighted = true },
                onDidDismiss: { isContextHighlighted = false },
                onDelete: { StoreManager.shared.deleteItem(item) },
                onPin: { onPin(item) }
            )
        )
        .onAppear {
            loadAppInfo()
            fetchLinkPreviewIfNeeded()
        }
        .onChange(of: item.content) { old, _ in
            Self.imageCache.removeObject(forKey: old as NSString)
            fetchLinkPreviewIfNeeded()
        }
    }

    // MARK: - 顶部栏（始终使用主题色背景）

    private var topBar: some View {
        HStack(spacing: 0) {
            Image(systemName: item.contentType.iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .padding(.leading, 10)

            Spacer()
        }
        .frame(height: Self.headerHeight)
        .background(themeColor)
        .clipped()
        .overlay(alignment: .topTrailing) {
            appIconOverlay
        }
    }

    /// 应用图标 — 60×60，标题栏内垂直居中，右移 50% 让一半溢出卡片被裁切
    @ViewBuilder
    private var appIconOverlay: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
            } else {
                Color.clear
            }
        }
        .frame(width: Self.appIconSize, height: Self.appIconSize)
        // 垂直居中于标题栏再上移一点
        .offset(x: 12, y: (Self.headerHeight - Self.appIconSize) / 2 - 2)
        .animation(.easeInOut(duration: 0.25), value: appIcon != nil)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var contentArea: some View {
        switch item.contentType {
        case .image:   imagePreview
        case .fileURL: fileURLContent
        case .html:    htmlWithImagePreview
        default:
            if let url = detectedLink { linkContent(url) }
            else { textPreview }
        }
    }

    // MARK: - 链接预览（demo 风格，缩略图 + 标题 + 描述 + 域名）

    @ViewBuilder
    private func linkContent(_ url: URL) -> some View {
        let preview = linkPreview
        VStack(spacing: 0) {
            if linkPreview == nil && !previewLoadAttempted {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 56)
                        .padding(.bottom, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 11)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.12))
                            .frame(height: 9)
                            .frame(maxWidth: 100, alignment: .leading)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.10))
                            .frame(height: 8)
                            .frame(maxWidth: 70, alignment: .leading)
                    }
                }
                .redacted(reason: .placeholder)
            } else if let p = preview, !p.title.isEmpty {
                // 缩略图
                linkThumbnail(imageURL: p.imageURL)
                    .frame(height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 4)

                // 文字
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let desc = p.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(p.host)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.6))
                        .lineLimit(1)
                }
            } else {
                Text(url.absoluteString)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func linkThumbnail(imageURL: String?) -> some View {
        if let url = imageURL {
            RemoteThumbnail(urlString: url)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary.opacity(0.35))
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        let key = item.content as NSString
        let nsImage: NSImage? = {
            if let cached = Self.imageCache.object(forKey: key) { return cached }
            guard let loaded = NSImage(contentsOfFile: item.content) else { return nil }
            Self.imageCache.setObject(loaded, forKey: key)
            return loaded
        }()
        VStack(spacing: 0) {
            if let nsImage = nsImage {
                Image(nsImage: nsImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fallbackPreview
            }
            if let annotation = item.textAnnotation, !annotation.isEmpty {
                Text(annotation)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - 文件预览

    /// 文件预览策略（扩展：加 case + 在 filePreviewStyle 中匹配即可）
    enum FilePreviewStyle {
        case thumbnail   // 图片 → NSImage 缩略图
        case systemIcon  // 其他 → NSWorkspace 系统图标
    }

    static func filePreviewStyle(for url: URL) -> FilePreviewStyle {
        if imageExtensions.contains(url.pathExtension.lowercased()) { return .thumbnail }
        return .systemIcon
    }

    @ViewBuilder
    private var fileURLContent: some View {
        let urls = fileURLs
        if urls.count == 1 {
            singleFilePreview(urls[0], style: Self.filePreviewStyle(for: urls[0]))
        } else {
            fileURLList
        }
    }

    /// 单文件卡片：统一布局，预览内容按策略切换
    private func singleFilePreview(_ url: URL, style: FilePreviewStyle) -> some View {
        VStack(spacing: style == .thumbnail ? 6 : 4) {
            filePreviewContent(url: url, style: style)
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func filePreviewContent(url: URL, style: FilePreviewStyle) -> some View {
        switch style {
        case .thumbnail:
            if let img = cachedImage(for: url) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fallbackPreview
            }
        case .systemIcon:
            if let icon = systemIcon(for: url) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// NSImage 文件缓存（缩略图用）
    private func cachedImage(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = Self.imageCache.object(forKey: key) { return cached }
        guard let loaded = NSImage(contentsOfFile: url.path) else { return nil }
        Self.imageCache.setObject(loaded, forKey: key)
        return loaded
    }

    // MARK: - 文件列表（多文件 → 小图标行）

    private var fileURLList: some View {
        let urls = fileURLs
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(urls.prefix(4), id: \.self) { url in
                HStack(spacing: 4) {
                    if let icon = systemIcon(for: url) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    Text(url.lastPathComponent).lineLimit(1).font(.system(size: 10)).foregroundColor(.primary)
                }
            }
            if urls.count > 4 {
                Text("+\(urls.count - 4) 个文件").font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// NSWorkspace 文件图标缓存
    private func systemIcon(for url: URL) -> NSImage? {
        let cacheKey = "icon:\(url.path)" as NSString
        if let cached = Self.imageCache.object(forKey: cacheKey) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.imageCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif",
    ]

    private var textPreview: some View {
        Text(previewText).lineLimit(7).font(.system(size: 11)).foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// HTML 图文预览：按 segments 原始顺序渲染
    @ViewBuilder
    private var htmlWithImagePreview: some View {
        if let segs = item.segments, !segs.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { idx, seg in
                        switch seg {
                        case .text(let t):
                            Text(t)
                                .font(.system(size: 11))
                                .foregroundColor(.primary)
                                .lineLimit(idx == 0 ? 5 : 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        case .image(let url):
                            htmlImageThumbnail(url: url)
                        }
                    }
                }
            }
        } else if let url = detectedLink {
            linkContent(url)
        } else {
            textPreview
        }
    }

    /// 单张 HTML 内嵌图片缩略图（异步加载，与微信图文缩略图大小一致）
    private func htmlImageThumbnail(url: String) -> some View {
        RemoteThumbnail(urlString: url)
            .frame(maxWidth: .infinity)
            .aspectRatio(contentMode: .fit)
            .cornerRadius(4)
            .padding(.vertical, 2)
    }

    private var fallbackPreview: some View {
        VStack {
            Spacer()
            Image(systemName: "photo.badge.exclamationmark").font(.title2).foregroundColor(.secondary.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 底部栏

    private var footerBar: some View {
        HStack(spacing: 4) {
            Text(formattedTime).font(.system(size: 9)).foregroundColor(.secondary)
            if let app = item.appName {
                Text("·").font(.caption2).foregroundColor(.secondary)
                Text(app).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - 时间戳

    private var formattedTime: String {
        let now = Date()
        let diff = now.timeIntervalSince(item.timestamp)
        if diff < 60 { return "刚刚" }
        else if diff < 3600 { return "\(Int(diff / 60)) 分钟前" }
        else if diff < 86400 { return "\(Int(diff / 3600)) 小时前" }
        else if diff < 604800 { return "\(Int(diff / 86400)) 天前" }
        Self.timeFormatter.dateFormat = "M月d日"
        return Self.timeFormatter.string(from: item.timestamp)
    }

    // MARK: - 链接

    private var detectedLink: URL? {
        let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return url }
        if let d = Self.linkDetector,
           let m = d.firstMatch(in: item.content, range: NSRange(item.content.startIndex..., in: item.content)),
           let url = m.url, let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return url }
        return nil
    }

    /// 链接预览：缓存优先，body 求值时同步读取，零帧延迟
    private var linkPreview: LinkPreviewLoader.Preview? {
        _ = previewLoadTrigger
        guard let url = detectedLink else { return nil }
        return LinkPreviewLoader.shared.cachedPreview(for: url.absoluteString)
    }

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func fetchLinkPreviewIfNeeded() {
        guard let url = detectedLink else { return }
        // 缓存命中：计算属性已读取，无需额外操作
        if linkPreview != nil { return }

        // 缓存未命中：延迟后加载
        linkPreviewTask?.cancel()
        linkPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            LinkPreviewLoader.shared.load(url: url) { preview in
                self.previewLoadAttempted = true
                guard preview != nil else { return }
                self.previewLoadTrigger &+= 1
            }
        }
    }

    // MARK: - 辅助

    private var previewText: String {
        let t = item.content.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        return t.count > 240 ? String(t.prefix(240)) + "…" : t
    }

    private var fileURLs: [URL] {
        item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    private func loadAppInfo() {
        let provider = AppIconProvider.shared
        let name = item.appName
        self.themeColor = Color(nsColor: provider.themeColor(for: name))
        DispatchQueue.global(qos: .userInitiated).async {
            let icon = provider.icon(for: name)
            DispatchQueue.main.async {
                self.appIcon = icon
            }
        }
    }

    // MARK: - 测试入口

    /// 供单元测试：扩展名 → 预览策略映射
    static func filePreviewStyleForTesting(extension ext: String) -> FilePreviewStyle {
        filePreviewStyle(for: URL(fileURLWithPath: "/tmp/test.\(ext)"))
    }

    /// 供单元测试：图片扩展名集合
    static var imageExtensionsForTesting: Set<String> { imageExtensions }
}

// MARK: - 远程图片缩略图（异步加载，NSCache 缓存）
private struct RemoteThumbnail: View {
    let urlString: String

    @State private var image: NSImage?
    @State private var didRequest = false
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else if loadFailed {
                fallback
            } else {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.12))
                    .redacted(reason: .placeholder)
            }
        }
        .onAppear {
            guard !didRequest else { return }
            didRequest = true
            if let cached = RemoteImageLoader.shared.cached(for: urlString) {
                image = cached
                return
            }
            RemoteImageLoader.shared.load(urlString: urlString) { loaded in
                if let img = loaded {
                    self.image = img
                } else {
                    self.loadFailed = true
                }
            }
        }
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.1)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "link")
                .font(.system(size: 14, weight: .light))
                .foregroundColor(.secondary.opacity(0.35))
        }
    }
}

// MARK: - 右键拦截器 —— 同步 popUpContextMenu，Esc 只按一次
private struct RightClickInterceptor: NSViewRepresentable {
    let onWillShow: () -> Void
    let onDidDismiss: () -> Void
    let onDelete: () -> Void
    let onPin: () -> Void

    func makeNSView(context: Context) -> _InterceptorView {
        let v = _InterceptorView()
        v.coord = context.coordinator
        return v
    }

    func updateNSView(_ nsView: _InterceptorView, context: Context) {
        nsView.coord = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onWillShow: onWillShow, onDidDismiss: onDidDismiss, onDelete: onDelete, onPin: onPin)
    }

    final class Coordinator: NSObject {
        let onWillShow: () -> Void
        let onDidDismiss: () -> Void
        let onDelete: () -> Void
        let onPin: () -> Void
        init(onWillShow: @escaping () -> Void, onDidDismiss: @escaping () -> Void, onDelete: @escaping () -> Void, onPin: @escaping () -> Void) {
            self.onWillShow = onWillShow; self.onDidDismiss = onDidDismiss; self.onDelete = onDelete; self.onPin = onPin
        }
        @objc func deleteAction() { onDelete() }
        @objc func pinAction() { onPin() }
    }
}

private final class _InterceptorView: NSView {
    var coord: RightClickInterceptor.Coordinator?

    override func rightMouseDown(with event: NSEvent) {
        guard let coord else { super.rightMouseDown(with: event); return }

        coord.onWillShow()

        let menu = NSMenu()
        let pinItem = NSMenuItem(title: "钉选", action: #selector(RightClickInterceptor.Coordinator.pinAction), keyEquivalent: "")
        pinItem.target = coord
        menu.addItem(pinItem)
        menu.addItem(.separator())
        let deleteItem = NSMenuItem(title: "删除", action: #selector(RightClickInterceptor.Coordinator.deleteAction), keyEquivalent: "")
        deleteItem.target = coord
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)

        coord.onDidDismiss()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let e = NSApp.currentEvent, e.type == .rightMouseDown { return self }
        return nil
    }
}

