import Cocoa
import OSLog

// MARK: - 图片缓存管理器
final class ImageCacheManager {
    nonisolated(unsafe) static let shared = ImageCacheManager()

    private let log = Logger(subsystem: "com.nekutai.pastry", category: "image-cache")

    /// 缓存磁盘用量上限（超过触发淘汰）
    private static let maxCacheSize: Int64 = 200 * 1024 * 1024  // 200 MB
    /// 淘汰后目标磁盘用量
    private static let targetCacheSize: Int64 = 150 * 1024 * 1024  // 150 MB

    private let cacheDir: URL

    private init() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else {
            log.error("无法获取 Application Support 目录")
            fatalError("Application Support directory is unavailable")
        }
        cacheDir = appSupport
            .appendingPathComponent(Constants.appName)
            .appendingPathComponent("ImageCache")
        do {
            try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        } catch {
            log.error("无法创建图片缓存目录: \(self.cacheDir.path, privacy: .public), error: \(error.localizedDescription)")
        }
    }

    func save(image: NSImage, data: Data) -> String? {
        let filename = "\(UUID().uuidString).png"
        let fileURL = cacheDir.appendingPathComponent(filename)
        let thumb = thumbnail(from: image, maxSize: NSSize(width: 256, height: 256))
        guard let thumbData = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: thumbData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        do {
            try pngData.write(to: fileURL)
            evictIfNeeded()
            return fileURL.path
        } catch {
            return nil
        }
    }

    /// LRU 磁盘淘汰：超过 maxCacheSize 时按修改时间删除最旧文件，直到低于 targetCacheSize
    private func evictIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var totalSize: Int64 = 0
        var fileInfos: [(url: URL, size: Int64, modDate: Date)] = []

        for file in files {
            guard let attrs = try? file.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            ),
                  let size = attrs.fileSize.map(Int64.init)
            else { continue }
            totalSize += size
            fileInfos.append((file, size, attrs.contentModificationDate ?? Date.distantPast))
        }

        guard totalSize > Self.maxCacheSize else { return }

        // 按修改时间升序（最旧 → 最新）
        fileInfos.sort { $0.modDate < $1.modDate }

        for info in fileInfos {
            guard totalSize > Self.targetCacheSize else { break }
            do {
                try fm.removeItem(at: info.url)
                totalSize -= info.size
            } catch {
                // 无法删除的文件跳过，继续处理下一个
            }
        }
    }

    private func thumbnail(from image: NSImage, maxSize: NSSize) -> NSImage {
        let ratio = min(maxSize.width / max(image.size.width, 1),
                        maxSize.height / max(image.size.height, 1))
        let newSize = NSSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        return thumb
    }
}
