import Cocoa
import OSLog

enum PasteboardWriteResult: Equatable {
    case written
    case noWritableContent
}

struct PasteboardWriter {
    struct Options {
        var filterMissingFileURLs: Bool
        var includeImageAnnotation: Bool
        var preferOriginalImage: Bool

        static let storeSingle = Options(
            filterMissingFileURLs: false,
            includeImageAnnotation: false,
            preferOriginalImage: false
        )

        static let overlaySingle = Options(
            filterMissingFileURLs: true,
            includeImageAnnotation: true,
            preferOriginalImage: true
        )
    }

    private static let log = Logger(subsystem: "com.nekutai.pastry", category: "pasteboard-writer")

    static func write(
        _ item: ClipboardItem,
        to pasteboard: NSPasteboard = .general,
        options: Options,
        loadFullContent: (ClipboardItem) -> String? = { item in
            DatabaseManager.shared.loadFullContent(id: item.id) ?? item.content
        },
        originalImagePath: (String) -> String? = { thumbnailPath in
            ImageCacheManager.shared.originalPath(forThumbnail: thumbnailPath)
        }
    ) async -> PasteboardWriteResult {
        pasteboard.clearContents()

        switch item.sourceFormat {
        case .text:
            pasteboard.setString(loadFullContent(item) ?? item.content, forType: .string)
            return .written

        case .rtf, .html:
            pasteboard.setString(loadFullContent(item) ?? item.content, forType: .string)
            if let raw = item.rawFormatData, let typeStr = item.rawFormatType {
                pasteboard.setData(raw, forType: NSPasteboard.PasteboardType(typeStr))
            }
            return .written

        case .fileURL:
            let urls = item.content
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            let writableURLs = options.filterMissingFileURLs
                ? urls.filter { FileManager.default.fileExists(atPath: $0.path) }
                : urls
            guard !writableURLs.isEmpty else { return .noWritableContent }
            pasteboard.writeObjects(writableURLs as [NSURL])
            return .written

        case .image:
            let imagePath = options.preferOriginalImage
                ? (originalImagePath(item.content) ?? item.content)
                : item.content
            guard let image = await Task.detached(priority: .userInitiated, operation: { () -> NSImage? in
                NSImage(contentsOfFile: imagePath)
            }).value else {
                return .noWritableContent
            }

            if options.includeImageAnnotation,
               let annotation = item.textAnnotation,
               !annotation.isEmpty {
                writeAnnotatedImage(image, annotation: annotation, to: pasteboard)
            } else {
                pasteboard.writeObjects([image])
            }
            return .written
        }
    }

    static func writePlainText(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func writeAnnotatedImage(_ image: NSImage, annotation: String, to pasteboard: NSPasteboard) {
        let attr = NSMutableAttributedString()
        let attachment = NSTextAttachment()
        attachment.image = image
        attr.append(NSAttributedString(attachment: attachment))
        attr.append(NSAttributedString(string: "\n\(annotation)"))

        do {
            let rtfd = try attr.data(
                from: NSRange(location: 0, length: attr.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]
            )
            pasteboard.setData(rtfd, forType: .rtfd)
        } catch {
            log.error("RTFD 写入失败: \(error.localizedDescription)")
        }

        pasteboard.setData(image.tiffRepresentation, forType: .tiff)
        pasteboard.setString(annotation, forType: .string)
    }
}
