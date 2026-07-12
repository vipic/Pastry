import XCTest
@testable import Pastry

/// DisplayMode.resolve 纯逻辑：SourceFormat + ContentTags + 链接行 → 卡片展示类型。
final class DisplayModeTests: XCTestCase {

    private func item(
        content: String,
        format: SourceFormat,
        tags: ContentTags = .empty
    ) -> ClipboardItem {
        ClipboardItem(content: content, sourceFormat: format, tags: tags)
    }

    // MARK: - 基础类型

    func testPlainText() {
        let mode = DisplayMode.resolve(item: item(content: "hello", format: .text))
        XCTAssertEqual(mode, .plainText)
    }

    func testRichTextRTF() {
        let mode = DisplayMode.resolve(item: item(content: "rtf body", format: .rtf))
        XCTAssertEqual(mode, .richText)
    }

    func testRichTextHTMLWithoutSegmentsOrURL() {
        let mode = DisplayMode.resolve(item: item(content: "<b>hi</b>", format: .html))
        XCTAssertEqual(mode, .richText)
    }

    func testMixedMediaHTMLWithSegments() {
        var tags = ContentTags.empty
        tags.hasSegments = true
        let mode = DisplayMode.resolve(
            item: item(content: "html", format: .html, tags: tags)
        )
        XCTAssertEqual(mode, .mixedMedia)
    }

    func testImage() {
        let mode = DisplayMode.resolve(item: item(content: "/tmp/a.png", format: .image))
        XCTAssertEqual(mode, .image)
    }

    func testImageMissingViaTag() {
        var tags = ContentTags.empty
        tags.isMissing = true
        let mode = DisplayMode.resolve(
            item: item(content: "/tmp/gone.png", format: .image, tags: tags)
        )
        XCTAssertEqual(mode, .missing)
    }

    func testImageMissingViaRuntimeFlag() {
        let mode = DisplayMode.resolve(
            item: item(content: "/tmp/a.png", format: .image),
            hasMissingFiles: true
        )
        XCTAssertEqual(mode, .missing)
    }

    func testSingleFile() {
        let mode = DisplayMode.resolve(
            item: item(content: "/tmp/report.pdf", format: .fileURL)
        )
        XCTAssertEqual(mode, .singleFile)
    }

    func testMultiFile() {
        var tags = ContentTags.empty
        tags.isMultiFile = true
        let mode = DisplayMode.resolve(
            item: item(content: "/a\n/b", format: .fileURL, tags: tags)
        )
        XCTAssertEqual(mode, .multiFile)
    }

    func testMissingFileViaTag() {
        var tags = ContentTags.empty
        tags.isMissing = true
        let mode = DisplayMode.resolve(
            item: item(content: "/tmp/missing.pdf", format: .fileURL, tags: tags)
        )
        XCTAssertEqual(mode, .missing)
    }

    // MARK: - 链接

    func testSingleLinkText() {
        var tags = ContentTags.empty
        tags.isURL = true
        let mode = DisplayMode.resolve(
            item: item(content: "https://example.com/path", format: .text, tags: tags)
        )
        guard case .link(let url) = mode else {
            return XCTFail("expected .link, got \(mode)")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com/path")
    }

    func testMultiLinkText() {
        var tags = ContentTags.empty
        tags.isURL = true
        let content = "https://a.example\nhttps://b.example"
        let mode = DisplayMode.resolve(
            item: item(content: content, format: .text, tags: tags)
        )
        guard case .multiLink(let urls) = mode else {
            return XCTFail("expected .multiLink, got \(mode)")
        }
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://a.example",
            "https://b.example",
        ])
    }

    func testLinkUpgradesHTTPToHTTPS() {
        var tags = ContentTags.empty
        tags.isURL = true
        let mode = DisplayMode.resolve(
            item: item(content: "http://example.com", format: .html, tags: tags)
        )
        guard case .link(let url) = mode else {
            return XCTFail("expected .link, got \(mode)")
        }
        XCTAssertEqual(url.scheme, "https")
    }

    func testHTMLSegmentsTakePriorityOverURL() {
        var tags = ContentTags.empty
        tags.hasSegments = true
        tags.isURL = true
        let mode = DisplayMode.resolve(
            item: item(content: "https://example.com", format: .html, tags: tags)
        )
        XCTAssertEqual(mode, .mixedMedia)
    }

    func testURLTagWithoutValidSchemeFallsBackToPlainText() {
        var tags = ContentTags.empty
        tags.isURL = true
        // 无 scheme 的行不会进入 detectedLinks
        let mode = DisplayMode.resolve(
            item: item(content: "not-a-url", format: .text, tags: tags)
        )
        XCTAssertEqual(mode, .plainText)
    }

    // MARK: - detectedLinks / upgradeToHTTPS

    func testDetectedLinksEmptyWhenNotURLTagged() {
        let item = item(content: "https://example.com", format: .text)
        XCTAssertTrue(DisplayMode.detectedLinks(from: item).isEmpty)
    }

    func testUpgradeToHTTPSLeavesHTTPSUnchanged() {
        let url = URL(string: "https://example.com/a")!
        XCTAssertEqual(DisplayMode.upgradeToHTTPS(url), url)
    }
}
