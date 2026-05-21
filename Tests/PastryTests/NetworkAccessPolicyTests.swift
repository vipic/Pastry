import XCTest
@testable import Pastry

final class NetworkAccessPolicyTests: XCTestCase {

    func testAllowsPublicHTTPSURL() {
        XCTAssertTrue(NetworkAccessPolicy.isAllowedRemoteResourceURL(URL(string: "https://example.com/article")!))
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
}
