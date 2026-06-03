import XCTest
@testable import Pastry
import SwiftUI

// MARK: - Constants 测试套件
// 验证常量定义的一致性

final class ConstantsTests: XCTestCase {

    // MARK: - UserDefaults Keys

    func testHotkeyKeyCodeKeyUsedInManager() {
        // GlobalHotkeyManager 读取 key 一致
        XCTAssertEqual(UserDefaultsKeys.hotkeyKeyCode, "hotkey_keycode")
    }

    func testHotkeyModifiersKeyUsedInManager() {
        XCTAssertEqual(UserDefaultsKeys.hotkeyModifiers, "hotkey_modifiers")
    }

    func testLaunchAtLoginKey() {
        XCTAssertEqual(UserDefaultsKeys.launchAtLogin, "launch_at_login")
    }

    func testSoundEnabledKey() {
        XCTAssertEqual(UserDefaultsKeys.soundEnabled, "sound_enabled")
    }

    func testLinkPreviewNetworkEnabledKey() {
        XCTAssertEqual(UserDefaultsKeys.linkPreviewNetworkEnabled, "link_preview_network_enabled")
    }

    func testHistoryRetentionKeys() {
        XCTAssertEqual(UserDefaultsKeys.historyMaxItems, "history_max_items")
        XCTAssertEqual(UserDefaultsKeys.historyMaxAgeDays, "history_max_age_days")
    }

    func testPerformanceLoggingKey() {
        XCTAssertEqual(UserDefaultsKeys.performanceLoggingEnabled, "performance_logging_enabled")
    }

    func testSettingsAccessibilityIdentifiers() {
        XCTAssertEqual(AccessibilityIdentifiers.Settings.performanceLoggingToggle, "settings.performance-logging-toggle")
    }

    func testHistoryRetentionPolicySanitizesValues() {
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxItems(500), 500)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxItems(-1), HistoryRetentionPolicy.defaultMaxItems)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxAgeDays(30), 30)
        XCTAssertEqual(HistoryRetentionPolicy.sanitizedMaxAgeDays(13), HistoryRetentionPolicy.defaultMaxAgeDays)
    }

    // MARK: - AppName

    func testAppName() {
        #if DEBUG
        XCTAssertEqual(Constants.appName, "Pastry Dev")
        #else
        XCTAssertEqual(Constants.appName, "Pastry")
        #endif
    }

    // MARK: - Colors

    func testClipBackgroundColor() {
        let color = Color.clipBackground
        // NSColor → Color 可双向转换
        let nsColor = NSColor(color)
        XCTAssertNotNil(nsColor.usingColorSpace(.sRGB))
    }

    func testClipRowHoverColor() {
        let color = Color.clipRowHover
        let nsColor = NSColor(color)
        XCTAssertNotNil(nsColor.usingColorSpace(.sRGB))
    }

    func testClipAccentColor() {
        let color = Color.clipAccent
        let nsColor = NSColor(color)
        XCTAssertNotNil(nsColor.usingColorSpace(.sRGB))
    }

    func testUICardConstantsAreStable() {
        XCTAssertEqual(UIConstants.Card.size, 240)
        XCTAssertEqual(UIConstants.Card.headerHeight, 48)
        XCTAssertEqual(UIConstants.Card.cornerRadius, 10)
    }

    func testUIOverlayConstantsAreStable() {
        XCTAssertEqual(UIConstants.Overlay.cardSpacing, 10)
        XCTAssertEqual(UIConstants.Overlay.emptyStateMinHeight, UIConstants.Card.size + 12)
        XCTAssertEqual(UIConstants.Overlay.compactListMaxWidth, 520)
    }

    // MARK: - SF Symbols

    func testAppIconSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.app.isEmpty)
    }

    func testSearchSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.search.isEmpty)
    }

    func testStarSymbolsNotEmpty() {
        XCTAssertFalse(AppIcons.star.isEmpty)
        XCTAssertFalse(AppIcons.starEmpty.isEmpty)
    }

    func testSettingsSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.settings.isEmpty)
    }

    func testPinSymbolNotEmpty() {
        XCTAssertFalse(AppIcons.pin.isEmpty)
    }
}
