import XCTest
@testable import Pastry
import Foundation

// MARK: - UpdateChecker 测试套件

final class UpdateCheckerTests: XCTestCase {
    private var networkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["PASTRY_NETWORK_TESTS"] == "1"
    }

    private func requireNetworkTestsEnabled() throws {
        guard networkTestsEnabled else {
            throw XCTSkip("Set PASTRY_NETWORK_TESTS=1 to run network-dependent updater tests")
        }
    }

    private final class ProgressRecorder: @unchecked Sendable {
        private var values: [Double] = []
        private let lock = NSLock()

        func append(_ value: Double) {
            lock.withLock { values.append(value) }
        }

        var snapshot: [Double] {
            lock.withLock { values }
        }
    }

    // MARK: - downloadBinary 进度回调

    /// onProgress 在下载过程中被调用，提供 0.0~1.0 范围内的进度值
    func testDownloadBinaryProgressCallback() async throws {
        try requireNetworkTestsEnabled()

        let checker = UpdateChecker.shared

        guard let result = await checker.checkForUpdate(force: true) else {
            throw XCTSkip("无可用更新或网络不可达，跳过下载测试")
        }

        let progress = ProgressRecorder()

        let url = try await checker.downloadBinary(
            from: result.downloadURL,
            onProgress: { value in
                progress.append(value)
            }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        let values = progress.snapshot

        // 小文件可能一次回调完成，也可能因 CDN 响应不带 Content-Length 无回调
        // 只要文件下载成功即可
        if !values.isEmpty {
            if let last = values.last {
                XCTAssertEqual(last, 1.0, accuracy: 0.01, "最终进度应接近 1.0")
            }
            if let first = values.first {
                XCTAssertGreaterThanOrEqual(first, 0.0, "起始进度应 ≥ 0")
            }
        }

        try? FileManager.default.removeItem(at: url)
    }

    /// onProgress 为 nil 时不应崩溃
    func testDownloadBinaryNilProgress() async throws {
        try requireNetworkTestsEnabled()

        let checker = UpdateChecker.shared

        guard let result = await checker.checkForUpdate(force: true) else {
            throw XCTSkip("无可用更新或网络不可达，跳过下载测试")
        }

        let url = try await checker.downloadBinary(from: result.downloadURL, onProgress: nil)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        try? FileManager.default.removeItem(at: url)
    }

    func testDownloadBinaryRejectsInsecureURL() async {
        do {
            _ = try await UpdateChecker.shared.downloadBinary(from: "http://example.com/Pastry.dmg")
            XCTFail("HTTP 下载链接应被拒绝")
        } catch let error as UpdateChecker.UpdateError {
            XCTAssertEqual(error, .insecureURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - isDevBuild

    func testIsDevBuildDetection() {
        let checker = UpdateChecker.shared
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let isDev = version.contains("-dev")
        XCTAssertEqual(checker.isDevBuild, isDev)
    }

    func testDisplayVersionStripsLeadingV() {
        XCTAssertEqual(UpdateChecker.displayVersion("v1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.displayVersion("vv1.2.3"), "1.2.3")
        XCTAssertEqual(UpdateChecker.displayVersion("1.2.3"), "1.2.3")
    }

    func testVersionComparisonHandlesLeadingVAndDifferentLengths() {
        XCTAssertTrue(UpdateChecker.isNewer(tag: "v1.10.0", than: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer(tag: "vv2.0", than: "v1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "v1.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer(tag: "1.2.3", than: "v1.2.4"))
    }
}
