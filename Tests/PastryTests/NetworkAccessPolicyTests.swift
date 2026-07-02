import XCTest
@testable import Pastry

final class NetworkAccessPolicyTests: XCTestCase {

    func testAllowsPublicHTTPSURL() {
        // 用 IP 字面量避开测试环境 DNS 劫持（某些 CI/代理会把 example.com 解析到 198.18.x）
        XCTAssertTrue(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://8.8.8.8/article")!))
    }

    func testRejectsHTTPURL() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "http://example.com/article")!))
    }

    func testRejectsLocalhost() {
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://localhost/test")!))
        XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://dev.localhost/test")!))
    }

    func testRejectsPrivateIPv4Ranges() {
        let blocked = [
            "https://10.0.0.1/a",
            "https://127.0.0.1/a",
            "https://169.254.1.1/a",
            "https://172.16.0.1/a",
            "https://172.31.255.255/a",
            "https://192.168.1.1/a",
            "https://100.64.0.1/a",
        ]
        for raw in blocked {
            XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: raw)!), raw)
        }
    }

    func testRejectsPrivateIPv6Ranges() {
        let blocked = [
            "https://[::1]/a",
            "https://[fe80::1]/a",
            "https://[fc00::1]/a",
            "https://[fd00::1]/a",
        ]
        for raw in blocked {
            XCTAssertFalse(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: raw)!), raw)
        }
    }

    func testHTMLByteLimitAllowsLargeModernPages() {
        XCTAssertEqual(NetworkAccessPolicy.maxHTMLBytes, 2_000_000)
    }

    func testRejectsRedirectToPrivateAddress() {
        XCTAssertFalse(NetworkAccessPolicy.shouldFollowRedirect(to: URL(string: "https://127.0.0.1/admin")!))
        XCTAssertFalse(NetworkAccessPolicy.shouldFollowRedirect(to: URL(string: "https://192.168.1.1/admin")!))
    }

    func testResponseWithinLimitRejectsFinalPrivateURL() {
        let response = HTTPURLResponse(
            url: URL(string: "https://127.0.0.1/metadata")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "128"]
        )

        XCTAssertFalse(NetworkAccessPolicy.responseWithinLimit(response, maxBytes: 1_000))
    }

    func testResponseWithinLimitRejectsOversizedContentLength() {
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com/page")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "\(NetworkAccessPolicy.maxHTMLBytes + 1)"]
        )

        XCTAssertFalse(NetworkAccessPolicy.responseWithinLimit(response, maxBytes: NetworkAccessPolicy.maxHTMLBytes))
    }
}
