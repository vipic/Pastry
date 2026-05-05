import XCTest
@testable import Pastry

// MARK: - DatabaseManager 测试套件
// 每个测试用例使用独立的临时数据库，互不干扰

final class DatabaseManagerTests: XCTestCase {

    var db: DatabaseManager!
    var tempPath: String!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
        tempPath = tmp.appendingPathComponent("pastry-test-\(UUID().uuidString).db").path
        db = DatabaseManager(dbPath: tempPath)
    }

    override func tearDown() {
        db = nil
        if let path = tempPath {
            // 清理 WAL/SHM 文件
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + "-wal")
            try? FileManager.default.removeItem(atPath: path + "-shm")
        }
        super.tearDown()
    }

    // MARK: - 辅助方法

    private func makeItem(
        content: String = "测试文本",
        type: ClipType = .text,
        app: String? = "Safari",
        pinned: Bool = false,
        isHandoff: Bool = false
    ) -> ClipboardItem {
        ClipboardItem(
            content: content,
            contentType: type,
            appName: app,
            isHandoff: isHandoff,
            isPinned: pinned
        )
    }

    // MARK: - 基本 CRUD

    /// 插入一条 → recent() 应包含它
    func testInsertAndRetrieve() {
        let item = makeItem(content: "Hello World")
        XCTAssertTrue(db.insert(item))

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content, "Hello World")
        XCTAssertEqual(items[0].contentType, .text)
        XCTAssertEqual(items[0].appName, "Safari")
    }

    /// 插入多条 → recent() 按时间倒序
    func testInsertMultiple() {
        let a = makeItem(content: "A")
        Thread.sleep(forTimeInterval: 0.01)
        let b = makeItem(content: "B")
        Thread.sleep(forTimeInterval: 0.01)
        let c = makeItem(content: "C")

        db.insert(a)
        db.insert(b)
        db.insert(c)

        let items = db.recent()
        XCTAssertEqual(items.count, 3)
        // 最新在前
        XCTAssertEqual(items[0].content, "C")
        XCTAssertEqual(items[1].content, "B")
        XCTAssertEqual(items[2].content, "A")
    }

    /// 插入不同类型的内容
    func testInsertDifferentTypes() {
        let textItem = makeItem(content: "文本", type: .text)
        Thread.sleep(forTimeInterval: 0.01)
        let imageItem = makeItem(content: "/tmp/img.png", type: .image)
        Thread.sleep(forTimeInterval: 0.01)
        let fileItem = makeItem(content: "/Users/test/file.pdf", type: .fileURL)

        db.insert(textItem)
        db.insert(imageItem)
        db.insert(fileItem)

        let items = db.recent()
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].contentType, .fileURL)
        XCTAssertEqual(items[1].contentType, .image)
        XCTAssertEqual(items[2].contentType, .text)
    }

    // MARK: - 去重

    /// 相同 dedupKey 的条目第二次插入应被拒绝
    func testDedupRejectsDuplicate() {
        let item1 = makeItem(content: "相同内容")
        XCTAssertTrue(db.insert(item1))

        let item2 = makeItem(content: "相同内容")
        XCTAssertFalse(db.insert(item2), "重复条目应被拒绝")

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
    }

    /// 不同 dedupKey 应正常插入
    func testDedupAllowsDifferent() {
        XCTAssertTrue(db.insert(makeItem(content: "内容A")))
        XCTAssertTrue(db.insert(makeItem(content: "内容B")))
        XCTAssertEqual(db.recent().count, 2)
    }

    /// 不同内容类型 + 相同内容 = 不同 dedupKey
    func testDedupDifferentTypesAllowed() {
        let textItem = makeItem(content: "hello", type: .text)
        let htmlItem = makeItem(content: "hello", type: .html)

        XCTAssertTrue(db.insert(textItem))
        XCTAssertTrue(db.insert(htmlItem))
        XCTAssertEqual(db.recent().count, 2)
    }

    // MARK: - 删除

    func testDeleteExisting() {
        let item = makeItem()
        db.insert(item)

        XCTAssertTrue(db.delete(id: item.id.uuidString))
        XCTAssertEqual(db.recent().count, 0)
    }

    func testDeleteNonexistent() {
        XCTAssertFalse(db.delete(id: "invalid-uuid"))
    }

    // MARK: - Pin 切换

    func testTogglePinOn() {
        let item = makeItem(pinned: false)
        db.insert(item)

        XCTAssertTrue(db.togglePin(id: item.id.uuidString))

        let favs = db.favorites()
        XCTAssertEqual(favs.count, 1)
        XCTAssertTrue(favs[0].isPinned)
    }

    func testTogglePinOff() {
        let item = makeItem(pinned: true)
        db.insert(item)

        XCTAssertTrue(db.togglePin(id: item.id.uuidString))

        let favs = db.favorites()
        XCTAssertEqual(favs.count, 0)
    }

    func testTogglePinNonexistent() {
        XCTAssertFalse(db.togglePin(id: UUID().uuidString))
    }

    // MARK: - 清空

    func testClearNonPinnedPreservesPinned() {
        let pinned = makeItem(content: "钉选的", pinned: true)
        let normal = makeItem(content: "普通的", pinned: false)

        db.insert(pinned)
        db.insert(normal)

        db.clearNonPinned()

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].content, "钉选的")
    }

    func testClearAllRemovesEverything() {
        db.insert(makeItem(content: "A", pinned: true))
        db.insert(makeItem(content: "B", pinned: false))

        db.clearAll()
        XCTAssertEqual(db.recent().count, 0)
        XCTAssertEqual(db.favorites().count, 0)
    }

    // MARK: - 统计

    func testStatsEmpty() {
        let stats = db.stats()
        XCTAssertEqual(stats.totalItems, 0)
        XCTAssertEqual(stats.favoriteCount, 0)
    }

    func testStatsWithItems() {
        db.insert(makeItem(content: "A", pinned: true))
        db.insert(makeItem(content: "BB", pinned: false))
        db.insert(makeItem(content: "CCC", pinned: false))

        let stats = db.stats()
        XCTAssertEqual(stats.totalItems, 3)
        XCTAssertEqual(stats.favoriteCount, 1)
        // content 长度: 1 + 2 + 3 = 6 bytes → 6/1024 = 0 KB（整数除法）
    }

    // MARK: - bumpTimestamp

    func testBumpTimestampMovesToTop() {
        let a = makeItem(content: "旧条目")
        db.insert(a)
        Thread.sleep(forTimeInterval: 0.01)

        let b = makeItem(content: "新条目")
        db.insert(b)

        // bump 旧条目
        db.bumpTimestamp(id: a.id.uuidString)

        let items = db.recent()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].content, "旧条目", "bump 后应排到最前")
        XCTAssertEqual(items[1].content, "新条目")
    }

    // MARK: - incrementDisplayCount

    func testIncrementDisplayCount() {
        let item = makeItem()
        db.insert(item)

        db.incrementDisplayCount(id: item.id.uuidString)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].displayCount, 1)
    }

    func testIncrementDisplayCountMultiple() {
        let item = makeItem()
        db.insert(item)

        db.incrementDisplayCount(id: item.id.uuidString)
        db.incrementDisplayCount(id: item.id.uuidString)
        db.incrementDisplayCount(id: item.id.uuidString)

        let items = db.recent()
        XCTAssertEqual(items[0].displayCount, 3)
    }

    // MARK: - 搜索

    func testSearchEmptyReturnsRecent() {
        db.insert(makeItem(content: "Hello"))
        db.insert(makeItem(content: "World"))

        let results = db.search(query: "")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchFindsMatchingContent() {
        db.insert(makeItem(content: "去买牛奶"))
        db.insert(makeItem(content: "买鸡蛋"))
        db.insert(makeItem(content: "看电影"))

        let results = db.search(query: "牛奶")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "去买牛奶")
    }

    func testSearchNoMatch() {
        db.insert(makeItem(content: "Hello"))
        let results = db.search(query: "XYZ不存在")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - textAnnotation 持久化

    /// 插入带 textAnnotation 的图片条目 → 读回应包含附注文字
    func testTextAnnotationInsertAndRetrieve() {
        let item = ClipboardItem(
            content: "/tmp/img.png",
            contentType: .image,
            appName: "WeChat",
            textAnnotation: "这是附带的文字"
        )
        XCTAssertTrue(db.insert(item))

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].textAnnotation, "这是附带的文字")
    }

    /// 不带 textAnnotation 的条目 → 读回 nil
    func testTextAnnotationNil() {
        let item = makeItem(content: "普通文本", type: .text)
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].textAnnotation)
    }

    /// 空字符串 textAnnotation 应正常持久化
    func testTextAnnotationEmptyString() {
        let item = ClipboardItem(
            content: "/tmp/img2.png",
            contentType: .image,
            textAnnotation: ""
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items[0].textAnnotation, "")
    }

    // MARK: - segments 持久化

    /// 带 segments 的 HTML 条目插入后读回
    func testSegmentsInsertAndRetrieve() {
        let segs: [ContentSegment] = [
            .image(url: "https://a.com/pic.png"),
            .text("图片后的文字"),
        ]
        let item = ClipboardItem(
            content: "图片后的文字",
            contentType: .html,
            segments: segs
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].segments?.count, 2)
        XCTAssertEqual(items[0].segments?[0].imageURL, "https://a.com/pic.png")
        XCTAssertEqual(items[0].segments?[1].textValue, "图片后的文字")
        // imageURLs 计算属性应从 segments 派生
        XCTAssertEqual(items[0].imageURLs, ["https://a.com/pic.png"])
    }

    /// 不含 segments 的普通条目 → nil
    func testSegmentsNilForNonHTML() {
        let item = makeItem(content: "纯文本", type: .text)
        db.insert(item)

        let items = db.recent()
        XCTAssertNil(items[0].segments)
        XCTAssertNil(items[0].imageURLs)
    }

    /// segments 为空数组 → nil
    func testSegmentsEmptyArray() {
        let item = ClipboardItem(
            content: "无图 HTML",
            contentType: .html,
            segments: []
        )
        db.insert(item)

        let items = db.recent()
        XCTAssertNil(items[0].segments)
    }

    // MARK: - isHandoff 持久化

    /// 插入带 isHandoff 的条目 → 读回应保留标记
    func testIsHandoffInsertAndRetrieve() {
        let item = makeItem(content: "来自 iPhone 的文本", app: nil, isHandoff: true)
        XCTAssertTrue(db.insert(item))

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items[0].isHandoff)
        XCTAssertNil(items[0].appName, "Handoff 条目 appName 应为 nil")
    }

    /// 不带 isHandoff 的条目 → 读回 false
    func testIsHandoffDefaultFalse() {
        let item = makeItem(content: "本地复制")
        db.insert(item)

        let items = db.recent()
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].isHandoff)
    }

    /// 多种类型 + isHandoff → 全部正确持久化
    func testIsHandoffMultipleTypes() {
        let text = makeItem(content: "text", type: .text, isHandoff: true)
        let img = makeItem(content: "/tmp/pic.png", type: .image, isHandoff: true)
        let file = makeItem(content: "/tmp/file.pdf", type: .fileURL, isHandoff: false)

        db.insert(text)
        Thread.sleep(forTimeInterval: 0.01)
        db.insert(img)
        Thread.sleep(forTimeInterval: 0.01)
        db.insert(file)

        let items = db.recent()
        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items[0].isHandoff == false)   // file (latest, isHandoff: false)
        XCTAssertTrue(items[1].isHandoff)             // img  (isHandoff: true)
        XCTAssertTrue(items[2].isHandoff)             // text (isHandoff: true)
    }

    /// 搜索也应保留 isHandoff
    func testIsHandoffSurvivesSearch() {
        let item = makeItem(content: "Handoff 搜索测试", isHandoff: true)
        db.insert(item)

        let results = db.search(query: "Handoff")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isHandoff)
    }

    // MARK: - 边界条件

    /// recent(limit:) 应遵守 limit
    func testRecentLimit() {
        for i in 0..<20 {
            let item = makeItem(content: "Item \(i)")
            db.insert(item)
            Thread.sleep(forTimeInterval: 0.001)
        }

        let limited = db.recent(limit: 5)
        XCTAssertEqual(limited.count, 5)
    }

    /// favorites(limit:) 应遵守 limit
    func testFavoritesLimit() {
        for i in 0..<10 {
            let item = makeItem(content: "Pin \(i)", pinned: true)
            db.insert(item)
            Thread.sleep(forTimeInterval: 0.001)
        }

        let limited = db.favorites(limit: 3)
        XCTAssertEqual(limited.count, 3)
    }
}
