import Cocoa
import SwiftUI
import OSLog

// MARK: - 自定义覆盖层面板
final class ClipboardOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown,
           event.keyCode == 53,
           OverlayPanelManager.shared.keyboardOwner == .searchField,
           !OverlayPanelManager.shared.isAlertActive {
            routeCancelKey()
            return
        }
        if event.type == .keyDown,
           Self.isSearchShortcut(keyCode: event.keyCode, modifierFlags: event.modifierFlags),
           OverlayPanelManager.shared.keyboardOwner != .favoriteNoteEditor,
           !OverlayPanelManager.shared.isAlertActive {
            routeOpenSearchKey()
            return
        }
        super.sendEvent(event)
    }

    override func keyDown(with event: NSEvent) {
        if !OverlayPanelManager.shared.isAlertActive,
           OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
            super.keyDown(with: event)
            return
        }

        switch Self.keyRoute(for: event,
                             isSearchActive: OverlayPanelManager.shared.isSearchActive,
                             isAlertActive: OverlayPanelManager.shared.isAlertActive,
                             keyboardOwner: OverlayPanelManager.shared.keyboardOwner) {
        case .cancel:
            routeCancelKey()
        case .cancelFavoriteNoteEditing:
            routeFavoriteNoteCancelKey()
        case .confirmAlert:
            routeAlertConfirmKey()
        case .selectAll:
            routeSelectAllKey()
        case .openSearch:
            routeOpenSearchKey()
        case .consume:
            break
        case .system:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if !OverlayPanelManager.shared.isAlertActive,
           OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
            return super.performKeyEquivalent(with: event)
        }

        switch Self.keyRoute(for: event,
                             isSearchActive: OverlayPanelManager.shared.isSearchActive,
                             isAlertActive: OverlayPanelManager.shared.isAlertActive,
                             keyboardOwner: OverlayPanelManager.shared.keyboardOwner) {
        case .cancel:
            routeCancelKey()
            return true
        case .cancelFavoriteNoteEditing:
            routeFavoriteNoteCancelKey()
            return true
        case .confirmAlert:
            routeAlertConfirmKey()
            return true
        case .selectAll:
            routeSelectAllKey()
            return true
        case .openSearch:
            routeOpenSearchKey()
            return true
        case .consume:
            return true
        case .system:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if OverlayPanelManager.shared.isAlertActive {
            routeCancelKey()
            return
        }
        if OverlayPanelManager.shared.keyboardOwner == .favoriteNoteEditor {
            NotificationCenter.default.post(name: .overlayCancelFavoriteNoteEditing, object: nil)
            return
        }
        if OverlayPanelManager.shared.keyboardOwner == .searchField {
            routeCancelKey()
            return
        }
        routeCancelKey()
    }

    enum KeyRoute: Equatable {
        case cancel
        case cancelFavoriteNoteEditing
        case confirmAlert
        case selectAll
        case openSearch
        case consume
        case system
    }

    static func keyRoute(
        keyCode: UInt16,
        chars: String? = nil,
        isSearchActive: Bool,
        isAlertActive: Bool = false,
        modifierFlags: NSEvent.ModifierFlags = [],
        keyboardOwner: OverlayKeyboardOwner = .overlayNavigation
    ) -> KeyRoute {
        if isAlertActive, keyCode == 53 {
            return .cancel
        }

        if isAlertActive {
            if OverlayKeyboardRouter.isAlertConfirmKey(keyCode: keyCode) {
                return .confirmAlert
            }
            return OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: keyCode) ? .consume : .system
        }

        if keyboardOwner == .favoriteNoteEditor {
            if keyCode == 53 {
                return .cancelFavoriteNoteEditing
            }
            return .system
        }

        if keyCode == 53 {
            return .cancel
        }

        if Self.isSearchShortcut(keyCode: keyCode, modifierFlags: modifierFlags) {
            return .openSearch
        }

        if keyboardOwner == .searchField {
            if keyCode == 48, modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
                return .consume
            }
            return .system
        }

        if keyCode == 0, modifierFlags.contains(.command) {
            return .selectAll
        }

        guard !isSearchActive else { return .system }

        if keyCode == 36 || keyCode == 51 || keyCode == 117 {
            return .consume
        }
        if modifierFlags.contains(.command), OverlayKeyboardRouter.cmdNumberIndex(keyCode: keyCode) != nil {
            return .consume
        }
        if keyCode == 123 || keyCode == 124 || keyCode == 125 || keyCode == 126 {
            return .consume
        }
        if OverlayKeyboardRouter.shouldFocusSearch(
            chars: chars,
            isSearchActive: isSearchActive,
            modifierFlags: modifierFlags
        ) {
            return .consume
        }

        return .system
    }

    static func keyRoute(
        for event: NSEvent,
        isSearchActive: Bool,
        isAlertActive: Bool,
        keyboardOwner: OverlayKeyboardOwner
    ) -> KeyRoute {
        keyRoute(
            keyCode: event.keyCode,
            chars: event.characters,
            isSearchActive: isSearchActive,
            isAlertActive: isAlertActive,
            modifierFlags: event.modifierFlags,
            keyboardOwner: keyboardOwner
        )
    }

    private func routeAlertConfirmKey() {
        NotificationCenter.default.post(name: .overlayAlertConfirm, object: nil)
    }

    private func routeFavoriteNoteCancelKey() {
        NotificationCenter.default.post(name: .overlayCancelFavoriteNoteEditing, object: nil)
    }

    private func routeSelectAllKey() {
        NotificationCenter.default.post(name: .overlaySelectAll, object: nil)
    }

    private func routeOpenSearchKey() {
        NotificationCenter.default.post(name: .overlayOpenSearchImmediate, object: nil)
    }

    private func routeCancelKey() {
        if OverlayPanelManager.shared.isAlertActive {
            NotificationCenter.default.post(name: .overlayAlertCancel, object: nil)
        } else if QLPreviewHelper.shared.isShowing {
            QLPreviewHelper.shared.dismiss()
        } else if OverlayPanelManager.shared.isSearchActive {
            NotificationCenter.default.post(name: .overlayCloseSearch, object: nil)
        } else {
            NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
        }
    }

    private static func isSearchShortcut(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        keyCode == 3 && modifierFlags.contains(.command)
    }
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
    private var previousFrontApp: NSRunningApplication?
    private var alertActive = false
    private var isPasting = false
    private var isDragThrough = false
    private var panelResignKeyObserver: NSObjectProtocol?
    private lazy var keyboardRouter = OverlayKeyboardRouter(
        isAlertActive: { [weak self] in self?.alertActive ?? false },
        isSearchActive: { [weak self] in self?.isSearchActive ?? false },
        keyboardOwner: { [weak self] in self?.keyboardOwner ?? .overlayNavigation }
    )

    private init() {
        NotificationCenter.default.addObserver(
            forName: .overlayAlertActive, object: nil, queue: .main
        ) { [weak self] note in
            self?.alertActive = (note.userInfo?["active"] as? Bool) ?? false
        }
    }

    // MARK: - 显示/隐藏

    /// 热键触发时刻 — 由 GlobalHotkeyManager 在 Carbon 回调中设置，
    /// showPanel() 读取后清零
    nonisolated(unsafe) static var hotkeyFiredAt: CFAbsoluteTime?

    private static let perfLogQueue = DispatchQueue(label: "com.nekutai.pastry.perflog", qos: .utility)

    private static var isPerformanceLoggingEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.performanceLoggingEnabled)
            || ProcessInfo.processInfo.environment["PASTRY_PERF_LOG"] == "1"
    }

    /// 性能日志写入（~/Library/Logs/Pastry/perf.log），异步不阻塞热路径
    private static func writePerfLog(_ line: String) {
        perfLogQueue.async {
            guard let logDirBase = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
            let logDir = logDirBase.appendingPathComponent("Logs/Pastry")
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            let logFile = logDir.appendingPathComponent("perf.log")
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(Data((line + "\n").utf8))
                try? handle.close()
            } else {
                try? (line + "\n").write(to: logFile, atomically: true, encoding: .utf8)
            }
        }
    }

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
    func hideAndPaste(_ item: ClipboardItem) async {
        guard panel != nil else { return }

        let t0 = CFAbsoluteTimeGetCurrent()
        let fmt = item.sourceFormat

        isPasting = true
        let targetApp = previousFrontApp
        previousFrontApp = nil

        // 1. 挂起监听，防止读到自己的写入
        ClipboardMonitor.shared.suspend()

        // 2. 先激活目标 App + 隐藏面板，避免完整内容或图片读取让面板退场慢一拍。
        closePanelForPaste(targetApp: targetApp)
        let t1 = CFAbsoluteTimeGetCurrent()

        // 3. 写剪贴板（文本/文件立即，图片 I/O 后台完成）
        let result = await PasteboardWriter.write(item, options: .overlaySingle)
        ClipboardMonitor.shared.ignoreCurrentChange()
        let t2 = CFAbsoluteTimeGetCurrent()
        guard result == .written else {
            // 文件全部缺失或图片读取失败时，静默取消粘贴。
            ClipboardMonitor.shared.resume()
            isPasting = false
            return
        }

        // 4. ⌘V（面板已隐藏，目标 App 在前台）
        let didPostPaste = Self.simulatePaste()
        if didPostPaste {
            SoundFeedback.play(Self.pasteSound)
        }
        let t3 = CFAbsoluteTimeGetCurrent()

        // 5. 后台收尾：DB / 恢复监听 / 刷新
        DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
        DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
        ClipboardMonitor.shared.resume()
        StoreManager.shared.refresh()
        isPasting = false

        if Self.isPerformanceLoggingEnabled {
            let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
            let perfLine = "\(Date()) | type: paste | sourceFormat: \(fmt) | closePanel: \(ms(t1-t0))ms | clipboardWrite: \(ms(t2-t1))ms | simulatePaste: \(ms(t3-t2))ms | total: \(ms(t3-t0))ms"
            log.info("⏱ \(perfLine, privacy: .public)")
            Self.writePerfLog(perfLine)
        }
    }

    /// 多选粘贴：将所有选中条目的文本拼接后一次性 ⌘V
    @MainActor
    func hideAndPasteMultiple(_ items: [ClipboardItem]) {
        guard panel != nil, !items.isEmpty else { return }

        let t0 = CFAbsoluteTimeGetCurrent()

        isPasting = true
        let targetApp = previousFrontApp
        previousFrontApp = nil

        ClipboardMonitor.shared.suspend()

        // 先关闭面板，避免收集完整内容时视觉上慢一拍。
        closePanelForPaste(targetApp: targetApp)
        let t1 = CFAbsoluteTimeGetCurrent()

        // 收集所有文本内容（文本类 + 文件路径），用换行拼接
        let lines = items.compactMap { item -> String? in
            switch item.sourceFormat {
            case .text, .rtf, .html:
                return DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content
            case .fileURL:
                return item.content  // 文件路径也是文本
            case .image:
                return nil  // 跳过多选的图片
            }
        }
        let combined = lines.joined(separator: "\n")
        PasteboardWriter.writePlainText(combined)
        ClipboardMonitor.shared.ignoreCurrentChange()
        let t2 = CFAbsoluteTimeGetCurrent()

        // ⌘V
        let didPostPaste = Self.simulatePaste()
        if didPostPaste {
            SoundFeedback.play(Self.pasteSound)
        }
        let t3 = CFAbsoluteTimeGetCurrent()

        // 后台收尾：每个条目更新 DB
        for item in items {
            DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
            DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
        }
        ClipboardMonitor.shared.resume()
        StoreManager.shared.refresh()
        isPasting = false

        if Self.isPerformanceLoggingEnabled {
            let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
            let perfLine = "\(Date()) | type: pasteMulti | itemCount: \(items.count) | closePanel: \(ms(t1-t0))ms | writeText: \(ms(t2-t1))ms | simulatePaste: \(ms(t3-t2))ms | total: \(ms(t3-t0))ms"
            log.info("⏱ \(perfLine, privacy: .public)")
            Self.writePerfLog(perfLine)
        }
    }

    /// 拖拽开始时临时透传鼠标事件，让拖拽能到达目标应用
    @MainActor
    func beginDragThrough() {
        panel?.ignoresMouseEvents = true
        isDragThrough = true
        panel?.orderOut(nil)   // 拖拽开始即收起面板
        // 轮询鼠标释放来触发清理
        DispatchQueue.main.async { [weak self] in
            self?.pollDragEnd()
        }
    }

    /// 轮询鼠标按键状态，释放时关闭面板
    @MainActor
    private func pollDragEnd() {
        guard isDragThrough else { return }
        if NSEvent.pressedMouseButtons == 0 {
            // 鼠标已释放 → 拖拽完成，直接关闭
            isDragThrough = false
            hide()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.pollDragEnd()
            }
        }
    }

    @MainActor
    private func closePanelForPaste(targetApp: NSRunningApplication?) {
        targetApp?.activate()
        cleanup()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)
    }

    var isVisible: Bool { panel != nil }

    /// 搜索栏是否展开 — ESC 优先级判断
    var isSearchActive = false

    /// 当前键盘事件归属。只有 overlayNavigation 会执行卡片级快捷键。
    var keyboardOwner: OverlayKeyboardOwner = .overlayNavigation

    /// 删除确认弹窗是否活跃 — Esc 放行给系统弹窗处理
    var isAlertActive: Bool { alertActive }

    // MARK: - 私有

    @MainActor
    private func showPanel() {
        let t0 = CFAbsoluteTimeGetCurrent()

        // 若有快捷键触发时刻，预取并计算调用链延迟
        let hotkeyAt = Self.hotkeyFiredAt
        let hotkeyDispatchMs: Int? = hotkeyAt.map { hotkey in
            Int(((t0 - hotkey) * 1000).rounded())
        }

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

        if Self.isPerformanceLoggingEnabled {
            // 性能日志（OSLog + 文件持久化）
            let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
            let itemCount = StoreManager.shared.items.count
            let maxLen = StoreManager.shared.items.map { $0.content.count }.max() ?? 0
            let totalLen = StoreManager.shared.items.reduce(0) { $0 + $1.content.count }

            var perfLine = "\(Date()) | type: panel | items: \(itemCount) | maxContent: \(maxLen) | totalContent: \(totalLen)"
            if let dispatchMs = hotkeyDispatchMs {
                perfLine += " | hotkeyDispatch: \(dispatchMs)ms"
            }
            perfLine += " | panelInit: \(ms(t1-t0))ms | overlayView: \(ms(t2-t1))ms | hostingInit: \(ms(t2a-t2))ms | hostingLayout: \(ms(t3-t2a))ms | orderFront: \(ms(t4-t3))ms | total: \(ms(t4-t0))ms"

            log.info("⏱ \(perfLine, privacy: .public)")
            Self.writePerfLog(perfLine)
        }
        Self.hotkeyFiredAt = nil

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

    private func cleanup() {
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
        isSearchActive = false
        keyboardOwner = .overlayNavigation
    }

    // MARK: - 键盘事件拦截

    private func installKeyboardMonitor() {
        keyboardRouter.install()
    }

    static func cmdNumberIndex(keyCode: UInt16) -> Int? {
        OverlayKeyboardRouter.cmdNumberIndex(keyCode: keyCode)
    }

    static func shouldAllowEnterForIME() -> Bool {
        OverlayKeyboardRouter.shouldAllowEnterForIME()
    }

    static func isRedirectableChar(_ chars: String) -> Bool {
        OverlayKeyboardRouter.isRedirectableChar(chars)
    }

    static func shouldFocusSearch(
        chars: String?,
        isSearchActive: Bool,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        OverlayKeyboardRouter.shouldFocusSearch(
            chars: chars,
            isSearchActive: isSearchActive,
            modifierFlags: modifierFlags
        )
    }

    private func removeKeyboardMonitor() {
        keyboardRouter.remove()
    }

    // MARK: - ⌘V 模拟

    private static func simulatePaste() -> Bool {
        let vKey = CGKeyCode(9)
        guard let source = CGEventSource(stateID: .privateState) else {
            Logger(subsystem: "com.nekutai.pastry", category: "paste").warning("CGEventSource 创建失败 — 可能缺少辅助功能权限")
            return false
        }

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return false
        }

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        cmdDown.postToPid(pid)
        cmdUp.postToPid(pid)
        return true
    }

    deinit {
        removeKeyboardMonitor()
    }
}
