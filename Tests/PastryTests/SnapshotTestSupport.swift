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
        let digest = SHA256.hash(data: pngData)
            .map { String(format: "%02x", $0) }
            .joined()
        let snapshotURL = snapshotDirectory(file: file)
            .appendingPathComponent("\(name).sha256")

        if environment["PASTRY_RECORD_SNAPSHOTS"] == "1" {
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try "\(digest)\n".write(to: snapshotURL, atomically: true, encoding: .utf8)
            return
        }

        let expected = try String(contentsOf: snapshotURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(digest, expected, "Snapshot mismatch: \(name)", file: file, line: line)
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

    private enum SnapshotError: Error {
        case bitmapCreationFailed
        case pngEncodingFailed
    }
}
