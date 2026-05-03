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

// MARK: - 核心数据模型
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let content: String         // 文本内容 / 图片缓存路径 / 文件URL拼接
    let contentType: ClipType
    let appName: String?        // 来源应用名
    let textAnnotation: String? // 图片附带的文字（同时复制图文时保留）
    var displayCount: Int       // 被粘贴回的次数（可变，不计入 hash）
    var isPinned: Bool          // 钉选（pin），批量删除时保留（可变，不计入 hash）

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
        textAnnotation: String? = nil,
        displayCount: Int = 0,
        isPinned: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.contentType = contentType
        self.appName = appName
        self.textAnnotation = textAnnotation
        self.displayCount = displayCount
        self.isPinned = isPinned
    }

    /// 去重用的内容摘要（足够长以避免长文本误判）
    var dedupKey: String {
        "\(contentType.storageKey):\(content):\(textAnnotation ?? "")"
    }
}

// MARK: - 历史状态统计
struct ClipboardStats: Codable {
    let totalItems: Int
    let todayItems: Int
    let favoriteCount: Int
    let storageSizeKB: Int
}
