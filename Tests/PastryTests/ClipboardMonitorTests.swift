import XCTest
@testable import Pastry

// MARK: - ClipboardMonitor 测试套件
// 验证剪贴板格式读取（微信/QQ 自定义类型等）

final class ClipboardMonitorTests: XCTestCase {

    // MARK: - TencentAttributeStringType plist 解析

    /// 标准 Tencent plist：图片 + 文字混合
    func testTencentPlistMixedContent() throws {
        let plist: [[String: Any]] = [
            ["TencentElementType": 1, "TencentElementValue": "/tmp/img.png"],
            ["TencentElementType": 11, "TencentElementValue": "这是文字内容"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        // 写入剪贴板，用 Monitor 读取
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertEqual(text, "这是文字内容")
    }

    /// 只有图片没有文字
    func testTencentPlistImageOnly() throws {
        let plist: [[String: Any]] = [
            ["TencentElementType": 1, "TencentElementValue": "/tmp/img.png"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }

    /// 多条文字拼接
    func testTencentPlistMultipleTexts() throws {
        let plist: [[String: Any]] = [
            ["TencentElementType": 11, "TencentElementValue": "第一段"],
            ["TencentElementType": 1, "TencentElementValue": "/tmp/img.png"],
            ["TencentElementType": 11, "TencentElementValue": "第二段"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertEqual(text, "第一段第二段")
    }

    /// 空数组
    func testTencentPlistEmpty() throws {
        let plist: [[String: Any]] = []
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }

    /// 无 TencentAttributeStringType 数据
    func testTencentPlistNotPresent() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("普通文字", forType: .string)

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }
}
