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
            L10n["menu.onboarding"],
            L10n["menu.check_updates"],
            L10n["menu.settings"],
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

    func testMenuHasTwoSeparatorsAndFiveActions() {
        let menu = makeMenu().menu
        let separators = menu.items.filter(\.isSeparatorItem)
        let actions = menu.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(separators.count, 2)
        XCTAssertEqual(actions.count, 5)
        XCTAssertEqual(menu.items.count, 7)
    }

    func testMenuItemsHaveTargetsAndSymbols() {
        let result = makeMenu()
        let target = DummyMenuTarget()
        // rebuild with known target instance
        let menu = MenuBarMenuFactory.build(
            target: target,
            actions: MenuBarMenuActions(
                openOverlay: #selector(DummyMenuTarget.openOverlay),
                showOnboarding: #selector(DummyMenuTarget.showOnboarding),
                checkUpdates: #selector(DummyMenuTarget.checkUpdates),
                openSettings: #selector(DummyMenuTarget.openSettings),
                quit: #selector(DummyMenuTarget.quit)
            )
        ).menu

        for item in menu.items where !item.isSeparatorItem {
            XCTAssertTrue(item.target === target)
            XCTAssertNotNil(item.action)
            XCTAssertNotNil(item.image, "菜单项应有 SF Symbol 图标: \(item.title)")
        }
        _ = result
    }

    func testMenuAutoenablesItemsIsDisabled() {
        XCTAssertFalse(makeMenu().menu.autoenablesItems)
    }

    private func makeMenu() -> MenuBarMenuBuildResult {
        MenuBarMenuFactory.build(
            target: DummyMenuTarget(),
            actions: MenuBarMenuActions(
                openOverlay: #selector(DummyMenuTarget.openOverlay),
                showOnboarding: #selector(DummyMenuTarget.showOnboarding),
                checkUpdates: #selector(DummyMenuTarget.checkUpdates),
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
    @objc func showOnboarding() {}
    @objc func checkUpdates() {}
    @objc func openSettings() {}
    @objc func quit() {}
}
