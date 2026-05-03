import Cocoa
import OSLog

// MARK: - 应用图标与主题色提取
// 缓存已查询的应用图标和颜色，避免重复 I/O
final class AppIconProvider {

    static let shared = AppIconProvider()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "appicon")

    // 常用应用固定颜色映射（美观、稳定）
    private static let appColorMap: [String: NSColor] = [
        "Finder":             NSColor(red: 0.20, green: 0.60, blue: 0.86, alpha: 1),  // 蓝
        "Safari":             NSColor(red: 0.10, green: 0.47, blue: 0.82, alpha: 1),  // 蓝
        "Google Chrome":      NSColor(red: 0.96, green: 0.78, blue: 0.16, alpha: 1),  // 黄
        "Arc":                NSColor(red: 0.60, green: 0.38, blue: 0.88, alpha: 1),  // 紫
        "Brave Browser":      NSColor(red: 0.96, green: 0.47, blue: 0.18, alpha: 1),  // 橙
        "Firefox":            NSColor(red: 0.91, green: 0.33, blue: 0.14, alpha: 1),  // 红橙
        "Microsoft Edge":     NSColor(red: 0.10, green: 0.67, blue: 0.36, alpha: 1),  // 绿
        "Terminal":           NSColor(red: 0.25, green: 0.25, blue: 0.25, alpha: 1),  // 深灰
        "iTerm2":             NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1),  // 黑
        "Warp":               NSColor(red: 0.00, green: 0.68, blue: 0.58, alpha: 1),  // 青
        "Visual Studio Code": NSColor(red: 0.13, green: 0.37, blue: 0.66, alpha: 1),  // 藏蓝
        "Code":               NSColor(red: 0.13, green: 0.37, blue: 0.66, alpha: 1),  // vs code
        "Xcode":              NSColor(red: 0.23, green: 0.48, blue: 0.82, alpha: 1),  // 蓝
        "Slack":              NSColor(red: 0.55, green: 0.13, blue: 0.47, alpha: 1),  // 紫红
        "Discord":            NSColor(red: 0.35, green: 0.42, blue: 0.80, alpha: 1),  // 靛蓝
        "Telegram":           NSColor(red: 0.16, green: 0.62, blue: 0.89, alpha: 1),  // 蓝
        "Notes":              NSColor(red: 0.86, green: 0.73, blue: 0.16, alpha: 1),  // 黄
        "备忘录":             NSColor(red: 0.86, green: 0.73, blue: 0.16, alpha: 1),  // 黄
        "Pages":              NSColor(red: 0.92, green: 0.61, blue: 0.06, alpha: 1),  // 橙
        "Numbers":            NSColor(red: 0.45, green: 0.69, blue: 0.17, alpha: 1),  // 草绿
        "Keynote":            NSColor(red: 0.00, green: 0.48, blue: 0.77, alpha: 1),  // 蓝
        "Preview":            NSColor(red: 0.33, green: 0.67, blue: 0.83, alpha: 1),  // 浅蓝
        "预览程序":           NSColor(red: 0.33, green: 0.67, blue: 0.83, alpha: 1),  // 浅蓝
        "Photos":             NSColor(red: 0.58, green: 0.15, blue: 0.47, alpha: 1),  // 紫
        "照片":               NSColor(red: 0.58, green: 0.15, blue: 0.47, alpha: 1),  // 紫
        "Music":              NSColor(red: 0.94, green: 0.32, blue: 0.22, alpha: 1),  // 红
        "音乐":               NSColor(red: 0.94, green: 0.32, blue: 0.22, alpha: 1),  // 红
    ]

    private let iconCache = NSCache<NSString, NSImage>()
    private let colorCache = NSCache<NSString, NSColor>()
    private let lock = NSLock()

    private init() {}

    /// 测试专用
    init(forTesting: Void) {}

    // MARK: - 公开接口

    /// 获取应用图标（SF Symbol fallback）
    func icon(for appName: String?) -> NSImage {
        guard let name = appName, !name.isEmpty else {
            return defaultIcon
        }

        let nsName = name as NSString
        lock.lock()
        if let cached = iconCache.object(forKey: nsName) { lock.unlock(); return cached }
        lock.unlock()

        let icon = findAppIcon(named: name)

        lock.lock()
        iconCache.setObject(icon, forKey: nsName)
        lock.unlock()

        return icon
    }

    /// 获取主题色
    func themeColor(for appName: String?) -> NSColor {
        guard let name = appName, !name.isEmpty else {
            return NSColor.controlAccentColor
        }

        let nsName = name as NSString
        lock.lock()
        if let cached = colorCache.object(forKey: nsName) { lock.unlock(); return cached }

        // 1. 查固定映射表
        if let mapped = Self.appColorMap[name] {
            colorCache.setObject(mapped, forKey: nsName)
            lock.unlock()
            return mapped
        }
        lock.unlock()

        // 2. 从应用图标提取主色
        let appIcon = self.icon(for: appName)
        if let extracted = extractDominantColor(from: appIcon) {
            lock.lock()
            colorCache.setObject(extracted, forKey: nsName)
            lock.unlock()
            return extracted
        }

        // 3. 基于名称哈希生成稳定色
        let hash = name.hash
        let hue = abs(CGFloat(hash % 360)) / 360.0
        let color = NSColor(hue: hue, saturation: 0.6, brightness: 0.7, alpha: 1)
        lock.lock()
        colorCache.setObject(color, forKey: nsName)
        lock.unlock()
        return color
    }

    // MARK: - 内部方法

    private var defaultIcon: NSImage {
        NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
            ?? NSImage()
    }

    /// 通过应用名查找实际图标
    private func findAppIcon(named name: String) -> NSImage {
        let ws = NSWorkspace.shared

        // 1. 常见路径精确匹配
        let paths = [
            "/Applications/\(name).app",
            "/Applications/Utilities/\(name).app",
            "/System/Applications/\(name).app",
            "\(NSHomeDirectory())/Applications/\(name).app",
        ]

        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return ws.icon(forFile: path)
            }
        }

        // 2. 通过 Bundle ID 查找
        if let bundleID = bundleID(for: name),
           let appURL = ws.urlForApplication(withBundleIdentifier: bundleID) {
            return ws.icon(forFile: appURL.path)
        }

        // 3. 模糊搜索（双向匹配，处理 iTerm2↔iTerm 这种差异）
        let appDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices",
            NSHomeDirectory() + "/Applications",
        ]

        for dir in appDirs {
            if let apps = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                let matched = apps.first {
                    $0.hasSuffix(".app") &&
                    ($0.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0))
                }
                if let match = matched {
                    return ws.icon(forFile: "\(dir)/\(match)")
                }
            }
        }

        return defaultIcon
    }

    /// 从应用图标提取主色
    private func extractDominantColor(from image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = min(cgImage.width, 32)
        let height = min(cgImage.height, 32)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, count: CGFloat = 0

        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let pr = CGFloat(pixels[i]) / 255
            let pg = CGFloat(pixels[i + 1]) / 255
            let pb = CGFloat(pixels[i + 2]) / 255
            let pa = CGFloat(pixels[i + 3]) / 255

            // 跳过透明像素和接近白色的像素
            if pa < 0.5 || (pr > 0.9 && pg > 0.9 && pb > 0.9) { continue }

            r += pr
            g += pg
            b += pb
            count += 1
        }

        guard count > 0 else { return nil }

        return NSColor(
            red: r / count,
            green: g / count,
            blue: b / count,
            alpha: 1
        )
    }

    /// 应用名 → Bundle ID 映射
    private func bundleID(for name: String) -> String? {
        let map: [String: String] = [
            "Finder":           "com.apple.finder",
            "Safari":           "com.apple.Safari",
            "Google Chrome":    "com.google.Chrome",
            "Firefox":          "org.mozilla.firefox",
            "Terminal":         "com.apple.Terminal",
            "iTerm2":           "com.googlecode.iterm2",
            "Xcode":            "com.apple.dt.Xcode",
            "Code":             "com.microsoft.VSCode",
            "Visual Studio Code": "com.microsoft.VSCode",
            "Slack":            "com.tinyspeck.slackmacgap",
            "Discord":          "com.hnc.Discord",
            "Telegram":         "ru.keepcoder.Telegram",
            "Notes":            "com.apple.Notes",
            "备忘录":           "com.apple.Notes",
            "Music":            "com.apple.Music",
            "音乐":             "com.apple.Music",
            "Photos":           "com.apple.Photos",
            "照片":             "com.apple.Photos",
            "Preview":          "com.apple.Preview",
            "预览程序":         "com.apple.Preview",
        ]
        return map[name]
    }
}

// MARK: - NSString convenience
extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive]) != nil
    }
}
