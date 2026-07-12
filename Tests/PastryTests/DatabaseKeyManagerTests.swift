import OSLog
import XCTest
@testable import Pastry

/// SQLCipher 密钥文件：生成、持久化、同路径复用。
final class DatabaseKeyManagerTests: XCTestCase {
    private var tempDir: URL!
    private var dbPath: String!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastry-key-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        dbPath = tempDir.appendingPathComponent("clips.db").path
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        tempDir = nil
        dbPath = nil
    }

    private func manager() -> DatabaseKeyManager {
        DatabaseKeyManager(
            dbPath: dbPath,
            log: Logger(subsystem: "com.nekutai.pastry.tests", category: "key")
        )
    }

    func testGetOrCreateKeyReturns256BitKey() {
        let key = manager().getOrCreateKey()
        XCTAssertEqual(key.count, 32)
    }

    func testGetOrCreateKeyIsStableAcrossInstances() {
        let first = manager().getOrCreateKey()
        let second = manager().getOrCreateKey()
        XCTAssertEqual(first, second, "同路径第二次应读回已有 DEK，不得重新生成")
    }

    func testKeyFileIsCreatedBesideDatabase() {
        _ = manager().getOrCreateKey()
        let keyPath = dbPath + ".key"
        XCTAssertTrue(FileManager.default.fileExists(atPath: keyPath))
    }

    func testKeyFilePermissionsAreOwnerReadWriteOnly() throws {
        _ = manager().getOrCreateKey()
        let keyPath = dbPath + ".key"
        let attrs = try FileManager.default.attributesOfItem(atPath: keyPath)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertNotNil(perms)
        // 0600
        XCTAssertEqual(perms?.intValue ?? 0, 0o600)
    }

    func testDifferentDatabasePathsGetDifferentKeys() {
        let otherPath = tempDir.appendingPathComponent("other.db").path
        let a = manager().getOrCreateKey()
        let b = DatabaseKeyManager(
            dbPath: otherPath,
            log: Logger(subsystem: "com.nekutai.pastry.tests", category: "key")
        ).getOrCreateKey()
        XCTAssertNotEqual(a, b, "不同库路径应有独立 DEK")
    }
}
