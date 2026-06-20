import Foundation

enum NetworkAccessPolicy {
    static let maxHTMLBytes = 2_000_000
    static let maxImageBytes = 5_000_000

    static var isLinkPreviewEnabled: Bool {
        UserDefaults.standard.bool(forKey: UserDefaultsKeys.linkPreviewNetworkEnabled)
    }

    static func isAllowedRemoteResourceURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host(percentEncoded: false)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else { return false }

        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized == "localhost" || normalized.hasSuffix(".localhost") { return false }
        if normalized.hasSuffix(".local") { return false }
        if isBlockedIPv4(normalized) || isBlockedIPv6(normalized) { return false }
        return true
    }

    static func responseWithinLimit(_ response: URLResponse?, maxBytes: Int) -> Bool {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let finalURL = http.url,
              isAllowedRemoteResourceURL(finalURL)
        else { return false }

        let expected = http.expectedContentLength
        return expected < 0 || expected <= Int64(maxBytes)
    }

    static func shouldFollowRedirect(to url: URL) -> Bool {
        isAllowedRemoteResourceURL(url)
    }

    private static func isBlockedIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".")
        guard parts.count == 4,
              let a = UInt8(parts[0]),
              let b = UInt8(parts[1])
        else { return false }

        switch a {
        case 0, 10, 127:
            return true
        case 100:
            return (64...127).contains(b)
        case 169:
            return b == 254
        case 172:
            return (16...31).contains(b)
        case 192:
            return b == 168 || b == 0
        case 198:
            return b == 18 || b == 19
        default:
            return a >= 224
        }
    }

    private static func isBlockedIPv6(_ host: String) -> Bool {
        guard host.contains(":") else { return false }
        if host == "::1" || host == "::" { return true }
        if host.hasPrefix("fe80:") { return true }
        if host.hasPrefix("fc") || host.hasPrefix("fd") { return true }
        return false
    }
}
