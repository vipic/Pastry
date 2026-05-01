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
    private let log = Logger(subsystem: "com.clipboardmanager", category: "overlay")

    private var panel: ClipboardOverlayPanel?
    private var keyboardMonitor: Any?
    private var previousFrontApp: NSRunningApplication?

    private init() {}

    // MARK: - 显示/隐藏

    @MainActor
    func show() {
        guard panel == nil else { return }
        showPanel()
    }

    @MainActor
    func hide() {
        cleanup()
        log.info("覆盖层已关闭")
    }

    @MainActor
    func toggle() {
        if panel != nil {
            hide()
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

        // 延迟后：暂停监听 → 激活目标应用 → 写入剪贴板 → 更新条目时间戳 → 恢复监听
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // 暂停监听，避免写入剪贴板时产生重复条目
            ClipboardMonitor.shared.suspend()

            if let app = targetApp {
                app.activate(options: .activateIgnoringOtherApps)
            }

            // 写入剪贴板
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

            // 更新原条目的时间戳到最新（移动到列表最前），而非创建新条目
            DatabaseManager.shared.bumpTimestamp(id: item.id.uuidString)
            DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)

            // 恢复监听（自动跳过我们自己写入的变化）
            ClipboardMonitor.shared.resume()

            // 刷新内存列表以反映最新的时间戳顺序
            StoreManager.shared.refresh()

            // 等目标应用完全激活后再发 ⌘V
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
            guard self != nil else { return nil }
            if event.keyCode == 53 {
                // 发通知让 OverlayView 触发退场动画
                NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
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

        // cgSessionEventTap: 发到当前用户会话事件流，不需要辅助功能权限也能工作
        cmdDown.post(tap: .cgSessionEventTap)
        cmdUp.post(tap: .cgSessionEventTap)
    }

    deinit {
        removeKeyboardMonitor()
    }
}
