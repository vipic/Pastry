import Cocoa

// MARK: - 剪贴板内容类型
enum ClipType: String, Codable, CaseIterable {
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
}

// MARK: - 核心数据模型
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let timestamp: Date
    let content: String         // 文本内容 / 图片缓存路径 / 文件URL拼接
    let contentType: ClipType
    let appName: String?        // 来源应用名
    var isFavorite: Bool
    var displayCount: Int       // 被粘贴回的次数

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        content: String,
        contentType: ClipType,
        appName: String? = nil,
        isFavorite: Bool = false,
        displayCount: Int = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
        self.contentType = contentType
        self.appName = appName
        self.isFavorite = isFavorite
        self.displayCount = displayCount
    }

    /// 去重用的内容摘要（忽略时间戳）
    var dedupKey: String {
        "\(contentType.rawValue):\(content.prefix(200))"
    }
}

// MARK: - 历史状态统计
struct ClipboardStats {
    let totalItems: Int
    let todayItems: Int
    let favoriteCount: Int
    let storageSizeKB: Int
}
