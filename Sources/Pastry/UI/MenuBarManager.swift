import Cocoa
import SwiftUI
import OSLog

// MARK: - 菜单栏管理器（左键打开面板，右键弹出菜单）
final class MenuBarManager: NSObject, NSMenuDelegate {

    nonisolated(unsafe) static let shared = MenuBarManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "menubar")

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var statsItem: NSMenuItem?
    private var storageItem: NSMenuItem?

    private override init() {
        super.init()
    }

    @MainActor
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        buildMenu()
        // macOS 27: sendAction(.rightMouseUp) 和 local monitor 均无法捕获右键。
        // menu 属性会覆盖左键 action，因此统一用左键弹出菜单，
        // overlay 面板通过全局快捷键或菜单第一项「打开剪贴板」唤出。
        statusItem.menu = menu

        if let button = statusItem.button {
            button.image = menuBarIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
        }

        log.info("菜单栏已配置")
    }

    // MARK: - 点击处理

    @MainActor
    @objc private func statusItemClicked() {
        OverlayPanelManager.shared.toggle()
    }


    // MARK: - 构建菜单

    @MainActor
    private func buildMenu() {
        let result = MenuBarMenuFactory.build(
            target: self,
            actions: MenuBarMenuActions(
                openOverlay: #selector(openOverlay),
                clearHistory: #selector(clearHistoryAction),
                openAbout: #selector(openAboutAction),
                openSettings: #selector(openSettingsAction),
                quit: #selector(quitApp)
            ),
            stats: StoreManager.shared.stats
        )
        menu = result.menu
        menu.delegate = self
        statsItem = result.statsItem
        storageItem = result.storageItem
    }

    @MainActor
    private func refreshStats() {
        guard let statsItem, let storageItem else { return }
        MenuBarMenuFactory.updateStats(
            statsItem: statsItem,
            storageItem: storageItem,
            stats: StoreManager.shared.stats
        )
    }

    // MARK: - 操作

    private func menuBarIcon() -> NSImage? {
        let symbolName = isUpdateDevBuild ? "clipboard" : "doc.on.clipboard"
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pastry")
    }

    private var isUpdateDevBuild: Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        return version.contains("-dev")
    }

    @MainActor
    @objc private func openOverlay() {
        OverlayPanelManager.shared.toggle()
    }

    @MainActor
    @objc private func openAboutAction() {
        OverlayPanelManager.shared.hide()
        DispatchQueue.main.async {
            AppDelegate.shared?.showAboutWindow()
        }
    }

    @MainActor
    @objc private func clearHistoryAction() {
        StoreManager.shared.clearNonPinned()
    }

    @MainActor
    @objc private func openSettingsAction() {
        OverlayPanelManager.shared.hide()
        // 延迟一帧：等面板关闭和菜单退出 tracking mode 后再创建设置窗口
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow()
        }
    }

    @MainActor
    @objc private func quitApp() {
        OverlayPanelManager.shared.hide()
        GlobalHotkeyManager.shared.unregister()
        NSApp.terminate(nil)
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in
            refreshStats()
        }
    }
}
