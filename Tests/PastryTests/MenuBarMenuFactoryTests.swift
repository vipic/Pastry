import Cocoa
import XCTest
@testable import Pastry

@MainActor
final class MenuBarMenuFactoryTests: XCTestCase {
    func testBuildCreatesExpectedMenuItems() {
        let result = makeMenu()

        let titles = result.menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)

        XCTAssertEqual(titles, [
            L10n["menu.open_clipboard"],
            L10n["menu.check_updates"],
            L10n["menu.settings"],
            L10n["menu.clear_history"],
            L10n["menu.quit"],
        ])
    }

    func testKeyboardShortcutsAreConfigured() {
        let result = makeMenu()
        let settingsItem = item(titled: L10n["menu.settings"], in: result.menu)
        let quitItem = item(titled: L10n["menu.quit"], in: result.menu)

        XCTAssertEqual(settingsItem?.keyEquivalent, ",")
        XCTAssertEqual(settingsItem?.keyEquivalentModifierMask, .command)
        XCTAssertEqual(quitItem?.keyEquivalent, "q")
        XCTAssertEqual(quitItem?.keyEquivalentModifierMask, .command)
    }

    func testStatusItemClickRouting() {
        XCTAssertTrue(MenuBarManager.shouldOpenMenu(for: .rightMouseUp))
        XCTAssertFalse(MenuBarManager.shouldOpenMenu(for: .leftMouseUp))
        XCTAssertFalse(MenuBarManager.shouldOpenMenu(for: nil))
    }

    private func makeMenu() -> MenuBarMenuBuildResult {
        MenuBarMenuFactory.build(
            target: DummyMenuTarget(),
            actions: MenuBarMenuActions(
                openOverlay: #selector(DummyMenuTarget.openOverlay),
                checkUpdates: #selector(DummyMenuTarget.checkUpdates),
                clearHistory: #selector(DummyMenuTarget.clearHistory),
                openSettings: #selector(DummyMenuTarget.openSettings),
                quit: #selector(DummyMenuTarget.quit)
            )
        )
    }

    private func item(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }
}

private final class DummyMenuTarget: NSObject {
    @objc func openOverlay() {}
    @objc func checkUpdates() {}
    @objc func clearHistory() {}
    @objc func openSettings() {}
    @objc func quit() {}
}
