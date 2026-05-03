import SwiftUI
import Cocoa

// MARK: - 链接预览加载器
final class LinkPreviewLoader {
    static let shared = LinkPreviewLoader()

    struct Preview {
        let title: String
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
            let title = self.extractTitle(from: html)
            let preview = Preview(title: title ?? "", host: url.host ?? "")
            self.cache.setObject(PreviewWrapper(preview), forKey: key as NSString)
            DispatchQueue.main.async { completion(preview) }
        }.resume()
    }

    private func extractTitle(from html: String) -> String? {
        if let s = html.range(of: "<title>", options: .caseInsensitive),
           let e = html.range(of: "</title>", options: .caseInsensitive),
           s.upperBound <= e.lowerBound {
            let t = html[s.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        for pattern in [
            "og:title\" content=\"",
            "og:title' content='",
            "property=\"og:title\" content=\"",
            "property='og:title' content='",
        ] {
            if let s = html.range(of: pattern, options: .caseInsensitive),
               let e = html.range(of: "\"", range: s.upperBound..<html.endIndex) ??
                        html.range(of: "'", range: s.upperBound..<html.endIndex) {
                return String(html[s.upperBound..<e.lowerBound])
            }
        }
        return nil
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

    @State private var linkPreview: LinkPreviewLoader.Preview?
    @State private var linkPreviewLoaded = false
    @State private var linkPreviewTask: Task<Void, Never>?

    private static let cardSize: CGFloat = 200
    private static let headerHeight: CGFloat = 40
    private static let appIconSize: CGFloat = 60

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
        .compositingGroup()  // 拍平所有子图层，消除圆角裁边白线
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
        .onChange(of: item.content) { _ in
            linkPreview = nil; linkPreviewLoaded = false
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
        case .fileURL: fileURLPreview
        default:
            if let url = detectedLink { linkPreviewView(url) }
            else { textPreview }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let nsImage = NSImage(contentsOfFile: item.content) {
            Image(nsImage: nsImage)
                .resizable().aspectRatio(contentMode: .fit)
                .cornerRadius(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            fallbackPreview
        }
    }

    private var fileURLPreview: some View {
        let urls = fileURLs
        return VStack(alignment: .leading, spacing: 3) {
            ForEach(urls.prefix(4), id: \.self) { url in
                HStack(spacing: 4) {
                    Image(systemName: "doc").font(.system(size: 9)).foregroundColor(themeColor)
                    Text(url.lastPathComponent).lineLimit(1).font(.system(size: 10)).foregroundColor(.primary)
                }
            }
            if urls.count > 4 {
                Text("+\(urls.count - 4) 个文件").font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func linkPreviewView(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "link").font(.system(size: 10, weight: .semibold)).foregroundColor(.blue.opacity(0.75))
                Text(linkDisplayTitle(url: url)).font(.system(size: 11, weight: .semibold)).foregroundColor(.primary).lineLimit(2)
            }
            Text(url.absoluteString).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2)
            if !linkPreviewLoaded, detectedLink != nil {
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                    Text("获取预览…").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkDisplayTitle(url: URL) -> String {
        if let p = linkPreview, !p.title.isEmpty { return p.title }
        return url.host ?? url.absoluteString
    }

    private var textPreview: some View {
        Text(previewText).lineLimit(7).font(.system(size: 11)).foregroundColor(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private static let linkDetector: NSDataDetector? = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private func fetchLinkPreviewIfNeeded() {
        guard let url = detectedLink else { return }
        linkPreviewTask?.cancel()
        linkPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            LinkPreviewLoader.shared.load(url: url) { self.linkPreview = $0; self.linkPreviewLoaded = true }
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

