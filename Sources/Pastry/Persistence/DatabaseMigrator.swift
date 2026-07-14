import CSQLCipher
import Foundation
import OSLog

// MARK: - SQLCipher 迁移

struct DatabaseMigrator {
    private let dbPath: String
    private let key: Data
    private let log: Logger
    private let diagnosticsLog = PastryLogger(category: "database-migration")

    init(dbPath: String, key: Data, log: Logger) {
        self.dbPath = dbPath
        self.key = key
        self.log = log
    }

    /// 检测到现有数据库不可用时：优先按明文迁移，失败则保留原库并创建新加密库。
    ///
    /// 使用 SQLCipher 官方推荐的 `sqlcipher_export()` 流程：在新加密库上 ATTACH 明文库，
    /// 用一条 `INSERT INTO … SELECT …` 把数据按行绑定复制过来，再重建 schema。
    /// 相比旧版 dump-and-replay（按 `;\n` 分割 SQL 字符串），不会因剪贴板内容包含
    /// `;\n` 而损坏还原，且全程走 SQLite 的参数/值通道，无注入与截断风险。
    func migratePlaintextOrCreateFresh() -> OpaquePointer? {
        let plainPath = dbPath
        let tempEncPath = dbPath + ".enc-migrate"
        let backupPath = dbPath + ".plaintext-backup"

        try? FileManager.default.removeItem(atPath: tempEncPath)

        var plainDB: OpaquePointer?
        guard sqlite3_open_v2(plainPath, &plainDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let plain = plainDB else {
            log.error("迁移跳过：无法按明文打开数据库，原文件已保留")
            diagnosticsLog.error(
                "无法按明文打开旧数据库",
                event: "database_migration.plaintext_open.failed"
            )
            return preserveUnreadableDatabaseAndCreateFresh()
        }

        guard validateReadable(plain) else {
            sqlite3_close(plain)
            log.error("迁移跳过：数据库不是可读明文库，原文件已保留")
            diagnosticsLog.error(
                "旧数据库不可读",
                event: "database_migration.plaintext_validation.failed"
            )
            return preserveUnreadableDatabaseAndCreateFresh()
        }
        sqlite3_close(plain)

        guard createEncryptedDatabaseViaExport(at: tempEncPath, plainPath: plainPath) else {
            return nil
        }

        guard validateEncryptedDatabase(at: tempEncPath) else {
            log.error("迁移失败：临时加密数据库不可读，原文件已保留")
            diagnosticsLog.critical(
                "迁移后的临时加密数据库不可读",
                event: "database_migration.encrypted_validation.failed"
            )
            return preserveUnreadableDatabaseAndCreateFresh()
        }

        try? FileManager.default.removeItem(atPath: backupPath)
        do {
            try FileManager.default.moveItem(atPath: plainPath, toPath: backupPath)
            try FileManager.default.moveItem(atPath: tempEncPath, toPath: plainPath)
        } catch {
            log.error("迁移失败：替换数据库文件失败: \(error.localizedDescription)")
            diagnosticsLog.critical(
                "迁移数据库替换失败",
                event: "database_migration.replace.failed",
                metadata: ["error": error.localizedDescription]
            )
            if !FileManager.default.fileExists(atPath: plainPath),
               FileManager.default.fileExists(atPath: backupPath) {
                try? FileManager.default.moveItem(atPath: backupPath, toPath: plainPath)
            }
            return nil
        }

        let migrated = openEncryptedDatabase(at: plainPath)
        if migrated != nil {
            // 迁移成功后立刻删除明文备份，避免历史内容明文滞留磁盘 / 被 Time Machine 快照
            try? FileManager.default.removeItem(atPath: backupPath)
            log.info("明文数据库迁移完成 → 加密，明文备份已删除")
            diagnosticsLog.notice(
                "明文数据库迁移完成",
                event: "database_migration.completed"
            )
        } else {
            log.error("迁移后无法打开加密数据库")
            diagnosticsLog.critical(
                "迁移后无法打开加密数据库",
                event: "database_migration.reopen.failed"
            )
        }
        return migrated
    }

    private func validateReadable(_ database: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        let ok = sqlite3_prepare_v2(database, "SELECT count(*) FROM sqlite_master;", -1, &stmt, nil) == SQLITE_OK
            && sqlite3_step(stmt) == SQLITE_ROW
        sqlite3_finalize(stmt)
        return ok
    }

    /// 用 `sqlcipher_export()` 把已 ATTACH 的明文库逐行复制到新加密库。
    /// 整个过程在单条事务内，schema + 数据 + 索引/触发器由 SQLCipher 自动重建。
    private func createEncryptedDatabaseViaExport(at encPath: String, plainPath: String) -> Bool {
        try? FileManager.default.removeItem(atPath: encPath)

        var encDB: OpaquePointer?
        guard sqlite3_open(encPath, &encDB) == SQLITE_OK, let enc = encDB else {
            log.error("迁移失败：无法创建加密数据库")
            diagnosticsLog.critical(
                "无法创建迁移用加密数据库",
                event: "database_migration.encrypted_create.failed"
            )
            return false
        }
        defer { sqlite3_close(enc) }

        applyKey(to: enc)

        // ATTACH 明文库（无 key，明文库不需要解密）
        let attachSQL = "ATTACH DATABASE '\(escapedSQLLiteral(plainPath))' AS plaintext KEY '';"
        if sqlite3_exec(enc, attachSQL, nil, nil, nil) != SQLITE_OK {
            log.error("迁移失败：ATTACH 明文库失败: \(String(cString: sqlite3_errmsg(enc)))")
            diagnosticsLog.critical(
                "迁移时挂载明文数据库失败",
                event: "database_migration.attach.failed"
            )
            return false
        }

        // 用 sqlcipher_export 把 plaintext 的全部对象复制到主库（加密）
        // 事务包裹，任一步失败回滚
        let exportSQL = """
        BEGIN;
        SELECT sqlcipher_export('main', 'plaintext');
        COMMIT;
        """
        if sqlite3_exec(enc, exportSQL, nil, nil, nil) != SQLITE_OK {
            log.error("迁移失败：sqlcipher_export 失败: \(String(cString: sqlite3_errmsg(enc)))")
            diagnosticsLog.critical(
                "SQLCipher 数据导出失败",
                event: "database_migration.export.failed"
            )
            _ = sqlite3_exec(enc, "ROLLBACK;", nil, nil, nil)
            _ = sqlite3_exec(enc, "DETACH DATABASE plaintext;", nil, nil, nil)
            return false
        }

        _ = sqlite3_exec(enc, "DETACH DATABASE plaintext;", nil, nil, nil)
        return true
    }

    /// 转义路径中的单引号，用于内联到 ATTACH 的 KEY 子句（路径来自本地文件系统，可信但仍防御）。
    private func escapedSQLLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func validateEncryptedDatabase(at path: String) -> Bool {
        guard let database = openEncryptedDatabase(at: path) else { return false }
        defer { sqlite3_close(database) }
        return validateReadable(database)
    }

    private func openEncryptedDatabase(at path: String) -> OpaquePointer? {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK, let opened = database else {
            return nil
        }
        applyKey(to: opened)
        return opened
    }

    private func preserveUnreadableDatabaseAndCreateFresh() -> OpaquePointer? {
        let preservedPath = dbPath + ".unreadable-\(Int(Date().timeIntervalSince1970))"
        do {
            if FileManager.default.fileExists(atPath: dbPath) {
                try FileManager.default.moveItem(atPath: dbPath, toPath: preservedPath)
                log.error("不可读数据库已保留为: \(preservedPath, privacy: .public)")
            }
            guard let fresh = openEncryptedDatabase(at: dbPath) else {
                log.error("创建新加密数据库失败")
                diagnosticsLog.critical(
                    "保留不可读数据库后创建新库失败",
                    event: "database_migration.fresh_create.failed"
                )
                return nil
            }
            return fresh
        } catch {
            log.error("保留不可读数据库失败: \(error.localizedDescription)")
            diagnosticsLog.critical(
                "保留不可读数据库失败",
                event: "database_migration.preserve.failed",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func applyKey(to database: OpaquePointer) {
        _ = key.withUnsafeBytes { ptr in
            sqlite3_key(database, ptr.baseAddress, Int32(key.count))
        }
    }
}
