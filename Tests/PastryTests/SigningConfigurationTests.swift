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

        XCTAssertTrue(deployScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        XCTAssertTrue(releaseScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Nekutai}""#))
        XCTAssertFalse(deployScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Pastry Dev}""#))
        XCTAssertFalse(releaseScript.contains(#"IDENTITY="${CODESIGN_IDENTITY:-Pastry Release}""#))
    }

    func testDocumentsDescribeReusableAuthorCertificate() throws {
        let readme = try contents(of: "README.md")
        let releaseGuide = try contents(of: "RELEASE.md")
        let agentGuide = try contents(of: "AGENTS.md")

        XCTAssertTrue(readme.contains("同一个作者的多个应用可以共用"))
        XCTAssertTrue(readme.contains(#"export CODESIGN_IDENTITY="Nekutai""#))
        XCTAssertTrue(releaseGuide.contains("多个应用可以共用同一张代码签名证书"))
        XCTAssertTrue(agentGuide.contains("证书不再按应用拆分成 Dev/Release"))

        XCTAssertFalse(readme.contains("Release 同理，证书名改为 `Pastry Release`"))
        XCTAssertFalse(releaseGuide.contains("建议使用 `Pastry Release`"))
        XCTAssertFalse(agentGuide.contains("| `release.sh` | `Pastry Release` |"))
    }
}
