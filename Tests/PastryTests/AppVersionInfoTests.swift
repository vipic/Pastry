import XCTest
@testable import Pastry

final class AppVersionInfoTests: XCTestCase {
    func testDisplayCurrentFallsBackToBundleWhenGeneratedIsPlaceholder() {
        XCTAssertEqual(AppVersion.displayCurrent(generated: "0.0.0-dev", bundle: "1.3.17"), "1.3.17")
    }

    func testDisplayCurrentPrefersBundleVersion() {
        XCTAssertEqual(AppVersion.displayCurrent(generated: "v1.4.0", bundle: "1.3.17"), "1.3.17")
    }

    func testDisplayCurrentUsesGeneratedReleaseVersionWhenBundleMissing() {
        XCTAssertEqual(AppVersion.displayCurrent(generated: "v1.4.0", bundle: nil), "1.4.0")
    }

    func testDisplayBuildFallsBackToBundleWhenGeneratedIsPlaceholder() {
        XCTAssertEqual(AppVersion.displayBuild(generated: "0", bundle: "abc1234"), "abc1234")
    }

    func testDisplayBuildPrefersGeneratedReleaseBuild() {
        XCTAssertEqual(AppVersion.displayBuild(generated: "42", bundle: "abc1234"), "42")
    }
}
