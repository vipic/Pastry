import Foundation

// MARK: - 展示类型（从 SourceFormat + ContentTags 派生）

enum DisplayMode: Equatable {
    case plainText
    case richText
    case mixedMedia
    case link(URL)
    case multiLink([URL])
    case image
    case singleFile
    case multiFile
    case missing

    /// 从条目 + 可选「文件缺失」运行时状态派生展示模式（纯逻辑，可单测）。
    /// - Parameters:
    ///   - item: 剪贴板条目
    ///   - hasMissingFiles: 异步探测到的磁盘缺失（主要用于图片缓存路径）
    static func resolve(item: ClipboardItem, hasMissingFiles: Bool = false) -> DisplayMode {
        let links = detectedLinks(from: item)
        let isMultiURL = item.tags.isURL && links.count > 1

        switch item.sourceFormat {
        case .image:
            return (hasMissingFiles || item.tags.isMissing) ? .missing : .image
        case .fileURL:
            if item.tags.isMultiFile { return .multiFile }
            return item.tags.isMissing ? .missing : .singleFile
        case .html:
            if item.tags.hasSegments { return .mixedMedia }
            if isMultiURL { return .multiLink(links) }
            if item.tags.isURL, let url = links.first { return .link(url) }
            return .richText
        case .rtf:
            if isMultiURL { return .multiLink(links) }
            if item.tags.isURL, let url = links.first { return .link(url) }
            return .richText
        case .text:
            if isMultiURL { return .multiLink(links) }
            if item.tags.isURL, let url = links.first { return .link(url) }
            return .plainText
        }
    }

    /// 内容中的全部 http/https URL（按行拆分；http 升为 https）。
    static func detectedLinks(from item: ClipboardItem) -> [URL] {
        guard item.tags.isURL else { return [] }
        let lines = item.content.components(separatedBy: "\n")
        return lines.compactMap { line -> URL? in
            guard let url = URL(string: line.trimmingCharacters(in: .whitespaces)),
                  let scheme = url.scheme,
                  scheme == "http" || scheme == "https" else { return nil }
            return upgradeToHTTPS(url)
        }
    }

    /// NSDataDetector / 裸域名场景：把 http 升为 https。
    static func upgradeToHTTPS(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http" else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        return components?.url ?? url
    }
}
