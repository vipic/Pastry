import XCTest
@testable import Pastry

// MARK: - ClipboardItem 搜索过滤测试套件

final class ClipboardSearchTests: XCTestCase {

    // MARK: - 辅助方法

    private func makeItem(
        content: String,
        app: String? = "Safari",
        type: SourceFormat = .text
    ) -> ClipboardItem {
        ClipboardItem(content: content, sourceFormat: type, appName: app)
    }

    private func makeItems(_ contents: [String]) -> [ClipboardItem] {
        contents.map { makeItem(content: $0) }
    }

    // MARK: - 基本匹配

    /// 精确匹配：查询词完全等于 content
    func testExactMatch() {
        let items = makeItems(["hello world", "foo bar", "baz"])
        let results = items.filtered(by: "hello world")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "hello world")
    }

    /// 子串匹配：查询词是 content 的一部分
    func testSubstringMatch() {
        let items = makeItems(["去买牛奶", "买鸡蛋", "看电影"])
        let results = items.filtered(by: "牛奶")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "去买牛奶")
    }

    /// 多个匹配结果
    func testMultipleMatches() {
        let items = makeItems(["Swift programming", "Swift is great", "Rust language"])
        let results = items.filtered(by: "swift")
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].content, "Swift programming")
        XCTAssertEqual(results[1].content, "Swift is great")
    }

    /// 无匹配
    func testNoMatch() {
        let items = makeItems(["Hello", "World", "Test"])
        let results = items.filtered(by: "XYZ不存在")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - 大小写

    /// 查询全小写，content 全大写 → 应匹配
    func testCaseInsensitiveQueryLower() {
        let items = makeItems(["HELLO WORLD"])
        let results = items.filtered(by: "hello")
        XCTAssertEqual(results.count, 1)
    }

    /// 查询全大写，content 全小写 → 应匹配
    func testCaseInsensitiveQueryUpper() {
        let items = makeItems(["hello world"])
        let results = items.filtered(by: "HELLO")
        XCTAssertEqual(results.count, 1)
    }

    /// 查询混合大小写，content 混合大小写 → 应匹配
    func testCaseInsensitiveMixedCase() {
        let items = makeItems(["HeLLo WoRLd"])
        let results = items.filtered(by: "hEllO")
        XCTAssertEqual(results.count, 1)
    }

    /// 中文不区分"大小写"（中日韩字符的小写 == 自身）
    func testCJKCharacters() {
        let items = makeItems(["你好世界", "こんにちは", "안녕하세요"])
        let results = items.filtered(by: "世界")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "你好世界")
    }

    // MARK: - 边界条件

    /// 空数组
    func testEmptyArray() {
        let items: [ClipboardItem] = []
        let results = items.filtered(by: "anything")
        XCTAssertEqual(results.count, 0)
    }

    /// 空查询 → 返回空数组（不是返回全部）
    func testEmptyQuery() {
        let items = makeItems(["A", "B", "C"])
        let results = items.filtered(by: "")
        XCTAssertEqual(results.count, 0)
    }

    /// 纯空白查询 → 返回空数组
    func testWhitespaceOnlyQuery() {
        let items = makeItems(["A", "B", "C"])
        let results = items.filtered(by: "   \n  ")
        XCTAssertEqual(results.count, 0)
    }

    /// 特殊字符查询
    func testSpecialCharacters() {
        let items = makeItems(["email@example.com", "https://example.com", "price: $100.50"])
        let results = items.filtered(by: "@example")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "email@example.com")
    }

    /// Emoji 查询
    func testEmojiQuery() {
        let items = makeItems(["🎉 Party time! 🎊", "Regular text"])
        let results = items.filtered(by: "🎉")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].content, "🎉 Party time! 🎊")
    }

    /// 查询词长于所有 content（不可能匹配）
    func testQueryLongerThanContent() {
        let items = makeItems(["short", "ab"])
        let results = items.filtered(by: "very long query string that won't match anything")
        XCTAssertEqual(results.count, 0)
    }

    // MARK: - App 名称匹配

    /// 通过 App 名称匹配
    func testAppNameMatch() {
        let items = [
            makeItem(content: "剪贴板文本", app: "Xcode"),
            makeItem(content: "笔记内容", app: "Notes"),
            makeItem(content: "网页内容", app: "Safari"),
        ]
        let results = items.filtered(by: "xcode")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].appName, "Xcode")
        XCTAssertEqual(results[0].content, "剪贴板文本")
    }

    /// App 名称大小写不敏感
    func testAppNameCaseInsensitive() {
        let items = [makeItem(content: "text", app: "SAFARI")]
        let results = items.filtered(by: "safari")
        XCTAssertEqual(results.count, 1)
    }

    /// 禁用 App 名称搜索
    func testExcludeAppName() {
        let items = [
            makeItem(content: "random content", app: "SpecialApp42"),
        ]
        // includeAppName: true → 匹配
        let withApp = items.filtered(by: "specialapp", includeAppName: true)
        XCTAssertEqual(withApp.count, 1, "应通过 appName 匹配")

        // includeAppName: false → 不匹配
        let withoutApp = items.filtered(by: "specialapp", includeAppName: false)
        XCTAssertEqual(withoutApp.count, 0, "不应通过 appName 匹配")
    }

    /// appName 为 nil 时不崩溃
    func testNilAppName() {
        let items = [makeItem(content: "无来源文本", app: nil)]
        let results = items.filtered(by: "文本")
        XCTAssertEqual(results.count, 1)
    }

    /// 同时匹配 content 和 appName → 每项只保留一份
    func testMatchBothContentAndAppName() {
        let items = [
            makeItem(content: "Hello World", app: "Safari"),
        ]
        let results = items.filtered(by: "hello")
        XCTAssertEqual(results.count, 1)

        let results2 = items.filtered(by: "safari")
        XCTAssertEqual(results2.count, 1)
    }

    // MARK: - 性能

    /// 10000 条数据应在合理时间内完成
    func testPerformance10k() {
        let count = 10000
        var items: [ClipboardItem] = []
        for i in 0..<count {
            items.append(makeItem(content: "Item number \(i)"))
        }

        measure {
            let results = items.filtered(by: "9999")
            XCTAssertEqual(results.count, 1)
        }
    }

    /// 保持原序（filter 不改变顺序）
    func testPreservesOrder() {
        let items = makeItems(["A first", "B second", "A third", "C fourth"])
        let results = items.filtered(by: "A", includeAppName: false)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].content, "A first")
        XCTAssertEqual(results[1].content, "A third")
    }

    /// 不修改原数组（值语义）
    func testDoesNotMutate() {
        let items = makeItems(["A", "B", "C"])
        let originalCount = items.count
        _ = items.filtered(by: "A")
        XCTAssertEqual(items.count, originalCount)
    }

    // MARK: - 多种内容类型

    /// 图片类型项的 content（路径）也可搜索
    func testImageTypeSearchable() {
        let items = [makeItem(content: "/tmp/screenshot.png", app: "Preview", type: .image)]
        let results = items.filtered(by: "screenshot")
        XCTAssertEqual(results.count, 1)
    }

    /// 文件 URL 类型也可搜索
    func testFileURLTypeSearchable() {
        let items = [makeItem(content: "/Users/mason/Documents/report.pdf", app: "Finder", type: .fileURL)]
        let results = items.filtered(by: "report")
        XCTAssertEqual(results.count, 1)
    }

    /// HTML 类型也可搜索
    func testHTMLTypeSearchable() {
        let items = [makeItem(content: "<h1>Hello</h1>", app: "Chrome", type: .html)]
        let results = items.filtered(by: "<h1>")
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - linkTitle / favoriteNote

    /// 仅 linkTitle 命中（content 不匹配）
    func testLinkTitleMatch() {
        let items = [
            ClipboardItem(
                content: "https://example.com/a",
                sourceFormat: .text,
                tags: ContentTags(isURL: true),
                appName: "Safari",
                linkTitle: "Pastry Release Notes"
            ),
            makeItem(content: "unrelated body"),
        ]
        let results = items.filtered(by: "release", includeAppName: false)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].linkTitle, "Pastry Release Notes")
    }

    /// linkTitle 大小写不敏感
    func testLinkTitleCaseInsensitive() {
        let items = [
            ClipboardItem(
                content: "https://x.test",
                sourceFormat: .text,
                tags: ContentTags(isURL: true),
                linkTitle: "OpenAI Blog"
            ),
        ]
        XCTAssertEqual(items.filtered(by: "openai").count, 1)
    }

    /// 仅 favoriteNote 命中
    func testFavoriteNoteMatch() {
        let items = [
            ClipboardItem(
                content: "opaque token xyz",
                sourceFormat: .text,
                isPinned: true,
                favoriteNote: "客户甲合同参考"
            ),
            makeItem(content: "其他内容"),
        ]
        let results = items.filtered(by: "合同", includeAppName: false)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].favoriteNote, "客户甲合同参考")
    }

    /// favoriteNote 大小写不敏感
    func testFavoriteNoteCaseInsensitive() {
        let items = [
            ClipboardItem(
                content: "body",
                sourceFormat: .text,
                favoriteNote: "KeepForLater"
            ),
        ]
        XCTAssertEqual(items.filtered(by: "keepforlater").count, 1)
    }

    /// nil linkTitle / favoriteNote 不崩溃且不误匹配
    func testNilLinkTitleAndFavoriteNote() {
        let items = [makeItem(content: "plain")]
        XCTAssertEqual(items.filtered(by: "anything-missing").count, 0)
    }

    /// content 与 note 同时可命中时仍只返回一次
    func testDoesNotDuplicateWhenContentAndNoteBothMatch() {
        let items = [
            ClipboardItem(
                content: "contract draft",
                sourceFormat: .text,
                favoriteNote: "contract follow-up"
            ),
        ]
        XCTAssertEqual(items.filtered(by: "contract").count, 1)
    }
}
