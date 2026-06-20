import Foundation

final class RemoteResourceRedirectDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = RemoteResourceRedirectDelegate()

    private override init() {}

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard let url = request.url,
              NetworkAccessPolicy.shouldFollowRedirect(to: url)
        else {
            completionHandler(nil)
            return
        }

        completionHandler(request)
    }
}
