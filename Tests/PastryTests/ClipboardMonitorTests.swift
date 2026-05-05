import XCTest
@testable import Pastry

// MARK: - ClipboardMonitor 测试套件
// 验证剪贴板格式读取（微信/QQ 自定义类型等）
// 所有剪贴板操作使用独立 pasteboard，不触及系统剪贴板

final class ClipboardMonitorTests: XCTestCase {

    /// 创建测试用独立 pasteboard
    private func makeTestPasteboard(_ name: String) -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("test.hermes.pastry.\(name)"))
    }

    // MARK: - TencentAttributeStringType plist 解析

    /// 标准 Tencent plist：图片 + 文字混合
    func testTencentPlistMixedContent() throws {
        let plist: [[String: Any]] = [
            ["TencentElementType": 1, "TencentElementValue": "/tmp/img.png"],
            ["TencentElementType": 11, "TencentElementValue": "这是文字内容"],
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = makeTestPasteboard("tencentMixed")
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

        let pb = makeTestPasteboard("tencentImageOnly")
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

        let pb = makeTestPasteboard("tencentMultiple")
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertEqual(text, "第一段第二段")
    }

    /// 空数组
    func testTencentPlistEmpty() throws {
        let plist: [[String: Any]] = []
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)

        let pb = makeTestPasteboard("tencentEmpty")
        pb.setData(data, forType: NSPasteboard.PasteboardType("TencentAttributeStringType"))

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }

    /// 无 TencentAttributeStringType 数据
    func testTencentPlistNotPresent() {
        let pb = makeTestPasteboard("tencentNotPresent")
        pb.setString("普通文字", forType: .string)

        let text = ClipboardMonitor.readTencentTextForTesting(from: pb)
        XCTAssertNil(text)
    }

    // MARK: - ContentSegment Codable

    func testContentSegmentTextCodableRoundTrip() throws {
        let seg = ContentSegment.text("hello world")
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(ContentSegment.self, from: data)
        XCTAssertEqual(decoded, seg)
        XCTAssertEqual(decoded.textValue, "hello world")
        XCTAssertNil(decoded.imageURL)
    }

    func testContentSegmentImageCodableRoundTrip() throws {
        let seg = ContentSegment.image(url: "https://example.com/img.png")
        let data = try JSONEncoder().encode(seg)
        let decoded = try JSONDecoder().decode(ContentSegment.self, from: data)
        XCTAssertEqual(decoded, seg)
        XCTAssertEqual(decoded.imageURL, "https://example.com/img.png")
        XCTAssertNil(decoded.textValue)
    }

    func testContentSegmentArrayCodableRoundTrip() throws {
        let segs: [ContentSegment] = [
            .text("段落一"),
            .image(url: "https://a.com/1.png"),
            .text("段落二"),
            .image(url: "https://a.com/2.png"),
        ]
        let data = try JSONEncoder().encode(segs)
        let decoded = try JSONDecoder().decode([ContentSegment].self, from: data)
        XCTAssertEqual(decoded, segs)
    }

    // MARK: - extractOrderedSegments

    func testSegmentsImageFirstThenText() {
        let html = "<img src='https://a.com/pic.png'><p>后面的文字</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].imageURL, "https://a.com/pic.png")
        XCTAssertEqual(segs[1].textValue, "后面的文字")
    }

    func testSegmentsTextFirstThenImage() {
        let html = "<p>前面的文字</p><img src='https://a.com/pic.png'>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].textValue, "前面的文字")
        XCTAssertEqual(segs[1].imageURL, "https://a.com/pic.png")
    }

    func testSegmentsTextOnly() {
        let html = "<p>只有文字没有图</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertTrue(segs.isEmpty)
    }

    func testSegmentsImageOnly() {
        let html = "<img src='https://a.com/pic.png'>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 1)
        XCTAssertEqual(segs[0].imageURL, "https://a.com/pic.png")
    }

    func testSegmentsDataURIFiltered() {
        let html = "<img src='data:image/png;base64,abc'><p>data URI 应被过滤，只剩文字走 textPreview</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertTrue(segs.isEmpty)
    }

    func testSegmentsMultipleImagesInterleaved() {
        let html = "<p>开头</p><img src='https://a.com/1.png'><p>中间</p><img src='https://a.com/2.png'><p>结尾</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 5)
        XCTAssertEqual(segs[0].textValue, "开头")
        XCTAssertEqual(segs[1].imageURL, "https://a.com/1.png")
        XCTAssertEqual(segs[2].textValue, "中间")
        XCTAssertEqual(segs[3].imageURL, "https://a.com/2.png")
        XCTAssertEqual(segs[4].textValue, "结尾")
    }

    func testSegmentsDuplicateURLFiltered() {
        let html = "<img src='https://a.com/pic.png'><img src='https://a.com/pic.png'><p>重复图片应去重</p>"
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].imageURL, "https://a.com/pic.png")
        XCTAssertEqual(segs[1].textValue, "重复图片应去重")
    }

    func testSegmentsRelativeURLResolved() {
        let html = "<img src='/images/pic.png'><p>文字</p>"
        let source = URL(string: "https://example.com/blog/post.html")!
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: source)
        XCTAssertEqual(segs.count, 2)
        XCTAssertEqual(segs[0].imageURL, "https://example.com/images/pic.png")
        XCTAssertEqual(segs[1].textValue, "文字")
    }

    func testSegmentsMaxFiveImages() {
        let html = (0..<7).map { i in "<img src='https://a.com/\(i).png'>" }.joined()
        let segs = ClipboardMonitor.extractOrderedSegmentsForTesting(from: html, sourceURL: nil)
        let imageCount = segs.filter { $0.imageURL != nil }.count
        XCTAssertEqual(imageCount, 5)
    }

    // MARK: - readFileURLs isFileURL 过滤

    /// pasteboard 上只有 file:// URL → 应识别为 fileURL
    func testFileURLsOnlyFileScheme() {
        let pb = makeTestPasteboard("fileURLsOnly")
        pb.clearContents()
        pb.writeObjects([URL(fileURLWithPath: "/Users/test/photo.png") as NSURL])
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.contentType, .fileURL)
        XCTAssertEqual(item?.content, "/Users/test/photo.png")
    }

    /// pasteboard 上只有 web URL（模拟 Handoff 同步） → 不应识别为 fileURL
    func testFileURLsHandoffWebURL() {
        let pb = makeTestPasteboard("fileURLsHandoff")
        pb.clearContents()
        pb.writeObjects([URL(string: "https://example.com/article")! as NSURL])
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNil(item, "Handoff 同步的 web URL 不应被误判为 fileURL")
    }

    /// pasteboard 上同时有 file:// 和 http:// URL → 只保留 file://
    func testFileURLsMixedSchemes() {
        let pb = makeTestPasteboard("fileURLsMixed")
        pb.clearContents()
        let fileURL = URL(fileURLWithPath: "/tmp/actual-file.pdf") as NSURL
        let webURL = URL(string: "https://example.com/wrong")! as NSURL
        pb.writeObjects([fileURL, webURL])
        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.contentType, .fileURL)
        XCTAssertEqual(item?.content, "/tmp/actual-file.pdf")
    }
}
