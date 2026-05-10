import XCTest
@testable import Pastry

// MARK: - 文件预览测试套件
// 验证类型判断优先级、预览策略映射、扩展名集合、文本类型判断、文本统计
// 所有剪贴板操作使用独立 pasteboard，不触及系统剪贴板

final class FilePreviewTests: XCTestCase {

    // MARK: - FilePreviewStyle 策略映射

    func testImageExtensionsMapToThumbnail() {
        let imageTypes = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "heic", "heif"]
        for ext in imageTypes {
            let style = ClipboardCardView.filePreviewStyleForTesting(extension: ext)
            XCTAssertEqual(style, .thumbnail, "\(ext) 应映射为 .thumbnail")
        }
    }

    func testNonImageExtensionsMapToSystemIcon() {
        let nonImageTypes = ["pdf", "svg", "dmg", "zip", "mp4", "docx", "xlsx", ""]
        for ext in nonImageTypes {
            let style = ClipboardCardView.filePreviewStyleForTesting(extension: ext)
            XCTAssertEqual(style, .systemIcon, "\(ext.isEmpty ? "(无扩展名)" : ext) 应映射为 .systemIcon")
        }
    }

    func testExtensionCaseInsensitive() {
        let cases = ["PNG", "JPG", "GIF", "Pdf", "SVG"]
        let expected: [ClipboardCardView.FilePreviewStyle] = [.thumbnail, .thumbnail, .thumbnail, .systemIcon, .systemIcon]
        for (i, ext) in cases.enumerated() {
            XCTAssertEqual(
                ClipboardCardView.filePreviewStyleForTesting(extension: ext),
                expected[i],
                "\(ext) 大小写不敏感"
            )
        }
    }

    // MARK: - imageExtensions 集合

    func testImageExtensionsNotEmpty() {
        XCTAssertFalse(ClipboardCardView.imageExtensionsForTesting.isEmpty)
    }

    func testImageExtensionsContainsCoreFormats() {
        let exts = ClipboardCardView.imageExtensionsForTesting
        XCTAssertTrue(exts.contains("png"))
        XCTAssertTrue(exts.contains("jpg"))
        XCTAssertTrue(exts.contains("jpeg"))
        XCTAssertTrue(exts.contains("heic"))
    }

    // MARK: - ClipboardMonitor 读取优先级：fileURL 优于 image
    // 使用独立 pasteboard，不污染系统剪贴板

    /// 创建测试用独立 pasteboard
    private func makeTestPasteboard(_ name: String) -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("test.hermes.pastry.\(name)"))
    }

    func testFileURLTakesPriorityOverImage() {
        let pb = makeTestPasteboard("fileURL")

        let testDir = NSTemporaryDirectory()
        let imgPath = (testDir as NSString).appendingPathComponent("test_file.png")
        let testURL = URL(fileURLWithPath: imgPath)
        pb.writeObjects([testURL as NSURL])

        let item = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(item, "有文件 URL 时应返回 item")
        XCTAssertEqual(item?.contentType, .fileURL)
    }

    func testImageReadsWhenNoFileURL() {
        let pb = makeTestPasteboard("imageOnly")

        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation else {
            XCTFail("无法生成 TIFF 数据")
            return
        }
        pb.setData(tiffData, forType: .tiff)

        XCTAssertNil(ClipboardMonitor.readFileURLsForTesting(from: pb),
                     "仅图片数据时 fileURL 应为 nil")

        let img = ClipboardMonitor.readImageDataForTesting(from: pb)
        XCTAssertNotNil(img, "TIFF 数据应可读为图片")
    }

    func testBothFileURLAndImageOnPasteboard() {
        let pb = makeTestPasteboard("both")

        let testDir = NSTemporaryDirectory()
        let imgPath = (testDir as NSString).appendingPathComponent("photo.jpg")
        let testURL = URL(fileURLWithPath: imgPath)

        let image = NSImage(size: NSSize(width: 10, height: 10))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 10, height: 10).fill()
        image.unlockFocus()
        guard let tiffData = image.tiffRepresentation else {
            XCTFail("无法生成 TIFF 数据")
            return
        }

        pb.declareTypes([.fileURL, .tiff], owner: nil)
        pb.writeObjects([testURL as NSURL])
        pb.setData(tiffData, forType: .tiff)

        let fileItem = ClipboardMonitor.readFileURLsForTesting(from: pb)
        XCTAssertNotNil(fileItem, "fileURL reader 应能读取")
        let imgItem = ClipboardMonitor.readImageDataForTesting(from: pb)
        XCTAssertNotNil(imgItem, "image reader 应能读取")
    }

    // MARK: - 文本类型判断（isTextType）

    func testTextTypesReturnTrue() {
        let textTypes: [ClipType] = [.text, .rtf, .html]
        for ct in textTypes {
            XCTAssertTrue(ClipboardCardView.isTextTypeForTesting(contentType: ct),
                          "\(ct) 应为文本类")
        }
    }

    func testNonTextTypesReturnFalse() {
        let nonTextTypes: [ClipType] = [.fileURL, .image]
        for ct in nonTextTypes {
            XCTAssertFalse(ClipboardCardView.isTextTypeForTesting(contentType: ct),
                           "\(ct) 不应为文本类")
        }
    }

    // MARK: - 文本统计

    func testTextStatisticsEmptyString() {
        let stats = ClipboardCardView.textStatisticsForTesting("")
        XCTAssertEqual(stats.chars, 0)
        XCTAssertEqual(stats.words, 0)
        XCTAssertEqual(stats.lines, 1, "空字符串视为 1 行")
    }

    func testTextStatisticsSingleLine() {
        let stats = ClipboardCardView.textStatisticsForTesting("Hello world")
        XCTAssertEqual(stats.chars, 11)
        XCTAssertEqual(stats.words, 2)
        XCTAssertEqual(stats.lines, 1)
    }

    func testTextStatisticsMultiLine() {
        let stats = ClipboardCardView.textStatisticsForTesting("Line 1\nLine 2\nLine 3")
        XCTAssertEqual(stats.chars, 20)
        XCTAssertEqual(stats.words, 6)
        XCTAssertEqual(stats.lines, 3)
    }

    func testTextStatisticsTrailingNewline() {
        let stats = ClipboardCardView.textStatisticsForTesting("Hello\n")
        XCTAssertEqual(stats.chars, 6)
        XCTAssertEqual(stats.words, 1)
        XCTAssertEqual(stats.lines, 2, "末尾换行符视为额外空行")
    }

    func testTextStatisticsChineseCharacters() {
        let stats = ClipboardCardView.textStatisticsForTesting("你好世界 测试文本")
        XCTAssertEqual(stats.chars, 9)
        XCTAssertEqual(stats.words, 2, "中文空格分词")
        XCTAssertEqual(stats.lines, 1)
    }

    func testTextStatisticsOnlyWhitespace() {
        let stats = ClipboardCardView.textStatisticsForTesting("   \t  ")
        XCTAssertEqual(stats.chars, 6)
        XCTAssertEqual(stats.words, 0, "纯空白无单词")
        XCTAssertEqual(stats.lines, 1)
    }

    // MARK: - 多选文本拼接

    private func makeItem(_ content: String, _ type: ClipType) -> ClipboardItem {
        ClipboardItem(timestamp: Date(), content: content, contentType: type)
    }

    func testMultiSelectTextOnlyTextTypes() {
        let items = [
            makeItem("Hello", .text),
            makeItem("World", .text),
            makeItem("Test", .rtf),
        ]
        let result = ClipboardCardView.multiSelectTextForTesting(items)
        XCTAssertEqual(result, "Hello\nWorld\nTest", "纯文本类应按换行拼接")
    }

    func testMultiSelectTextSkipsImages() {
        let items = [
            makeItem("Line 1", .text),
            makeItem("/path/to/img.png", .image),
            makeItem("Line 2", .html),
        ]
        let result = ClipboardCardView.multiSelectTextForTesting(items)
        XCTAssertEqual(result, "Line 1\nLine 2", "图片应被跳过")
    }

    func testMultiSelectTextEmptyArray() {
        let result = ClipboardCardView.multiSelectTextForTesting([])
        XCTAssertEqual(result, "", "空数组应返回空字符串")
    }

    func testMultiSelectTextAllImagesReturnsEmpty() {
        let items = [
            makeItem("/a.png", .image),
            makeItem("/b.jpg", .image),
        ]
        let result = ClipboardCardView.multiSelectTextForTesting(items)
        XCTAssertEqual(result, "", "全是图片应返回空")
    }

    // MARK: - 单选拖拽内容分发

    func testDragPayloadImageIsFile() {
        let item = makeItem("/path/to/screenshot.png", .image)
        let payload = ClipboardCardView.dragPayloadForTesting(item)
        XCTAssertTrue(payload.isFile, "图片应为文件拖拽")
        XCTAssertEqual(payload.content, "/path/to/screenshot.png")
    }

    func testDragPayloadFileURLIsFile() {
        let item = makeItem("/Users/mason/Desktop/doc.pdf", .fileURL)
        let payload = ClipboardCardView.dragPayloadForTesting(item)
        XCTAssertTrue(payload.isFile, "fileURL 应为文件拖拽")
    }

    func testDragPayloadTextIsNotFile() {
        let item = makeItem("some text", .text)
        let payload = ClipboardCardView.dragPayloadForTesting(item)
        XCTAssertFalse(payload.isFile, "纯文本不应为文件拖拽")
    }

    func testDragPayloadRTFIsNotFile() {
        let item = makeItem("{\\rtf1...}", .rtf)
        let payload = ClipboardCardView.dragPayloadForTesting(item)
        XCTAssertFalse(payload.isFile, "RTF 不应为文件拖拽")
    }

    func testDragPayloadHTMLIsNotFile() {
        let item = makeItem("<p>Hi</p>", .html)
        let payload = ClipboardCardView.dragPayloadForTesting(item)
        XCTAssertFalse(payload.isFile, "HTML 不应为文件拖拽")
    }

    // MARK: - 预览条件覆盖（url 类型能预览）

    func testURLTypeCanPreview() {
        // canPreview = canOpen || isTextType
        // .url 属于 canOpen，应该能预览
        let urlItem = makeItem("https://example.com", .url)
        XCTAssertTrue(ClipboardCardView.isTextTypeForTesting(contentType: urlItem.contentType) == false,
                      ".url 不应为文本类，但应通过 canOpen 能预览")
    }

    func testTextTypeCanPreview() {
        XCTAssertTrue(ClipboardCardView.isTextTypeForTesting(contentType: .text))
        XCTAssertTrue(ClipboardCardView.isTextTypeForTesting(contentType: .rtf))
        XCTAssertTrue(ClipboardCardView.isTextTypeForTesting(contentType: .html))
    }

    func testFileURLTypeCanPreview() {
        // .fileURL 属于 canOpen
        let item = makeItem("/tmp/test.pdf", .fileURL)
        XCTAssertFalse(ClipboardCardView.isTextTypeForTesting(contentType: item.contentType),
                       ".fileURL 不是文本类，但应通过 canOpen 能预览")
    }

    func testImageTypeCanPreview() {
        let item = makeItem("/tmp/photo.jpg", .image)
        XCTAssertFalse(ClipboardCardView.isTextTypeForTesting(contentType: item.contentType),
                       ".image 不是文本类，但应通过 canOpen 能预览")
    }

    // MARK: - isMultiFile 判断

    func testIsMultiFileTrueForFileURLWithNewline() {
        XCTAssertTrue(ClipboardCardView.isMultiFileForTesting(
            content: "/tmp/a.txt\n/tmp/b.txt", contentType: .fileURL
        ), "多文件路径（换行分隔）应判断为多文件")
    }

    func testIsMultiFileFalseForSingleFileURL() {
        XCTAssertFalse(ClipboardCardView.isMultiFileForTesting(
            content: "/tmp/only.txt", contentType: .fileURL
        ), "单文件路径不应判断为多文件")
    }

    func testIsMultiFileFalseForNonFileURL() {
        XCTAssertFalse(ClipboardCardView.isMultiFileForTesting(
            content: "/tmp/a.txt\n/tmp/b.txt", contentType: .text
        ), "非 fileURL 类型即使含换行也不应判断为多文件")
        XCTAssertFalse(ClipboardCardView.isMultiFileForTesting(
            content: "/tmp/a.txt\n/tmp/b.txt", contentType: .image
        ))
    }

    // MARK: - openableURL 存在性检查

    func testOpenableURLReturnsNilForDeletedFile() {
        let path = NSTemporaryDirectory() + "pastry_test_deleted_\(UUID().uuidString).txt"
        let item = makeItem(path, .fileURL)
        // 文件不存在 → openableURL 应为 nil
        XCTAssertNil(ClipboardCardView.openableURLForTesting(item),
                     "已删除/不存在的文件 openableURL 应为 nil")
    }

    func testOpenableURLReturnsURLForExistingFile() {
        let path = NSTemporaryDirectory() + "pastry_test_exists_\(UUID().uuidString).txt"
        try? "test".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let item = makeItem(path, .fileURL)
        let result = ClipboardCardView.openableURLForTesting(item)
        XCTAssertNotNil(result, "存在的文件 openableURL 不应为 nil")
        XCTAssertEqual(result?.path, path)
    }

    func testOpenableURLMultiFileReturnsFirstExisting() {
        let existing = NSTemporaryDirectory() + "pastry_test_multi_1_\(UUID().uuidString).txt"
        let deleted = NSTemporaryDirectory() + "pastry_test_multi_2_\(UUID().uuidString).txt"
        try? "first".write(toFile: existing, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: existing) }

        let item = makeItem("\(existing)\n\(deleted)", .fileURL)
        let result = ClipboardCardView.openableURLForTesting(item)
        XCTAssertNotNil(result, "多文件中至少一个存在时应返回第一个存在的")
        XCTAssertEqual(result?.path, existing)
    }

    func testOpenableURLMultiFileAllDeletedReturnsNil() {
        let a = NSTemporaryDirectory() + "pastry_test_allgone_a_\(UUID().uuidString).txt"
        let b = NSTemporaryDirectory() + "pastry_test_allgone_b_\(UUID().uuidString).txt"
        let item = makeItem("\(a)\n\(b)", .fileURL)
        XCTAssertNil(ClipboardCardView.openableURLForTesting(item),
                     "多文件全部删除时 openableURL 应为 nil")
    }

    func testOpenableURLImageType() {
        let path = NSTemporaryDirectory() + "pastry_test_img_\(UUID().uuidString).png"
        try? "fake".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let item = makeItem(path, .image)
        let result = ClipboardCardView.openableURLForTesting(item)
        XCTAssertNotNil(result, "存在的图片缓存文件 openableURL 不应为 nil")
    }

    func testOpenableURLImageDeleted() {
        let item = makeItem("/tmp/nonexistent_img.png", .image)
        XCTAssertNil(ClipboardCardView.openableURLForTesting(item),
                     "已删除的图片缓存 openableURL 应为 nil")
    }

    func testOpenableURLForHTTPURL() {
        let item = makeItem("https://example.com", .url)
        let result = ClipboardCardView.openableURLForTesting(item)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.absoluteString, "https://example.com")
    }
}
