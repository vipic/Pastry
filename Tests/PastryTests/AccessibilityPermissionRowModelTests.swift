import XCTest
@testable import Pastry

final class AccessibilityPermissionRowModelTests: XCTestCase {
    func testTrustedState() {
        let model = AccessibilityPermissionRowModel.resolve(isTrusted: true)

        XCTAssertEqual(model.iconName, "checkmark.shield.fill")
        XCTAssertEqual(model.title, L10n["settings.accessibility_granted"])
        XCTAssertEqual(model.subtitle, L10n["settings.accessibility_paste_ok"])
        XCTAssertFalse(model.showsGrantButton)
    }

    func testDeniedState() {
        let model = AccessibilityPermissionRowModel.resolve(isTrusted: false)

        XCTAssertEqual(model.iconName, "exclamationmark.triangle.fill")
        XCTAssertEqual(model.title, L10n["settings.accessibility_denied"])
        XCTAssertEqual(model.subtitle, L10n["settings.accessibility_paste_need"])
        XCTAssertTrue(model.showsGrantButton)
    }
}
