import XCTest
@testable import Pastry

// MARK: - ImageCacheManager 测试套件
// 验证图片双存储（原始数据 .orig + 缩略图 .png）及粘贴路径推导

final class ImageCacheManagerTests: XCTestCase {

    let manager = ImageCacheManager.shared

    // MARK: - save() 双存储

    /// 保存后同时存在 .orig（原始数据）和 .png（缩略图）
    func testSaveCreatesBothFiles() throws {
        let originalData = generateTestTIFFData(width: 1200, height: 800)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)
        XCTAssertNotNil(thumbPath, "save() 应返回缩略图路径")
        XCTAssertTrue(FileManager.default.fileExists(atPath: thumbPath!), "缩略图文件应存在")

        let origPath = manager.originalPath(forThumbnail: thumbPath!)
        XCTAssertNotNil(origPath, "原始数据路径应存在")
        XCTAssertTrue(FileManager.default.fileExists(atPath: origPath!), "原始数据文件应存在")
    }

    /// 原始数据文件内容与剪贴板读取到的原始 data 一致
    func testOrigFileContainsExactOriginalData() throws {
        let originalData = generateTestTIFFData(width: 1200, height: 800)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)
        let origPath = manager.originalPath(forThumbnail: thumbPath!)
        let savedData = try Data(contentsOf: URL(fileURLWithPath: origPath!))

        XCTAssertEqual(savedData, originalData, "原始数据应逐字节一致")
    }

    /// 缩略图逻辑尺寸不超过 256（点，非像素 — 像素尺寸取决于屏幕 scale）
    func testThumbnailLogicSizeMax256() throws {
        let originalData = generateTestTIFFData(width: 2400, height: 1600)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)!
        let thumb = NSImage(contentsOfFile: thumbPath)!

        XCTAssertLessThanOrEqual(Int(thumb.size.width), 256, "缩略图逻辑宽度 ≤ 256pt")
        XCTAssertLessThanOrEqual(Int(thumb.size.height), 256, "缩略图逻辑高度 ≤ 256pt")
    }

    // MARK: - originalPath(forThumbnail:)

    /// 通过缩略图路径反查原始路径
    func testOriginalPathDerivesCorrectly() throws {
        let originalData = generateTestTIFFData(width: 100, height: 100)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)!
        let origPath = manager.originalPath(forThumbnail: thumbPath)!

        XCTAssertTrue(origPath.hasSuffix(".orig"), "原始数据文件扩展名应为 .orig")
        // 缩略图路径去掉扩展名后的 stem 应与原始路径一致
        let thumbStem = URL(fileURLWithPath: thumbPath).deletingPathExtension().lastPathComponent
        let origStem = URL(fileURLWithPath: origPath).deletingPathExtension().lastPathComponent
        XCTAssertEqual(thumbStem, origStem, "缩略图和原始数据应共享 UUID stem")
    }

    /// 不存在 .orig 时返回 nil（兼容旧缓存）
    func testOriginalPathReturnsNilWhenNoOrigFile() {
        let nonexistentThumbPath = "/tmp/______nonexistent______.png"
        let result = manager.originalPath(forThumbnail: nonexistentThumbPath)
        XCTAssertNil(result, "无 .orig 文件时应返回 nil")
    }

    // MARK: - 旧缓存兼容

    /// 旧缓存只有 .png 无 .orig 时，originalPath 返回 nil
    func testOldCacheWithoutOrigReturnsNil() throws {
        let originalData = generateTestTIFFData(width: 100, height: 100)
        let image = NSImage(data: originalData)!

        let thumbPath = manager.save(image: image, data: originalData)!
        let origPath = manager.originalPath(forThumbnail: thumbPath)!

        // 模拟删除 .orig 文件（旧缓存场景）
        try FileManager.default.removeItem(atPath: origPath)

        XCTAssertNil(manager.originalPath(forThumbnail: thumbPath), "删除 .orig 后应返回 nil")
    }

    // MARK: - 帮助函数

    /// 生成测试用 TIFF 数据
    private func generateTestTIFFData(width: Int, height: Int) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        image.unlockFocus()
        return image.tiffRepresentation!
    }
}
