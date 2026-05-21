import SwiftUI

// MARK: - 远程图片缩略图（异步加载，NSCache 缓存）
struct RemoteThumbnail: View {
    let urlString: String

    @State private var image: NSImage?
    @State private var didRequest = false

    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 300
        return c
    }()

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Color.clear
                    .onAppear { loadIfNeeded() }
            }
        }
    }

    private func loadIfNeeded() {
        guard !didRequest else { return }
        didRequest = true

        let key = urlString as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }

        RemoteImageLoader.shared.load(urlString: urlString) { img in
            guard let img else { return }
            Self.cache.setObject(img, forKey: key)
            image = img
        }
    }
}
