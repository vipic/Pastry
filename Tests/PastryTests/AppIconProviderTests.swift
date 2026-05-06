import XCTest
@testable import Pastry
import Cocoa

// MARK: - AppIconProvider 测试套件
// 测试主题色提取、哈希确定性、默认值、缓存

final class AppIconProviderTests: XCTestCase {

    var provider: AppIconProvider!

    override func setUp() {
        super.setUp()
        provider = AppIconProvider(forTesting: ())
    }

    override func tearDown() {
        provider = nil
        super.tearDown()
    }

    // MARK: - themeColor: 已知应用（从图标提取主色）

    func testThemeColorKnownAppSafari() {
        let color = provider.themeColor(for: "Safari")
        assertValidColor(color)
    }

    func testThemeColorKnownAppXcode() {
        let color = provider.themeColor(for: "Xcode")
        assertValidColor(color)
    }

    func testThemeColorKnownAppFinder() {
        let color = provider.themeColor(for: "Finder")
        assertValidColor(color)
    }

    func testThemeColorKnownAppChrome() {
        let color = provider.themeColor(for: "Google Chrome")
        assertValidColor(color)
    }

    func testThemeColorKnownAppChineseName() {
        let color = provider.themeColor(for: "备忘录")
        assertValidColor(color)
    }

    // MARK: - themeColor: nil / 空

    func testThemeColorNilReturnsAccentColor() {
        let color = provider.themeColor(for: nil)
        XCTAssertEqual(color, NSColor.controlAccentColor)
    }

    func testThemeColorEmptyReturnsAccentColor() {
        let color = provider.themeColor(for: "")
        XCTAssertEqual(color, NSColor.controlAccentColor)
    }

    // MARK: - themeColor: 未知应用哈希色（确定性）

    func testThemeColorUnknownAppDeterministic() {
        let color1 = provider.themeColor(for: "MyCustomApp")
        let color2 = provider.themeColor(for: "MyCustomApp")
        XCTAssertEqual(color1, color2, "相同应用名应返回相同颜色")
    }

    // MARK: - icon: nil / 空

    func testIconNilReturnsDefault() {
        let icon = provider.icon(for: nil)
        XCTAssertFalse(icon.size.width == 0, "应返回有效图标")
    }

    func testIconEmptyReturnsDefault() {
        let icon = provider.icon(for: "")
        XCTAssertFalse(icon.size.width == 0, "应返回有效图标")
    }

    // MARK: - 缓存

    func testThemeColorCaching() {
        let color1 = provider.themeColor(for: "Safari")
        let color2 = provider.themeColor(for: "Safari")
        // 缓存应返回同一对象（指针相等）
        XCTAssertTrue(color1 === color2)
    }

    func testIconCaching() {
        let icon1 = provider.icon(for: "Safari")
        let icon2 = provider.icon(for: "Safari")
        // 缓存应返回同一对象
        XCTAssertTrue(icon1 === icon2)
    }

    // MARK: - 辅助

    private func assertValidColor(
        _ color: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // 不应返回默认的 accent color（说明走了图标提取或哈希分支）
        XCTAssertNotEqual(color, NSColor.controlAccentColor, "应返回派生色而非默认 accent 色", file: file, line: line)
    }
}
