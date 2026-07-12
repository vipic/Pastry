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
}
