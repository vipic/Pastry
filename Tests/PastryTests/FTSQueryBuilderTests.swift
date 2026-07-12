import XCTest
@testable import Pastry

/// DatabaseManager.ftsMatchQuery：FTS5 MATCH 字符串构建（转义 / 前缀 / 多词 AND）。
final class FTSQueryBuilderTests: XCTestCase {

    func testSingleTokenGetsQuotedPrefix() {
        XCTAssertEqual(DatabaseManager.ftsMatchQuery(from: "hello"), "\"hello\"*")
    }

    func testMultipleTokensJoinedWithAND() {
        XCTAssertEqual(
            DatabaseManager.ftsMatchQuery(from: "hello world"),
            "\"hello\"* AND \"world\"*"
        )
    }

    func testEmbeddedDoubleQuotesAreEscaped() {
        // FTS 双引号转义： " → ""
        let q = DatabaseManager.ftsMatchQuery(from: "a\"b")
        XCTAssertEqual(q, "\"a\"\"b\"*")
    }

    func testOperatorLikeTokensAreQuotedNotInterpreted() {
        // 用户输入 OR / NOT 等应被引号包裹，不能作为 FTS 操作符
        let q = DatabaseManager.ftsMatchQuery(from: "OR NOT AND")
        XCTAssertEqual(q, "\"OR\"* AND \"NOT\"* AND \"AND\"*")
        XCTAssertFalse(q.contains(" OR "), "raw OR operator must not appear unquoted")
    }

    func testCollapsesOnlySpaceSeparatedTokens() {
        // split(separator: " ") 不会拆 tab；保持与生产一致
        XCTAssertEqual(DatabaseManager.ftsMatchQuery(from: "a  b"), "\"a\"* AND \"b\"*")
    }

    func testChineseToken() {
        XCTAssertEqual(DatabaseManager.ftsMatchQuery(from: "剪贴板"), "\"剪贴板\"*")
    }

    func testEmptyStringYieldsEmptyMatch() {
        XCTAssertEqual(DatabaseManager.ftsMatchQuery(from: ""), "")
    }
}
