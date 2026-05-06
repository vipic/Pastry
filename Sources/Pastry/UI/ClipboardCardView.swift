import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import Quartz

// MARK: - 剪贴板卡片视图
struct ClipboardCardView: View {

    let item: ClipboardItem
    let isSelected: Bool
    let cmdBadgeIndex: Int?
    let onTap: (ClipboardItem) -> Void
    let onPin: (ClipboardItem) -> Void

    @State private var appIcon: NSImage?
    @State private var themeColor: Color = .accentColor
    @State private var didPaste = false
    @State private var isHovered = false

    @State private var linkPreviewTask: Task<Void, Never>?
    /// 链接预览版本号（递增触发重绘，配合计算属性从缓存读取）
    @State private var previewLoadTrigger = 0

    private static let cardSize: CGFloat = 240
    private static let headerHeight: CGFloat = 48
    private static let appIconSize: CGFloat = 72

    /// 路径 → NSImage 缓存，避免重绘时重复创建实例导致闪烁
    private static let imageCache = NSCache<NSString, NSImage>()

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

    /// 可打开的 URL（文件路径或文本中的 URL）
    private var openableURL: URL? {
        switch item.contentType {
        case .fileURL, .image:
            return URL(fileURLWithPath: item.content)
        case .text:
            if let url = URL(string: item.content),
               url.scheme == "http" || url.scheme == "https" {
                return url
            }
            return nil
        default:
            return nil
        }
    }

    /// 是否为文本类（text / rtf / html）—— 可预览、可分享
    private var isTextType: Bool {
        item.contentType == .text || item.contentType == .rtf || item.contentType == .html
    }

    /// 用默认应用打开
    private func openItem() {
        guard let url = openableURL else { return }
        OverlayPanelManager.shared.hide()
        NSWorkspace.shared.open(url)
    }

    /// 选择应用打开
    private func openWith() {
        guard let url = openableURL else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "打开"
        panel.message = "选择用于打开此文件的应用"
        OverlayPanelManager.shared.hide()
        panel.begin { response in
            guard response == .OK, let appURL = panel.url else { return }
            NSWorkspace.shared.open([url], withApplicationAt: appURL,
                                    configuration: NSWorkspace.OpenConfiguration())
        }
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
                .fill(Color.white.opacity(0.4))
            Text("\(idx)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.black)
        }
        .frame(width: 18, height: 18)
        .padding(6)
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
        switch item.contentType {
        case .image:   imagePreview
        case .fileURL: fileURLContent
        case .html:    htmlWithImagePreview
        default:
            if let url = detectedLink { linkContent(url) }
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
            if item.isHandoff {
                Text("·").font(.caption2).foregroundColor(.secondary)
                Text("来自其他设备").font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
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
        let name: String? = item.isHandoff ? "📱 Handoff" : item.appName
        self.themeColor = Color(nsColor: provider.themeColor(for: name))
        if item.isHandoff {
            // Handoff 来源：用 SF Symbol
            self.appIcon = nil  // 强制用 SF Symbol
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let icon = provider.icon(for: name)
            DispatchQueue.main.async {
                self.appIcon = icon
            }
        }
    }

    private func pasteItem() {
        didPaste = true
        OverlayPanelManager.shared.hideAndPaste(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            didPaste = false
        }
    }

    /// 右键菜单（使用系统 NSMenu.popUpContextMenu）
    private func showContextMenu(with event: NSEvent, for view: NSView) {
        let menu = NSMenu()
        let handler = _MenuHandler { title in
            switch title {
            case "钉选", "取消钉选": onPin(item)
            case "打开":         openItem()
            case "选择应用打开":     openWith()
            case "预览":         previewItem(from: view)
            case "分享":         shareItem(from: view)
            case "删除":         StoreManager.shared.deleteItem(item)
            default: break
            }
        }

        let pinTitle = item.isPinned ? "取消钉选" : "钉选"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        pinItem.target = handler
        pinItem.representedObject = handler
        menu.addItem(pinItem)

        let canOpen = item.contentType == .fileURL || item.contentType == .image
            || (item.contentType == .text && openableURL != nil)
        let canPreview = canOpen || isTextType

        if canOpen {
            menu.addItem(.separator())
            let openItem = NSMenuItem(title: "打开", action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
            openItem.target = handler
            openItem.representedObject = handler
            menu.addItem(openItem)
            let openWithItem = NSMenuItem(title: "选择应用打开", action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
            openWithItem.target = handler
            openWithItem.representedObject = handler
            menu.addItem(openWithItem)
        }

        if canPreview {
            menu.addItem(.separator())
            let previewItem = NSMenuItem(title: "预览", action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
            previewItem.target = handler
            previewItem.representedObject = handler
            menu.addItem(previewItem)
            let shareItem = NSMenuItem(title: "分享", action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
            shareItem.target = handler
            shareItem.representedObject = handler
            menu.addItem(shareItem)
        }

        menu.addItem(.separator())
        let deleteItem = NSMenuItem(title: "删除", action: #selector(_MenuHandler.invoke(_:)), keyEquivalent: "")
        deleteItem.target = handler
        deleteItem.representedObject = handler
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// Quick Look 预览（popover 浮动预览，三角指向卡片，面板保持可见）
    private func previewItem(from sourceView: NSView) {
        let metadata: QLPreviewHelper.PreviewMetadata

        if let url = openableURL {
            switch item.contentType {
            case .fileURL:
                let fileName = (item.content as NSString).lastPathComponent
                let ext = (fileName as NSString).pathExtension.uppercased()
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: url, displayName: fileName,
                    fileType: ext.isEmpty ? "文件" : ext,
                    infoText: fileName, isLocalFile: true
                )
            case .image:
                let fileName = (item.content as NSString).lastPathComponent
                let ext = (fileName as NSString).pathExtension.uppercased()
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: url, displayName: fileName,
                    fileType: ext.isEmpty ? "图片" : ext,
                    infoText: fileName, isLocalFile: true
                )
            case .text:
                let host = url.host ?? ""
                metadata = QLPreviewHelper.PreviewMetadata(
                    url: url, displayName: host,
                    fileType: "链接",
                    infoText: url.absoluteString, isLocalFile: false
                )
            default:
                return
            }
        } else if isTextType {
            // 纯文本 / RTF / HTML：写临时文件供 QLPreviewView 预览
            let ext: String
            let typeLabel: String
            switch item.contentType {
            case .rtf:  ext = "rtf";  typeLabel = "RTF"
            case .html: ext = "html"; typeLabel = "HTML"
            default:    ext = "txt";  typeLabel = "文本"
            }
            let tmpDir = FileManager.default.temporaryDirectory
            let tmpFile = tmpDir.appendingPathComponent("pastry_preview_\(UUID().uuidString.prefix(8)).\(ext)")
            try? item.content.write(to: tmpFile, atomically: true, encoding: .utf8)

            let charCount = item.content.count
            let wordCount = item.content.split { $0.isWhitespace || $0.isNewline }.count
            let lineCount = item.content.split(separator: "\n", omittingEmptySubsequences: false).count

            metadata = QLPreviewHelper.PreviewMetadata(
                url: tmpFile, displayName: "\(typeLabel)预览",
                fileType: typeLabel,
                infoText: "\(charCount) 字符  \(wordCount) 单词  \(lineCount) 行",
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
        if let url = openableURL {
            items = [url]
        } else if isTextType {
            items = [item.content]
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
    static func isTextTypeForTesting(contentType: ClipType) -> Bool {
        contentType == .text || contentType == .rtf || contentType == .html
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
            switch item.contentType {
            case .text, .rtf, .html, .fileURL: return item.content
            default: return nil
            }
        }.joined(separator: "\n")
    }

    /// 供单元测试：单选拖拽 → 按类型返回 (isFile: Bool, content: String)
    static func dragPayloadForTesting(_ item: ClipboardItem) -> (isFile: Bool, content: String) {
        switch item.contentType {
        case .image, .fileURL:
            return (true, item.content)
        default:
            return (false, item.content)
        }
    }
}



