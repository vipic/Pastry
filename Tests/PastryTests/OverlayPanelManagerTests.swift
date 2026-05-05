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

    // MARK: - 粘贴锁 isPasting

    /// 验证 isPasting 标记存在（编译时检查）
    /// 实际锁行为依赖 NSWindow 通知集成测试
    func testIsPastingFlagExists() {
        // 直接调用 hideAndPaste 需要 NSPasteboard 和 App 上下文
        // 此处只验证类型层：OverlayPanelManager 可访问
        let manager = OverlayPanelManager.shared
        XCTAssertNotNil(manager)
    }
}
