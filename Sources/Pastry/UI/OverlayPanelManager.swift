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
    @MainActor
    func hideAndPaste(_ item: ClipboardItem) {
        guard panel != nil else { return }

        removeKeyboardMonitor()
        panel?.orderOut(nil)
        panel = nil

        let targetApp = previousFrontApp
        previousFrontApp = nil

        NotificationCenter.default.post(name: .overlayDidHide, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ClipboardMonitor.shared.suspend()

            if let app = targetApp {
                app.activate(options: .activateIgnoringOtherApps)
            }

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
                    pb.writeObjects([image])
                }
            }

            DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
            DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)
            ClipboardMonitor.shared.resume()
            StoreManager.shared.refresh()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Self.simulatePaste()
            }
        }
    }

    var isVisible: Bool { panel != nil }

    // MARK: - 私有

    @MainActor
    private func showPanel() {
        guard let screen = NSScreen.main else {
            log.error("无法获取主屏幕")
            return
        }

        previousFrontApp = NSWorkspace.shared.frontmostApplication

        let screenFrame = screen.frame

        let newPanel = ClipboardOverlayPanel(
            contentRect: screenFrame,
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.level = .screenSaver
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
            // Esc：弹窗激活时放行，否则关闭面板
            if event.keyCode == 53 {
                if self.alertActive { return event }
                NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
                return nil
            }
            // ⌘A 全选
            if event.keyCode == 0, event.modifierFlags.contains(.command) {
                NotificationCenter.default.post(name: .overlaySelectAll, object: nil)
                return nil
            }
            // Delete / Forward Delete 删除选中
            if event.keyCode == 51 || event.keyCode == 117 {
                NotificationCenter.default.post(name: .overlayDeleteSelected, object: nil)
                return nil
            }
            return event
        }
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

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return
        }

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        cmdDown.post(tap: .cgSessionEventTap)
        cmdUp.post(tap: .cgSessionEventTap)
    }

    deinit {
        removeKeyboardMonitor()
    }
}
