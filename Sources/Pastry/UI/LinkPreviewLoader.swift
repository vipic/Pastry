import SwiftUI
import Cocoa
import UniformTypeIdentifiers
import Quartz

// MARK: - 链接预览加载器
final class LinkPreviewLoader {
    nonisolated(unsafe) static let shared = LinkPreviewLoader()

    struct Preview {
        let title: String
        let description: String?
        let imageURL: String?
        let host: String
    }

    /// Wrapper to store Preview struct in NSCache (requires class type)
    final class PreviewWrapper {
        let preview: Preview
        init(_ preview: Preview) { self.preview = preview }
    }

    private let cache: NSCache<NSString, PreviewWrapper> = {
        let c = NSCache<NSString, PreviewWrapper>()
        c.countLimit = 200
        return c
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    private init() {}

    /// 同步查询缓存（不发起网络请求）
    func cachedPreview(for key: String) -> Preview? {
        cache.object(forKey: key as NSString)?.preview
    }

    func load(url: URL, completion: @escaping (Preview?) -> Void) {
        guard NetworkAccessPolicy.isLinkPreviewEnabled,
              NetworkAccessPolicy.isAllowedRemoteResourceURL(url)
        else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let key = url.absoluteString
        if let cached = cache.object(forKey: key as NSString) {
            completion(cached.preview)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let self,
                  NetworkAccessPolicy.responseWithinLimit(response, maxBytes: NetworkAccessPolicy.maxHTMLBytes),
                  let data = data,
                  data.count <= NetworkAccessPolicy.maxHTMLBytes,
                  let html = String(data: data, encoding: .utf8)
            else { DispatchQueue.main.async { completion(nil) }; return }
            let title = self.extractMeta(from: html, tag: "og:title")
                ?? self.extractTitleTag(from: html)
                ?? self.extractMeta(from: html, tag: "og:site_name")
            let description = self.extractMeta(from: html, tag: "og:description")
            let imageURL = self.extractMeta(from: html, tag: "og:image").flatMap { src in
                self.resolveImageURL(src: src, baseURL: url)
            } ?? self.extractMeta(from: html, tag: "twitter:image").flatMap { src in
                self.resolveImageURL(src: src, baseURL: url)
            } ?? self.extractBestImage(from: html, baseURL: url)
            let preview = Preview(
                title: title ?? "",
                description: description,
                imageURL: imageURL,
                host: url.host ?? ""
            )
            self.cache.setObject(PreviewWrapper(preview), forKey: key as NSString)
            DispatchQueue.main.async { completion(preview) }
        }.resume()
    }

    // MARK: - HTML 元数据提取

    private func extractMeta(from html: String, tag: String) -> String? {
        // 匹配 og 属性的多种写法
        let patterns = [
            "\(tag)\" content=\"",
            "\(tag)' content='",
            "property=\"\(tag)\" content=\"",
            "property='\(tag)' content='",
            "name=\"\(tag)\" content=\"",
            "name='\(tag)' content='",
        ]
        for pattern in patterns {
            guard let s = html.range(of: pattern, options: .caseInsensitive) else { continue }
            let quote = html[html.index(before: s.upperBound)] == "\"" ? "\"" : "'"
            let searchStart = s.upperBound
            guard let e = html.range(of: quote, range: searchStart..<html.endIndex) else { continue }
            let value = String(html[searchStart..<e.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return value }
        }
        return nil
    }

    private func extractTitleTag(from html: String) -> String? {
        guard let s = html.range(of: "<title>", options: .caseInsensitive),
              let e = html.range(of: "</title>", options: .caseInsensitive),
              s.upperBound <= e.lowerBound
        else { return nil }
        let t = html[s.upperBound..<e.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 相对路径图片 URL 用页面 URL 解析
    private func resolveImageURL(src: String, baseURL: URL) -> String? {
        if let resolved = URL(string: src, relativeTo: baseURL) {
            return resolved.absoluteString
        }
        return URL(string: src)?.absoluteString
    }

    /// og:image 缺失时的降级方案：语义排序选择最佳内容图片
    private func extractBestImage(from html: String, baseURL: URL) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<img[^>]+>",
            options: .caseInsensitive
        ) else { return nil }

        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        struct Candidate {
            let src: String
            let score: Int
        }
        var candidates: [Candidate] = []

        for match in matches.prefix(30) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])

            // 提取 src，懒加载降级到 data-src
            var src = extractSrc(from: tag)
            if src?.hasPrefix("data:") ?? true {
                if let lazy = extractAttr(from: tag, attr: "data-src"), !lazy.isEmpty {
                    src = lazy
                }
            }
            guard let src, !src.hasPrefix("data:") else { continue }

            let lower = src.lowercased()
            let lowerTag = tag.lowercased()

            // 黑名单过滤：logo / icon / favicon / gravatar / 追踪像素 / footer/header 装饰图
            if isNoiseImage(src: lower, tag: lowerTag) { continue }

            // 尺寸过滤：跳过明确的小图标
            if isSmallIcon(tag: tag) { continue }

            // 打分
            var score = 0

            // 语义关键词加分
            let semanticBoost = [
                "featured": 20, "hero": 20, "cover": 15, "wp-image": 15,
                "thumbnail": 12, "thumb": 10,
                "og-image": 18, "post-image": 15, "entry-image": 15,
                "article-image": 15, "content-image": 12,
            ]
            for (keyword, points) in semanticBoost {
                if lowerTag.contains(keyword) || lower.contains(keyword) {
                    score += points
                }
            }

            // 尺寸加分
            score += sizeScore(from: tag)

            // alt 文本非空加分（说明是内容图）
            if let alt = extractAttr(from: tag, attr: "alt"), !alt.trimmingCharacters(in: .whitespaces).isEmpty {
                let lt = alt.lowercased()
                if !lt.contains("logo") && !lt.contains("icon") && !lt.contains("home") {
                    score += 5
                }
            }

            candidates.append(Candidate(src: src, score: score))
        }

        // 按分数降序，取最佳
        candidates.sort { $0.score > $1.score }

        if let best = candidates.first {
            return resolveImageURL(src: best.src, baseURL: baseURL)
        }

        // 全部被过滤：降级取第一个非 dataURI 的 img
        for match in matches.prefix(10) {
            guard let tagRange = Range(match.range, in: html) else { continue }
            let tag = String(html[tagRange])
            guard let src = extractSrc(from: tag), !src.hasPrefix("data:") else { continue }
            return resolveImageURL(src: src, baseURL: baseURL)
        }

        return nil
    }

    // MARK: - 图片语义分析辅助

    /// 从 <img> 标签提取 src 属性值
    private func extractSrc(from tag: String) -> String? {
        for quote in ["\"", "'"] {
            if let s = tag.range(of: "src=\(quote)", options: .caseInsensitive) {
                let start = s.upperBound
                guard let e = tag.range(of: quote, range: start..<tag.endIndex) else { continue }
                let val = String(tag[start..<e.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !val.isEmpty { return val }
            }
        }
        return nil
    }

    /// 从标签提取指定属性值
    private func extractAttr(from tag: String, attr: String) -> String? {
        for quote in ["\"", "'"] {
            if let s = tag.range(of: "\(attr)=\(quote)", options: .caseInsensitive) {
                let start = s.upperBound
                guard let e = tag.range(of: quote, range: start..<tag.endIndex) else { continue }
                return String(tag[start..<e.lowerBound])
            }
        }
        return nil
    }

    /// 是否为噪音图片（logo / icon / 追踪像素等）
    private func isNoiseImage(src: String, tag: String) -> Bool {
        let noisePatterns = [
            "logo", "icon", "avatar", "favicon", "gravatar",
            "1x1", "pixel", "tracking", "beacon", "analytics",
            "button", "header-logo", "site-logo", "footer-logo",
            "menu-icon", "nav-icon", "social-icon",
        ]
        for pattern in noisePatterns {
            if src.contains(pattern) || tag.contains(pattern) { return true }
        }
        return false
    }

    /// 是否为明确的小图标（width/height 属性 < 100px）
    private func isSmallIcon(tag: String) -> Bool {
        if let w = extractAttr(from: tag, attr: "width"),
           let width = Int(w), width > 0, width < 100 { return true }
        if let h = extractAttr(from: tag, attr: "height"),
           let height = Int(h), height > 0, height < 100 { return true }
        return false
    }

    /// 根据标签尺寸估算得分
    private func sizeScore(from tag: String) -> Int {
        var w = 0, h = 0
        if let ws = extractAttr(from: tag, attr: "width"), let v = Int(ws) { w = v }
        if let hs = extractAttr(from: tag, attr: "height"), let v = Int(hs) { h = v }
        if w > 0 && h > 0 {
            let area = w * h
            if area >= 500_000 { return 15 }      // ≥ 1000×500
            if area >= 200_000 { return 10 }      // ≥ 500×400
            if area >= 80_000  { return 5 }       // ≥ 400×200
        }
        // 从 URL 参数推测（如 ?w=1200 或 /1200x800）
        if let wRegex = try? NSRegularExpression(pattern: "[?&/]w=(\\d{3,4})", options: .caseInsensitive) {
            let nsTag = tag as NSString
            let range = NSRange(location: 0, length: nsTag.length)
            if let m = wRegex.firstMatch(in: tag, range: range),
               let r = Range(m.range(at: 1), in: tag),
               let v = Int(tag[r]), v >= 800 { return 12 }
        }
        return 0
    }

    // MARK: — 向后兼容

    private func extractTitle(from html: String) -> String? {
        extractTitleTag(from: html) ?? extractMeta(from: html, tag: "og:title")
    }

    // MARK: — 测试入口

    static func extractMetaForTesting(from html: String, tag: String) -> String? {
        shared.extractMeta(from: html, tag: tag)
    }

    static func extractBestImageForTesting(from html: String, baseURL: URL?) -> String? {
        shared.extractBestImage(from: html, baseURL: baseURL ?? URL(string: "https://example.com")!)
    }

    static func resolveImageURLForTesting(src: String, baseURL: URL?) -> String? {
        shared.resolveImageURL(src: src, baseURL: baseURL ?? URL(string: "https://example.com")!)
    }

    static func extractTitleTagForTesting(from html: String) -> String? {
        shared.extractTitleTag(from: html)
    }
}
