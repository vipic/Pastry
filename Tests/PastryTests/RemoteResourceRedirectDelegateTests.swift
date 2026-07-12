import XCTest
@testable import Pastry

/// RemoteResourceRedirectDelegate：仅当目标 URL 通过 NetworkAccessPolicy 时跟随重定向。
final class RemoteResourceRedirectDelegateTests: XCTestCase {

    private let delegate = RemoteResourceRedirectDelegate.shared

    private func redirectDecision(to urlString: String) -> URLRequest? {
        let original = URLRequest(url: URL(string: "https://8.8.8.8/start")!)
        let response = HTTPURLResponse(
            url: original.url!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": urlString]
        )!
        var newRequest = URLRequest(url: URL(string: urlString)!)
        newRequest.httpMethod = "GET"

        var decided: URLRequest?
        let exp = expectation(description: "redirect completion")
        delegate.urlSession(
            URLSession.shared,
            task: URLSession.shared.dataTask(with: original),
            willPerformHTTPRedirection: response,
            newRequest: newRequest
        ) { request in
            decided = request
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        return decided
    }

    func testAllowsRedirectToPublicHTTPS() {
        let result = redirectDecision(to: "https://8.8.8.8/next")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.url?.absoluteString, "https://8.8.8.8/next")
    }

    func testBlocksRedirectToLoopback() {
        XCTAssertNil(redirectDecision(to: "https://127.0.0.1/secret"))
    }

    func testBlocksRedirectToPrivateLAN() {
        XCTAssertNil(redirectDecision(to: "https://192.168.1.1/admin"))
    }

    func testBlocksRedirectToHTTP() {
        XCTAssertNil(redirectDecision(to: "http://8.8.8.8/insecure"))
    }

    func testBlocksRedirectToLocalSuffix() {
        XCTAssertNil(redirectDecision(to: "https://nas.local/share"))
    }
}
