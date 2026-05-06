import Cocoa
import OSLog

// MARK: - 应用图标与主题色提取
// 缓存已查询的应用图标和颜色，避免重复 I/O
final class AppIconProvider {

    static let shared = AppIconProvider()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "appicon")

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
        lock.unlock()

        // 1. 从应用图标提取主色
        let appIcon = self.icon(for: appName)
        if let extracted = extractDominantColor(from: appIcon) {
            lock.lock()
            colorCache.setObject(extracted, forKey: nsName)
            lock.unlock()
            return extracted
        }

        // 2. 基于名称哈希生成稳定色
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
        // 1. 常见路径精确匹配
        let paths = [
            "/Applications/\(name).app",
            "/Applications/Utilities/\(name).app",
            "/System/Applications/\(name).app",
            "\(NSHomeDirectory())/Applications/\(name).app",
        ]

        for path in paths {
            let resolved = (path as NSString).resolvingSymlinksInPath
            if let icon = iconFromBundle(at: resolved) ?? iconFromWorkspace(at: resolved) {
                return icon
            }
        }

        // 2. 模糊搜索（双向匹配，处理 iTerm2↔iTerm 这种差异）
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
                    let resolved = ("\(dir)/\(match)" as NSString).resolvingSymlinksInPath
                    if let icon = iconFromBundle(at: resolved) ?? iconFromWorkspace(at: resolved) {
                        return icon
                    }
                }
            }
        }

        // 3. 通用降级：从正在运行的进程中按名称匹配（覆盖 AppTranslocation 等非常规安装路径）
        if let runningApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.localizedName == name
        }), let icon = runningApp.icon {
            return icon
        }

        return defaultIcon
    }

    /// 直接从 .app bundle 读取 icns 图标（避免 NSWorkspace 的快捷方式角标）
    private func iconFromBundle(at path: String) -> NSImage? {
        guard let bundle = Bundle(path: path),
              let iconName = (bundle.infoDictionary?["CFBundleIconFile"] as? String)
                ?? (bundle.infoDictionary?["CFBundleIconName"] as? String)
        else { return nil }

        // 先尝试 .icns，再尝试通用 resource
        let iconPath = bundle.path(forResource: iconName, ofType: "icns")
            ?? bundle.path(forResource: iconName, ofType: nil)
        guard let iconPath else { return nil }

        return NSImage(contentsOfFile: iconPath)
    }

    /// 通过 NSWorkspace 获取图标（fallback）
    private func iconFromWorkspace(at path: String) -> NSImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
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

}

// MARK: - NSString convenience
extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive]) != nil
    }
}