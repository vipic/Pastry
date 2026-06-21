import Cocoa
import SwiftUI

struct FilePreviewContent: View {
    let urls: [URL]
    let missingURLs: Set<URL>
    let thumbnailImage: NSImage?
    let fileIcons: [URL: NSImage]
    let fileSizes: [URL: Int64]
    let styleForURL: (URL) -> ClipboardCardView.FilePreviewStyle

    var body: some View {
        if urls.count == 1, let url = urls.first {
            singleFilePreview(url, style: styleForURL(url))
        } else {
            fileURLList
        }
    }

    /// 单文件卡片：统一布局，预览内容按策略切换。缺失文件在图标区显示提示，文件名加删除线
    private func singleFilePreview(_ url: URL, style: ClipboardCardView.FilePreviewStyle) -> some View {
        let isMissing = missingURLs.contains(url)
        return VStack(spacing: style == .thumbnail ? 6 : 4) {
            if isMissing {
                missingIconPlaceholder
            } else {
                filePreviewContent(url: url, style: style)
            }
            Text(formattedFileLabel(url: url))
                .font(.system(size: 9))
                .foregroundColor(isMissing ? .secondary.opacity(0.4) : .secondary)
                .strikethrough(isMissing)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func filePreviewContent(url: URL, style: ClipboardCardView.FilePreviewStyle) -> some View {
        switch style {
        case .thumbnail:
            if let img = thumbnailImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                fallbackPreview
            }
        case .systemIcon:
            if let icon = fileIcons[url] {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 缺失文件的图标占位区（等高等宽替换原有图标/缩略图，居中布局）
    private var missingIconPlaceholder: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "questionmark.folder")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.3))
            Text(L10n["card.file_not_found"])
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.45))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 文件预览列表（多文件）

    private var fileURLList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(urls.prefix(4), id: \.self) { url in
                let isMissing = missingURLs.contains(url)
                HStack(spacing: 4) {
                    if isMissing {
                        Image(systemName: "questionmark.folder")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.4))
                    } else if let icon = fileIcons[url] {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 12, height: 12)
                    }
                    Text(formattedFileLabel(url: url))
                        .lineLimit(1)
                        .font(.system(size: 10))
                        .foregroundColor(isMissing ? .secondary.opacity(0.4) : .primary)
                        .strikethrough(isMissing)
                }
            }
            if urls.count > 4 {
                Text(String(format: L10n["card.extra_files"], urls.count - 4))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 文件大小格式化

    private func formattedFileLabel(url: URL) -> String {
        let name = url.lastPathComponent
        guard let size = fileSizes[url] else { return name }
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "\(name)  — \(sizeStr)"
    }

    private var fallbackPreview: some View {
        VStack {
            Spacer()
            Image(systemName: "photo.badge.exclamationmark")
                .font(.title2)
                .foregroundColor(.secondary.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
