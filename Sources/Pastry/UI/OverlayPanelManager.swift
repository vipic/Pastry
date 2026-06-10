import Cocoa
import SwiftUI
import OSLog

// MARK: - 自定义覆盖层面板
final class ClipboardOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
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

        // 2. 写剪贴板（文本/文件立即，图片 I/O 后台完成）
        let result = await PasteboardWriter.write(item, options: .overlaySingle)
        let t1 = CFAbsoluteTimeGetCurrent()
        guard result == .written else {
            // 文件全部缺失或图片读取失败时，静默取消粘贴，关闭面板
            ClipboardMonitor.shared.resume()
            panel?.orderOut(nil)
            panel = nil
            removeKeyboardMonitor()
            NotificationCenter.default.post(name: .overlayDidHide, object: nil)
            isPasting = false
            return
        }

        // 内容就绪 → 反馈音效（异步避免阻塞粘贴）
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            DispatchQueue.main.async { Self.pasteSound?.play() }
        }

        // 3. 激活目标 App + 隐藏面板
        targetApp?.activate()
        let t2 = CFAbsoluteTimeGetCurrent()
        panel?.orderOut(nil)
        panel = nil
        removeKeyboardMonitor()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)
        let t3 = CFAbsoluteTimeGetCurrent()

        // 4. ⌘V（面板已隐藏，目标 App 在前台）
        Self.simulatePaste()
        let t4 = CFAbsoluteTimeGetCurrent()

        // 5. 后台收尾：DB / 恢复监听 / 刷新
        DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
        DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
        ClipboardMonitor.shared.resume()
        StoreManager.shared.refresh()
        isPasting = false

        if Self.isPerformanceLoggingEnabled {
            let ms = { (d: CFAbsoluteTime) in Int((d * 1000).rounded()) }
            let perfLine = "\(Date()) | type: paste | sourceFormat: \(fmt) | clipboardWrite: \(ms(t1-t0))ms | activateApp: \(ms(t2-t1))ms | orderOut: \(ms(t3-t2))ms | simulatePaste: \(ms(t4-t3))ms | total: \(ms(t4-t0))ms"
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
        let t1 = CFAbsoluteTimeGetCurrent()

        // 音效
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            DispatchQueue.main.async { Self.pasteSound?.play() }
        }

        // 激活目标 App + 隐藏面板
        targetApp?.activate()
        let t2 = CFAbsoluteTimeGetCurrent()
        panel?.orderOut(nil)
        panel = nil
        removeKeyboardMonitor()
        NotificationCenter.default.post(name: .overlayDidHide, object: nil)
        let t3 = CFAbsoluteTimeGetCurrent()

        // ⌘V
        Self.simulatePaste()
        let t4 = CFAbsoluteTimeGetCurrent()

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
            let perfLine = "\(Date()) | type: pasteMulti | itemCount: \(items.count) | writeText: \(ms(t1-t0))ms | activateApp: \(ms(t2-t1))ms | orderOut: \(ms(t3-t2))ms | simulatePaste: \(ms(t4-t3))ms | total: \(ms(t4-t0))ms"
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

    var isVisible: Bool { panel != nil }

    /// 搜索栏是否展开 — ESC 优先级判断
    var isSearchActive = false

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
    }

    // MARK: - 键盘事件拦截

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return nil }
            // Esc：筛选气泡 → 预览 popover → 搜索栏 → 关闭面板（逐层收起）
            if event.keyCode == 53 {
                if self.alertActive { return event }
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
            let extend = event.modifierFlags.contains(.shift)
            switch event.keyCode {
            case 126: // 上
                if self.isSearchActive { return event }
                NotificationCenter.default.post(name: .overlayMoveUp, object: nil, userInfo: ["extend": extend])
                return nil
            case 125: // 下
                if self.isSearchActive { return event }
                NotificationCenter.default.post(name: .overlayMoveDown, object: nil, userInfo: ["extend": extend])
                return nil
            case 123: // 左
                if self.isSearchActive { return event }
                NotificationCenter.default.post(name: .overlayMoveLeft, object: nil, userInfo: ["extend": extend])
                return nil
            case 124: // 右
                if self.isSearchActive { return event }
                NotificationCenter.default.post(name: .overlayMoveRight, object: nil, userInfo: ["extend": extend])
                return nil
            case 36: // Enter
                // IME 正在拼写时放行 —— 中文拼音按回车确认英文上屏，不应触发粘贴
                if Self.shouldAllowEnterForIME() {
                    return event
                }
                if self.isSearchActive {
                    NotificationCenter.default.post(name: .overlaySearchEnterPaste, object: nil)
                    return nil
                }
                NotificationCenter.default.post(name: .overlayConfirmPaste, object: nil)
                return nil
            // ⌘+1~9 — 粘贴对应序号的卡片（搜索时也生效）
            case let kc where event.modifierFlags.contains(.command):
                if let idx = Self.cmdNumberIndex(keyCode: kc) {
                    NotificationCenter.default.post(name: .overlayCmdPaste, object: nil,
                                                    userInfo: ["index": idx])
                    return nil
                }
                fallthrough
            default:
                if self.isSearchActive {
                    // 搜索框活跃 — 非快捷键字符放行给 TextField
                    break
                }
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

    /// 当前输入框是否有 IME 正在拼写（中文拼音等）。
    /// Enter 键在 marked text 期间应放行给输入法确认上屏，不应被面板拦截。
    static func shouldAllowEnterForIME() -> Bool {
        guard NSApp != nil,
              let window = NSApp.keyWindow,
              let fr = window.firstResponder as? NSTextView else { return false }
        return fr.hasMarkedText()
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
