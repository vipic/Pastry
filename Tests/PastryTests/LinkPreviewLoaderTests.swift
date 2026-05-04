import XCTest
@testable import Pastry

// MARK: - LinkPreviewLoader 测试套件
// 验证 HTML 元数据提取（og/twitter）+ 图片语义排序降级 + title 标签降级 + 缓存

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
        XCTAssertNil(result)
    }

    // MARK: - twitter:image 提取（新增）

    func testTwitterImageExtracted() {
        let html = "<meta name=\"twitter:image\" content=\"https://example.com/tw-card.jpg\">"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "twitter:image")
        XCTAssertEqual(result, "https://example.com/tw-card.jpg")
    }

    func testTwitterImagePropertyAttr() {
        let html = "<meta property=\"twitter:image\" content=\"https://example.com/tw-prop.jpg\">"
        let result = LinkPreviewLoader.extractMetaForTesting(from: html, tag: "twitter:image")
        XCTAssertEqual(result, "https://example.com/tw-prop.jpg")
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

    // MARK: - 降级图片提取（基础）

    func testFirstImageSimple() {
        let html = "<img src='https://example.com/pic.jpg'><p>text</p>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/pic.jpg")
    }

    func testFirstImageSkipsDataURI() {
        let html = "<img src='data:image/png;base64,abc'><img src='https://example.com/real.png'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/real.png")
    }

    func testFirstImageSkipsTrackingPixel() {
        let html = "<img src='https://a.com/1x1.gif'><img src='https://a.com/real.jpg'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://a.com")!
        )
        XCTAssertEqual(result, "https://a.com/real.jpg")
    }

    func testFirstImageNoImages() {
        let html = "<p>纯文字页面</p>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertNil(result)
    }

    func testFirstImageAllDataURIs() {
        let html = "<img src='data:image/svg+xml,abc'><img src='data:image/gif,def'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertNil(result)
    }

    // MARK: - 语义过滤：logo / icon 黑名单（新增）

    func testSkipsLogoBySrc() {
        let html = "<img src='/images/logo.png'><img src='/images/content.jpg'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/images/content.jpg")
    }

    func testSkipsLogoByClass() {
        let html = "<img class='site-logo' src='/logo.png'><img src='/hero.jpg'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/hero.jpg")
    }

    func testSkipsFavicon() {
        let html = "<img src='/favicon.ico'><img src='/blog-thumb.png'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/blog-thumb.png")
    }

    func testSkipsGravatar() {
        let html = "<img src='https://gravatar.com/avatar/abc'><img src='/post-hero.jpg'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/post-hero.jpg")
    }

    func testSkipsAnalyticsPixel() {
        let html = "<img src='https://a.com/analytics/pixel.gif'><img src='/photo.jpg'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/photo.jpg")
    }

    // MARK: - 语义加权：featured / hero 优先（新增）

    func testPrioritizesFeaturedImage() {
        let html = """
        <img src='/logo.png' class='nav-logo'>
        <img src='/featured.jpg' class='featured-image'>
        <img src='/other.jpg'>
        """
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/featured.jpg")
    }

    func testPrioritizesHeroImage() {
        let html = """
        <img src='/icons/menu.png'>
        <img src='/hero-banner.jpg' class='hero'>
        <img src='/inline.jpg'>
        """
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/hero-banner.jpg")
    }

    func testPrioritizesWpImage() {
        let html = """
        <img src='/logo.png'>
        <img class='wp-image-123' src='/content-photo.jpg'>
        """
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/content-photo.jpg")
    }

    func testPrioritizesThumbnail() {
        let html = """
        <img src='/icon.png' class='header-icon'>
        <img src='/thumb.jpg' class='post-thumbnail'>
        """
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/thumb.jpg")
    }

    // MARK: - 懒加载图片（data-src 降级，新增）

    func testLazyLoadedImageDataSrc() {
        // src 是 data URI 占位图，真实图片在 data-src
        let html = """
        <img src='data:image/gif;base64,R0lGODlhAQABAIAAAA' data-src='/real-photo.jpg'>
        <img src='/avatar.jpg'>
        """
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        // data-src 被提取，avatar.jpg 被过滤
        XCTAssertEqual(result, "https://example.com/real-photo.jpg")
    }

    // MARK: - 尺寸过滤（新增）

    func testSkipsSmallImageByWidth() {
        let html = "<img width='32' height='32' src='/icon.png'><img src='/big.jpg'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://example.com/big.jpg")
    }

    func testSkipsSmallImageByHeight() {
        let html = "<img width='800' height='60' src='/banner.gif'><img src='/photo.jpg'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        // banner.gif 高仅 60 → 被当小图标过滤
        XCTAssertEqual(result, "https://example.com/photo.jpg")
    }

    // MARK: - 保底：全部被过滤时返回最大尺寸图（新增）

    func testFallsBackToFirstWhenAllFiltered() {
        // 两个噪音图都被过滤，返回第一个非 dataURI 的
        let html = "<img src='https://a.com/logo.png'><img src='https://a.com/favicon.ico'>"
        let result = LinkPreviewLoader.extractBestImageForTesting(
            from: html,
            baseURL: URL(string: "https://example.com")!
        )
        XCTAssertEqual(result, "https://a.com/logo.png")
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
