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
}
