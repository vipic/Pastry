import Cocoa

// MARK: - 剪贴板内容类型
enum ClipType: Codable, CaseIterable {
    case text
    case rtf
    case image
    case fileURL
    case html

    var iconName: String {
        switch self {
        case .text:    return "text.alignleft"
        case .rtf:     return "doc.richtext"
        case .image:   return "photo"
        case .fileURL: return "folder"
        case .html:    return "chevron.left.forwardslash.chevron.right"
        }
    }

    var label: String {
        switch self {
        case .text:    return "文本"
        case .rtf:     return "富文本"
        case .image:   return "图片"
        case .fileURL: return "文件"
        case .html:    return "HTML"
        }
    }

    /// 数据库存储键（用于 Codable 和 SQLite）
    var storageKey: String {
        switch self {
        case .text:    return "text"
        case .rtf:     return "rtf"
        case .image:   return "image"
        case .fileURL: return "fileURL"
        case .html:    return "html"
        }
    }

    init(storageKey: String) {
        switch storageKey {
        case "rtf":     self = .rtf
        case "image":   self = .image
        case "fileURL": self = .fileURL
        case "html":    self = .html
        default:        self = .text
        }
    }

    // Codable
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let key = try container.decode(String.self)
        self = ClipType(storageKey: key)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageKey)
    }
}

// MARK: - HTML 内容段（保留原始 DOM 图文顺序）
enum ContentSegment: Codable, Equatable {
    case text(String)
    case image(url: String)

    var textValue: String? { if case .text(let s) = self { return s }; return nil }
    var imageURL: String? { if case .image(let u) = self { return u }; return nil }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(t)
        } else if let u = try container.decodeIfPresent(String.self, forKey: .image) {
            self = .image(url: u)
        } else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "invalid segment"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):  try container.encode(s, forKey: .text)
        case .image(let u): try container.encode(u, forKey: .image)
        }
    }

    private enum CodingKeys: String, CodingKey { case text, image }
}

// MARK: - 核心数据模型
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let content: String         // 文本内容 / 图片缓存路径 / 文件URL拼接
    let contentType: ClipType
    let appName: String?        // 来源应用名
    let isHandoff: Bool          // 是否来自 Handoff（iPhone/iPad 通用剪贴板）
    let textAnnotation: String?       // 图片附带的文字（同时复制图文时保留）
    let segments: [ContentSegment]?  // HTML 图文混排的有序段（仅 .html 类型）
    var displayCount: Int             // 被粘贴回的次数（可变，不计入 hash）
    var isPinned: Bool                // 钉选（pin），批量删除时保留（可变，不计入 hash）

    /// 从 segments 中提取的远程图片 URL 列表（方便卡片视图和去重使用）
    var imageURLs: [String]? {
        segments?.compactMap { $0.imageURL }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        lhs.id == rhs.id
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String,
        contentType: ClipType,
        appName: String? = nil,
        isHandoff: Bool = false,
        textAnnotation: String? = nil,
        segments: [ContentSegment]? = nil,
        displayCount: Int = 0,
        isPinned: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.contentType = contentType
        self.appName = appName
        self.isHandoff = isHandoff
        self.textAnnotation = textAnnotation
        self.segments = segments
        self.displayCount = displayCount
        self.isPinned = isPinned
    }

    /// 去重用的内容摘要（足够长以避免长文本误判）
    var dedupKey: String {
        let segSig = segments.map { segs in
            segs.map { $0.imageURL != nil ? "img" : "txt" }.joined(separator: ",")
        } ?? "nil"
        return "\(contentType.storageKey):\(content):\(textAnnotation ?? ""):\(imageURLs?.joined(separator: ",") ?? ""):\(segSig)"
    }
}

// MARK: - 历史状态统计
struct ClipboardStats: Codable {
    let totalItems: Int
    let todayItems: Int
    let favoriteCount: Int
    let storageSizeKB: Int
}
