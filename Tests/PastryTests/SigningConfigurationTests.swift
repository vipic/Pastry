import Foundation
import XCTest

final class SigningConfigurationTests: XCTestCase {
    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func contents(of relativePath: String) throws -> String {
        let url = repositoryRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testScriptsDefaultToSharedAuthorSigningIdentity() throws {
        let deployScript = try contents(of: "deploy.sh")
        let releaseScript = try contents(of: "release.sh")
        let benchScript = try contents(of: "bench.sh")

        XCTAssertTrue(deployScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        XCTAssertTrue(releaseScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        XCTAssertTrue(benchScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        XCTAssertFalse(deployScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Pastry Dev}""#))
        XCTAssertFalse(releaseScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Pastry Release}""#))
    }

    func testScriptsRejectAdhocSigningFallback() throws {
        let deployScript = try contents(of: "deploy.sh")
        let releaseScript = try contents(of: "release.sh")
        let benchScript = try contents(of: "bench.sh")

        for script in [deployScript, releaseScript, benchScript] {
            XCTAssertTrue(script.contains("不能使用 ad-hoc 签名"))
            XCTAssertFalse(script.contains("回退 ad-hoc"))
            XCTAssertFalse(script.contains("codesign --force --sign -"))
            XCTAssertFalse(script.contains("codesign --force --deep --sign -"))
        }
    }

    func testDocumentsDescribeReusableAuthorCertificate() throws {
        let developmentGuide = try contents(of: "docs/DEVELOPMENT.md")
        let releaseGuide = try contents(of: "RELEASE.md")

        XCTAssertTrue(developmentGuide.contains("Pastry 必须使用稳定代码签名"))
        XCTAssertTrue(developmentGuide.contains("不要使用 ad-hoc 签名"))
        XCTAssertTrue(developmentGuide.contains(#"export CODESIGN_IDENTITY="Your Certificate Name""#))
        XCTAssertTrue(releaseGuide.contains("多个应用可以共用同一张代码签名证书"))
        XCTAssertTrue(releaseGuide.contains("没有匹配证书或签名失败时脚本会直接停止"))

        XCTAssertFalse(developmentGuide.contains("Release 同理，证书名改为 `Pastry Release`"))
        XCTAssertFalse(releaseGuide.contains("建议使用 `Pastry Release`"))
    }
}
