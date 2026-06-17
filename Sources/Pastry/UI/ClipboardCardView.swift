import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import Quartz

// MARK: - 剪贴板卡片视图
struct ClipboardCardView: View {

    let item: ClipboardItem
    let isSelected: Bool
    let cmdBadgeIndex: Int?
    @Binding var selectedIds: Set<UUID>
    let onTap: (ClipboardItem) -> Void
    let onPin: (ClipboardItem, Set<UUID>) -> Void
    let onDelete: (ClipboardItem) -> Void

    @State private var appIcon: NSImage?
    @State private var themeColor: Color = .accentColor
    @State private var didPaste = false
    @State private var isHovered = false

    /// 链接预览版本号（递增触发重绘，配合计算属性从缓存读取）
    @State private var previewLoadTrigger = 0

    // 异步加载状态 — 避免主线程同步 I/O 触发 TCC 死锁
    @State private var asyncFilePreview: NSImage?
    @State private var asyncFileIcons: [URL: NSImage] = [:]
    @State private var missingFileURLs: Set<URL> = []

    /// 路径 → NSImage 缓存，避免重绘时重复创建实例导致闪烁
    private nonisolated(unsafe) static let imageCache = NSCache<NSString, NSImage>()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    var body: some View {
        cardBase
            .onHover { isHovered = $0 }
            .onTapGesture {
                let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
                let cmdDown = flags.contains(.command)
                let shiftDown = flags.contains(.shift)
                if cmdDown {
                    onTap(item)
                } else if shiftDown {
                    onTap(item)
                } else if isSelected {
                    pasteItem()
                } else {
                    onTap(item)
                }
            }
            .overlay(
                RightClickDetector { view, event in
                    showContextMenu(with: event, for: view)
                }
            )
            .onAppear { loadAppInfo() }
            .task(id: item.id) { await fetchLinkPreviewIfNeeded() }
            .onChange(of: item.content) { old, _ in
                Self.imageCache.removeObject(forKey: old as NSString)
            }
            .task(id: filePreviewTaskID) { await loadFilePreviewsIfNeeded() }
    }

    /// 卡片基础渲染（样式 + 内容，不含手势和生命周期）
    private var cardBase: some View {
        VStack(spacing: 0) {
            topBar
            contentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, UIConstants.Card.contentHorizontalPadding)
                .padding(.vertical, UIConstants.Card.contentVerticalPadding)
            footerBar
                .padding(.horizontal, UIConstants.Card.contentHorizontalPadding)
                .padding(.bottom, UIConstants.Card.footerBottomPadding)
        }
        .frame(width: UIConstants.Card.size, height: UIConstants.Card.size)
        .background(Color(nsColor: NSColor.windowBackgroundColor))
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius, style: .continuous)
                .stroke(cardIdleBorderColor, lineWidth: 0.8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius, style: .continuous)
                .stroke(cardSelectedGlowColor, lineWidth: 5)
                .blur(radius: 1.6)
                .opacity(isSelected ? 1 : 0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius - 2, style: .continuous)
                .stroke(.white.opacity(isSelected ? 0.42 : 0), lineWidth: 1)
                .padding(3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius, style: .continuous)
                .stroke(lineWidth: UIConstants.Card.selectedBorderWidth)
                .foregroundStyle(cardBorderColor)
                .animation(.easeInOut(duration: UIConstants.Card.animationDuration), value: isSelected)
                .animation(.easeInOut(duration: UIConstants.Card.animationDuration), value: isHovered)
        )
        .overlay(alignment: .bottomTrailing) {
            if let idx = cmdBadgeIndex {
                cmdBadge(idx)
                    .transition(.scale(scale: 0.74, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: UIConstants.Card.animationDuration), value: isSelected)
        .animation(.easeInOut(duration: UIConstants.Card.animationDuration), value: isHovered)
        .scaleEffect(didPaste ? UIConstants.Card.pasteScale : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: didPaste)
        .overlay(
            RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius, style: .continuous)
                .stroke(didPaste ? Color.green : Color.clear, lineWidth: UIConstants.Card.selectedBorderWidth)
        )
        .animation(.easeOut(duration: 0.5), value: didPaste)
        .contentShape(RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius))
    }

    // MARK: - 打开文件

    /// 可打开的 URL（文件路径或文本中的 URL）。多文件时返回第一个存在的文件，全缺失返回 nil。
    var openableURL: URL? {
        switch item.sourceFormat {
        case .fileURL:
            return existingFileURLs.first
        case .image:
            return imageOpenableURL
        case .text, .rtf, .html:
            return detectedLink
        }
    }

    /// 是否为文本类（text / rtf / html）—— 可预览、可分享
    var isTextType: Bool {
        item.sourceFormat == .text || item.sourceFormat == .rtf || item.sourceFormat == .html || item.tags.isURL
    }

    // MARK: - DisplayMode（统一切换展示类型）

    /// 从来源格式和语义标记派生展示模式
    var displayMode: DisplayMode {
        switch item.sourceFormat {
        case .image:
            return (!missingFileURLs.isEmpty || item.tags.isMissing) ? .missing : .image
        case .fileURL:
            if item.tags.isMultiFile { return .multiFile }
            return item.tags.isMissing ? .missing : .singleFile
        case .html:
            if item.tags.hasSegments { return .mixedMedia }
            if isMultiURL { return .multiLink(detectedLinks) }
            if item.tags.isURL, let url = detectedLink { return .link(url) }
            return .richText
        case .rtf:
            if isMultiURL { return .multiLink(detectedLinks) }
            if item.tags.isURL, let url = detectedLink { return .link(url) }
            return .richText
        case .text:
            if isMultiURL { return .multiLink(detectedLinks) }
            if item.tags.isURL, let url = detectedLink { return .link(url) }
            return .plainText
        }
    }

    /// 卡片状态边框颜色
    private var cardBorderColor: Color {
        if isSelected { return cardAccentColor.opacity(0.88) }
        if isHovered { return .white.opacity(0.30) }
        return .clear
    }

    private var cardIdleBorderColor: Color {
        .white.opacity(0.42)
    }

    private var cardSelectedGlowColor: Color {
        cardAccentColor.opacity(0.28)
    }

    private var cardAccentColor: Color {
        Color(red: 0.85, green: 0.62, blue: 0.26)
    }

    private var cardAccentStrongColor: Color {
        Color(red: 0.72, green: 0.45, blue: 0.15)
    }

    /// ⌘+数字角标 — 按住 ⌘ 时在卡片右下角显示序号
    private func cmdBadge(_ idx: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.89, green: 0.70, blue: 0.39),
                            Color(red: 0.76, green: 0.48, blue: 0.19)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(cardAccentStrongColor.opacity(0.52), lineWidth: 1)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(.white.opacity(0.34), lineWidth: 1)
                            .padding(1)
                    }
                )
            Text("\(idx)")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.23, green: 0.15, blue: 0.06))
        }
        .frame(width: 24, height: 24)
        .shadow(color: Color(red: 0.38, green: 0.20, blue: 0.08).opacity(0.28), radius: 7, x: 0, y: 4)
        .shadow(color: .white.opacity(0.22), radius: 0, x: 0, y: 1)
        .padding(7)
    }

    // MARK: - 顶部栏（始终使用主题色背景）

    private var topBar: some View {
        HStack(spacing: 0) {
            Image(systemName: item.sourceFormat.iconName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .padding(.leading, 10)

            Text(cardTypeLabel)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.76))
                .lineLimit(1)
                .padding(.leading, 5)

            Spacer()
        }
        .frame(height: UIConstants.Card.headerHeight)
        .background(
            LinearGradient(
                colors: [themeColor.opacity(0.74), themeColor.opacity(0.58)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(Color.white.opacity(0.06))
        .clipped()
        .overlay(alignment: .topTrailing) {
            appIconOverlay
        }
    }

    private var cardTypeLabel: String {
        if item.tags.isURL { return L10n["filetype.link"] }
        if item.tags.isMultiFile { return L10n["filter.type.fileURL"] }
        return item.sourceFormat.label
    }

    /// 应用图标 — 60×60，标题栏内垂直居中，右移 50% 让一半溢出卡片被裁切
    @ViewBuilder
    private var appIconOverlay: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.Card.cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
            } else if item.isHandoff {
                // Handoff 来源：SF Symbol 图标
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: UIConstants.Card.appIconSize * 0.55, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Color.clear
            }
        }
        .frame(width: UIConstants.Card.appIconSize, height: UIConstants.Card.appIconSize)
        .offset(x: 12, y: (UIConstants.Card.headerHeight - UIConstants.Card.appIconSize) / 2 - 2)
        .animation(.easeInOut(duration: 0.25), value: appIcon != nil)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var contentArea: some View {
        switch item.sourceFormat {
        case .image:   imagePreview
        case .fileURL: fileURLContent
        case .html:    htmlWithImagePreview
        default:
            if isMultiURL { multiLinkContent(detectedLinks) }
            else if item.tags.isURL, let url = detectedLink { linkContent(url) }
            else { textPreview }
        }
    }

    // MARK: - 链接预览（缩略图 + 标题 + 描述 + 域名 —— 始终用卡片框架，字段独立降级）

    @ViewBuilder
    private func linkContent(_ url: URL) -> some View {
        let text = Self.linkCardText(url: url, preview: linkPreview)
        ClipboardLinkContentView(preview: linkPreview, text: text)
    }

    @ViewBuilder
    private var imagePreview: some View {
        let nsImage: NSImage? = {
            // 缓存命中 (已在后台加载过)
            let key = item.content as NSString
            if let cached = Self.imageCache.object(forKey: key) { return cached }
            // 异步加载中或失败 → 返回 nil，用 asyncFilePreview 的 placeholder
            return nil
        }()
        ClipboardImageContentView(image: asyncFilePreview ?? nsImage, annotation: item.textAnnotation)
    }

    // MARK: - 文件预览

    /// 文件预览策略（扩展：加 case + 在 filePreviewStyle 中匹配即可）
    enum FilePreviewStyle {
        case thumbnail   // 图片 → NSImage 缩略图
        case systemIcon  // 其他 → NSWorkspace 系统图标
    }

    nonisolated static func filePreviewStyle(for url: URL) -> FilePreviewStyle {
        if imageExtensions.contains(url.pathExtension.lowercased()) { return .thumbnail }
        return .systemIcon
    }

    @ViewBuilder
    private var fileURLContent: some View {
        FilePreviewContent(
            urls: fileURLs,
            missingURLs: missingFileURLs,
            thumbnailImage: asyncFilePreview,
            fileIcons: asyncFileIcons,
            styleForURL: Self.filePreviewStyle(for:)
        )
    }

    private var filePreviewTaskID: String {
        "\(item.id.uuidString):\(item.sourceFormat.rawValue):\(item.content)"
    }

    /// 异步加载文件预览 — 避免主线程同步 I/O 触发 TCC 权限弹窗死锁
    private func loadFilePreviewsIfNeeded() async {
        asyncFilePreview = nil
        asyncFileIcons = [:]
        missingFileURLs = []

        guard item.sourceFormat == .image || item.sourceFormat == .fileURL else { return }

        // 图片类型 — 异步加载 NSImage
        if item.sourceFormat == .image {
            let path = item.content
            let key = path as NSString

            // 文件已删除 → 清除缓存，显示缺失状态
            if !FileManager.default.fileExists(atPath: path) {
                Self.imageCache.removeObject(forKey: key)
                await MainActor.run {
                    missingFileURLs.insert(URL(fileURLWithPath: path))
                    asyncFilePreview = nil
                }
                return
            }

            if let cached = Self.imageCache.object(forKey: key) {
                guard !Task.isCancelled else { return }
                asyncFilePreview = cached
                return
            }
            let imageLoadTask = Task.detached(priority: .userInitiated, operation: { () -> NSImage? in
                guard !Task.isCancelled else { return nil }
                return NSImage(contentsOfFile: path)
            })
            let img = await withTaskCancellationHandler {
                await imageLoadTask.value
            } onCancel: {
                imageLoadTask.cancel()
            }
            guard !Task.isCancelled else { return }
            if let img = img {
                Self.imageCache.setObject(img, forKey: key)
                asyncFilePreview = img
            }
            return
        }

        // 文件 URL 类型 — 异步检查存在性并加载图标
        if item.sourceFormat == .fileURL {
            let urls = fileURLs
            let fileLoadTask = Task.detached(priority: .userInitiated, operation: { () -> (missing: Set<URL>, icons: [(URL, NSImage, Bool)]) in
                var missing: Set<URL> = []
                var icons: [(URL, NSImage, Bool)] = []
                for url in urls {
                    guard !Task.isCancelled else { break }
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        missing.insert(url)
                        continue
                    }
                    let style = Self.filePreviewStyle(for: url)
                    let cacheKey: NSString
                    let needsThumbnail: Bool
                    switch style {
                    case .thumbnail:
                        cacheKey = url.path as NSString
                        needsThumbnail = true
                    case .systemIcon:
                        cacheKey = "icon:\(url.path)" as NSString
                        needsThumbnail = false
                    }

                    if let cached = Self.imageCache.object(forKey: cacheKey) {
                        icons.append((url, cached, needsThumbnail))
                        continue
                    }

                    let loaded: NSImage? = needsThumbnail
                        ? NSImage(contentsOfFile: url.path)
                        : NSWorkspace.shared.icon(forFile: url.path)

                    if let loaded = loaded {
                        Self.imageCache.setObject(loaded, forKey: cacheKey)
                        icons.append((url, loaded, needsThumbnail))
                    }
                }
                return (missing, icons)
            })
            let result = await withTaskCancellationHandler {
                await fileLoadTask.value
            } onCancel: {
                fileLoadTask.cancel()
            }

            guard !Task.isCancelled else { return }
            missingFileURLs = result.missing
            for (url, icon, isThumbnail) in result.icons {
                if isThumbnail { asyncFilePreview = icon }
                else { asyncFileIcons[url] = icon }
            }
        }
    }

    // MARK: - 文件列表（多文件 → 小图标行）

    // MARK: - 多链接列表（多个 URL 换行复制时的展示）

    @ViewBuilder
    private func multiLinkContent(_ urls: [URL]) -> some View {
        ClipboardMultiLinkContentView(urls: urls)
    }

    nonisolated static let imageExtensions: Set<String> = [
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
            ClipboardHTMLSegmentsContentView(segments: segs)
        } else if isMultiURL {
            multiLinkContent(detectedLinks)
        } else if item.tags.isURL, let url = detectedLink {
            linkContent(url)
        } else {
            textPreview
        }
    }

    // MARK: - 底部栏

    private var footerBar: some View {
        HStack(spacing: 4) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(themeColor)
                Text("·").font(.caption2).foregroundColor(.secondary)
            }
            Text(formattedTime).font(.system(size: 9)).foregroundColor(.secondary)
            if item.isHandoff {
                Text("·").font(.caption2).foregroundColor(.secondary)
                Text(L10n["card.handoff_label"]).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
            } else if let app = item.appName {
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
        if diff < 60 { return L10n["time.just_now"] }
        else if diff < 3600 { return String(format: L10n["time.minutes_ago"], Int(diff / 60)) }
        else if diff < 86400 { return String(format: L10n["time.hours_ago"], Int(diff / 3600)) }
        else if diff < 604800 { return String(format: L10n["time.days_ago"], Int(diff / 86400)) }
        if Self.timeFormatter.dateFormat != L10n["time.date_format"] {
            Self.timeFormatter.dateFormat = L10n["time.date_format"]
        }
        return Self.timeFormatter.string(from: item.timestamp)
    }

    // MARK: - 链接

    struct LinkCardText: Equatable {
        let title: String
        let description: String?
        let host: String
        let titleLineLimit: Int
    }

    static func linkCardText(url: URL, preview: LinkPreviewLoader.Preview?) -> LinkCardText {
        let host = normalizedLinkText(preview?.host) ?? url.host ?? ""
        let rawTitle = normalizedLinkText(preview?.title)
        let rawDescription = normalizedLinkText(preview?.description)
        let title = sanitizedLinkTitle(rawTitle, host: host) ?? fallbackLinkTitle(for: url)
        let usesCompactDescription = title.count <= 34
        let description = usesCompactDescription ? rawDescription : nil

        return LinkCardText(
            title: title,
            description: description,
            host: host,
            titleLineLimit: description == nil ? 2 : 1
        )
    }

    private static func normalizedLinkText(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private static func sanitizedLinkTitle(_ title: String?, host: String) -> String? {
        guard var title else { return nil }
        let bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let siteNames = [host, bareHost]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for site in siteNames {
            for separator in [" - ", " | ", " · ", " — "] where title.hasSuffix(separator + site) {
                title.removeLast((separator + site).count)
                return normalizedLinkText(title)
            }
        }
        return title
    }

    private static func fallbackLinkTitle(for url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return host }
        return "\(host)/\(path)"
    }

    private var detectedLink: URL? {
        let trimmed = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPS(url) }
        if let d = Self.linkDetector,
           let m = d.firstMatch(in: item.content, range: NSRange(item.content.startIndex..., in: item.content)),
           let url = m.url, let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPS(url) }
        return nil
    }

    /// NSDataDetector 返回 http:// 裸域名时升级为 https://，避免重定向和不必要的 HTTP 请求
    private func upgradeToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = "https"
        return c?.url ?? url
    }

    /// 链接预览：缓存优先，body 求值时同步读取，零帧延迟
    private var linkPreview: LinkPreviewLoader.Preview? {
        _ = previewLoadTrigger
        guard let url = detectedLink else { return nil }
        return LinkPreviewLoader.shared.cachedPreview(for: url.absoluteString)
    }

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func fetchLinkPreviewIfNeeded() async {
        guard let url = detectedLink else { return }
        if linkPreview != nil { return }

        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }

        await withCheckedContinuation { continuation in
            LinkPreviewLoader.shared.load(url: url) { preview in
                guard let preview else { continuation.resume(); return }
                let title = preview.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    StoreManager.shared.updateLinkTitle(item.id, linkTitle: title)
                }
                self.previewLoadTrigger &+= 1
                continuation.resume()
            }
        }
    }

    // MARK: - 辅助

    private var previewText: String {
        let t = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > 240 ? String(t.prefix(240)) + "…" : t
    }

    var fileURLs: [URL] {
        item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// 所有实际存在于磁盘的文件 URL（从异步加载的 missingFileURLs 反推，不阻塞主线程）
    var existingFileURLs: [URL] {
        guard item.sourceFormat == .fileURL || item.sourceFormat == .image else { return [] }
        if item.sourceFormat == .image, !item.content.contains("\n") {
            return imageOpenableURL.map { [$0] } ?? []
        }
        // 异步检测还没跑完 → 暂时当作全部存在（不触发 TCC）
        return fileURLs.filter { !missingFileURLs.contains($0) }
    }

    private var imageOpenableURL: URL? {
        if item.content.contains("\n") {
            return fileURLs.first { FileManager.default.fileExists(atPath: $0.path) }
        }
        let preferredPath = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
        let url = URL(fileURLWithPath: preferredPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// 是否为多文件条目
    var isMultiFile: Bool {
        item.sourceFormat == .fileURL && item.content.contains("\n")
    }

    /// 内容中的全部 http/https URL
    var detectedLinks: [URL] {
        guard item.tags.isURL else { return [] }
        let lines = item.content.components(separatedBy: "\n")
        return lines.compactMap { line -> URL? in
            guard let url = URL(string: line.trimmingCharacters(in: .whitespaces)),
                  let s = url.scheme,
                  s == "http" || s == "https" else { return nil }
            return upgradeToHTTPS(url)
        }
    }

    /// 是否为多链接条目
    var isMultiURL: Bool {
        item.tags.isURL && detectedLinks.count > 1
    }

    private func loadAppInfo() {
        let provider = AppIconProvider.shared
        let name: String? = item.isHandoff ? "📱 Handoff" : item.appName
        self.themeColor = Color(nsColor: provider.themeColor(for: name))
        if item.isHandoff {
            // Handoff 来源：用 SF Symbol
            self.appIcon = nil  // 强制用 SF Symbol
            return
        }
        Task {
            let icon = await Task.detached(priority: .userInitiated) {
                provider.icon(for: name)
            }.value
            guard !Task.isCancelled else { return }
            self.appIcon = icon
        }
    }

    private func pasteItem() {
        didPaste = true
        Task { await OverlayPanelManager.shared.hideAndPaste(item) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            didPaste = false
        }
    }

    // MARK: - 测试入口

    /// 供单元测试：扩展名 → 预览策略映射
    static func filePreviewStyleForTesting(extension ext: String) -> FilePreviewStyle {
        filePreviewStyle(for: URL(fileURLWithPath: "/tmp/test.\(ext)"))
    }

    /// 供单元测试：图片扩展名集合
    static var imageExtensionsForTesting: Set<String> { imageExtensions }

    /// 供单元测试：contentType → 是否为文本类（.text / .rtf / .html）
    static func isTextTypeForTesting(sourceFormat: SourceFormat) -> Bool {
        sourceFormat == .text || sourceFormat == .rtf || sourceFormat == .html
    }

    /// 供单元测试：文本统计（字符数 / 单词数 / 行数）
    static func textStatisticsForTesting(_ text: String) -> (chars: Int, words: Int, lines: Int) {
        let chars = text.count
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return (chars, words, lines)
    }

    /// 供单元测试：多选条目 → 拼接文本（hideAndPasteMultiple 的核心逻辑）
    static func multiSelectTextForTesting(_ items: [ClipboardItem]) -> String {
        items.compactMap { item -> String? in
            switch item.sourceFormat {
            case .text, .rtf, .html, .fileURL: return item.content
            default: return nil
            }
        }.joined(separator: "\n")
    }

    /// 供单元测试：单选拖拽 → 按类型返回 (isFile: Bool, content: String)
    static func dragPayloadForTesting(_ item: ClipboardItem) -> (isFile: Bool, content: String) {
        switch item.sourceFormat {
        case .image, .fileURL:
            return (true, item.content)
        default:
            return (false, item.content)
        }
    }

    /// 供单元测试：content → 是否为多文件条目
    static func isMultiFileForTesting(content: String, sourceFormat: SourceFormat) -> Bool {
        sourceFormat == .fileURL && content.contains("\n")
    }

    /// 供单元测试：item → openableURL 计算（单文件/多文件兼容）
    static func openableURLForTesting(_ item: ClipboardItem) -> URL? {
        switch item.sourceFormat {
        case .fileURL:
            let urls = item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            return urls.first { FileManager.default.fileExists(atPath: $0.path) }
        case .image:
            let path = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
            let url = URL(fileURLWithPath: path)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .text, .rtf, .html:
            return detectedLinkForTesting(in: item.content)
        }
    }

    /// 供单元测试：从文本中检测 URL（与 detectedLink 逻辑一致）
    private static func detectedLinkForTesting(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPSTesting(url) }
        if let d = linkDetector,
           let m = d.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let url = m.url, let s = url.scheme, ["http", "https"].contains(s.lowercased()) { return upgradeToHTTPSTesting(url) }
        return nil
    }

    /// 测试专用：http → https 升级
    private static func upgradeToHTTPSTesting(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }
        var c = URLComponents(url: url, resolvingAgainstBaseURL: false)
        c?.scheme = "https"
        return c?.url ?? url
    }

}
