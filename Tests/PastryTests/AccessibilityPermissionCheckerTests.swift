import XCTest
@testable import Pastry

final class AccessibilityPermissionCheckerTests: XCTestCase {
    func testTrustedStatusReturnsCheckerResult() {
        let fake = FakeAccessibilityPermissionChecker(result: true)
        let checker = AccessibilityPermissionChecker(checker: fake)

        XCTAssertTrue(checker.isTrusted())
        XCTAssertEqual(fake.prompts, [false])
    }

    func testPromptFlagIsForwarded() {
        let fake = FakeAccessibilityPermissionChecker(result: false)
        let checker = AccessibilityPermissionChecker(checker: fake)

        XCTAssertFalse(checker.isTrusted(prompt: true))
        XCTAssertEqual(fake.prompts, [true])
    }

    func testRequestTrustedForPasteSkipsPromptWhenAlreadyTrusted() {
        let fake = FakeAccessibilityPermissionChecker(result: true)
        let checker = AccessibilityPermissionChecker(checker: fake)

        XCTAssertTrue(checker.requestTrustedForPaste())
        XCTAssertEqual(fake.prompts, [false], "已授权时不应弹系统授权窗")
    }

    func testRequestTrustedForPastePromptsWhenDenied() {
        let fake = FakeAccessibilityPermissionChecker(result: false)
        let checker = AccessibilityPermissionChecker(checker: fake)

        XCTAssertFalse(checker.requestTrustedForPaste())
        XCTAssertEqual(
            fake.prompts,
            [false, true],
            "未授权应先静默检查再以 prompt:true 触发系统对话框"
        )
    }

    func testRequestTrustedForPasteSucceedsAfterPromptGrant() {
        let fake = FakeAccessibilityPermissionChecker(result: false)
        fake.grantOnPrompt = true
        let checker = AccessibilityPermissionChecker(checker: fake)

        XCTAssertTrue(checker.requestTrustedForPaste())
        XCTAssertEqual(fake.prompts, [false, true])
    }
}

private final class FakeAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    let result: Bool
    /// 若为 true：仅在 `prompt == true` 时返回已授权（模拟用户在弹窗路径同意）
    var grantOnPrompt = false
    var prompts: [Bool] = []

    init(result: Bool) {
        self.result = result
    }

    func isTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        if grantOnPrompt, prompt { return true }
        return result
    }
}
