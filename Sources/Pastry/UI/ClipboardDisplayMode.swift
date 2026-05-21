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
}
