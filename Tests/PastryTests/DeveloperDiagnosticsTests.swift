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
        DeveloperDiagnostics.resetRuntimeLogForTesting()
        DeveloperDiagnostics.runtimeLogMaxBytesOverrideForTesting = nil

        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.performanceLoggingEnabled)
    }

    override func tearDown() {
        DeveloperDiagnostics.resetUsageForTesting()
        DeveloperDiagnostics.resetRuntimeLogForTesting()
        DeveloperDiagnostics.runtimeLogMaxBytesOverrideForTesting = nil
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

    func testRuntimeLogIsNoOpWhenDiagnosticsDisabled() {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.performanceLoggingEnabled)

        PastryLogger(category: "test").error(
            "测试错误",
            event: "test.failure",
            metadata: ["operation": "disabled"]
        )
        DeveloperDiagnostics.flushForTesting()

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempLogsDir.appendingPathComponent("runtime.jsonl").path
            )
        )
    }

    func testRuntimeLogWritesStructuredEventWhenEnabled() throws {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.performanceLoggingEnabled)

        PastryLogger(category: "update").warning(
            "更新检查失败",
            event: "update.check.failed",
            metadata: [
                "status": "network_error",
                "content": "secret",
                "source_url": "https://secret.example",
                "text_item_count": "3",
                "context": "paste",
                "error": "failed at https://secret.example"
            ],
            durationMilliseconds: 321
        )
        DeveloperDiagnostics.flushForTesting()

        let url = tempLogsDir.appendingPathComponent("runtime.jsonl")
        let line = try XCTUnwrap(String(contentsOf: url, encoding: .utf8).split(separator: "\n").last)
        let data = Data(line.utf8)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["level"] as? String, "warning")
        XCTAssertEqual(json["category"] as? String, "update")
        XCTAssertEqual(json["event"] as? String, "update.check.failed")
        XCTAssertEqual(json["message"] as? String, "更新检查失败")
        XCTAssertEqual(json["duration_ms"] as? Int, 321)
        XCTAssertEqual((json["metadata"] as? [String: String])?["status"], "network_error")
        XCTAssertEqual((json["metadata"] as? [String: String])?["content"], "<redacted>")
        XCTAssertEqual((json["metadata"] as? [String: String])?["source_url"], "<redacted>")
        XCTAssertEqual((json["metadata"] as? [String: String])?["text_item_count"], "3")
        XCTAssertEqual((json["metadata"] as? [String: String])?["context"], "paste")
        XCTAssertEqual((json["metadata"] as? [String: String])?["error"], "<redacted>")
        XCTAssertNotNil(json["session_id"] as? String)
        XCTAssertNotNil(json["timestamp"] as? String)
    }

    func testRuntimeLogRotatesWhenSizeLimitIsReached() {
        UserDefaults.standard.set(true, forKey: UserDefaultsKeys.performanceLoggingEnabled)
        DeveloperDiagnostics.runtimeLogMaxBytesOverrideForTesting = 300
        let logger = PastryLogger(category: "rotation")

        for index in 0..<8 {
            logger.info(
                String(repeating: "x", count: 100),
                event: "rotation.\(index)"
            )
        }
        DeveloperDiagnostics.flushForTesting()

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempLogsDir.appendingPathComponent("runtime.1.jsonl").path
            )
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: tempLogsDir.appendingPathComponent("runtime.jsonl").path
            )
        )
    }
}
