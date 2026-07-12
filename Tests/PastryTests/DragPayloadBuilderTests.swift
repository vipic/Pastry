import XCTest
@testable import Pastry

/// 多选拖拽载荷：文本拼接、仅全链接时暴露 URL、文件 URL 过滤。
final class DragPayloadBuilderTests: XCTestCase {

    private func text(_ content: String, isURL: Bool = false) -> ClipboardItem {
        ClipboardItem(
            timestamp: Date(),
            content: content,
            sourceFormat: .text,
            tags: ContentTags(isURL: isURL)
        )
    }

    private func file(_ path: String) -> ClipboardItem {
        ClipboardItem(timestamp: Date(), content: path, sourceFormat: .fileURL)
    }

    private func image(_ path: String) -> ClipboardItem {
        ClipboardItem(timestamp: Date(), content: path, sourceFormat: .image)
    }

    // MARK: - multiSelectText

    func testMultiSelectTextIncludesFilePathsAndSkipsImages() {
        let items = [
            text("a"),
            image("/tmp/x.png"),
            file("/tmp/doc.txt"),
            text("b", isURL: true)
        ]
        // file path may or may not exist; content still included as text for fileURL
        let result = DragPayloadBuilder.multiSelectText(items)
        XCTAssertTrue(result.contains("a"))
        XCTAssertTrue(result.contains("b"))
        XCTAssertTrue(result.contains("/tmp/doc.txt"))
        XCTAssertFalse(result.contains("/tmp/x.png"), "图片不应进入多选文本")
    }

    func testMultiSelectTextUsesLoadFullContentOverride() {
        let item = text("preview")
        let result = DragPayloadBuilder.multiSelectText([item]) { _ in "full body" }
        XCTAssertEqual(result, "full body")
    }

    // MARK: - webURLsForLinkSelection

    func testWebURLsForLinkSelectionRequiresEveryItemToBeLink() {
        let links = [
            text("https://a.example", isURL: true),
            text("http://b.example/path", isURL: true)
        ]
        let urls = DragPayloadBuilder.webURLsForLinkSelection(links)
        XCTAssertEqual(urls.map(\.scheme), ["https", "https"], "http 应升级为 https")
        XCTAssertEqual(urls.map(\.host), ["a.example", "b.example"])
    }

    func testWebURLsForLinkSelectionReturnsEmptyWhenMixedWithNonLink() {
        let items = [
            text("https://a.example", isURL: true),
            text("not a link", isURL: false)
        ]
        XCTAssertTrue(
            DragPayloadBuilder.webURLsForLinkSelection(items).isEmpty,
            "混入非链接时不得暴露 webURL 列表（避免拖到编辑器只剩 URL flavor）"
        )
    }

    func testWebURLsForLinkSelectionEmptyInput() {
        XCTAssertTrue(DragPayloadBuilder.webURLsForLinkSelection([]).isEmpty)
    }

    // MARK: - payloadForSelection

    func testPayloadForSelectionAllLinks() {
        let items = [
            text("https://one.test", isURL: true),
            text("https://two.test", isURL: true)
        ]
        let payload = DragPayloadBuilder.payloadForSelection(items)
        XCTAssertFalse(payload.isEmpty)
        XCTAssertEqual(payload.webURLs.count, 2)
        XCTAssertTrue(payload.text.contains("https://one.test"))
        XCTAssertTrue(payload.fileURLs.isEmpty)
    }

    func testPayloadForSelectionTextOnlyIsNotEmpty() {
        let payload = DragPayloadBuilder.payloadForSelection([text("hello"), text("world")])
        XCTAssertEqual(payload.text, "hello\nworld")
        XCTAssertTrue(payload.webURLs.isEmpty)
        XCTAssertTrue(payload.fileURLs.isEmpty)
        XCTAssertFalse(payload.isEmpty)
    }

    func testPayloadForSelectionEmptyWhenOnlyMissingImages() {
        let payload = DragPayloadBuilder.payloadForSelection([
            image("/path/that/does/not/exist-\(UUID().uuidString).png")
        ])
        XCTAssertTrue(payload.text.isEmpty)
        XCTAssertTrue(payload.webURLs.isEmpty)
        XCTAssertTrue(payload.fileURLs.isEmpty)
        XCTAssertTrue(payload.isEmpty)
    }

    // MARK: - fileURLsForSelection

    func testFileURLsForSelectionSkipsMissingPaths() {
        let missing = "/tmp/pastry-missing-\(UUID().uuidString).bin"
        let urls = DragPayloadBuilder.fileURLsForSelection([file(missing)])
        XCTAssertTrue(urls.isEmpty)
    }

    func testFileURLsForSelectionIncludesExistingTempFile() throws {
        let path = NSTemporaryDirectory() + "pastry-drag-\(UUID().uuidString).txt"
        try "x".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let urls = DragPayloadBuilder.fileURLsForSelection([file(path)])
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls[0].path, path)
    }
}
