import XCTest
@testable import Pastry

// MARK: - LinkPreviewLoader 测试套件
// 验证 HTML 元数据提取（og:title/description/image）+ 图片降级策略 + title 标签降级 + 缓存

final class LinkPreviewLoaderTests: XCTestCase {

    // MARK: - og 元数据提取

    func testOGTitleStandard() {
        let html = "<meta property=\"og:title\" content=\"测试标题\">"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:title")
        XCTAssertEqual(result, "测试标题")
    }

    func testOGTitleSingleQuote() {
        let html = "<meta property='og:title' content='单引号标题'>"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:title")
        XCTAssertEqual(result, "单引号标题")
    }

    func testOGTitleNameAttr() {
        let html = "<meta name=\"og:title\" content=\"name 属性标题\">"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:title")
        XCTAssertEqual(result, "name 属性标题")
    }

    func testOGTitleNotPresent() {
        let html = "<html><head></head><body>no meta</body></html>"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:title")
        XCTAssertNil(result)
    }

    func testOGDescription() {
        let html = "<meta property=\"og:description\" content=\"这是一段描述\">"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:description")
        XCTAssertEqual(result, "这是一段描述")
    }

    func testOGImageStandard() {
        let html = "<meta property=\"og:image\" content=\"https://example.com/thumb.jpg\">"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:image")
        XCTAssertEqual(result, "https://example.com/thumb.jpg")
    }

    func testOGImageNotPresent() {
        let html = "<html><head></head><body>no og:image</body></html>"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:image")
        XCTAssertNil(result)
    }

    func testEmptyContentValueIgnored() {
        let html = "<meta property=\"og:title\" content=\"\">"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "og:title")
        // 空值会被 trim 后判空 → nil
        XCTAssertNil(result)
    }

    // MARK: - 图片 URL 解析

    func testResolveAbsoluteURL() {
        let result = LinkPreviewLoader.resolveImageURLForTesting(
            src: "https://cdn.example.com/img.png",
            baseURL: URL(string: "https://example.com/page")!
        )
        XCTAssertEqual(result, "https://cdn.example.com/img.png")
    }

    func testResolveRelativeURL() {
        let result = LinkPreviewLoader.resolveImageURLForTesting(
            src: "/images/hero.png",
            baseURL: URL(string: "https://example.com/blog/post")!
        )
        XCTAssertEqual(result, "https://example.com/images/hero.png")
    }

    func testResolveRelativeURLNoLeadingSlash() {
        let result = LinkPreviewLoader.resolveImageURLForTesting(
            src: "images/hero.png",
            baseURL: URL(string: "https://example.com/blog/")!
        )
        XCTAssertEqual(result, "https://example.com/blog/images/hero.png")
    }

    // MARK: - 降级图片提取

    func testFirstImageSimple() {
        let html = "<img src='https://example.com/pic.jpg'><p>text</p>"
        let result = LinkPreviewLoader.extractFirstImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/pic.jpg")
    }

    func testFirstImageSkipsDataURI() {
        let html = "<img src='data:image/png;base64,abc'><img src='https://example.com/real.png'>"
        let result = LinkPreviewLoader.extractFirstImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/real.png")
    }

    func testFirstImageSkipsTrackingPixel() {
        let html = "<img src='https://a.com/1x1.gif'><img src='https://a.com/real.jpg'>"
        let result = LinkPreviewLoader.extractFirstImageForTesting(
            from: html,
            baseURL: URL(string: "https://a.com")!
        )
        XCTAssertEqual(result, "https://a.com/real.jpg")
    }

    func testFirstImageNoImages() {
        let html = "<p>纯文字页面</p>"
        let result = LinkPreviewLoader.extractFirstImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertNil(result)
    }

    func testFirstImageAllDataURIs() {
        let html = "<img src='data:image/svg+xml,abc'><img src='data:image/gif,def'>"
        let result = LinkPreviewLoader.extractFirstImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertNil(result)
    }

    // MARK: - <title> 标签提取（og:title 缺失时的降级）

    func testTitleTagSimple() {
        let html = "<html><head><title>页面标题</title></head><body></body></html>"
        let result = LinkPreviewLoader.extractTitleTagForTesting(from: html)
        XCTAssertEqual(result, "页面标题")
    }

    func testTitleTagWithWhitespace() {
        let html = "<title>  前后空格  </title>"
        let result = LinkPreviewLoader.extractTitleTagForTesting(from: html)
        XCTAssertEqual(result, "前后空格")
    }

    func testTitleTagEmpty() {
        let html = "<title></title>"
        let result = LinkPreviewLoader.extractTitleTagForTesting(from: html)
        XCTAssertNil(result)
    }

    func testTitleTagNotPresent() {
        let html = "<html><head></head><body>无标题</body></html>"
        let result = LinkPreviewLoader.extractTitleTagForTesting(from: html)
        XCTAssertNil(result)
    }

    func testTitleTagCaseInsensitive() {
        let html = "<HTML><HEAD><TITLE>大写标题</TITLE></HEAD></HTML>"
        let result = LinkPreviewLoader.extractTitleTagForTesting(from: html)
        XCTAssertEqual(result, "大写标题")
    }

    func testTitleTagOnlyWhitespace() {
        let html = "<title>   </title>"
        let result = LinkPreviewLoader.extractTitleTagForTesting(from: html)
        // trim 后为空 → nil
        XCTAssertNil(result)
    }

    // MARK: - 缓存行为

    func testCachedPreviewInitiallyNil() {
        let result = LinkPreviewLoader.shared.cachedPreview(for: "https://never-seen.example.com")
        XCTAssertNil(result, "未加载过的 URL 缓存应为 nil")
    }

    func testPreviewStructInit() {
        let p = LinkPreviewLoader.Preview(
            title: "标题",
            description: "描述",
            imageURL: "https://img.example.com/pic.jpg",
            host: "example.com"
        )
        XCTAssertEqual(p.title, "标题")
        XCTAssertEqual(p.description, "描述")
        XCTAssertEqual(p.imageURL, "https://img.example.com/pic.jpg")
        XCTAssertEqual(p.host, "example.com")
    }

    func testPreviewStructNilDescription() {
        let p = LinkPreviewLoader.Preview(
            title: "仅标题",
            description: nil,
            imageURL: nil,
            host: "host.com"
        )
        XCTAssertEqual(p.title, "仅标题")
        XCTAssertNil(p.description)
        XCTAssertNil(p.imageURL)
    }
}
