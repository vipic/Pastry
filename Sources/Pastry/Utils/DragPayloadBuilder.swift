import AppKit
import Foundation
import UniformTypeIdentifiers

enum DragPayloadBuilder {
    static func provider(
        for item: ClipboardItem,
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> NSItemProvider {
        if let provider = urlProvider(for: item, loadFullContent: loadFullContent) {
            return provider
        }

        switch item.sourceFormat {
        case .image:
            let imagePath = ImageCacheManager.shared.originalPath(forThumbnail: item.content) ?? item.content
            let imageURL = URL(fileURLWithPath: imagePath)
            if FileManager.default.fileExists(atPath: imagePath),
               let provider = NSItemProvider(contentsOf: imageURL) {
                provider.suggestedName = imageURL.lastPathComponent
                return provider
            }
            return NSItemProvider(object: item.content as NSString)
        case .fileURL:
            let firstPath = item.content.split(separator: "\n").first.map(String.init) ?? item.content
            let fileURL = URL(fileURLWithPath: firstPath)
            if FileManager.default.fileExists(atPath: firstPath),
               let provider = NSItemProvider(contentsOf: fileURL) {
                provider.suggestedName = fileURL.lastPathComponent
                return provider
            }
            return NSItemProvider(object: item.content as NSString)
        default:
            let content = loadFullContent(item) ?? item.content
            return NSItemProvider(object: content as NSString)
        }
    }

    static func providerForSelection(
        _ items: [ClipboardItem],
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> NSItemProvider {
        let urls = items.flatMap { webURLs(in: $0, loadFullContent: loadFullContent) }
        if !urls.isEmpty {
            return urlProvider(for: urls)
        }

        let text = multiSelectText(items, loadFullContent: loadFullContent)
        guard !text.isEmpty else { return NSItemProvider(object: "" as NSString) }
        return NSItemProvider(object: text as NSString)
    }

    static func multiSelectText(
        _ items: [ClipboardItem],
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> String {
        items.compactMap { item -> String? in
            switch item.sourceFormat {
            case .text, .rtf, .html:
                return loadFullContent(item) ?? item.content
            case .fileURL:
                return item.content
            default:
                return nil
            }
        }.joined(separator: "\n")
    }

    static func webURLs(
        in item: ClipboardItem,
        loadFullContent: (ClipboardItem) -> String? = { _ in nil }
    ) -> [URL] {
        guard item.tags.isURL else { return [] }
        let content = loadFullContent(item) ?? item.content
        let lineURLs = content
            .split(whereSeparator: \.isNewline)
            .compactMap { webURL(from: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
        if !lineURLs.isEmpty { return lineURLs }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return detector.matches(in: content, options: [], range: range).compactMap { match in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else { return nil }
            return upgradeToHTTPS(url)
        }
    }

    private static func urlProvider(
        for item: ClipboardItem,
        loadFullContent: (ClipboardItem) -> String?
    ) -> NSItemProvider? {
        let urls = webURLs(in: item, loadFullContent: loadFullContent)
        guard !urls.isEmpty else { return nil }
        return urlProvider(for: urls)
    }

    private static func urlProvider(for urls: [URL]) -> NSItemProvider {
        let text = urls.map(\.absoluteString).joined(separator: "\n")
        let provider = urls.count == 1
            ? NSItemProvider(object: urls[0] as NSURL)
            : NSItemProvider(object: text as NSString)
        registerPlainText(text, on: provider)
        registerPrimaryURL(urls[0], on: provider)
        return provider
    }

    private static func registerPlainText(_ text: String, on provider: NSItemProvider) {
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(text.data(using: .utf8), nil)
            return nil
        }
    }

    private static func registerPrimaryURL(_ url: URL, on provider: NSItemProvider) {
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.url.identifier,
            visibility: .all
        ) { completion in
            completion(url.absoluteString.data(using: .utf8), nil)
            return nil
        }
    }

    private static func webURL(from text: String) -> URL? {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return upgradeToHTTPS(url)
    }

    private static func upgradeToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }
}
