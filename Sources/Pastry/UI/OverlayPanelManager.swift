import Cocoa
import SwiftUI
import OSLog
import Quartz

// MARK: - 自定义覆盖层面板
final class ClipboardOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Quick Look 预览辅助（NSPopover + QLPreviewView，带自定义控件）
final class QLPreviewHelper: NSObject {
    nonisolated(unsafe) static let shared = QLPreviewHelper()

    struct PreviewMetadata {
        let url: URL
        let displayName: String
        let fileType: String
        let infoText: String
        let isLocalFile: Bool
    }

    private var popover: NSPopover?
    private var previewView: QLPreviewView?
    private var closeObserver: NSObjectProtocol?
    private var currentMetadata: PreviewMetadata?

    /// 是否有预览 popover 正在显示
    var isShowing: Bool { popover != nil }

    /// 以 popover 形式预览文件（三角指向源卡片，不影响面板 key 状态）
    func showPreview(metadata: PreviewMetadata, from sourceView: NSView) {
        dismiss()

        self.currentMetadata = metadata

        // 预览视图
        let preview = QLPreviewView()
        preview.autostarts = true
        preview.previewItem = metadata.url as NSURL
        self.previewView = preview

        // 容器视图
        let container = PreviewContainerView(
            previewView: preview,
            metadata: metadata,
            onClose: { [weak self] in self?.dismiss() },
            onShare: { [weak self] in self?.shareFromContainer() },
            onReveal: { [weak self] in self?.revealInFinder() }
        )

        let vc = NSViewController()
        vc.view = container

        let p = NSPopover()
        p.contentViewController = vc
        p.behavior = .transient
        p.animates = true

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: p, queue: .main
        ) { [weak self] _ in
            self?.dismiss()
        }

        self.popover = p
        p.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .maxY)
    }

    func dismiss() {
        if let observer = closeObserver {
            NotificationCenter.default.removeObserver(observer)
            closeObserver = nil
        }
        popover?.close()
        popover = nil
        previewView = nil
        currentMetadata = nil
    }

    // MARK: - 控件动作

    private func shareFromContainer() {
        guard let metadata = currentMetadata, let popover else { return }
        let picker = NSSharingServicePicker(items: [metadata.url as NSURL])
        // 从 popover 的内容视图触发，让分享面板也带三角
        if let contentView = popover.contentViewController?.view {
            picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
        }
    }

    private func revealInFinder() {
        guard let metadata = currentMetadata, metadata.isLocalFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([metadata.url])
    }
}

// MARK: - 预览容器视图（QLPreviewView + 浮层控件）
private final class PreviewContainerView: NSView {

    private let onClose: () -> Void
    private let onShare: () -> Void
    private let onReveal: () -> Void
    private let metadata: QLPreviewHelper.PreviewMetadata
    private weak var shareButton: NSButton?

    init(previewView: QLPreviewView, metadata: QLPreviewHelper.PreviewMetadata,
         onClose: @escaping () -> Void, onShare: @escaping () -> Void,
         onReveal: @escaping () -> Void) {
        self.metadata = metadata
        self.onClose = onClose
        self.onShare = onShare
        self.onReveal = onReveal

        // 总高度 = 预览 360 + 顶栏 32 + 底栏 28
        super.init(frame: NSRect(x: 0, y: 0, width: 480, height: 420))

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true

        // QLPreviewView 放在顶栏和底栏之间，避免被遮挡
        let topBarHeight: CGFloat = 32
        let bottomBarHeight: CGFloat = 28
        let previewHeight = bounds.height - topBarHeight - bottomBarHeight
        previewView.frame = NSRect(x: 0, y: bottomBarHeight, width: bounds.width, height: previewHeight)
        previewView.wantsLayer = true // Retina 渲染
        previewView.layer?.backgroundColor = NSColor.black.cgColor
        previewView.autoresizingMask = [.width, .height]
        addSubview(previewView)

        // 顶栏
        let topBar = NSVisualEffectView(frame: NSRect(x: 0, y: bounds.height - 32, width: bounds.width, height: 32))
        topBar.material = .hudWindow
        topBar.blendingMode = .withinWindow
        topBar.state = .active
        topBar.autoresizingMask = [.width, .minYMargin]
        topBar.wantsLayer = true
        topBar.layer?.cornerRadius = 0
        addSubview(topBar)

        // 关闭按钮
        let closeBtn = NSButton(frame: NSRect(x: 6, y: 6, width: 20, height: 20))
        closeBtn.bezelStyle = .regularSquare
        closeBtn.isBordered = false
        closeBtn.title = ""
        closeBtn.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n["a11y.close"])
        closeBtn.imagePosition = .imageOnly
        closeBtn.contentTintColor = .secondaryLabelColor
        closeBtn.target = self
        closeBtn.action = #selector(closeTapped)
        topBar.addSubview(closeBtn)

        // 类型标签
        let typeLabel = NSTextField(labelWithString: metadata.fileType)
        typeLabel.frame = NSRect(x: 30, y: 8, width: 120, height: 16)
        typeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        typeLabel.textColor = .secondaryLabelColor
        topBar.addSubview(typeLabel)

        // 分享按钮
        let shareBtn = NSButton(frame: NSRect(x: bounds.width - 32, y: 6, width: 24, height: 20))
        shareBtn.bezelStyle = .regularSquare
        shareBtn.isBordered = false
        shareBtn.title = ""
        shareBtn.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: L10n["a11y.share"])
        shareBtn.imagePosition = .imageOnly
        shareBtn.contentTintColor = .secondaryLabelColor
        shareBtn.target = self
        shareBtn.action = #selector(shareTapped)
        shareBtn.autoresizingMask = .minXMargin
        topBar.addSubview(shareBtn)
        self.shareButton = shareBtn

        // 底栏
        let bottomBar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: 28))
        bottomBar.material = .hudWindow
        bottomBar.blendingMode = .withinWindow
        bottomBar.state = .active
        bottomBar.autoresizingMask = [.width, .maxYMargin]
        addSubview(bottomBar)

        // 信息文本（左下角）
        let infoLabel = NSTextField(labelWithString: metadata.infoText)
        infoLabel.frame = NSRect(x: 10, y: 5, width: bounds.width - 120, height: 18)
        infoLabel.font = .systemFont(ofSize: 10.5)
        infoLabel.textColor = .tertiaryLabelColor
        infoLabel.lineBreakMode = .byTruncatingMiddle
        infoLabel.autoresizingMask = .width
        bottomBar.addSubview(infoLabel)

        // Reveal in Finder（右下角，仅本地文件显示）
        if metadata.isLocalFile {
            let revealBtn = NSButton(frame: NSRect(x: bounds.width - 130, y: 2, width: 120, height: 24))
            revealBtn.bezelStyle = .regularSquare
            revealBtn.isBordered = false
            revealBtn.font = .systemFont(ofSize: 11)
            // 图标嵌入标题，间距可控
            let icon = NSTextAttachment()
            icon.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let iconStr = NSAttributedString(attachment: icon)
            let label = NSAttributedString(
                string: " \(L10n["preview.reveal"])",
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 11)]
            )
            let title = NSMutableAttributedString()
            title.append(iconStr)
            title.append(label)
            revealBtn.attributedTitle = title
            revealBtn.target = self
            revealBtn.action = #selector(revealTapped)
            revealBtn.autoresizingMask = .minXMargin
            bottomBar.addSubview(revealBtn)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    @objc private func closeTapped() { onClose() }
    @objc private func shareTapped() { onShare() }
    @objc private func revealTapped() { onReveal() }
}

// MARK: - 全屏覆盖层面板管理器
final class OverlayPanelManager: @unchecked Sendable {

    static let shared = OverlayPanelManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "overlay")

    /// 粘贴提示音（预加载避免每次读磁盘阻塞主线程）
    private static let pasteSound: NSSound? = {
        guard let path = Bundle.main.path(forResource: "Paste", ofType: "aiff") else { return nil }
        let sound = NSSound(contentsOfFile: path, byReference: true)
        // 预暖音频管线，避免首次 play() 的冷启动延迟
        sound?.play()
        sound?.stop()
        return sound
    }()

    private var panel: ClipboardOverlayPanel?
    private var keyboardMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var cmdWasDown = false
    private var previousFrontApp: NSRunningApplication?
    private var alertActive = false
    private var isPasting = false
    private var isDragThrough = false
    private var panelResignKeyObserver: NSObjectProtocol?

    /// 筛选气泡
    private var filterPopover: NSPopover?
    private var filterPopoverCloseObserver: NSObjectProtocol?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .overlayAlertActive, object: nil, queue: .main
        ) { [weak self] note in
            self?.alertActive = (note.userInfo?["active"] as? Bool) ?? false
        }
        NotificationCenter.default.addObserver(
            forName: .overlayToggleFilterPopover, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.toggleFilterPopover() }
        }
    }

    // MARK: - 显示/隐藏

    @MainActor
    func show() {
        guard panel == nil else { return }
        showPanel()
    }

    @MainActor
    func hide() {
        cleanup()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)
        log.info("覆盖层已关闭")
    }

    @MainActor
    func toggle() {
        if panel != nil {
            NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
        } else {
            show()
        }
    }

    /// 隐藏 + 粘贴到之前的前台应用（点击卡片使用）
    /// 先写剪贴板 + ⌘V，面板隐藏/DB/音效后台收尾，不阻塞粘贴
    @MainActor
    func hideAndPaste(_ item: ClipboardItem) {
        guard panel != nil else { return }

        isPasting = true
        let targetApp = previousFrontApp
        previousFrontApp = nil

        // 1. 挂起监听，防止读到自己的写入
        ClipboardMonitor.shared.suspend()

        // 2. 写剪贴板（立即，主线程 <1ms）
        let pb = NSPasteboard.general
        pb.clearContents()

        // 列表查询只取前 256 字符，粘贴前按需取完整内容
        let fullContent: String
        switch item.contentType {
        case .text, .url, .rtf, .html:
            fullContent = DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content
        default:
            fullContent = item.content
        }

        switch item.contentType {
        case .text, .url:
            pb.setString(fullContent, forType: .string)
        case .rtf, .html:
            pb.setString(fullContent, forType: .string)
            if let raw = item.rawFormatData, let typeStr = item.rawFormatType {
                pb.setData(raw, forType: NSPasteboard.PasteboardType(typeStr))
            }
        case .fileURL:
            let urls = item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            pb.writeObjects(urls as [NSURL])
        case .image:
            // 优先从原始数据路径加载（高清），回退到缩略图路径
            let imagePath = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
            if let image = NSImage(contentsOfFile: imagePath) {
                if let annotation = item.textAnnotation, !annotation.isEmpty {
                    let attr = NSMutableAttributedString()
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attr.append(NSAttributedString(attachment: attachment))
                    attr.append(NSAttributedString(string: "\n\(annotation)"))
                    do {
                        let rtfd = try attr.data(
                            from: NSRange(location: 0, length: attr.length),
                            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
                        )
                        pb.setData(rtfd, forType: .rtfd)
                    } catch {
                        log.error("RTFD 写入失败: \(error.localizedDescription)")
                    }
                    pb.setData(image.tiffRepresentation, forType: .tiff)
                    pb.setString(annotation, forType: .string)
                } else {
                    pb.writeObjects([image])
                }
            }
        }

        // 内容就绪 → 反馈音效（异步避免阻塞粘贴）
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            DispatchQueue.main.async { Self.pasteSound?.play() }
        }

        // 3. 激活目标 App + 隐藏面板（并行）
        targetApp?.activate()
        panel?.orderOut(nil)
        panel = nil
        removeKeyboardMonitor()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)

        // 4. ⌘V（面板已隐藏，目标 App 在前台）
        Self.simulatePaste()

        // 5. 后台收尾：DB / 恢复监听 / 刷新
        DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
        DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
        ClipboardMonitor.shared.resume()
        StoreManager.shared.refresh()
        isPasting = false
    }

    /// 多选粘贴：将所有选中条目的文本拼接后一次性 ⌘V
    @MainActor
    func hideAndPasteMultiple(_ items: [ClipboardItem]) {
        guard panel != nil, !items.isEmpty else { return }

        isPasting = true
        let targetApp = previousFrontApp
        previousFrontApp = nil

        ClipboardMonitor.shared.suspend()

        // 收集所有文本内容（文本类 + 文件路径），用换行拼接
        let lines = items.compactMap { item -> String? in
            switch item.contentType {
            case .text, .rtf, .html, .url:
                return DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content
            case .fileURL:
                return item.content  // 文件路径也是文本
            case .image:
                return nil  // 跳过多选的图片
            }
        }
        let combined = lines.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)

        // 音效
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            DispatchQueue.main.async { Self.pasteSound?.play() }
        }

        // 激活目标 App + 隐藏面板
        targetApp?.activate()
        panel?.orderOut(nil)
        panel = nil
        removeKeyboardMonitor()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)

        // ⌘V
        Self.simulatePaste()

        // 后台收尾：每个条目更新 DB
        for item in items {
            DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
            DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
        }
        ClipboardMonitor.shared.resume()
        StoreManager.shared.refresh()
        isPasting = false
    }

    /// 拖拽开始时临时透传鼠标事件，让拖拽能到达目标应用
    @MainActor
    func beginDragThrough() {
        panel?.ignoresMouseEvents = true
        isDragThrough = true
        // 轮询鼠标释放来检测拖拽结束
        DispatchQueue.main.async { [weak self] in
            self?.pollDragEnd()
        }
    }

    /// 轮询鼠标按键状态，释放时恢复面板交互
    private func pollDragEnd() {
        guard isDragThrough else { return }
        if NSEvent.pressedMouseButtons == 0 {
            // 鼠标已释放 → 拖拽结束，等一小会让 drop 完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, self.isDragThrough else { return }
                self.isDragThrough = false
                self.panel?.ignoresMouseEvents = false
                self.panel?.makeKey()   // 重新成为 key window，这样后续点击空白仍会触发 didResignKey → hide
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.pollDragEnd()
            }
        }
    }

    var isVisible: Bool { panel != nil }

    /// 搜索栏是否展开 — ESC 优先级判断
    var isSearchActive = false

    // MARK: - 私有

    @MainActor
    private func showPanel() {
        let t0 = CFAbsoluteTimeGetCurrent()

        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first else {
            log.error("无法获取屏幕")
            return
        }

        previousFrontApp = NSWorkspace.shared.frontmostApplication

        let screenFrame = screen.visibleFrame  // 不含菜单栏，保留菜单栏交互

        let newPanel = ClipboardOverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .popUpMenu
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        newPanel.isReleasedWhenClosed = false
        newPanel.ignoresMouseEvents = false
        newPanel.acceptsMouseMovedEvents = true
        newPanel.hidesOnDeactivate = false
        newPanel.animationBehavior = .none

        let t1 = CFAbsoluteTimeGetCurrent()

        let overlayView = OverlayView()
            .environmentObject(StoreManager.shared)

        let t2 = CFAbsoluteTimeGetCurrent()

        let hostingView = NSHostingView(rootView: overlayView)

        let t2a = CFAbsoluteTimeGetCurrent()

        hostingView.frame = screenFrame
        hostingView.autoresizingMask = [.width, .height]
        newPanel.contentView = hostingView

        let t3 = CFAbsoluteTimeGetCurrent()

        newPanel.orderFrontRegardless()
        newPanel.makeKey()

        let t4 = CFAbsoluteTimeGetCurrent()

        // 性能日志（OSLog + 文件持久化）
        let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
        let itemCount = StoreManager.shared.items.count
        // 统计最大 content 长度，检测是否有未被截断的大文本
        let maxLen = StoreManager.shared.items.map { $0.content.count }.max() ?? 0
        let totalLen = StoreManager.shared.items.reduce(0) { $0 + $1.content.count }
        let perfLine = "\(Date()) | items: \(itemCount) | maxContent: \(maxLen) | totalContent: \(totalLen) | panel: \(ms(t1-t0))ms | overlayView: \(ms(t2-t1))ms | hostingInit: \(ms(t2a-t2))ms | hostingLayout: \(ms(t3-t2a))ms | orderFront: \(ms(t4-t3))ms | total: \(ms(t4-t0))ms"
        log.info("⏱ \(perfLine, privacy: .public)")

        // 追加写入文件（~/Library/Logs/Pastry/perf.log）
        guard let logDirBase = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            log.error("无法获取 Library 目录，性能日志写入跳过")
            return
        }
        let logDir = logDirBase.appendingPathComponent("Logs/Pastry")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        let logFile = logDir.appendingPathComponent("perf.log")
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(Data((perfLine + "\n").utf8))
            try? handle.close()
        } else {
            try? (perfLine + "\n").write(to: logFile, atomically: true, encoding: .utf8)
        }

        // 面板失焦（Cmd+Tab / 点其他 App）→ 自动收起（拖拽穿透期间除外）
        panelResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: newPanel, queue: .main
        ) { [weak self] _ in
            guard let self, !self.isPasting, !self.alertActive, !self.isDragThrough else { return }
            DispatchQueue.main.async { self.hide() }
        }

        self.panel = newPanel
        installKeyboardMonitor()

        log.info("覆盖层已显示")
    }

    // MARK: - 筛选气泡

    @MainActor
    func toggleFilterPopover(sourceFrame: CGRect? = nil) {
        try? "toggleFilterPopover frame=\(sourceFrame?.debugDescription ?? "nil")\n".write(toFile: "/tmp/pastry_debug.txt", atomically: false, encoding: .utf8)
        if filterPopover != nil {
            dismissFilterPopover()
        } else {
            showFilterPopover(sourceFrame: sourceFrame)
        }
    }

    @MainActor
    private func showFilterPopover(sourceFrame: CGRect?) {
        guard let panel else {
            try? "panel nil\n".write(toFile: "/tmp/pastry_debug.txt", atomically: false, encoding: .utf8)
            return
        }

        // 用 panel 的 contentView 顶部区域做锚点（简化，不纠结按钮精确定位）
        guard let contentView = panel.contentView else {
            return
        }
        // 在 contentView 坐标系的顶部偏右位置创建锚点矩形
        let anchorRect = NSRect(x: contentView.bounds.maxX - 120,
                                y: contentView.bounds.maxY - 30,
                                width: 30, height: 10)

        let rootView = FilterPopoverContent(store: StoreManager.shared)
        let hostingVC = NSHostingController(rootView: rootView)
        hostingVC.view.frame.size = hostingVC.view.fittingSize

        let p = NSPopover()
        p.contentViewController = hostingVC
        p.behavior = .transient
        p.animates = true

        filterPopoverCloseObserver = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification, object: p, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissFilterPopover() }
        }

        filterPopover = p
        NotificationCenter.default.post(name: .filterPopoverStateChanged,
                                        object: nil, userInfo: ["showing": true])
        p.show(relativeTo: anchorRect, of: contentView, preferredEdge: .minY)
    }

    @MainActor
    private func dismissFilterPopover() {
        if let observer = filterPopoverCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            filterPopoverCloseObserver = nil
        }
        filterPopover?.close()
        filterPopover = nil
        NotificationCenter.default.post(name: .filterPopoverStateChanged,
                                        object: nil, userInfo: ["showing": false])
    }

    /// 递归查找指定 accessibilityIdentifier 的子视图
    private func findView(by identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier { return view }
        for subview in view.subviews {
            if let found = findView(by: identifier, in: subview) { return found }
        }
        return nil
    }

    /// 诊断用：递归打印视图层级
    private func dumpViewHierarchy(_ view: NSView, indent: Int) {
        let pad = String(repeating: "  ", count: indent)
        let aid = view.accessibilityIdentifier()
        log.info("\(pad)[\(type(of: view))] accessibilityID=\(aid)")
        for sub in view.subviews {
            dumpViewHierarchy(sub, indent: indent + 1)
        }
    }

    private func cleanup() {
        MainActor.assumeIsolated { dismissFilterPopover() }
        if let observer = panelResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
            panelResignKeyObserver = nil
        }
        removeKeyboardMonitor()
        isDragThrough = false
        panel?.ignoresMouseEvents = false
        panel?.orderOut(nil)
        panel = nil
        previousFrontApp = nil
    }

    // MARK: - 键盘事件拦截

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return nil }
            // Esc：筛选气泡 → 预览 popover → 搜索栏 → 关闭面板（逐层收起）
            if event.keyCode == 53 {
                if self.alertActive { return event }
                if self.filterPopover != nil {
                    DispatchQueue.main.async { self.dismissFilterPopover() }
                    return nil
                }
                if QLPreviewHelper.shared.isShowing {
                    QLPreviewHelper.shared.dismiss()
                    return nil
                }
                if self.isSearchActive {
                    NotificationCenter.default.post(name: .overlayCloseSearch, object: nil)
                    return nil
                }
                NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
                return nil
            }
            // 弹窗活跃：Enter 确认删除 / 其他按键放行（Esc 已在上方处理）
            if self.alertActive {
                if event.keyCode == 36 {
                    NotificationCenter.default.post(name: .overlayAlertConfirm, object: nil)
                    return nil
                }
                return event
            }
            // Tab — 搜索栏↔卡片焦点互相切换（无 Shift/⌘/⌥/⌃ 修饰）
            if event.keyCode == 48,
               event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
                if self.isSearchActive {
                    NotificationCenter.default.post(name: .overlayCloseSearch, object: nil,
                                                    userInfo: ["clearFilter": false])
                } else {
                    NotificationCenter.default.post(name: .overlayOpenSearchImmediate, object: nil)
                }
                return nil
            }
            // ⌘F 搜索
            if event.keyCode == 3, event.modifierFlags.contains(.command) {
                if !self.isSearchActive {
                    NotificationCenter.default.post(name: .overlayOpenSearch, object: nil)
                }
                return nil
            }
            // ⌘A 全选 — 搜索框聚焦时也选中所有筛选结果（不收拢搜索栏）
            if event.keyCode == 0, event.modifierFlags.contains(.command) {
                if Self.isTextInputFocused() {
                    NotificationCenter.default.post(name: .overlaySelectAll, object: nil)
                    return nil
                }
                NotificationCenter.default.post(name: .overlaySelectAll, object: nil)
                return nil
            }
            // Delete / Forward Delete — 若焦点在文本输入框则放行
            if event.keyCode == 51 || event.keyCode == 117 {
                if Self.isTextInputFocused() { return event }
                NotificationCenter.default.post(name: .overlayDeleteSelected, object: nil)
                return nil
            }
            // 方向键 — 搜索框活跃时放行
            if self.isSearchActive { return event }
            let extend = event.modifierFlags.contains(.shift)
            switch event.keyCode {
            case 126: // 上
                NotificationCenter.default.post(name: .overlayMoveUp, object: nil, userInfo: ["extend": extend])
                return nil
            case 125: // 下
                NotificationCenter.default.post(name: .overlayMoveDown, object: nil, userInfo: ["extend": extend])
                return nil
            case 123: // 左
                NotificationCenter.default.post(name: .overlayMoveLeft, object: nil, userInfo: ["extend": extend])
                return nil
            case 124: // 右
                NotificationCenter.default.post(name: .overlayMoveRight, object: nil, userInfo: ["extend": extend])
                return nil
            case 36: // Enter
                NotificationCenter.default.post(name: .overlayConfirmPaste, object: nil)
                return nil
            // ⌘+1~9 — 粘贴对应序号的卡片
            case let kc where event.modifierFlags.contains(.command):
                if let idx = Self.cmdNumberIndex(keyCode: kc) {
                    NotificationCenter.default.post(name: .overlayCmdPaste, object: nil,
                                                    userInfo: ["index": idx])
                    return nil
                }
                fallthrough
            default:
                // 打印字符 → 打开搜索栏并聚焦（不输入字符，让用户自行输入）
                if Self.shouldFocusSearch(
                    chars: event.characters,
                    isSearchActive: self.isSearchActive,
                    modifierFlags: event.modifierFlags
                ) {
                    NotificationCenter.default.post(name: .overlayOpenSearchImmediate, object: nil)
                    return nil
                }
                break
            }
            return event
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self else { return event }
            let cmdNow = event.modifierFlags.contains(.command)
            if cmdNow != self.cmdWasDown {
                self.cmdWasDown = cmdNow
                NotificationCenter.default.post(name: .overlayCmdStateChanged, object: nil,
                                                userInfo: ["cmdDown": cmdNow])
            }
            return event
        }
    }

    /// ⌘+数字键映射：keyCode → 序号 (1-9)，非数字键返回 nil
    private static let cmdNumberMap: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]

    static func cmdNumberIndex(keyCode: UInt16) -> Int? {
        cmdNumberMap[keyCode]
    }

    /// 检查当前焦点是否在文本输入框内（搜索框等）
    private static func isTextInputFocused() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder.isKind(of: NSTextView.self) { return true }
        if responder.isKind(of: NSTextField.self) { return true }
        if responder.isKind(of: NSSearchField.self) { return true }
        return false
    }

    /// 判断字符串首字符是否应重定向到搜索栏（字母/数字/符号/标点/空格）
    static func isRedirectableChar(_ chars: String) -> Bool {
        guard let first = chars.first else { return false }
        return first.isLetter || first.isNumber || first.isSymbol || first.isPunctuation || first.isWhitespace
    }

    /// 判断按键是否应触发搜索栏聚焦（综合字符、状态、修饰键）
    static func shouldFocusSearch(
        chars: String?,
        isSearchActive: Bool,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard !isSearchActive,
              !modifierFlags.contains(.command),
              !modifierFlags.contains(.control),
              let chars,
              !chars.isEmpty,
              isRedirectableChar(chars) else {
            return false
        }
        return true
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        cmdWasDown = false
    }

    // MARK: - ⌘V 模拟

    private static func simulatePaste() {
        let vKey = CGKeyCode(9)
        guard let source = CGEventSource(stateID: .privateState) else {
            Logger(subsystem: "com.nekutai.pastry", category: "paste").warning("CGEventSource 创建失败 — 可能缺少辅助功能权限")
            NSSound.beep()
            return
        }

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            NSSound.beep()
            return
        }

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        cmdDown.postToPid(pid)
        cmdUp.postToPid(pid)
    }

    deinit {
        removeKeyboardMonitor()
    }
}
