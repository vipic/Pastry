import SwiftUI
import Cocoa

// MARK: - Clipboard card content components

struct ClipboardLinkContentView: View {
    let preview: LinkPreviewLoader.Preview?
    let text: ClipboardCardView.LinkCardText

    var body: some View {
        VStack(spacing: 0) {
            thumbnail(imageURL: preview?.imageURL)
                .frame(height: 106)
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.sm))
                .padding(.bottom, 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(text.title)
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(text.titleLineLimit)
                    .truncationMode(.tail)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Image(systemName: "link")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.secondary.opacity(0.35))
            }
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
