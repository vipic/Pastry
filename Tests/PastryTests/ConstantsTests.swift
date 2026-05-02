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

    // MARK: - AppName

    func testAppName() {
        XCTAssertEqual(Constants.appName, "Pastry")
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
