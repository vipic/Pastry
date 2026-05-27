import Cocoa

struct MenuBarMenuActions {
    let openOverlay: Selector
    let clearHistory: Selector
    let openAbout: Selector
    let openSettings: Selector
    let checkUpdate: Selector
    let quit: Selector
}

struct MenuBarMenuBuildResult {
    let menu: NSMenu
    let statsItem: NSMenuItem
    let storageItem: NSMenuItem
}

enum MenuBarMenuFactory {
    static func build(
        target: AnyObject,
        actions: MenuBarMenuActions,
        stats: ClipboardStats,
        isUpdateDevBuild: Bool
    ) -> MenuBarMenuBuildResult {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let openItem = item(
            title: L10n["menu.open_clipboard"],
            action: actions.openOverlay,
            target: target,
            symbolName: "rectangle.on.rectangle"
        )
        menu.addItem(openItem)
        menu.addItem(.separator())

        let statsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        menu.addItem(statsItem)

        let storageItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        storageItem.isEnabled = false
        menu.addItem(storageItem)
        menu.addItem(.separator())

        let clearItem = item(
            title: L10n["menu.clear_history"],
            action: actions.clearHistory,
            target: target,
            symbolName: "trash"
        )
        menu.addItem(clearItem)
        menu.addItem(.separator())

        let aboutItem = item(
            title: L10n["menu.about"],
            action: actions.openAbout,
            target: target,
            symbolName: "info.circle"
        )
        menu.addItem(aboutItem)

        let settingsItem = item(
            title: L10n["menu.settings"],
            action: actions.openSettings,
            target: target,
            symbolName: "gearshape",
            keyEquivalent: ",",
            keyEquivalentModifierMask: .command
        )
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let updateItem = item(
            title: L10n["menu.check_update"],
            action: actions.checkUpdate,
            target: target,
            symbolName: "arrow.triangle.2.circlepath"
        )
        updateItem.isEnabled = !isUpdateDevBuild
        menu.addItem(updateItem)
        menu.addItem(.separator())

        let quitItem = item(
            title: L10n["menu.quit"],
            action: actions.quit,
            target: target,
            symbolName: "power",
            keyEquivalent: "q",
            keyEquivalentModifierMask: .command
        )
        menu.addItem(quitItem)

        updateStats(statsItem: statsItem, storageItem: storageItem, stats: stats)

        return MenuBarMenuBuildResult(menu: menu, statsItem: statsItem, storageItem: storageItem)
    }

    static func updateStats(
        statsItem: NSMenuItem,
        storageItem: NSMenuItem,
        stats: ClipboardStats
    ) {
        statsItem.title = String(format: L10n["menu.stats"], stats.totalItems, stats.todayItems)
        if stats.storageSizeKB > 0 {
            storageItem.title = String(format: L10n["menu.storage"], stats.storageSizeKB)
            storageItem.isHidden = false
        } else {
            storageItem.isHidden = true
        }
    }

    private static func item(
        title: String,
        action: Selector?,
        target: AnyObject,
        symbolName: String,
        keyEquivalent: String = "",
        keyEquivalentModifierMask: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        menuItem.keyEquivalentModifierMask = keyEquivalentModifierMask
        menuItem.target = target
        menuItem.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        return menuItem
    }
}
