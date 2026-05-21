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

    @State private var linkPreviewTask: Task<Void, Never>?
    /// 链接预览版本号（递增触发重绘，配合计算属性从缓存读取）
    @State private var previewLoadTrigger = 0

    // 异步加载状态 — 避免主线程同步 I/O 触发 TCC 死锁
    @State private var asyncFilePreview: NSImage?
    @State private var asyncFileIcons: [URL: NSImage] = [:]
    @State private var missingFileURLs: Set<URL> = []


    private static let cardSize: CGFloat = 240
    private static let headerHeight: CGFloat = 48
    private static let appIconSize: CGFloat = 72

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
            .onAppear {
                loadAppInfo()
                fetchLinkPreviewIfNeeded()
            }
            .onChange(of: item.content) { old, _ in
                Self.imageCache.removeObject(forKey: old as NSString)
                fetchLinkPreviewIfNeeded()
            }
            .task(id: filePreviewTaskID) { await loadFilePreviewsIfNeeded() }
    }

    /// 卡片基础渲染（样式 + 内容，不含手势和生命周期）
    private var cardBase: some View {
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
                .stroke(lineWidth: 2.5)
                .foregroundStyle(cardBorderColor)
                .animation(.easeInOut(duration: 0.12), value: isSelected)
                .animation(.easeInOut(duration: 0.12), value: isHovered)
        )
        .overlay(alignment: .bottomTrailing) {
            if let idx = cmdBadgeIndex {
                cmdBadge(idx)
            }
        }
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .scaleEffect(didPaste ? 0.95 : 1.0)
        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: didPaste)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(didPaste ? Color.green : Color.clear, lineWidth: 2.5)
        )
        .animation(.easeOut(duration: 0.5), value: didPaste)
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 打开文件

    /// 可打开的 URL（文件路径或文本中的 URL）。多文件时返回第一个存在的文件，全缺失返回 nil。
    private var openableURL: URL? {
        switch item.sourceFormat {
        case .fileURL:
            return existingFileURLs.first
        case .image:
            let url = URL(fileURLWithPath: item.content)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        case .text, .rtf, .html:
            return detectedLink
        }
    }

    /// 是否为文本类（text / rtf / html）—— 可预览、可分享
    private var isTextType: Bool {
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
            if let url = detectedLink { return .link(url) }
            return .richText
        case .rtf:
            if isMultiURL { return .multiLink(detectedLinks) }
            if item.tags.isURL, let url = detectedLink { return .link(url) }
            if let url = detectedLink { return .link(url) }
            return .richText
        case .text:
            if isMultiURL { return .multiLink(detectedLinks) }
            if item.tags.isURL, let url = detectedLink { return .link(url) }
            if let url = detectedLink { return .link(url) }
            return .plainText
        }
    }

    /// 用默认应用打开（多文件/多链接时逐个打开所有存在的 URL）
    private func openItem() {
        if isMultiFile {
            let urls = existingFileURLs
            guard !urls.isEmpty else { return }
            OverlayPanelManager.shared.hide()
            for url in urls { NSWorkspace.shared.open(url) }
            return
        }
        if isMultiURL {
            let urls = detectedLinks
            guard !urls.isEmpty else { return }
            OverlayPanelManager.shared.hide()
            for url in urls { NSWorkspace.shared.open(url) }
            return
        }
        guard let url = openableURL else { return }
        OverlayPanelManager.shared.hide()
        NSWorkspace.shared.open(url)
    }

    /// 用指定应用打开
    private func openWithApp(_ appURL: URL) {
        guard let url = openableURL else { return }
        OverlayPanelManager.shared.hide()
        NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// 手动选择应用打开（"其他…" fallback）
    private func openWithOther() {
        guard let url = openableURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n["panel.open_prompt"]
        panel.message = L10n["panel.open_message"]
        OverlayPanelManager.shared.hide()
        panel.begin { response in
            guard response == .OK, let appURL = panel.url else { return }
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// 在访达中显示文件所在位置
    private func showInFinder() {
        guard let url = openableURL else { return }
        OverlayPanelManager.shared.hide()
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 构建系统的"打开方式"子菜单
    private func buildOpenWithSubmenu(for handler: _MenuHandler) -> NSMenu? {
        guard let url = openableURL else { return nil }
        let submenu = NSMenu()
        var addedApp = false

        if #available(macOS 12.0, *) {
            let appURLs = NSWorkspace.shared.urlsForApplications(toOpen: url)
            for appURL in appURLs {
                let name = FileManager.default.displayName(atPath: appURL.path)
                    .replacingOccurrences(of: ".app", with: "")
                let item = NSMenuItem(title: name, action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
                item.target = handler
                item.representedObject = appURL
                item.image = NSWorkspace.shared.icon(forFile: appURL.path)
                item.image?.size = NSSize(width: 16, height: 16)
                submenu.addItem(item)
                addedApp = true
            }
        }

        if addedApp { submenu.addItem(.separator()) }
        let otherItem = NSMenuItem(title: L10n["context.open_with_other"], action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        otherItem.target = handler
        otherItem.representedObject = "openWithOther" as NSString
        submenu.addItem(otherItem)
        return submenu
    }

    /// 卡片状态边框颜色
    private var cardBorderColor: Color {
        if isSelected { return .blue }
        if isHovered { return .white.opacity(0.15) }
        return .clear
    }

    /// ⌘+数字角标 — 按住 ⌘ 时在卡片右下角显示序号
    private func cmdBadge(_ idx: Int) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black.opacity(0.45))
            Text("\(idx)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 18, height: 18)
        .padding(6)
    }

    // MARK: - 顶部栏（始终使用主题色背景）

    private var topBar: some View {
        HStack(spacing: 0) {
            Image(systemName: item.sourceFormat.iconName)
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
            } else if item.isHandoff {
                // Handoff 来源：SF Symbol 图标
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: Self.appIconSize * 0.55, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Color.clear
            }
        }
        .frame(width: Self.appIconSize, height: Self.appIconSize)
        .offset(x: 12, y: (Self.headerHeight - Self.appIconSize) / 2 - 2)
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
            else if let url = detectedLink { linkContent(url) }
            else { textPreview }
        }
    }

    // MARK: - 链接预览（缩略图 + 标题 + 描述 + 域名 —— 始终用卡片框架，字段独立降级）

    @ViewBuilder
    private func linkContent(_ url: URL) -> some View {
        let preview = linkPreview
        let title: String = {
            if let t = preview?.title, !t.isEmpty { return t }
            return url.host ?? url.absoluteString
        }()
        let desc: String? = {
            if let d = preview?.description, !d.isEmpty { return d }
            return nil
        }()
        let host: String = {
            if let h = preview?.host, !h.isEmpty { return h }
            return url.host ?? ""
        }()

        VStack(spacing: 0) {
            linkThumbnail(imageURL: preview?.imageURL)
                .frame(height: 115)  // 1.91:1 at 220px content width
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let desc = desc {
                    Text(desc)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Text(host)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(0.6))
                    .lineLimit(1)
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
        let nsImage: NSImage? = {
            // 缓存命中 (已在后台加载过)
            let key = item.content as NSString
            if let cached = Self.imageCache.object(forKey: key) { return cached }
            // 异步加载中或失败 → 返回 nil，用 asyncFilePreview 的 placeholder
            return nil
        }()
        VStack(spacing: 0) {
            if let img = asyncFilePreview ?? nsImage {
                Image(nsImage: img)
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
        VStack(alignment: .leading, spacing: 0) {
            // 计数标签
            Text(String(format: L10n["card.multi_links"], urls.count))
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, 4)

            ForEach(Array(urls.prefix(6).enumerated()), id: \.offset) { idx, url in
                HStack(spacing: 6) {
                    // 域名首字母图标
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 20, height: 20)
                        Text(String(url.host?.prefix(1).uppercased() ?? "?"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(url.host ?? url.absoluteString)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(url.path.isEmpty ? "/" : url.path)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(idx % 2 == 0 ? 0.02 : 0))
                )
            }

            if urls.count > 6 {
                Text(String(format: L10n["card.extra_links"], urls.count - 6))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        } else if isMultiURL {
            multiLinkContent(detectedLinks)
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
                guard let preview else { return }
                // 持久化抓取的标题（空标题不覆盖已有值）
                let title = preview.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    StoreManager.shared.updateLinkTitle(item.id, linkTitle: title)
                }
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

    /// 所有实际存在于磁盘的文件 URL（从异步加载的 missingFileURLs 反推，不阻塞主线程）
    private var existingFileURLs: [URL] {
        guard item.sourceFormat == .fileURL || item.sourceFormat == .image else { return [] }
        // 异步检测还没跑完 → 暂时当作全部存在（不触发 TCC）
        return fileURLs.filter { !missingFileURLs.contains($0) }
    }

    /// 是否为多文件条目
    private var isMultiFile: Bool {
        item.sourceFormat == .fileURL && item.content.contains("\n")
    }

    /// 内容中的全部 http/https URL
    private var detectedLinks: [URL] {
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
    private var isMultiURL: Bool {
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

    /// 右键菜单（使用系统 NSMenu.popUpContextMenu）
    private func showContextMenu(with event: NSEvent, for view: NSView) {
        let menu = NSMenu()
        let handler = _MenuHandler { title, object in
            // representedObject 传递的动作标识优先
            if let appURL = object as? URL {
                self.openWithApp(appURL)
                return
            }
            if let tag = object as? NSString {
                switch tag {
                case "pin":
                    onPin(item, selectedIds)
                case "open":       openItem()
                case "show_in_finder": showInFinder()
                case "preview":    previewItem(from: view)
                case "share":      shareItem(from: view)
                case "delete":     onDelete(item)
                default: break
                }
                return
            }
            // fallback: title-based (用于"打开方式"子菜单项等)
            if title == L10n["context.open_with_other"] {
                self.openWithOther()
            }
        }

        let pinTitle = item.isPinned ? L10n["context.unpin"] : L10n["context.pin"]
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        pinItem.target = handler
        pinItem.representedObject = "pin" as NSString
        pinItem.image = NSImage(systemSymbolName: item.isPinned ? "pin.slash" : "pin", accessibilityDescription: nil)
        menu.addItem(pinItem)

        let isFileBased = item.sourceFormat == .fileURL || item.sourceFormat == .image
        let hasAnyFile = isFileBased && !existingFileURLs.isEmpty

        // Open / Open With — 文件类始终显示（缺失时灰显）
        let isTextLike = item.sourceFormat == .text || item.sourceFormat == .rtf || item.sourceFormat == .html
        let showOpenSection = isFileBased || item.tags.isURL
            || (isTextLike && openableURL != nil)

        if showOpenSection {
            menu.addItem(.separator())
            let openEnabled = hasAnyFile || (!isFileBased && openableURL != nil)
            let oItem = NSMenuItem(title: L10n["context.open"], action: openEnabled ? #selector(_MenuHandler.invoke(_:)) : nil, keyEquivalent: "")
            oItem.target = openEnabled ? handler : nil
            oItem.representedObject = openEnabled ? "open" as NSString : nil
            oItem.image = NSImage(systemSymbolName: "arrow.up.forward.app", accessibilityDescription: nil)
            oItem.isEnabled = openEnabled
            menu.addItem(oItem)

            let owEnabled = !isMultiFile && (hasAnyFile || (!isFileBased && openableURL != nil))
            let owItem = NSMenuItem(title: L10n["context.open_with"], action: nil, keyEquivalent: "")
            owItem.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: nil)
            owItem.isEnabled = owEnabled
            if owEnabled, let submenu = buildOpenWithSubmenu(for: handler) {
                menu.setSubmenu(submenu, for: owItem)
            }
            menu.addItem(owItem)

            // 在访达中显示（仅文件类有效）
            if isFileBased && hasAnyFile {
                let finderItem = NSMenuItem(title: L10n["context.show_in_finder"], action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
                finderItem.target = handler
                finderItem.representedObject = "show_in_finder" as NSString
                finderItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                menu.addItem(finderItem)
            }
        }

        // Preview / Share — 文件/图片：按存在性；文本/RTF/HTML/链接：始终可用
        let previewEnabled: Bool = {
            if isMultiFile { return false }
            if isFileBased { return hasAnyFile }
            if case .missing = displayMode { return false }
            return true  // 文本/RTF/HTML/链接均可预览
        }()
        let shareEnabled: Bool = {
            if isFileBased { return hasAnyFile }
            if case .missing = displayMode { return false }
            return true  // 文本/RTF/HTML/链接均可分享
        }()

        menu.addItem(.separator())

            let pItem = NSMenuItem(title: L10n["context.preview"], action: previewEnabled ? #selector(_MenuHandler.invoke(_:)) : nil, keyEquivalent: "")
            pItem.target = previewEnabled ? handler : nil
            pItem.representedObject = previewEnabled ? "preview" as NSString : nil
            pItem.image = NSImage(systemSymbolName: "eye", accessibilityDescription: nil)
            pItem.isEnabled = previewEnabled
            menu.addItem(pItem)

            let sItem = NSMenuItem(title: L10n["context.share"], action: shareEnabled ? #selector(_MenuHandler.invoke(_:)) : nil, keyEquivalent: "")
            sItem.target = shareEnabled ? handler : nil
            sItem.representedObject = shareEnabled ? "share" as NSString : nil
            sItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
            sItem.isEnabled = shareEnabled
            menu.addItem(sItem)

        menu.addItem(.separator())
        let deleteItem = NSMenuItem(title: L10n["context.delete"], action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        deleteItem.target = handler
        deleteItem.representedObject = "delete" as NSString
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// Quick Look 预览（popover 浮动预览，三角指向卡片，面板保持可见）
    private func previewItem(from sourceView: NSView) {
        let metadata: QLPreviewHelper.PreviewMetadata

        if let url = openableURL {
            switch item.sourceFormat {
            case .fileURL:
                let fileName = (item.content as NSString).lastPathComponent
                let ext = (fileName as NSString).pathExtension.uppercased()
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: url, displayName: fileName,
                    fileType: ext.isEmpty ? L10n["filetype.file"] : ext,
                    infoText: fileName, isLocalFile: true
                )
            case .image:
                let fileName = (item.content as NSString).lastPathComponent
                let ext = (fileName as NSString).pathExtension.uppercased()
                // 尝试从原始文件生成高清临时预览（.orig 无扩展名，Quick Look 无法直接渲染）
                let previewURL: URL = {
                    guard let origPath = ImageCacheManager.shared.originalPath(forThumbnail: item.content),
                          let origData = try? Data(contentsOf: URL(fileURLWithPath: origPath)),
                          let origImage = NSImage(data: origData),
                          let tiff = origImage.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:])
                    else { return url }
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("pastry_preview_\(UUID().uuidString.prefix(8)).png")
                    try? png.write(to: tmp)
                    return tmp
                }()
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: previewURL, displayName: fileName,
                    fileType: ext.isEmpty ? L10n["filetype.image"] : ext,
                    infoText: fileName, isLocalFile: true
                )
            case .text, .rtf, .html:
                let host = url.host ?? ""
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: url, displayName: host,
                    fileType: L10n["filetype.link"],
                    infoText: url.absoluteString, isLocalFile: false
                )
            }
        } else if isTextType {
            // 纯文本 / RTF / HTML：写临时文件供 QLPreviewView 预览
            let ext: String
            let typeLabel: String
            switch item.sourceFormat {
            case .rtf:  ext = "rtf";  typeLabel = "RTF"
            case .html: ext = "html"; typeLabel = "HTML"
            default:    ext = "txt";  typeLabel = L10n["filetype.text"]
            }
            let tmpDir = FileManager.default.temporaryDirectory
            let tmpFile = tmpDir.appendingPathComponent("pastry_preview_\(UUID().uuidString.prefix(8)).\(ext)")
            let fullContent = DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content

            // RTF: 写原始二进制数据，不是纯文本
            if item.sourceFormat == .rtf, let rawData = item.rawFormatData {
                try? rawData.write(to: tmpFile)
            } else {
                try? fullContent.write(to: tmpFile, atomically: true, encoding: .utf8)
            }

            let charCount = fullContent.count
            let wordCount = fullContent.split { $0.isWhitespace || $0.isNewline }.count
            let lineCount = fullContent.split(separator: "\n", omittingEmptySubsequences: false).count

            metadata = QLPreviewHelper.PreviewMetadata(
                url: tmpFile, displayName: String(format: L10n["preview.title"], typeLabel),
                fileType: typeLabel,
                infoText: String(format: L10n["preview.info"], charCount, wordCount, lineCount),
                isLocalFile: true
            )
        } else {
            return
        }

        QLPreviewHelper.shared.showPreview(metadata: metadata, from: sourceView)
    }

    /// 系统分享面板
    private func shareItem(from view: NSView) {
        let items: [Any]
        if isMultiFile {
            let urls = existingFileURLs
            guard !urls.isEmpty else { return }
            items = urls
        } else if let url = openableURL {
            items = [url]
        } else if isTextType {
            items = [DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content]
        } else {
            return
        }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
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
            let url = URL(fileURLWithPath: item.content)
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
