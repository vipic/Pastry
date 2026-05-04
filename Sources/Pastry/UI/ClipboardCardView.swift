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
            } ?? self.extractFirstImage(from: html, baseURL: url)
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

    /// og:image 缺失时的降级方案：提取 HTML 中第一个有效 <img src>
    private func extractFirstImage(from html: String, baseURL: URL) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+src=[\"']([^\"']+)[\"']",
            options: .caseInsensitive
        ) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        for match in matches.prefix(10) {
            guard let captureRange = Range(match.range(at: 1), in: html) else { continue }
            let src = String(html[captureRange])

            // 跳过 data URI 和常见追踪像素（1×1）
            guard !src.hasPrefix("data:") else { continue }
            let lower = src.lowercased()
            if lower.contains("1x1") || lower.contains("pixel") || lower.contains("tracking") { continue }

            return resolveImageURL(src: src, baseURL: baseURL)
        }
        return nil
    }

    // MARK: — 向后兼容

    private func extractTitle(from html: String) -> String? {
        extractTitleTag(from: html) ?? extractMeta(from: html, tag: "og:title")
    }

    // MARK: — 测试入口

    static func extractMetaForTesting(from html: String, tag: String) -> String? {
        shared.extractMeta(from: html, tag: tag)
    }

    static func extractFirstImageForTesting(from html: String, baseURL: URL?) -> String? {
        shared.extractFirstImage(from: html, baseURL: baseURL ?? URL(string: "https://example.com")!)
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

    @ViewBuilder
    private var fileURLContent: some View {
        let urls = fileURLs
        if urls.count == 1 {
            if Self.isImageFile(urls[0]) {
                singleImageFilePreview(urls[0])
            } else {
                singleFilePreview(urls[0])
            }
        } else {
            fileURLList
        }
    }

    // MARK: - 文件预览（非图片单文件 → 系统图标）

    /// 单非图片文件：大系统图标 + 文件名（类 QuickLook 体验）
    private func singleFilePreview(_ url: URL) -> some View {
        let icon = systemIcon(for: url)
        return VStack(spacing: 4) {
            if let icon = icon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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

    /// NSWorkspace 文件图标缓存（避免重复实例化 NSImage）
    private func systemIcon(for url: URL) -> NSImage? {
        let cacheKey = "icon:\(url.path)" as NSString
        if let cached = Self.imageCache.object(forKey: cacheKey) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.imageCache.setObject(icon, forKey: cacheKey)
        return icon
    }

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif",
    ]

    private static func isImageFile(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// 单个图片文件：大缩略图预览（NSImage 加载 + NSCache 缓存，失败降级为文件图标）
    private func singleImageFilePreview(_ url: URL) -> some View {
        let cacheKey = url.path as NSString
        let nsImage: NSImage? = {
            if let cached = Self.imageCache.object(forKey: cacheKey) { return cached }
            if let loaded = NSImage(contentsOfFile: url.path) {
                Self.imageCache.setObject(loaded, forKey: cacheKey)
                return loaded
            }
            return nil
        }()
        return VStack(spacing: 6) {
            if let img = nsImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fallbackPreview
            }
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

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
        // 主题色同步查字典 O(1)
        self.themeColor = Color(nsColor: provider.themeColor(for: name))
        // 图标异步加载，占位 SF Symbol 不会闪白
        DispatchQueue.global(qos: .userInitiated).async {
            let icon = provider.icon(for: name)
            DispatchQueue.main.async {
                self.appIcon = icon
            }
        }
    }
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

