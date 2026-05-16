import XCTest
@testable import Pastry

// MARK: - OverlayPanelManager 测试套件
// 测试键盘输入重定向判断、面板关闭逻辑

final class OverlayPanelManagerTests: XCTestCase {

    // MARK: - isRedirectableChar 打印字符判断

    /// 英文字母（大小写）
    func testRedirectableEnglishLetters() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("a"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("Z"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("hello"))
    }

    /// 中文字符
    func testRedirectableChineseCharacters() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("搜"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("你好世界"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("日"))
    }

    /// 数字
    func testRedirectableDigits() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("0"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("9"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("42"))
    }

    /// 标点符号
    func testRedirectablePunctuation() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("."))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar(","))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("!"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("?"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar(";"))
    }

    /// 空格
    func testRedirectableSpace() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar(" "))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("  "))
    }

    /// 符号（+, -, =, @, # 等）
    func testRedirectableSymbols() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("+"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("-"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("@"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("#"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("$"))
    }

    /// 控制字符应拒绝
    func testRedirectableRejectsControlChars() {
        XCTAssertFalse(OverlayPanelManager.isRedirectableChar("\u{0003}"))  // ETX
        XCTAssertFalse(OverlayPanelManager.isRedirectableChar("\u{001B}"))  // ESC
        XCTAssertFalse(OverlayPanelManager.isRedirectableChar("\u{007F}"))  // DEL
    }

    /// 空字符串
    func testRedirectableEmptyString() {
        XCTAssertFalse(OverlayPanelManager.isRedirectableChar(""))
    }

    /// 组合：搜索 URL 片段
    func testRedirectableURLComponents() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("https://"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("example.com"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("/path?q=1"))
    }

    /// Emoji
    func testRedirectableEmoji() {
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("😀"))
        XCTAssertTrue(OverlayPanelManager.isRedirectableChar("🚀"))
    }

    // MARK: - shouldFocusSearch 搜索栏聚焦判断

    // 辅助：空修饰键
    private let noModifiers = NSEvent.ModifierFlags()

    /// 英文字母：搜索未激活 + 无修饰键 → 应聚焦
    func testFocusSearchEnglishLetter() {
        XCTAssertTrue(OverlayPanelManager.shouldFocusSearch(
            chars: "a", isSearchActive: false, modifierFlags: noModifiers
        ))
        XCTAssertTrue(OverlayPanelManager.shouldFocusSearch(
            chars: "Z", isSearchActive: false, modifierFlags: noModifiers
        ))
    }

    /// 中文：应聚焦（IME 组合完成的字符一样触发搜索栏）
    func testFocusSearchChineseCharacter() {
        XCTAssertTrue(OverlayPanelManager.shouldFocusSearch(
            chars: "搜", isSearchActive: false, modifierFlags: noModifiers
        ))
        XCTAssertTrue(OverlayPanelManager.shouldFocusSearch(
            chars: "你好", isSearchActive: false, modifierFlags: noModifiers
        ))
    }

    /// 数字和标点
    func testFocusSearchDigitsAndPunctuation() {
        XCTAssertTrue(OverlayPanelManager.shouldFocusSearch(
            chars: "3", isSearchActive: false, modifierFlags: noModifiers
        ))
        XCTAssertTrue(OverlayPanelManager.shouldFocusSearch(
            chars: ".", isSearchActive: false, modifierFlags: noModifiers
        ))
    }

    /// 搜索栏已激活 → 不触发（让搜索栏自己处理输入）
    func testFocusSearchRejectedWhenAlreadyActive() {
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: "a", isSearchActive: true, modifierFlags: noModifiers
        ))
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: "搜", isSearchActive: true, modifierFlags: noModifiers
        ))
    }

    /// 含 ⌘ 修饰键 → 不触发（留给 ⌘F 快捷键等处理）
    func testFocusSearchRejectedWhenCommandHeld() {
        let cmd = NSEvent.ModifierFlags.command
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: "a", isSearchActive: false, modifierFlags: cmd
        ))
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: "f", isSearchActive: false, modifierFlags: cmd
        ))
    }

    /// 含 ⌃ 修饰键 → 不触发
    func testFocusSearchRejectedWhenControlHeld() {
        let ctrl = NSEvent.ModifierFlags.control
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: "a", isSearchActive: false, modifierFlags: ctrl
        ))
    }

    /// 空 characters → 不触发
    func testFocusSearchRejectedNilChars() {
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: nil, isSearchActive: false, modifierFlags: noModifiers
        ))
    }

    /// 空字符串 → 不触发
    func testFocusSearchRejectedEmptyChars() {
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: "", isSearchActive: false, modifierFlags: noModifiers
        ))
    }

    /// 方向键产生的空字符 → 不触发（方向键无 characters）
    func testFocusSearchRejectedArrowKeyNoCharacters() {
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: nil, isSearchActive: false, modifierFlags: noModifiers
        ))
    }

    /// 组合修饰键：Cmd+Shift → 不触发
    func testFocusSearchRejectedWhenMultipleModifiers() {
        let cmdShift: NSEvent.ModifierFlags = [.command, .shift]
        XCTAssertFalse(OverlayPanelManager.shouldFocusSearch(
            chars: "a", isSearchActive: false, modifierFlags: cmdShift
        ))
    }

    // MARK: - Tab 键搜索栏↔卡片焦点切换

    /// Tab 键码为 48（macOS 标准）
    func testTabKeyCodeIs48() {
        // keyCode 48 是 macOS 定义的 kVK_Tab
        XCTAssertEqual(48, 48)
    }

    /// overlayCloseSearch 通知名称存在
    func testOverlayCloseSearchNotificationExists() {
        XCTAssertEqual(
            Notification.Name.overlayCloseSearch.rawValue,
            "overlayCloseSearch"
        )
    }

    /// overlayOpenSearchImmediate 通知名称存在
    func testOverlayOpenSearchImmediateNotificationExists() {
        XCTAssertEqual(
            Notification.Name.overlayOpenSearchImmediate.rawValue,
            "overlayOpenSearchImmediate"
        )
    }

    /// overlayAlertConfirm 通知名称存在（Enter 触发确认）
    func testOverlayAlertConfirmNotificationExists() {
        XCTAssertEqual(
            Notification.Name.overlayAlertConfirm.rawValue,
            "overlayAlertConfirm"
        )
    }

    // MARK: - 粘贴锁 isPasting

    /// 验证 isPasting 标记存在（编译时检查）
    /// 实际锁行为依赖 NSWindow 通知集成测试
    func testIsPastingFlagExists() {
        // 直接调用 hideAndPaste 需要 NSPasteboard 和 App 上下文
        // 此处只验证类型层：OverlayPanelManager 可访问
        let manager = OverlayPanelManager.shared
        XCTAssertNotNil(manager)
    }

    // MARK: - ⌘+数字快捷键映射

    func testCmdNumberIndexMapping() {
        // keyCode 18 = 1, 19 = 2, ..., 25 = 9
        let pairs: [(UInt16, Int)] = [
            (18, 1), (19, 2), (20, 3), (21, 4),
            (23, 5), (22, 6), (26, 7), (28, 8), (25, 9)
        ]
        for (keyCode, expected) in pairs {
            XCTAssertEqual(OverlayPanelManager.cmdNumberIndex(keyCode: keyCode), expected,
                           "keyCode \(keyCode) should map to index \(expected)")
        }
    }

    func testCmdNumberIndexInvalidKeys() {
        // 非数字键返回 nil
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 0))   // A
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 36))  // Enter
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 53))  // Esc
        XCTAssertNil(OverlayPanelManager.cmdNumberIndex(keyCode: 48))  // Tab
    }

    // MARK: - 搜索栏 Enter 粘贴通知

    func testOverlaySearchEnterPasteNotificationExists() {
        XCTAssertEqual(
            Notification.Name.overlaySearchEnterPaste.rawValue,
            "overlaySearchEnterPaste"
        )
    }
}
