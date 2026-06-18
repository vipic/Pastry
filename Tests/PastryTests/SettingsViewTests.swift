import XCTest
@testable import Pastry

final class SettingsViewTests: XCTestCase {
    func testSettingsTabsIncludeAboutTabForMenuRouting() {
        XCTAssertTrue(SettingsSceneView.SettingsTab.allCases.contains(.about))
        XCTAssertEqual(SettingsSceneView.SettingsTab(rawValue: "about"), .about)
    }
}
