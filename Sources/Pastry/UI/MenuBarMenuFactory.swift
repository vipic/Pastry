import Cocoa

struct MenuBarMenuActions {
    let openOverlay: Selector
    let checkUpdates: Selector
    let clearHistory: Selector
    let openSettings: Selector
    let quit: Selector
}

struct MenuBarMenuBuildResult {
    let menu: NSMenu
}

enum MenuBarMenuFactory {
    static func build(
        target: AnyObject,
        actions: MenuBarMenuActions
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

        let updatesItem = item(
            title: L10n["menu.check_updates"],
            action: actions.checkUpdates,
            target: target,
            symbolName: "arrow.triangle.2.circlepath"
        )
        menu.addItem(updatesItem)

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

        let clearItem = item(
            title: L10n["menu.clear_history"],
            action: actions.clearHistory,
            target: target,
            symbolName: "trash"
        )
        menu.addItem(clearItem)
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

        return MenuBarMenuBuildResult(menu: menu)
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
