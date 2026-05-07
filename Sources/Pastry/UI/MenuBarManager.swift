import Cocoa
import SwiftUI
import OSLog

// MARK: - 菜单栏管理器（左键打开面板，右键弹出菜单）
final class MenuBarManager: NSObject, NSMenuDelegate {

    nonisolated(unsafe) static let shared = MenuBarManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "menubar")

    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    // MARK: - 菜单项
    private let statsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let storageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private override init() {
        super.init()
    }

    @MainActor
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = nil

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Pastry")
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        buildMenu()
        log.info("菜单栏已配置（左键面板 / 右键菜单）")
    }

    // MARK: - 点击处理

    @MainActor
    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            refreshStats()
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            OverlayPanelManager.shared.toggle()
        }
    }

    // MARK: - 构建菜单

    private func buildMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        let openItem = NSMenuItem(
            title: L10n["menu.open_clipboard"],
            action: #selector(openOverlay),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: nil)
        menu.addItem(openItem)
        menu.addItem(.separator())

        statsItem.isEnabled = false
        menu.addItem(statsItem)
        storageItem.isEnabled = false
        menu.addItem(storageItem)
        menu.addItem(.separator())

        let clearItem = NSMenuItem(
            title: L10n["menu.clear_history"],
            action: #selector(clearHistoryAction),
            keyEquivalent: ""
        )
        clearItem.target = self
        clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(clearItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(
            title: L10n["menu.about"],
            action: #selector(openAboutAction),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
        menu.addItem(aboutItem)

        let settingsItem = NSMenuItem(
            title: L10n["menu.settings"],
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n["menu.quit"],
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)
    }

    @MainActor
    private func refreshStats() {
        let stats = StoreManager.shared.stats
        statsItem.title = String(format: L10n["menu.stats"], stats.totalItems, stats.todayItems)
        if stats.storageSizeKB > 0 {
            storageItem.title = String(format: L10n["menu.storage"], stats.storageSizeKB)
            storageItem.isHidden = false
        } else {
            storageItem.isHidden = true
        }
    }

    // MARK: - 操作

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
