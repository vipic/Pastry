import XCTest
@testable import Pastry
import AppKit
import Carbon

// MARK: - 快捷键工具测试套件
// 测试 NSEvent→Carbon 修饰键转换、快捷键显示名称、keyCode 映射

final class HotkeyUtilsTests: XCTestCase {

    // MARK: - nseventModifiersToCarbon

    func testCommandOnly() {
        let flags: NSEvent.ModifierFlags = .command
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey))
    }

    func testShiftOnly() {
        let flags: NSEvent.ModifierFlags = .shift
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(shiftKey))
    }

    func testOptionOnly() {
        let flags: NSEvent.ModifierFlags = .option
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(optionKey))
    }

    func testControlOnly() {
        let flags: NSEvent.ModifierFlags = .control
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(controlKey))
    }

    func testCommandShift() {
        let flags: NSEvent.ModifierFlags = [.command, .shift]
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey) | UInt32(shiftKey))
    }

    func testCommandOptionControl() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .control]
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey) | UInt32(optionKey) | UInt32(controlKey))
    }

    func testAllFourModifiers() {
        let flags: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, UInt32(cmdKey) | UInt32(shiftKey) | UInt32(optionKey) | UInt32(controlKey))
    }

    func testNoModifiers() {
        let flags: NSEvent.ModifierFlags = []
        let carbon = nseventModifiersToCarbon(flags)
        XCTAssertEqual(carbon, 0)
    }

    // MARK: - NSEvent vs Carbon 编码差异验证（关键测试）

    func testNSEventCommandNotEqualToCarbonCmdKey() {
        // 确认 NSEvent.command.rawValue (0x100000) ≠ Carbon cmdKey (0x0100)
        XCTAssertNotEqual(UInt32(NSEvent.ModifierFlags.command.rawValue), UInt32(cmdKey),
            "NSEvent 和 Carbon 修饰键编码不同 — 转换函数必不可少")
    }

    func testNSEventShiftNotEqualToCarbonShiftKey() {
        XCTAssertNotEqual(UInt32(NSEvent.ModifierFlags.shift.rawValue), UInt32(shiftKey))
    }

    // MARK: - shortcutDisplayString

    func testShortcutDisplayStringCmdShiftV() {
        // keyCode 9 = V, modifiers = cmdKey|shiftKey = 0x0100|0x0200
        let result = shortcutDisplayString(keyCode: 9, modifiers: Int(UInt32(cmdKey) | UInt32(shiftKey)))
        XCTAssertTrue(result.contains("⌘"))
        XCTAssertTrue(result.contains("⇧"))
        XCTAssertTrue(result.contains("V"))
    }

    func testShortcutDisplayStringOptionW() {
        let result = shortcutDisplayString(keyCode: 13, modifiers: Int(UInt32(optionKey)))
        XCTAssertTrue(result.contains("⌥"))
        XCTAssertTrue(result.contains("W"))
    }

    func testShortcutDisplayStringNoModifiers() {
        let result = shortcutDisplayString(keyCode: 0, modifiers: 0) // A
        XCTAssertTrue(result.contains("A"))
        XCTAssertFalse(result.contains("⌘"))
        XCTAssertFalse(result.contains("⌥"))
    }

    // MARK: - keyCodeToDisplayName

    func testKeyCodeV() {
        XCTAssertEqual(keyCodeToDisplayName(9), "V")
    }

    func testKeyCodeA() {
        XCTAssertEqual(keyCodeToDisplayName(0), "A")
    }

    func testKeyCodeEscape() {
        XCTAssertEqual(keyCodeToDisplayName(53), "⎋")
    }

    func testKeyCodeSpace() {
        XCTAssertEqual(keyCodeToDisplayName(49), "␣")
    }

    func testKeyCodeReturn() {
        XCTAssertEqual(keyCodeToDisplayName(36), "↩")
    }

    func testKeyCodeDelete() {
        XCTAssertEqual(keyCodeToDisplayName(51), "⌫")
    }

    func testKeyCodeArrowLeft() {
        XCTAssertEqual(keyCodeToDisplayName(123), "←")
    }

    func testKeyCodeArrowRight() {
        XCTAssertEqual(keyCodeToDisplayName(124), "→")
    }

    func testKeyCodeF1() {
        XCTAssertEqual(keyCodeToDisplayName(122), "F1")
    }

    func testKeyCodeF12() {
        XCTAssertEqual(keyCodeToDisplayName(111), "F12")
    }

    func testKeyCodeUnknown() {
        XCTAssertNil(keyCodeToDisplayName(999))
    }
}
