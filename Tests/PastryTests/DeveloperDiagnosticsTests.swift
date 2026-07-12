import XCTest
@testable import Pastry

final class DeveloperDiagnosticsTests: XCTestCase {
    private var tempLogsDir: URL!

    override func setUp() {
        super.setUp()
        tempLogsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-diag-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempLogsDir, withIntermediateDirectories: true)
        DeveloperDiagnostics.logsDirectoryOverrideForTesting = tempLogsDir
        DeveloperDiagnostics.resetUsageForTesting()

        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.performanceLoggingEnabled)
    }

    override func tearDown() {
        DeveloperDiagnostics.resetUsageForTesting()
        DeveloperDiagnostics.logsDirectoryOverrideForTesting = nil
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.performanceLoggingEnabled)
        if let tempLogsDir {
            try? FileManager.default.removeItem(at: tempLogsDir)
        }
        super.tearDown()
    }

    func testRecordIsNoOpWhenDisabled() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.performanceLoggingEnabled)
        DeveloperDiagnostics.record(DiagnosticsEvent.preview)
        let counts = DeveloperDiagnostics.snapshotCountsForTesting()
        XCTAssertTrue(counts.isEmpty)
    }

    func testRecordIncrementsWhenEnabled() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.performanceLoggingEnabled)
        DeveloperDiagnostics.record(DiagnosticsEvent.preview)
        DeveloperDiagnostics.record(DiagnosticsEvent.preview)
        DeveloperDiagnostics.record(DiagnosticsEvent.copy)

        let counts = DeveloperDiagnostics.snapshotCountsForTesting()
        XCTAssertEqual(counts[DiagnosticsEvent.preview], 2)
        XCTAssertEqual(counts[DiagnosticsEvent.copy], 1)
    }

    func testWritePerfLineCreatesFileWhenEnabled() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.performanceLoggingEnabled)
        DeveloperDiagnostics.writePerfLine("test | type: panel | total: 1ms")

        // 等待异步队列落盘
        _ = DeveloperDiagnostics.snapshotCountsForTesting()

        let perfURL = tempLogsDir.appendingPathComponent("perf.log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: perfURL.path))
        let body = (try? String(contentsOf: perfURL, encoding: .utf8)) ?? ""
        XCTAssertTrue(body.contains("type: panel"))
    }

    func testUsagePersistsAcrossSnapshot() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.performanceLoggingEnabled)
        DeveloperDiagnostics.record(DiagnosticsEvent.favoritePin)
        _ = DeveloperDiagnostics.snapshotCountsForTesting()

        let usageURL = tempLogsDir.appendingPathComponent("usage.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: usageURL.path))
        let data = try! Data(contentsOf: usageURL)
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let counts = json["counts"] as! [String: Any]
        XCTAssertEqual(counts[DiagnosticsEvent.favoritePin] as? Int, 1)
        XCTAssertEqual(json["version"] as? Int, 1)
    }

    func testLogsDirectoryUsesAppName() {
        let dir = AppDirectories.logsDirectory()
        XCTAssertTrue(dir.path.hasSuffix("Logs/\(Constants.appName)") || dir.path.contains("/Logs/\(Constants.appName)"))
    }
}
