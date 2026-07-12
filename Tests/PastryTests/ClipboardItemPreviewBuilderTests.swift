import XCTest
@testable import Pastry

final class ClipboardItemPreviewBuilderTests: XCTestCase {

    func testCanPreviewText() {
        let item = ClipboardItem(
            content: "hello preview",
            sourceFormat: .text,
            appName: "Test"
        )
        XCTAssertTrue(ClipboardItemPreviewBuilder.canPreview(item))
        XCTAssertNotNil(ClipboardItemPreviewBuilder.makeMetadata(for: item))
    }

    func testCanPreviewRejectsMultiFile() {
        let item = ClipboardItem(
            content: "/tmp/a.txt\n/tmp/b.txt",
            sourceFormat: .fileURL,
            appName: "Test"
        )
        XCTAssertFalse(ClipboardItemPreviewBuilder.canPreview(item))
        XCTAssertNil(ClipboardItemPreviewBuilder.makeMetadata(for: item))
    }

    func testCanPreviewMissingFile() {
        let item = ClipboardItem(
            content: "/tmp/pastry-missing-\(UUID().uuidString).txt",
            sourceFormat: .fileURL,
            appName: "Test"
        )
        XCTAssertFalse(ClipboardItemPreviewBuilder.canPreview(item))
        XCTAssertNil(ClipboardItemPreviewBuilder.makeMetadata(for: item))
    }

    func testCanPreviewExistingFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-preview-\(UUID().uuidString).txt")
        try "preview body".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let item = ClipboardItem(
            content: url.path,
            sourceFormat: .fileURL,
            appName: "Test"
        )
        XCTAssertTrue(ClipboardItemPreviewBuilder.canPreview(item))
        let metadata = ClipboardItemPreviewBuilder.makeMetadata(for: item)
        XCTAssertEqual(metadata?.url.path, url.path)
    }
}
