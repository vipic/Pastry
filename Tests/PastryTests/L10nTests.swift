import XCTest
@testable import Pastry

// MARK: - L10n 本地化测试套件

final class L10nTests: XCTestCase {

    // MARK: - 菜单栏文案键值存在

    /// 菜单栏所有键在 catalog 中都有中英文翻译
    func testMenuBarKeysExist() {
        let keys = [
            "menu.open_clipboard", "menu.clear_history",
            "menu.about", "menu.settings", "menu.quit",
            "menu.stats", "menu.storage"
        ]
        for key in keys {
            let value = L10n[key]
            XCTAssertNotEqual(value, key,
                              "\(key) 应有翻译，不应返回 key 本身")
        }
    }

    /// 右键卡片菜单所有键存在
    func testContextMenuKeysExist() {
        let keys = [
            "context.pin", "context.unpin",
            "context.open", "context.open_with", "context.open_with_other",
            "context.preview", "context.share", "context.delete",
            "context.show_in_finder"
        ]
        for key in keys {
            let value = L10n[key]
            XCTAssertNotEqual(value, key,
                              "\(key) 应有翻译，不应返回 key 本身")
        }
    }

    /// 历史保留设置所有键存在
    func testHistoryRetentionSettingsKeysExist() {
        let keys = [
            "settings.history.section",
            "settings.history.max_items",
            "settings.history.max_age",
            "settings.history.retention_hint",
            "settings.history.max_items_value",
            "settings.history.age_never",
            "settings.history.age_days",
            "settings.history.age_one_year",
            "card.selected",
            "empty.no_pins_hint",
            "empty.no_results_hint",
            "empty.no_history_hint"
        ]
        for key in keys {
            let value = L10n[key]
            XCTAssertNotEqual(value, key,
                              "\(key) 应有翻译，不应返回 key 本身")
        }
    }

    // MARK: - 语言切换

    /// 切换到英文后返回英文翻译
    func testSwitchToEnglish() {
        let saved = UserDefaults.standard.string(forKey: "PastryLanguage")
        UserDefaults.standard.set("en", forKey: "PastryLanguage")
        // 强制重新加载 catalog
        L10n.reloadCatalogForTesting()

        let value = L10n["menu.open_clipboard"]
        XCTAssertEqual(value, "Open Clipboard")

        if let saved = saved {
            UserDefaults.standard.set(saved, forKey: "PastryLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "PastryLanguage")
        }
        L10n.reloadCatalogForTesting()
    }

    /// 切换到中文后返回中文翻译
    func testSwitchToChinese() {
        let saved = UserDefaults.standard.string(forKey: "PastryLanguage")
        UserDefaults.standard.set("zh-Hans", forKey: "PastryLanguage")
        L10n.reloadCatalogForTesting()

        let value = L10n["menu.open_clipboard"]
        XCTAssertEqual(value, "打开剪贴板")

        if let saved = saved {
            UserDefaults.standard.set(saved, forKey: "PastryLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "PastryLanguage")
        }
        L10n.reloadCatalogForTesting()
    }

    // MARK: - Fallback

    /// 不存在的 key 返回 key 本身
    func testMissingKeyReturnsSelf() {
        let value = L10n["this.key.does.not.exist"]
        XCTAssertEqual(value, "this.key.does.not.exist")
    }
}
