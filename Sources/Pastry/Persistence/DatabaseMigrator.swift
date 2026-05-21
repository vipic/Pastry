import CSQLCipher
import Foundation
import OSLog

// MARK: - SQLCipher 迁移

struct DatabaseMigrator {
    private let dbPath: String
    private let key: Data
    private let log: Logger

    init(dbPath: String, key: Data, log: Logger) {
        self.dbPath = dbPath
        self.key = key
        self.log = log
    }

    /// 检测到现有数据库不可用时：优先按明文迁移，失败则保留原库并创建新加密库。
    func migratePlaintextOrCreateFresh() -> OpaquePointer? {
        let plainPath = dbPath
        let tempEncPath = dbPath + ".enc-migrate"
        let backupPath = dbPath + ".plaintext-backup"

        try? FileManager.default.removeItem(atPath: tempEncPath)

        var plainDB: OpaquePointer?
        guard sqlite3_open_v2(plainPath, &plainDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let plain = plainDB else {
            log.error("迁移跳过：无法按明文打开数据库，原文件已保留")
            return preserveUnreadableDatabaseAndCreateFresh()
        }

        guard validateReadable(plain) else {
            sqlite3_close(plain)
            log.error("迁移跳过：数据库不是可读明文库，原文件已保留")
            return preserveUnreadableDatabaseAndCreateFresh()
        }

        let dump = dumpPlaintextDatabase(plain)
        sqlite3_close(plain)

        guard createEncryptedDatabase(at: tempEncPath, dump: dump) else {
            return nil
        }

        guard validateEncryptedDatabase(at: tempEncPath) else {
            log.error("迁移失败：临时加密数据库不可读，原文件已保留")
            return preserveUnreadableDatabaseAndCreateFresh()
        }

        try? FileManager.default.removeItem(atPath: backupPath)
        do {
            try FileManager.default.moveItem(atPath: plainPath, toPath: backupPath)
            try FileManager.default.moveItem(atPath: tempEncPath, toPath: plainPath)
        } catch {
            log.error("迁移失败：替换数据库文件失败: \(error.localizedDescription)")
            if !FileManager.default.fileExists(atPath: plainPath),
               FileManager.default.fileExists(atPath: backupPath) {
                try? FileManager.default.moveItem(atPath: backupPath, toPath: plainPath)
            }
            return nil
        }

        let migrated = openEncryptedDatabase(at: plainPath)
        if migrated != nil {
            log.info("明文数据库迁移完成 → 加密")
        } else {
            log.error("迁移后无法打开加密数据库")
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

    private func dumpPlaintextDatabase(_ database: OpaquePointer) -> (schema: String, data: String) {
        var schemaSQL = ""
        var dumpStmt: OpaquePointer?
        if sqlite3_prepare_v2(database, "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name;", -1, &dumpStmt, nil) == SQLITE_OK {
            while sqlite3_step(dumpStmt) == SQLITE_ROW {
                if let sql = sqlite3_column_text(dumpStmt, 0) {
                    schemaSQL += String(cString: sql) + ";\n"
                }
            }
        }
        sqlite3_finalize(dumpStmt)

        var dataSQL = ""
        var tableStmt: OpaquePointer?
        if sqlite3_prepare_v2(database, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';", -1, &tableStmt, nil) == SQLITE_OK {
            while sqlite3_step(tableStmt) == SQLITE_ROW {
                guard let tableName = sqlite3_column_text(tableStmt, 0) else { continue }
                dataSQL += dumpRows(from: String(cString: tableName), in: database)
            }
        }
        sqlite3_finalize(tableStmt)

        return (schemaSQL, dataSQL)
    }

    private func dumpRows(from tableName: String, in database: OpaquePointer) -> String {
        var dataSQL = ""
        var rowStmt: OpaquePointer?
        if sqlite3_prepare_v2(database, "SELECT * FROM \(tableName);", -1, &rowStmt, nil) == SQLITE_OK {
            let colCount = sqlite3_column_count(rowStmt)
            while sqlite3_step(rowStmt) == SQLITE_ROW {
                let values = (0..<colCount).map { sqlLiteral(column: $0, in: rowStmt) }
                dataSQL += "INSERT INTO \(tableName) VALUES (\(values.joined(separator: ", ")));\n"
            }
        }
        sqlite3_finalize(rowStmt)
        return dataSQL
    }

    private func sqlLiteral(column: Int32, in statement: OpaquePointer?) -> String {
        if sqlite3_column_type(statement, column) == SQLITE_NULL {
            return "NULL"
        }
        if let text = sqlite3_column_text(statement, column) {
            return "'\(String(cString: text).replacingOccurrences(of: "'", with: "''"))'"
        }
        if let blob = sqlite3_column_blob(statement, column) {
            let len = Int(sqlite3_column_bytes(statement, column))
            let data = Data(bytes: blob, count: len)
            let hex = data.map { String(format: "%02x", $0) }.joined()
            return "X'\(hex)'"
        }
        return "NULL"
    }

    private func createEncryptedDatabase(at path: String, dump: (schema: String, data: String)) -> Bool {
        try? FileManager.default.removeItem(atPath: path)

        var encDB: OpaquePointer?
        guard sqlite3_open(path, &encDB) == SQLITE_OK, let enc = encDB else {
            log.error("迁移失败：无法创建加密数据库")
            return false
        }
        defer { sqlite3_close(enc) }

        applyKey(to: enc)

        for statement in dump.schema.components(separatedBy: ";\n") {
            executeRaw(statement, on: enc)
        }
        for statement in dump.data.components(separatedBy: ";\n") {
            executeRaw(statement, on: enc)
        }
        return true
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
                return nil
            }
            return fresh
        } catch {
            log.error("保留不可读数据库失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func applyKey(to database: OpaquePointer) {
        _ = key.withUnsafeBytes { ptr in
            sqlite3_key(database, ptr.baseAddress, Int32(key.count))
        }
    }

    @discardableResult
    private func executeRaw(_ sql: String, on database: OpaquePointer) -> Bool {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(database, trimmed, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return false
        }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_DONE
    }
}
