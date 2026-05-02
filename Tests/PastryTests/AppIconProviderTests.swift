import XCTest
@testable import Pastry
import Cocoa

// MARK: - AppIconProvider 测试套件
// 测试主题色映射、哈希确定性、默认值、缓存

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

    // MARK: - themeColor: 已知应用固定色

    func testThemeColorKnownAppSafari() {
        let color = provider.themeColor(for: "Safari")
        let expected = NSColor(red: 0.10, green: 0.47, blue: 0.82, alpha: 1)
        assertColorsEqual(color, expected, accuracy: 0.01)
    }

    func testThemeColorKnownAppXcode() {
        let color = provider.themeColor(for: "Xcode")
        let expected = NSColor(red: 0.23, green: 0.48, blue: 0.82, alpha: 1)
        assertColorsEqual(color, expected, accuracy: 0.01)
    }

    func testThemeColorKnownAppFinder() {
        let color = provider.themeColor(for: "Finder")
        let expected = NSColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1)
        assertColorsEqual(color, expected, accuracy: 0.01)
    }

    func testThemeColorKnownAppChrome() {
        let color = provider.themeColor(for: "Google Chrome")
        let expected = NSColor(red: 0.96, green: 0.78, blue: 0.16, alpha: 1)
        assertColorsEqual(color, expected, accuracy: 0.01)
    }

    func testThemeColorKnownAppChineseName() {
        let color = provider.themeColor(for: "备忘录")
        let expected = NSColor(red: 0.86, green: 0.73, blue: 0.16, alpha: 1)
        assertColorsEqual(color, expected, accuracy: 0.01)
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

    // MARK: - themeColor: 未知应用哈希色

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

    private func assertColorsEqual(
        _ lhs: NSColor, _ rhs: NSColor,
        accuracy: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let l = lhs.usingColorSpace(.sRGB),
              let r = rhs.usingColorSpace(.sRGB) else {
            XCTFail("无法转换颜色空间", file: file, line: line)
            return
        }
        XCTAssertEqual(l.redComponent, r.redComponent, accuracy: accuracy, "红色分量不匹配", file: file, line: line)
        XCTAssertEqual(l.greenComponent, r.greenComponent, accuracy: accuracy, "绿色分量不匹配", file: file, line: line)
        XCTAssertEqual(l.blueComponent, r.blueComponent, accuracy: accuracy, "蓝色分量不匹配", file: file, line: line)
    }
}
