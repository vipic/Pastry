import Cocoa
import XCTest
@testable import Pastry

@MainActor
final class MenuBarMenuFactoryTests: XCTestCase {
    func testBuildCreatesExpectedMenuItems() {
        let result = makeMenu(stats: ClipboardStats(totalItems: 12, todayItems: 3, favoriteCount: 2, storageSizeKB: 128))

        let titles = result.menu.items
            .filter { !$0.isSeparatorItem }
            .map(\.title)

        XCTAssertEqual(titles, [
            L10n["menu.open_clipboard"],
            String(format: L10n["menu.stats"], 12, 3),
            String(format: L10n["menu.storage"], 128),
            L10n["menu.clear_history"],
            L10n["menu.about"],
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

    func testStorageItemHiddenWhenStorageIsEmpty() {
        let result = makeMenu(stats: ClipboardStats(totalItems: 1, todayItems: 1, favoriteCount: 0, storageSizeKB: 0))

        XCTAssertTrue(result.storageItem.isHidden)
    }

    func testUpdateStatsRefreshesExistingItems() {
        let result = makeMenu(stats: ClipboardStats(totalItems: 1, todayItems: 1, favoriteCount: 0, storageSizeKB: 0))

        MenuBarMenuFactory.updateStats(
            statsItem: result.statsItem,
            storageItem: result.storageItem,
            stats: ClipboardStats(totalItems: 42, todayItems: 7, favoriteCount: 4, storageSizeKB: 256)
        )

        XCTAssertEqual(result.statsItem.title, String(format: L10n["menu.stats"], 42, 7))
        XCTAssertEqual(result.storageItem.title, String(format: L10n["menu.storage"], 256))
        XCTAssertFalse(result.storageItem.isHidden)
    }

    func testStatusItemClickRouting() {
        XCTAssertTrue(MenuBarManager.shouldOpenMenu(for: .rightMouseUp))
        XCTAssertFalse(MenuBarManager.shouldOpenMenu(for: .leftMouseUp))
        XCTAssertFalse(MenuBarManager.shouldOpenMenu(for: nil))
    }

    private func makeMenu(
        stats: ClipboardStats = ClipboardStats(totalItems: 0, todayItems: 0, favoriteCount: 0, storageSizeKB: 0)
    ) -> MenuBarMenuBuildResult {
        MenuBarMenuFactory.build(
            target: DummyMenuTarget(),
            actions: MenuBarMenuActions(
                openOverlay: #selector(DummyMenuTarget.openOverlay),
                clearHistory: #selector(DummyMenuTarget.clearHistory),
                openAbout: #selector(DummyMenuTarget.openAbout),
                openSettings: #selector(DummyMenuTarget.openSettings),
                quit: #selector(DummyMenuTarget.quit)
            ),
            stats: stats
        )
    }

    private func item(titled title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }
}

private final class DummyMenuTarget: NSObject {
    @objc func openOverlay() {}
    @objc func clearHistory() {}
    @objc func openAbout() {}
    @objc func openSettings() {}
    @objc func quit() {}
}
