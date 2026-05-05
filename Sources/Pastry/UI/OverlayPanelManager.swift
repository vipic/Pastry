import Cocoa
import SwiftUI
import OSLog

// MARK: - 自定义覆盖层面板
final class ClipboardOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 全屏覆盖层面板管理器
final class OverlayPanelManager {

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
    private var previousFrontApp: NSRunningApplication?
    private var alertActive = false

    private init() {
        NotificationCenter.default.addObserver(
            forName: .overlayAlertActive, object: nil, queue: .main
        ) { [weak self] note in
            self?.alertActive = (note.userInfo?["active"] as? Bool) ?? false
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

        let targetApp = previousFrontApp
        previousFrontApp = nil

        // 1. 挂起监听，防止读到自己的写入
        ClipboardMonitor.shared.suspend()

        // 2. 写剪贴板（立即，主线程 <1ms）
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.contentType {
        case .text, .rtf, .html:
            pb.setString(item.content, forType: .string)
        case .fileURL:
            let urls = item.content.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
            pb.writeObjects(urls as [NSURL])
        case .image:
            if let image = NSImage(contentsOfFile: item.content) {
                if let annotation = item.textAnnotation, !annotation.isEmpty {
                    let attr = NSMutableAttributedString()
                    let attachment = NSTextAttachment()
                    attachment.image = image
                    attr.append(NSAttributedString(attachment: attachment))
                    attr.append(NSAttributedString(string: "\n\(annotation)"))
                    if let rtfd = try? attr.data(
                        from: NSRange(location: 0, length: attr.length),
                        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
                    ) {
                        pb.setData(rtfd, forType: .rtfd)
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
    }

    var isVisible: Bool { panel != nil }

    /// 搜索栏是否展开 — ESC 优先级判断
    var isSearchActive = false

    // MARK: - 私有

    @MainActor
    private func showPanel() {
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

        let overlayView = OverlayView()
            .environmentObject(StoreManager.shared)

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = screenFrame
        hostingView.autoresizingMask = [.width, .height]
        newPanel.contentView = hostingView

        newPanel.orderFrontRegardless()
        newPanel.makeKey()

        self.panel = newPanel
        installKeyboardMonitor()

        log.info("覆盖层已显示")
    }

    private func cleanup() {
        removeKeyboardMonitor()
        panel?.orderOut(nil)
        panel = nil
        previousFrontApp = nil
    }

    // MARK: - 键盘事件拦截

    private func installKeyboardMonitor() {
        removeKeyboardMonitor()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return nil }
            // Esc：搜索栏展开时先关搜索栏，否则关闭面板
            if event.keyCode == 53 {
                if self.alertActive { return event }
                if self.isSearchActive {
                    NotificationCenter.default.post(name: .overlayCloseSearch, object: nil)
                    return nil
                }
                NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
                return nil
            }
            // ⌘F 搜索
            if event.keyCode == 3, event.modifierFlags.contains(.command) {
                if !self.isSearchActive {
                    NotificationCenter.default.post(name: .overlayOpenSearch, object: nil)
                }
                return nil
            }
            // ⌘A 全选 — 若焦点在文本输入框则放行
            if event.keyCode == 0, event.modifierFlags.contains(.command) {
                if Self.isTextInputFocused() { return event }
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
            default:
                break
            }
            return event
        }
    }

    /// 检查当前焦点是否在文本输入框内（搜索框等）
    private static func isTextInputFocused() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        // 限定为已知的文本编辑类，避免误判自定义 View
        if responder.isKind(of: NSTextView.self) { return true }
        if responder.isKind(of: NSTextField.self) { return true }
        if responder.isKind(of: NSSearchField.self) { return true }
        return false
    }

    private func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
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
