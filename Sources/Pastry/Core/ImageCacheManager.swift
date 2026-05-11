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

    /// 保存图片：原始数据保留原格式（.orig），另存缩略图（.png）用于卡片预览。
    /// 返回缩略图路径（向后兼容 ClipboardItem.content）。
    func save(image: NSImage, data: Data) -> String? {
        let uuid = UUID().uuidString
        let thumbFilename = "\(uuid).png"
        let origFilename = "\(uuid).orig"
        let thumbURL = cacheDir.appendingPathComponent(thumbFilename)
        let origURL = cacheDir.appendingPathComponent(origFilename)

        // 1. 保存原始数据（保持剪贴板原有格式，TIFF/PNG）
        do {
            try data.write(to: origURL)
        } catch {
            log.error("原始图片写入失败: \(error.localizedDescription)")
            return nil
        }

        // 2. 生成并保存缩略图（用于卡片预览）
        let thumb = thumbnail(from: image, maxSize: NSSize(width: 256, height: 256))
        guard let thumbData = thumb.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: thumbData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            try? FileManager.default.removeItem(at: origURL)
            return nil
        }
        do {
            try pngData.write(to: thumbURL)
        } catch {
            try? FileManager.default.removeItem(at: origURL)
            return nil
        }

        evictIfNeeded()
        return thumbURL.path
    }

    /// 从缩略图路径推导原始图片路径（用于粘贴时读取高清数据）
    func originalPath(forThumbnail thumbnailPath: String) -> String? {
        let stem = URL(fileURLWithPath: thumbnailPath).deletingPathExtension().lastPathComponent
        let origURL = cacheDir.appendingPathComponent("\(stem).orig")
        return FileManager.default.fileExists(atPath: origURL.path) ? origURL.path : nil
    }

    /// 配对文件路径：.png ↔ .orig
    func counterpartURL(for url: URL) -> URL? {
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        switch ext {
        case "png": return cacheDir.appendingPathComponent("\(stem).orig")
        case "orig": return cacheDir.appendingPathComponent("\(stem).png")
        default: return nil
        }
    }

    /// LRU 磁盘淘汰：超过 maxCacheSize 时按修改时间删除最旧文件，直到低于 targetCacheSize。
    /// 跳过数据库中仍被引用的文件。
    private func evictIfNeeded() {
        let activePaths = DatabaseManager.shared.allImageContentPaths()
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
            // 跳过数据库中仍被引用的文件（防止卡片显示破损图标）
            let thumbPath: String? = info.url.pathExtension == "png"
                ? info.url.path
                : counterpartURL(for: info.url)?.path
            if let tp = thumbPath, activePaths.contains(tp) { continue }
            do {
                try fm.removeItem(at: info.url)
                totalSize -= info.size
                // 同时清理配对文件（.png ↔ .orig）
                if let c = counterpartURL(for: info.url),
                   let cSize = (try? fm.attributesOfItem(atPath: c.path)[.size] as? Int64) {
                    try? fm.removeItem(at: c)
                    totalSize -= cSize
                }
            } catch {
                // 无法删除的文件跳过，继续处理下一个
            }
        }
    }

    /// 清理孤儿缓存文件：删除数据库中已不存在图片条目的 .png + .orig 文件对
    func cleanupOrphans(activePaths: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }

        var removed = 0
        for file in files where file.pathExtension == "png" {
            guard !activePaths.contains(file.path) else { continue }
            try? FileManager.default.removeItem(at: file)
            if let c = counterpartURL(for: file) {
                try? FileManager.default.removeItem(at: c)
            }
            removed += 1
        }
        if removed > 0 {
            log.info("清理了 \(removed) 个孤儿图片缓存")
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
