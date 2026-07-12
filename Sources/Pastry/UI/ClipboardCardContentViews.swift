import SwiftUI
import Cocoa

// MARK: - Clipboard card content components

struct ClipboardLinkContentView: View {
    let preview: LinkPreviewLoader.Preview?
    let text: ClipboardCardView.LinkCardText
    /// 有备注时媒体图宽高等比缩小，标题/域名保持原尺寸。
    var compactMedia: Bool = false
    @AppStorage(UserDefaultsKeys.linkPreviewNetworkEnabled)
    private var linkPreviewNetworkEnabled = false

    private var mediaScale: CGFloat {
        compactMedia
            ? UIConstants.Card.linkThumbnailHeightCompact / UIConstants.Card.linkThumbnailHeight
            : 1
    }

    private var thumbnailHeight: CGFloat {
        UIConstants.Card.linkThumbnailHeight * mediaScale
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = geo.size.width * mediaScale
                let height = UIConstants.Card.linkThumbnailHeight * mediaScale
                thumbnail(imageURL: preview?.imageURL)
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.sm * mediaScale, style: .continuous))
                    .frame(width: geo.size.width, height: height, alignment: .center)
            }
            .frame(height: thumbnailHeight)
            .padding(.bottom, compactMedia ? 4 : 6)
            // 与文件卡备注出现时同款缓动（宽高一起插值）
            .animation(.easeInOut(duration: UIConstants.Motion.note), value: compactMedia)

            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(text.titleLineLimit)
                    .truncationMode(.tail)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let desc = text.description {
                    Text(desc)
                        .font(.system(size: UIConstants.TypeSize.caption2))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(text.host)
                    .font(.system(size: UIConstants.TypeSize.micro))
                    .foregroundColor(.secondary.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 有备注时不要把剩余高度撑在域名下方，否则域名与备注之间会出现大块空白
            .fixedSize(horizontal: false, vertical: true)

            if !compactMedia {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func thumbnail(imageURL: String?) -> some View {
        if let imageURL {
            RemoteThumbnail(urlString: imageURL)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.secondary.opacity(0.3), Color.secondary.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if linkPreviewNetworkEnabled {
                    Image(systemName: "link")
                        .font(.system(size: UIConstants.TypeSize.subhead, weight: .light))
                        .foregroundColor(.secondary.opacity(0.35))
                } else {
                    Button(action: openLinkPreviewNetworkSettings) {
                        Text(L10n["card.link_preview_enable_hint"])
                            .font(.system(size: UIConstants.TypeSize.caption2, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L10n["card.link_preview_enable_hint"])
                    .onHover { hovering in
                        if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                }
            }
        }
    }

    private func openLinkPreviewNetworkSettings() {
        OverlayPanelManager.shared.hide()
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow(selectedTab: .security)
        }
    }
}

struct ClipboardImageContentView: View {
    let image: NSImage?
    let annotation: String?

    var body: some View {
        VStack(spacing: 0) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .cornerRadius(UIConstants.Radius.sm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ClipboardImageFallbackView()
            }

            if let annotation, !annotation.isEmpty {
                Text(annotation)
                    .font(.system(size: UIConstants.TypeSize.caption))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
            }
        }
    }
}

struct ClipboardImageFallbackView: View {
    var body: some View {
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

struct ClipboardMultiLinkContentView: View {
    let urls: [URL]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(format: L10n["card.multi_links"], urls.count))
                .font(.system(size: UIConstants.TypeSize.micro, weight: .medium))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.bottom, 4)

            ForEach(Array(urls.prefix(6).enumerated()), id: \.offset) { idx, url in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(PastryPalette.warmAccent.opacity(0.12))
                            .frame(width: 20, height: 20)
                        Text(String(url.host?.prefix(1).uppercased() ?? "?"))
                            .font(.system(size: UIConstants.TypeSize.caption2, weight: .semibold))
                            .foregroundColor(PastryPalette.warmAccent)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        Text(url.host ?? url.absoluteString)
                            .font(.system(size: UIConstants.TypeSize.caption, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text(url.path.isEmpty ? "/" : url.path)
                            .font(.system(size: UIConstants.TypeSize.micro))
                            .foregroundColor(.secondary.opacity(0.5))
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 4)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.xs)
                        .fill(Color.primary.opacity(idx % 2 == 0 ? 0.02 : 0))
                )
            }

            if urls.count > 6 {
                Text(String(format: L10n["card.extra_links"], urls.count - 6))
                    .font(.system(size: UIConstants.TypeSize.caption2))
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ClipboardHTMLSegmentsContentView: View {
    let segments: [ContentSegment]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                    switch segment {
                    case .text(let text):
                        Text(text)
                            .font(.system(size: UIConstants.TypeSize.label))
                            .foregroundColor(.primary)
                            .lineLimit(idx == 0 ? 5 : 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .image(let url):
                        RemoteThumbnail(urlString: url)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(contentMode: .fit)
                            .cornerRadius(UIConstants.Radius.sm)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
