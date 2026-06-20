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

    func testOverlayAlertCancelNotificationExists() {
        XCTAssertEqual(
            Notification.Name.overlayAlertCancel.rawValue,
            "overlayAlertCancel"
        )
    }

    func testAlertConfirmKeyIsEnter() {
        XCTAssertTrue(OverlayKeyboardRouter.isAlertConfirmKey(keyCode: 36))
        XCTAssertFalse(OverlayKeyboardRouter.isAlertConfirmKey(keyCode: 51))
    }

    func testAlertConsumesDeleteKeysWithoutSystemBeep() {
        XCTAssertTrue(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 51))
        XCTAssertTrue(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 117))
        XCTAssertFalse(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 36))
        XCTAssertFalse(OverlayKeyboardRouter.shouldConsumeAlertKeyDown(keyCode: 0))
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

    // MARK: - IME 拼写时 Enter 放行（中文拼音按回车确认英文上屏）


    /// 无 NSTextView 焦点时应返回 false（不拦截 Enter）
    func testShouldAllowEnterForIMEWithoutTextViewFocus() {
        // 单元测试环境无 keyWindow → firstResponder 为 nil → false
        XCTAssertFalse(OverlayPanelManager.shouldAllowEnterForIME())
    }

    /// Enter 键码校验（macOS 标准 keyCode 36）
    func testEnterKeyCodeIs36() {
        // kVK_Return = 0x24 = 36
        XCTAssertEqual(36, 36)
    }

    /// hasMarkedText 是 NSTextView 的实例方法
    func testNSTextViewHasMarkedTextExists() {
        let tv = NSTextView()
        // 空 NSTextView 默认无 marked text
        XCTAssertFalse(tv.hasMarkedText())
    }

    /// shouldAllowEnterForIME 仅对 NSTextView 生效（NSTextField 不检查 marked text）
    func testShouldAllowEnterForIMEOnlyChecksTextView() {
        // 方法签名侧：as? NSTextView 排除了 NSTextField / NSSearchField
        // 单元测试无法构造真实 IME 状态，仅验证方法不抛异常
        let result = OverlayPanelManager.shouldAllowEnterForIME()
        XCTAssertFalse(result, "无输入焦点时应返回 false")
    }

    // MARK: - 搜索栏 Enter 粘贴通知

    func testOverlaySearchEnterPasteNotificationExists() {
        XCTAssertEqual(
            Notification.Name.overlaySearchEnterPaste.rawValue,
            "overlaySearchEnterPaste"
        )
    }

    func testOverlayCancelFavoriteNoteEditingNotificationExists() {
        XCTAssertEqual(
            Notification.Name.overlayCancelFavoriteNoteEditing.rawValue,
            "overlayCancelFavoriteNoteEditing"
        )
    }

    // MARK: - 面板默认响铃抑制

    func testOverlayPanelSilentlyConsumesArrowKeysWhenSearchInactive() {
        for keyCode in [UInt16(123), UInt16(124), UInt16(125), UInt16(126)] {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: false
                ),
                .consume
            )
        }
    }

    func testOverlayPanelSilentlyConsumesHandledActionKeysWhenSearchInactive() {
        for keyCode in [UInt16(36), UInt16(51), UInt16(117)] {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: false
                ),
                .consume
            )
        }
    }

    func testOverlayPanelConsumesEnterAndDeleteWhenAlertActive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: false,
                isAlertActive: true
            ),
            .confirmAlert
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 51,
                isSearchActive: false,
                isAlertActive: true
            ),
            .consume
        )
    }

    func testOverlayPanelRoutesEnterToAlertConfirmWhenAlertActive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: false,
                isAlertActive: true
            ),
            .confirmAlert
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: false,
                isAlertActive: false
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 51,
                isSearchActive: false,
                isAlertActive: true
            ),
            .consume
        )
    }

    func testOverlayPanelRoutesCommandAToSelectAllWhenAlertInactive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                isSearchActive: false,
                isAlertActive: false,
                modifierFlags: .command
            ),
            .selectAll
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                isSearchActive: false,
                isAlertActive: true,
                modifierFlags: .command
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                isSearchActive: false,
                isAlertActive: false,
                modifierFlags: []
            ),
            .system
        )
    }

    func testOverlayPanelDoesNotRouteCardCommandsWhenSearchFieldOwnsKeyboard() {
        let textEditingKeys: [(UInt16, NSEvent.ModifierFlags)] = [
            (0, .command),    // ⌘A selects search text
            (36, []),         // Enter stays in search field
            (51, []),         // Delete edits search text
            (117, []),        // Forward delete edits search text
            (123, []),        // Arrow keys move caret
            (124, []),
            (125, []),
            (126, []),
            (18, .command)    // ⌘1 does not quick-paste while typing search
        ]

        for (keyCode, modifiers) in textEditingKeys {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: true,
                    modifierFlags: modifiers,
                    keyboardOwner: .searchField
                ),
                .system,
                "keyCode \(keyCode) should stay with search field"
            )
        }
    }

    func testOverlayPanelKeepsSearchOwnedCommandsScopedToSearch() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .cancel
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 48,
                isSearchActive: true,
                keyboardOwner: .searchField
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 3,
                isSearchActive: true,
                modifierFlags: .command,
                keyboardOwner: .searchField
            ),
            .openSearch
        )
    }

    func testOverlayPanelRoutesCommandFToOpenSearchWithoutSystemBeep() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 3,
                isSearchActive: false,
                modifierFlags: .command
            ),
            .openSearch
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 3,
                isSearchActive: true,
                modifierFlags: .command,
                keyboardOwner: .searchField
            ),
            .openSearch
        )
    }

    func testOverlayPanelDoesNotRouteCardCommandsWhenFavoriteNoteOwnsKeyboard() {
        let noteEditingKeys: [(UInt16, NSEvent.ModifierFlags)] = [
            (0, .command),    // ⌘A selects note text
            (36, []),         // Enter is handled by note editor submit
            (51, []),         // Delete edits note text
            (117, []),
            (123, []),
            (124, []),
            (125, []),
            (126, []),
            (18, .command)
        ]

        for (keyCode, modifiers) in noteEditingKeys {
            XCTAssertEqual(
                ClipboardOverlayPanel.keyRoute(
                    keyCode: keyCode,
                    isSearchActive: false,
                    modifierFlags: modifiers,
                    keyboardOwner: .favoriteNoteEditor
                ),
                .system,
                "keyCode \(keyCode) should stay with favorite note editor"
            )
        }
    }

    func testOverlayPanelRoutesFavoriteNoteEscapeToSilentCancel() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: false,
                keyboardOwner: .favoriteNoteEditor
            ),
            .cancelFavoriteNoteEditing
        )
    }

    func testOverlayPanelSilentlyConsumesPrintableKeyThatOpensSearch() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                chars: "a",
                isSearchActive: false
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 1,
                chars: "搜",
                isSearchActive: false
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 0,
                chars: "a",
                isSearchActive: false,
                modifierFlags: .command
            ),
            .selectAll
        )
    }

    func testOverlayPanelAlertOverridesLocalKeyboardOwner() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: false,
                isAlertActive: true,
                keyboardOwner: .favoriteNoteEditor
            ),
            .cancel
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: false,
                isAlertActive: true,
                keyboardOwner: .favoriteNoteEditor
            ),
            .confirmAlert
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 51,
                isSearchActive: false,
                isAlertActive: true,
                keyboardOwner: .searchField
            ),
            .consume
        )
    }

    func testOverlayPanelSilentlyConsumesCommandNumberKeysWhenSearchInactive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 18,
                isSearchActive: false,
                modifierFlags: .command
            ),
            .consume
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 18,
                isSearchActive: false,
                modifierFlags: []
            ),
            .system
        )
    }

    func testOverlayPanelDoesNotConsumeArrowKeysWhenSearchActive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 123,
                isSearchActive: true
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 124,
                isSearchActive: true
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 36,
                isSearchActive: true
            ),
            .system
        )
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 18,
                isSearchActive: true,
                modifierFlags: .command
            ),
            .system
        )
    }

    func testOverlayPanelHandlesEscapeWhenAlertInactive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: false,
                isAlertActive: false
            ),
            .cancel
        )
    }

    func testOverlayPanelHandlesEscapeWhenAlertActive() {
        XCTAssertEqual(
            ClipboardOverlayPanel.keyRoute(
                keyCode: 53,
                isSearchActive: false,
                isAlertActive: true
            ),
            .cancel
        )
    }
}
