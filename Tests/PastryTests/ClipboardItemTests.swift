import XCTest
@testable import Pastry

// MARK: - ClipboardItem 测试套件
// 测试 SourceFormat 标签、dedupKey 等属性

final class ClipboardItemTests: XCTestCase {

    // MARK: - SourceFormat.label 本地化覆盖

    /// 所有类型都有非空标签（L10n 键缺失时返回空字符串）
    func testSourceFormatAllLabelsNonEmpty() {
        for type in SourceFormat.allCases {
            XCTAssertFalse(
                type.label.isEmpty,
                "SourceFormat.\(type) 的标签不应为空"
            )
        }
    }

    /// 所有类型标签互不相同
    func testSourceFormatLabelsAreUnique() {
        let labels = Set(SourceFormat.allCases.map { $0.label })
        XCTAssertEqual(
            labels.count,
            SourceFormat.allCases.count,
            "每种类型的标签应唯一"
        )
    }

    // MARK: - SourceFormat.iconName 覆盖

    /// 所有类型都有图标名（fallback 依赖 SF Symbol 存在性）
    func testSourceFormatAllIconsNonEmpty() {
        for type in SourceFormat.allCases {
            XCTAssertFalse(
                type.iconName.isEmpty,
                "SourceFormat.\(type) 的图标名不应为空"
            )
        }
    }

    // MARK: - segments 懒解码

    /// segments computed property 从 segmentsJSON 解码，返回正确内容
    func testSegmentsFromJSON() {
        let segs: [ContentSegment] = [.text("段落一"), .image(url: "https://example.com/img.png")]
        let jsonData = try! JSONEncoder().encode(segs)
        let jsonStr = String(data: jsonData, encoding: .utf8)!

        let item = ClipboardItem(
            content: "text", sourceFormat: .html,
            segmentsJSON: jsonStr
        )

        let decoded = item.segments
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?[0].textValue, "段落一")
        XCTAssertEqual(decoded?[1].imageURL, "https://example.com/img.png")
    }

    /// segments 参数被编码为 segmentsJSON，无需访问 segments 即已存储
    func testSegmentsEncodedAsJSON() {
        let segs: [ContentSegment] = [.text("测试"), .image(url: "img://a")]
        let item = ClipboardItem(
            content: "text", sourceFormat: .html,
            segments: segs
        )

        // segmentsJSON 应已编码但 segments 未被解码（未触发 computed）
        XCTAssertNotNil(item.segmentsJSON)
        XCTAssertFalse(item.segmentsJSON!.isEmpty)

        // 触发解码后应返回相同内容
        let decoded = item.segments
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?[0].textValue, "测试")
    }

    /// segmentsJSON 为 nil 时 segments 返回 nil
    func testSegmentsNilWhenJSONNil() {
        let item = ClipboardItem(content: "plain text", sourceFormat: .text)

        XCTAssertNil(item.segmentsJSON)
        XCTAssertNil(item.segments)
    }

    /// 空 segments 数组 → segmentsJSON 为 nil
    func testEmptySegmentsProducesNilJSON() {
        let item = ClipboardItem(
            content: "text", sourceFormat: .html,
            segments: []
        )
        XCTAssertNil(item.segmentsJSON)
        XCTAssertNil(item.segments)
    }

    /// segmentsJSON 为无效 JSON 时 segments 返回 nil（不崩溃）
    func testSegmentsHandlesInvalidJSON() {
        let item = ClipboardItem(
            content: "text", sourceFormat: .html,
            segmentsJSON: "not valid json {{{"
        )
        XCTAssertNil(item.segments)
    }

    // MARK: - SourceFormat.storageKey / 迁移

    func testStorageKeyRoundTripsForAllCases() {
        for format in SourceFormat.allCases {
            XCTAssertEqual(SourceFormat(storageKey: format.storageKey), format)
        }
    }

    func testLegacyUrlStorageKeyMapsToText() {
        XCTAssertEqual(SourceFormat(storageKey: "url"), .text, "存量 url 类型应映射为 text")
    }

    func testUnknownStorageKeyDefaultsToText() {
        XCTAssertEqual(SourceFormat(storageKey: "unknown-type"), .text)
        XCTAssertEqual(SourceFormat(storageKey: ""), .text)
    }

    // MARK: - ContentSegment / ContentTags

    func testContentSegmentTextAndImageAccessors() {
        let t = ContentSegment.text("hi")
        let i = ContentSegment.image(url: "https://x/y.png")
        XCTAssertEqual(t.textValue, "hi")
        XCTAssertNil(t.imageURL)
        XCTAssertEqual(i.imageURL, "https://x/y.png")
        XCTAssertNil(i.textValue)
    }

    func testContentSegmentCodableRoundTrip() throws {
        let segs: [ContentSegment] = [.text("a"), .image(url: "u")]
        let data = try JSONEncoder().encode(segs)
        let decoded = try JSONDecoder().decode([ContentSegment].self, from: data)
        XCTAssertEqual(decoded, segs)
    }

    func testContentTagsEmptyDefaults() {
        let tags = ContentTags.empty
        XCTAssertFalse(tags.isURL)
        XCTAssertFalse(tags.hasSegments)
        XCTAssertFalse(tags.isMultiFile)
        XCTAssertFalse(tags.isMissing)
    }

    // MARK: - ClipboardItem 身份

    func testEqualityAndHashUseIdOnly() {
        let id = UUID()
        let a = ClipboardItem(id: id, content: "a", sourceFormat: .text)
        let b = ClipboardItem(id: id, content: "b", sourceFormat: .image)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)

        let c = ClipboardItem(content: "a", sourceFormat: .text)
        XCTAssertNotEqual(a, c)
    }

    func testImageURLsExtractedFromSegments() {
        let item = ClipboardItem(
            content: "html",
            sourceFormat: .html,
            segments: [.text("t"), .image(url: "https://cdn/a.png"), .image(url: "https://cdn/b.png")]
        )
        XCTAssertEqual(item.imageURLs, ["https://cdn/a.png", "https://cdn/b.png"])
    }

    // MARK: - Codable / dedupKey

    func testClipboardItemCodableRoundTripPreservesTagsAndNotes() throws {
        var tags = ContentTags.empty
        tags.isURL = true
        tags.hasSegments = true
        let original = ClipboardItem(
            content: "https://example.com",
            sourceFormat: .html,
            tags: tags,
            appName: "Safari",
            isHandoff: true,
            linkTitle: "Example Domain",
            segments: [.text("body"), .image(url: "https://cdn/x.png")],
            displayCount: 3,
            isPinned: true,
            favoriteNote: "keep me"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ClipboardItem.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.content, original.content)
        XCTAssertEqual(decoded.sourceFormat, .html)
        XCTAssertEqual(decoded.tags, tags)
        XCTAssertEqual(decoded.appName, "Safari")
        XCTAssertTrue(decoded.isHandoff)
        XCTAssertEqual(decoded.linkTitle, "Example Domain")
        XCTAssertEqual(decoded.favoriteNote, "keep me")
        XCTAssertEqual(decoded.displayCount, 3)
        XCTAssertTrue(decoded.isPinned)
        XCTAssertEqual(decoded.segments?.count, 2)
    }

    func testDedupKeyUnifiesTextRTFHTMLPrefix() {
        let text = ClipboardItem(content: "same", sourceFormat: .text)
        let rtf = ClipboardItem(content: "same", sourceFormat: .rtf)
        let html = ClipboardItem(content: "same", sourceFormat: .html)
        XCTAssertTrue(text.dedupKey.hasPrefix("text:"))
        XCTAssertTrue(rtf.dedupKey.hasPrefix("text:"))
        XCTAssertTrue(html.dedupKey.hasPrefix("text:"))
        // 相同 content / 无 annotation / 无 segments → 前缀统一后 key 相同
        XCTAssertEqual(text.dedupKey, rtf.dedupKey)
        XCTAssertEqual(text.dedupKey, html.dedupKey)
    }

    func testDedupKeyKeepsImageAndFileURLSeparate() {
        let image = ClipboardItem(content: "/tmp/a.png", sourceFormat: .image)
        let file = ClipboardItem(content: "/tmp/a.png", sourceFormat: .fileURL)
        XCTAssertNotEqual(image.dedupKey, file.dedupKey)
        XCTAssertTrue(image.dedupKey.hasPrefix("image:"))
        XCTAssertTrue(file.dedupKey.hasPrefix("fileURL:"))
    }
}
