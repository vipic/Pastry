import XCTest
@testable import Pastry

// MARK: - ClipboardItem 测试套件
// 测试 ClipType 标签、dedupKey 等属性

final class ClipboardItemTests: XCTestCase {

    // MARK: - ClipType.label 本地化覆盖

    /// 所有类型都有非空标签（L10n 键缺失时返回空字符串）
    func testClipTypeAllLabelsNonEmpty() {
        for type in ClipType.allCases {
            XCTAssertFalse(
                type.label.isEmpty,
                "ClipType.\(type) 的标签不应为空"
            )
        }
    }

    /// 所有类型标签互不相同
    func testClipTypeLabelsAreUnique() {
        let labels = Set(ClipType.allCases.map { $0.label })
        XCTAssertEqual(
            labels.count,
            ClipType.allCases.count,
            "每种类型的标签应唯一"
        )
    }

    // MARK: - ClipType.iconName 覆盖

    /// 所有类型都有图标名（fallback 依赖 SF Symbol 存在性）
    func testClipTypeAllIconsNonEmpty() {
        for type in ClipType.allCases {
            XCTAssertFalse(
                type.iconName.isEmpty,
                "ClipType.\(type) 的图标名不应为空"
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
            content: "text", contentType: .html,
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
            content: "text", contentType: .html,
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
        let item = ClipboardItem(content: "plain text", contentType: .text)

        XCTAssertNil(item.segmentsJSON)
        XCTAssertNil(item.segments)
    }

    /// 空 segments 数组 → segmentsJSON 为 nil
    func testEmptySegmentsProducesNilJSON() {
        let item = ClipboardItem(
            content: "text", contentType: .html,
            segments: []
        )
        XCTAssertNil(item.segmentsJSON)
        XCTAssertNil(item.segments)
    }

    /// segmentsJSON 为无效 JSON 时 segments 返回 nil（不崩溃）
    func testSegmentsHandlesInvalidJSON() {
        let item = ClipboardItem(
            content: "text", contentType: .html,
            segmentsJSON: "not valid json {{{"
        )
        XCTAssertNil(item.segments)
    }
}
