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
}

private final class FakeAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    let result: Bool
    var prompts: [Bool] = []

    init(result: Bool) {
        self.result = result
    }

    func isTrusted(prompt: Bool) -> Bool {
        prompts.append(prompt)
        return result
    }
}
