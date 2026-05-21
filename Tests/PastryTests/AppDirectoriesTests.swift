import XCTest
@testable import Pastry

final class AppDirectoriesTests: XCTestCase {
    func testApplicationSupportDirectoryEndsWithAppName() {
        let dir = AppDirectories.applicationSupportDirectory()

        XCTAssertEqual(dir.lastPathComponent, Constants.appName)
        XCTAssertFalse(dir.path.isEmpty)
    }

    func testEnsureDirectoryCreatesNestedDirectory() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nested")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        AppDirectories.ensureDirectory(dir, logCategory: "tests")

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }
}
