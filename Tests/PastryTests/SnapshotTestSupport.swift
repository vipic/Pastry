import CryptoKit
import SwiftUI
import XCTest

enum SnapshotTestSupport {
    @MainActor
    static func assertSnapshot<V: View>(
        named name: String,
        size: CGSize,
        view: V,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["PASTRY_SNAPSHOT_TESTS"] == "1"
                || environment["PASTRY_RECORD_SNAPSHOTS"] == "1" else {
            throw XCTSkip("Set PASTRY_SNAPSHOT_TESTS=1 to verify snapshots or PASTRY_RECORD_SNAPSHOTS=1 to record them")
        }

        let pngData = try renderPNG(view: view, size: size)
        let snapshotDir = snapshotDirectory(file: file)
        let snapshotURL = snapshotDir.appendingPathComponent("\(name).png")

        if environment["PASTRY_RECORD_SNAPSHOTS"] == "1" {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: snapshotURL, options: .atomic)
            return
        }

        let expectedData = try Data(contentsOf: snapshotURL)
        let actualDigest = digest(for: pngData)
        let expectedDigest = digest(for: expectedData)
        guard actualDigest == expectedDigest else {
            let failureDir = snapshotDir.appendingPathComponent("__Failures__", isDirectory: true)
            try? FileManager.default.createDirectory(at: failureDir, withIntermediateDirectories: true)
            let actualURL = failureDir.appendingPathComponent("\(name).actual.png")
            let expectedURL = failureDir.appendingPathComponent("\(name).expected.png")
            try? pngData.write(to: actualURL, options: .atomic)
            try? expectedData.write(to: expectedURL, options: .atomic)
            XCTFail(
                "Snapshot mismatch: \(name). Wrote actual PNG to \(actualURL.path)",
                file: file,
                line: line
            )
            return
        }
    }

    @MainActor
    private static func renderPNG<V: View>(view: V, size: CGSize) throws -> Data {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SnapshotError.bitmapCreationFailed
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        return data
    }

    private static func snapshotDirectory(file: StaticString) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__", isDirectory: true)
    }

    private static func digest(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private enum SnapshotError: Error {
        case bitmapCreationFailed
        case pngEncodingFailed
    }
}
