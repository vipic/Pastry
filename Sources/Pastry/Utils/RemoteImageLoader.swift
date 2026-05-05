import Cocoa
import OSLog

// MARK: - 远程图片加载器
// 异步拉取 HTML 中引用的远程图片，NSCache 内存缓存
final class RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let log = Logger(subsystem: "com.nekutai.pastry", category: "remote-image")

    private let cache = NSCache<NSString, NSImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        ]
        return URLSession(configuration: config)
    }()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 20 * 1024 * 1024  // 20 MB
    }

    /// 同步查缓存
    func cached(for urlString: String) -> NSImage? {
        cache.object(forKey: urlString as NSString)
    }

    /// 异步拉取（缓存命中直接回调，未命中网络请求）
    func load(urlString: String, completion: @escaping (NSImage?) -> Void) {
        let key = urlString as NSString
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return
        }

        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }

        session.dataTask(with: url) { [weak self] data, _, error in
            guard let self, let data = data, error == nil,
                  let image = NSImage(data: data)
            else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // 缓存开销 = 数据字节数
            self.cache.setObject(image, forKey: key, cost: data.count)
            DispatchQueue.main.async { completion(image) }
        }.resume()
    }
}
