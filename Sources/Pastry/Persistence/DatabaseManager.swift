import CSQLCipher
import CryptoKit
import Foundation
import IOKit
import OSLog
import Security

// MARK: - SQLite 数据库管理
// 使用原生 sqlite3 API，SQLCipher 全库加密
final class DatabaseManager {

    nonisolated(unsafe) static let shared = DatabaseManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "database")
    private let lock = NSRecursiveLock()

    private var db: OpaquePointer?
    private let dbPath: String

    // 上次插入的去重 key + 时间，5 秒内连续相同才跳过
    private var lastKey: String?
    private var lastKeyTime: Date = .distantPast

    private init() {
        let dir = AppDirectories.applicationSupportDirectory()
        AppDirectories.ensureDirectory(dir, logCategory: "database")

        dbPath = dir.appendingPathComponent("clips.db").path
        openDatabase()
        createTables()
        runMigrations()
    }

    /// 测试专用：使用临时数据库，不污染生产数据（跳过加密，无需 Keychain）
    init(dbPath: String) {
        self.dbPath = dbPath
        openDatabase(useEncryption: false)
        createTables()
        runMigrations()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - 数据库操作

    /// 密钥文件路径（数据库同目录）
    private var keyFilePath: String { dbPath + ".key" }
    private static let keychainService = "com.nekutai.pastry.dbkey"
    private static let keychainAccount = "clips.db"
    private static let keychainAccessVersion = "pastry-keychain-access-v3"

    private struct KeychainEntry {
        let key: Data
        let needsAccessRefresh: Bool
    }

    /// 获取或创建 256-bit 加密密钥（Keychain 为主，旧文件密钥只作为迁移来源）
    private func getOrCreateKey() -> Data {
        if let entry = readKeyFromKeychain() {
            if entry.needsAccessRefresh {
                refreshKeychainAccess(for: entry.key)
            }
            return entry.key
        }

        // 兼容上个版本的文件密钥：读到后立即迁回 Keychain。
        if let fileKey = readKeyFromFile() {
            if writeKeyToKeychain(fileKey) {
                try? FileManager.default.removeItem(atPath: keyFilePath)
            }
            return fileKey
        }

        // 全新安装 → 生成新密钥，存入 Keychain。
        var keyBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        let newKey = Data(keyBytes)
        if !writeKeyToKeychain(newKey) {
            // Keychain 异常时保底写旧格式文件，避免应用完全不可用。
            writeKeyToFile(newKey)
        }
        return newKey
    }

    private func readKeyFromKeychain() -> KeychainEntry? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let keyData = item[kSecValueData as String] as? Data else { return nil }
        let accessVersion = item[kSecAttrComment as String] as? String
        return KeychainEntry(
            key: keyData,
            needsAccessRefresh: accessVersion != Self.keychainAccessVersion
        )
    }

    @discardableResult
    private func writeKeyToKeychain(_ key: Data) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        let attrs: [String: Any] = [
            kSecValueData as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrLabel as String: "Pastry Clipboard Database Key",
            kSecAttrComment as String: Self.keychainAccessVersion,
        ]
        let addAttrs: [String: Any]
        if let access = makeKeychainAccess() {
            addAttrs = attrs.merging([kSecAttrAccess as String: access]) { _, new in new }
        } else {
            addAttrs = attrs
        }

        let status = SecItemAdd(base.merging(addAttrs) { _, new in new } as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem {
            return SecItemUpdate(base as CFDictionary, attrs as CFDictionary) == errSecSuccess
        }
        log.error("Keychain 密钥写入失败: \(status)")
        return false
    }

    private func refreshKeychainAccess(for key: Data) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]

        let deleteStatus = SecItemDelete(base as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else {
            log.error("Keychain 密钥访问权限刷新失败，删除旧项失败: \(deleteStatus)")
            return
        }

        if !writeKeyToKeychain(key) {
            // 保底保存同一份密钥，避免删除旧 Keychain 项后下次启动无法解密数据库。
            writeKeyToFile(key)
        }
    }

    private func makeKeychainAccess() -> SecAccess? {
        var trustedApplication: SecTrustedApplication?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trustedApplication)
        guard trustedStatus == errSecSuccess, let trustedApplication else {
            log.error("Keychain 当前应用信任对象创建失败: \(trustedStatus)")
            return nil
        }

        var access: SecAccess?
        let accessStatus = SecAccessCreate(
            "Pastry Clipboard Database Key" as CFString,
            [trustedApplication] as CFArray,
            &access
        )
        guard accessStatus == errSecSuccess, let access else {
            log.error("Keychain 访问控制创建失败: \(accessStatus)")
            return nil
        }
        return access
    }

    // MARK: 文件密钥存储（设备派生 KEK，AES-256-GCM 加密）

    /// 从设备硬件标识派生密钥加密密钥（同一设备永远相同，跨设备无法复现）
    private static func deviceKEK() -> SymmetricKey {
        guard let salt = "com.nekutai.pastry.kek".data(using: .utf8),
              let material = deviceIdentity().data(using: .utf8),
              let info = "pastry-db-key".data(using: .utf8)
        else {
            // 字符串字面量和 IOKit UUID 均为 ASCII，此分支理论不可达
            // 但为安全起见，返回零密钥会导致数据库不可读，优于 crash
            return SymmetricKey(data: Data(repeating: 0, count: 32))
        }
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    /// 收集设备唯一标识（IOPlatformUUID——硬件标识，重装系统不变）
    private static func deviceIdentity() -> String {
        let platformExpert = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { if platformExpert != 0 { IOObjectRelease(platformExpert) } }

        guard platformExpert != 0,
              let uuid = IORegistryEntryCreateCFProperty(
                platformExpert, kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault, 0
              )?.takeRetainedValue() as? String
        else { return "pastry-fallback-identity" }

        return uuid
    }

    private func readKeyFromFile() -> Data? {
        guard FileManager.default.fileExists(atPath: keyFilePath),
              let sealed = try? Data(contentsOf: URL(fileURLWithPath: keyFilePath)),
              let box = try? AES.GCM.SealedBox(combined: sealed),
              let key = try? AES.GCM.open(box, using: Self.deviceKEK())
        else { return nil }
        return Data(key)
    }

    private func writeKeyToFile(_ key: Data) {
        do {
            let box = try AES.GCM.seal(key, using: Self.deviceKEK())
            guard let sealed = box.combined else {
                log.error("AES-GCM seal 失败")
                return
            }
            try sealed.write(to: URL(fileURLWithPath: keyFilePath), options: .atomic)
            chmod(keyFilePath, 0o600)
        } catch {
            log.error("密钥文件写入失败: \(error.localizedDescription)")
        }
    }

    /// 用 Keychain 密钥激活 SQLCipher 加密
    private func applyEncryptionKey() {
        let key = getOrCreateKey()
        let rc = key.withUnsafeBytes { ptr in
            sqlite3_key(db, ptr.baseAddress, Int32(key.count))
        }
        if rc != SQLITE_OK {
            log.error("sqlite3_key 失败: \(self.lastError)")
        }

        // 验证密钥是否正确：执行简单查询检测文件是否可读
        var testStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT count(*) FROM sqlite_master;", -1, &testStmt, nil) == SQLITE_OK {
            sqlite3_finalize(testStmt)
        } else {
            // 密钥不对或文件损坏 → 尝试迁移现有明文数据库
            attemptMigrationFromPlaintext(key: key)
        }
    }

    /// 检测到现有数据库是明文 → 导出 → 新建加密库 → 导入
    private func attemptMigrationFromPlaintext(key: Data) {
        // 关闭当前连接（打开时用了错误密钥，文件状态已损坏）
        sqlite3_close(db)
        db = nil

        let plainPath = dbPath
        let tempEncPath = dbPath + ".enc-migrate"
        let backupPath = dbPath + ".plaintext-backup"

        // 先删可能存在的残留临时文件
        try? FileManager.default.removeItem(atPath: tempEncPath)

        // Step 1: 用明文方式打开原数据库并先验证。验证失败时绝不删除原库。
        var plainDB: OpaquePointer?
        guard sqlite3_open_v2(plainPath, &plainDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let plain = plainDB else {
            log.error("迁移跳过：无法按明文打开数据库，原文件已保留")
            preserveUnreadableDatabaseAndCreateFresh(key: key)
            return
        }
        var validationStmt: OpaquePointer?
        let validationOK = sqlite3_prepare_v2(plain, "SELECT count(*) FROM sqlite_master;", -1, &validationStmt, nil) == SQLITE_OK
            && sqlite3_step(validationStmt) == SQLITE_ROW
        sqlite3_finalize(validationStmt)
        guard validationOK else {
            sqlite3_close(plain)
            log.error("迁移跳过：数据库不是可读明文库，原文件已保留")
            preserveUnreadableDatabaseAndCreateFresh(key: key)
            return
        }

        // 读取明文库的完整 SQL dump
        var dumpSQL = ""
        var dumpStmt: OpaquePointer?
        if sqlite3_prepare_v2(plain, "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL ORDER BY type, name;", -1, &dumpStmt, nil) == SQLITE_OK {
            while sqlite3_step(dumpStmt) == SQLITE_ROW {
                if let sql = sqlite3_column_text(dumpStmt, 0) {
                    dumpSQL += String(cString: sql) + ";\n"
                }
            }
            sqlite3_finalize(dumpStmt)
        }

        // 读取数据行
        var dataSQL = ""
        var tableStmt: OpaquePointer?
        if sqlite3_prepare_v2(plain, "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';", -1, &tableStmt, nil) == SQLITE_OK {
            while sqlite3_step(tableStmt) == SQLITE_ROW {
                if let tableName = sqlite3_column_text(tableStmt, 0) {
                    let name = String(cString: tableName)
                    var rowStmt: OpaquePointer?
                    if sqlite3_prepare_v2(plain, "SELECT * FROM \(name);", -1, &rowStmt, nil) == SQLITE_OK {
                        let colCount = sqlite3_column_count(rowStmt)
                        while sqlite3_step(rowStmt) == SQLITE_ROW {
                            var values: [String] = []
                            for i in 0..<colCount {
                                if let val = sqlite3_column_text(rowStmt, i) {
                                    values.append("'\(String(cString: val).replacingOccurrences(of: "'", with: "''"))'")
                                } else if sqlite3_column_type(rowStmt, i) == SQLITE_NULL {
                                    values.append("NULL")
                                } else if let blob = sqlite3_column_blob(rowStmt, i) {
                                    let len = Int(sqlite3_column_bytes(rowStmt, i))
                                    let data = Data(bytes: blob, count: len)
                                    let hex = data.map { String(format: "%02x", $0) }.joined()
                                    values.append("X'\(hex)'")
                                } else {
                                    values.append("NULL")
                                }
                            }
                            dataSQL += "INSERT INTO \(name) VALUES (\(values.joined(separator: ", ")));\n"
                        }
                        sqlite3_finalize(rowStmt)
                    }
                }
            }
            sqlite3_finalize(tableStmt)
        }

        sqlite3_close(plain)

        // Step 2: 创建新的加密数据库，执行 schema + 数据导入
        try? FileManager.default.removeItem(atPath: tempEncPath)

        var encDB: OpaquePointer?
        guard sqlite3_open(tempEncPath, &encDB) == SQLITE_OK, let enc = encDB else {
            log.error("迁移失败：无法创建加密数据库")
            db = nil
            return
        }

        _ = key.withUnsafeBytes { ptr in
            sqlite3_key(enc, ptr.baseAddress, Int32(key.count))
        }

        // 执行 schema
        for statement in dumpSQL.components(separatedBy: ";\n") {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            _ = executeRaw(trimmed, on: enc)
        }

        // 导入数据
        for statement in dataSQL.components(separatedBy: ";\n") {
            let trimmed = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            _ = executeRaw(trimmed, on: enc)
        }

        sqlite3_close(enc)
        db = nil

        // Step 3: 只有临时加密库验证通过后，才替换原明文库。
        var verifyDB: OpaquePointer?
        guard sqlite3_open(tempEncPath, &verifyDB) == SQLITE_OK, let verify = verifyDB else {
            log.error("迁移失败：无法验证临时加密数据库")
            return
        }
        _ = key.withUnsafeBytes { ptr in
            sqlite3_key(verify, ptr.baseAddress, Int32(key.count))
        }
        var verifyStmt: OpaquePointer?
        let verifyOK = sqlite3_prepare_v2(verify, "SELECT count(*) FROM sqlite_master;", -1, &verifyStmt, nil) == SQLITE_OK
            && sqlite3_step(verifyStmt) == SQLITE_ROW
        sqlite3_finalize(verifyStmt)
        sqlite3_close(verify)
        guard verifyOK else {
            log.error("迁移失败：临时加密数据库不可读，原文件已保留")
            preserveUnreadableDatabaseAndCreateFresh(key: key)
            return
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
            return
        }

        // Step 4: 重新打开加密数据库
        guard sqlite3_open(plainPath, &db) == SQLITE_OK else {
            log.error("迁移后无法打开加密数据库")
            return
        }
        _ = key.withUnsafeBytes { ptr in
            sqlite3_key(db, ptr.baseAddress, Int32(key.count))
        }

        log.info("明文数据库迁移完成 → 加密")
    }

    /// 无法解密且也不是可迁移明文库时，保留原文件并创建新的空加密库，避免启动后继续访问 nil db。
    private func preserveUnreadableDatabaseAndCreateFresh(key: Data) {
        let preservedPath = dbPath + ".unreadable-\(Int(Date().timeIntervalSince1970))"
        do {
            if FileManager.default.fileExists(atPath: dbPath) {
                try FileManager.default.moveItem(atPath: dbPath, toPath: preservedPath)
                log.error("不可读数据库已保留为: \(preservedPath, privacy: .public)")
            }
            if sqlite3_open(dbPath, &db) == SQLITE_OK, let fresh = db {
                _ = key.withUnsafeBytes { ptr in
                    sqlite3_key(fresh, ptr.baseAddress, Int32(key.count))
                }
            } else {
                log.error("创建新加密数据库失败")
                db = nil
            }
        } catch {
            log.error("保留不可读数据库失败: \(error.localizedDescription)")
            db = nil
        }
    }

    /// 在指定 db 上执行裸 SQL（不检查结果）
    @discardableResult
    private func executeRaw(_ sql: String, on targetDB: OpaquePointer) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(targetDB, sql, -1, &stmt, nil) == SQLITE_OK else {
            sqlite3_finalize(stmt)
            return false
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        return true
    }

    private func openDatabase(useEncryption: Bool = true) {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            log.error("无法打开数据库: \(self.dbPath)")
            db = nil
        } else {
            if useEncryption {
                applyEncryptionKey()
                guard db != nil else {
                    log.error("数据库加密初始化失败，跳过后续初始化以保留原文件")
                    return
                }
            }
            // 开启 WAL 模式，提升并发性能
            execute("PRAGMA journal_mode=WAL")
            execute("PRAGMA synchronous=NORMAL")
            execute("PRAGMA cache_size=-8000")  // 8MB 缓存
            log.info("数据库已打开: \(self.dbPath)")
        }
    }

    private func createTables() {
        let clipsSQL = """
        CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY,
            timestamp REAL NOT NULL,
            content TEXT NOT NULL,
            content_type TEXT NOT NULL,
            app_name TEXT,
            is_favorite INTEGER DEFAULT 0,
            display_count INTEGER DEFAULT 0
        );
        """

        let idxSQL = """
        CREATE INDEX IF NOT EXISTS idx_clips_timestamp ON clips(timestamp DESC);
        CREATE INDEX IF NOT EXISTS idx_clips_favorite ON clips(is_favorite) WHERE is_favorite = 1;
        CREATE INDEX IF NOT EXISTS idx_clips_type ON clips(content_type);
        """

        let ftsSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS clips_fts USING fts5(
            content,
            link_title,
            content='clips',
            content_rowid='rowid',
            tokenize='porter unicode61'
        );
        """

        // 安全网触发器：超过 50000 条时强制裁剪（兜底，主清理由 StoreManager 定时执行）
        let cleanupTrigger = """
        CREATE TRIGGER IF NOT EXISTS trg_cleanup_old
        AFTER INSERT ON clips
        BEGIN
            DELETE FROM clips WHERE rowid IN (
                SELECT rowid FROM clips ORDER BY timestamp ASC
                LIMIT MAX(0, (SELECT COUNT(*) FROM clips) - 50000)
            );
        END;
        """

        // 同步 FTS 删除
        let ftsDeleteTrigger = """
        CREATE TRIGGER IF NOT EXISTS trg_clips_fts_delete
        AFTER DELETE ON clips
        BEGIN
            DELETE FROM clips_fts WHERE rowid = old.rowid;
        END;
        """

        _ = execute(clipsSQL)
        _ = execute(idxSQL)
        _ = execute(ftsSQL)
        _ = execute(cleanupTrigger)
        _ = execute(ftsDeleteTrigger)

        log.info("数据库表初始化完成")
    }

    private func runMigrations() {
        let version = userVersion
        if version < 1 {
            userVersion = 1
        }
        if version < 2 {
            _ = execute("ALTER TABLE clips ADD COLUMN text_annotation TEXT;")
            userVersion = 2
        }
        if version < 3 {
            _ = execute("ALTER TABLE clips ADD COLUMN image_urls TEXT;")
            userVersion = 3
        }
        if version < 4 {
            _ = execute("ALTER TABLE clips ADD COLUMN segments TEXT;")
            userVersion = 4
        }
        if version < 5 {
            _ = execute("ALTER TABLE clips ADD COLUMN is_handoff INTEGER DEFAULT 0;")
            userVersion = 5
        }
        if version < 6 {
            _ = execute("ALTER TABLE clips ADD COLUMN raw_format_data BLOB;")
            _ = execute("ALTER TABLE clips ADD COLUMN raw_format_type TEXT;")
            userVersion = 6
        }
        if version < 7 {
            _ = execute("ALTER TABLE clips ADD COLUMN is_url INTEGER DEFAULT 0;")
            _ = execute("UPDATE clips SET content_type = 'text', is_url = 1 WHERE content_type = 'url';")
            userVersion = 7
        }
        if version < 8 {
            _ = execute("ALTER TABLE clips ADD COLUMN dedup_key TEXT;")
            _ = execute("CREATE INDEX IF NOT EXISTS idx_clips_dedup ON clips(dedup_key);")
            userVersion = 8
        }
        if version < 9 {
            _ = execute("ALTER TABLE clips ADD COLUMN link_title TEXT;")
            userVersion = 9
        }
        if version < 10 {
            // 重建 FTS5 表以加入 link_title 列，然后全量重建索引
            _ = execute("DROP TABLE IF EXISTS clips_fts;")
            let ftsSQL = """
            CREATE VIRTUAL TABLE clips_fts USING fts5(
                content,
                link_title,
                content='clips',
                content_rowid='rowid',
                tokenize='porter unicode61'
            );
            """
            _ = execute(ftsSQL)
            // 重新插入所有已有数据到 FTS 索引
            _ = execute("INSERT INTO clips_fts(rowid, content, link_title) SELECT rowid, content, link_title FROM clips;")
            // 重建 FTS 删除触发器
            _ = execute("DROP TRIGGER IF EXISTS trg_clips_fts_delete;")
            _ = execute("""
                CREATE TRIGGER trg_clips_fts_delete
                AFTER DELETE ON clips
                BEGIN
                    DELETE FROM clips_fts WHERE rowid = old.rowid;
                END;
            """)
            userVersion = 10
        }
    }

    // MARK: - CRUD

    enum InsertResult: Equatable {
        case inserted
        case replaced(oldID: String)
        case skippedDuplicate
        case skipped
    }

    /// 插入新项（去重）。重复内容会删除旧记录并置顶（新时间戳 + 新来源）。
    @discardableResult
    func insert(_ item: ClipboardItem) -> InsertResult {
        lock.lock()
        defer { lock.unlock() }
        let key = item.dedupKey
        let now = Date()

        // 跨历史去重：查找相同 dedupKey 的旧记录
        var oldID: String?
        let findSQL = "SELECT id FROM clips WHERE dedup_key = ? LIMIT 1;"
        var findStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, findSQL, -1, &findStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(findStmt, 1, (key as NSString).utf8String, -1, nil)
            if sqlite3_step(findStmt) == SQLITE_ROW {
                oldID = String(cString: sqlite3_column_text(findStmt, 0))
            }
            sqlite3_finalize(findStmt)
        }

        // 有旧记录 → 删除后重新插入（更新时间戳 + 来源）
        if let old = oldID {
            _ = delete(id: old)
        } else if key == lastKey, now.timeIntervalSince(lastKeyTime) < 5 {
            // 5 秒内同 key 且无历史记录 → 真正的快速重复，跳过
            return .skippedDuplicate
        }

        let sql = """
        INSERT OR IGNORE INTO clips (id, timestamp, content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url, dedup_key, link_title)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("INSERT prepare 失败: \(self.lastError)")
            return .skipped
        }

        sqlite3_bind_text(stmt, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_double(stmt, 2, item.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (item.content as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (item.sourceFormat.storageKey as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (item.appName as NSString?)?.utf8String ?? nil, -1, nil)
        sqlite3_bind_text(stmt, 6, (item.textAnnotation as NSString?)?.utf8String ?? nil, -1, nil)
        let imageURLsJSON = item.imageURLs.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        sqlite3_bind_text(stmt, 7, (imageURLsJSON as NSString?)?.utf8String ?? nil, -1, nil)
        sqlite3_bind_text(stmt, 8, (item.segmentsJSON as NSString?)?.utf8String ?? nil, -1, nil)
        sqlite3_bind_int(stmt, 9, item.isPinned ? 1 : 0)
        sqlite3_bind_int(stmt, 10, Int32(item.displayCount))
        sqlite3_bind_int(stmt, 11, item.isHandoff ? 1 : 0)
        if let rawData = item.rawFormatData {
            _ = rawData.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 12, ptr.baseAddress, Int32(rawData.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
        } else {
            sqlite3_bind_null(stmt, 12)
        }
        if let rawType = item.rawFormatType {
            sqlite3_bind_text(stmt, 13, (rawType as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 13)
        }
        sqlite3_bind_int(stmt, 14, item.tags.isURL ? 1 : 0)
        sqlite3_bind_text(stmt, 15, (key as NSString).utf8String, -1, nil)
        if let lt = item.linkTitle {
            sqlite3_bind_text(stmt, 16, (lt as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 16)
        }

        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        guard rc == SQLITE_DONE else { return .skipped }

        // 同步到 FTS 索引
        syncFTS(item)

        // 更新去重缓存
        lastKey = key
        lastKeyTime = now

        if let oldID { return .replaced(oldID: oldID) }
        return .inserted
    }

    /// 搜索（优先 FTS，fallback LIKE）
    func search(query: String, limit: Int = 100) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return recent(limit: limit)
        }

        // FTS5 搜索（带前缀通配）
        let ftsSQL = """
        SELECT c.id, c.timestamp, substr(c.content, 1, 256) AS content, c.content_type, c.app_name,
               c.text_annotation, c.image_urls, c.segments, c.is_favorite, c.display_count, c.is_handoff, c.raw_format_data, c.raw_format_type, c.is_url, c.link_title
        FROM clips c
        JOIN clips_fts f ON c.rowid = f.rowid
        WHERE clips_fts MATCH ?
        ORDER BY rank
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, ftsSQL, -1, &stmt, nil) == SQLITE_OK else {
            log.error("FTS search prepare 失败: \(self.lastError)")
            return fallbackSearch(query: query, limit: limit)
        }

        // FTS 查询字符串：双引号包裹防操作符注入 + 前缀匹配
        let ftsQuery = query
            .split(separator: " ")
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " AND ")

        sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)

        if !results.isEmpty { return results }
        return fallbackSearch(query: query, limit: limit)
    }

    /// LIKE 降级搜索
    private func fallbackSearch(query: String, limit: Int) -> [ClipboardItem] {
        let sql = """
        SELECT id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url, link_title
        FROM clips
        WHERE content LIKE ? OR link_title LIKE ?
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 3, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)
        return results
    }

    /// 最近历史
    func recent(limit: Int = 100) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url, link_title
        FROM clips
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)
        return results
    }

    /// 收藏列表
    func favorites(limit: Int = 200) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url, link_title
        FROM clips
        WHERE is_favorite = 1
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)
        return results
    }

    /// 切换 pin 状态
    @discardableResult
    func togglePin(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET is_favorite = CASE WHEN is_favorite THEN 0 ELSE 1 END WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        let changed = sqlite3_changes(db)
        sqlite3_finalize(stmt)
        return rc == SQLITE_DONE && changed > 0
    }

    /// 直接设置 pin 状态（不 toggle）
    @discardableResult
    func setPin(id: String, pinned: Bool) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET is_favorite = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }

        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)

        let rc = sqlite3_step(stmt)
        let changed = sqlite3_changes(db)
        sqlite3_finalize(stmt)
        return rc == SQLITE_DONE && changed > 0
    }

    /// 增加粘贴次数
    func incrementDisplayCount(id: String) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET display_count = display_count + 1 WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// 更新链接预览抓取的页面标题（nil 表示清空）
    func updateLinkTitle(id: String, linkTitle: String?) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET link_title = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        if let lt = linkTitle {
            sqlite3_bind_text(stmt, 1, (lt as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// 将条目时间戳更新为现在（移动到列表最前）
    func bumpTimestamp(id: String) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "UPDATE clips SET timestamp = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, (id as NSString).utf8String, -1, nil)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    /// 删除单项
    @discardableResult
    func delete(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let sql = "DELETE FROM clips WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("DELETE prepare 失败: \(self.lastError)")
            return false
        }
        sqlite3_bind_text(stmt, 1, (id as NSString).utf8String, -1, nil)
        let rc = sqlite3_step(stmt)
        let changed = sqlite3_changes(db)
        sqlite3_finalize(stmt)
        if changed > 0 { lastKey = nil }
        return rc == SQLITE_DONE && changed > 0
    }

    /// 清空所有（保留 pinned）
    func clearNonPinned() {
        lock.lock()
        defer { lock.unlock() }
        execute("DELETE FROM clips WHERE is_favorite = 0;")
        lastKey = nil
    }

    /// 清空全部
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        execute("DELETE FROM clips;")
        lastKey = nil
    }

    // MARK: - 统计

    func stats() -> ClipboardStats {
        lock.lock()
        defer { lock.unlock() }
        let total = scalarInt("SELECT COUNT(*) FROM clips;")
        let today = scalarInt("SELECT COUNT(*) FROM clips WHERE timestamp > strftime('%s', 'now', 'start of day') * 1.0;")
        let favs = scalarInt("SELECT COUNT(*) FROM clips WHERE is_favorite = 1;")
        let sizeK = scalarInt("SELECT COALESCE(SUM(LENGTH(content)), 0) / 1024 FROM clips;")

        return ClipboardStats(
            totalItems: total,
            todayItems: today,
            favoriteCount: favs,
            storageSizeKB: sizeK
        )
    }

    // MARK: - 内部方法

    private func syncFTS(_ item: ClipboardItem) {
        let sql = """
        INSERT INTO clips_fts (rowid, content, link_title)
        VALUES ((SELECT rowid FROM clips WHERE id = ?), ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(stmt, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (item.content as NSString).utf8String, -1, nil)
        if let lt = item.linkTitle {
            sqlite3_bind_text(stmt, 3, (lt as NSString).utf8String, -1, nil)
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func readItems(from stmt: OpaquePointer?) -> [ClipboardItem] {
        var items: [ClipboardItem] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let idStr = String(cString: sqlite3_column_text(stmt, 0))
            let timestamp = sqlite3_column_double(stmt, 1)
            let content = String(cString: sqlite3_column_text(stmt, 2))
            let typeStr = String(cString: sqlite3_column_text(stmt, 3))
            let appName: String? = {
                guard let ptr = sqlite3_column_text(stmt, 4) else { return nil }
                return String(cString: ptr)
            }()
            let textAnnotation: String? = {
                guard let ptr = sqlite3_column_text(stmt, 5) else { return nil }
                return String(cString: ptr)
            }()
            // image_urls 仅用于保留列位置（imageURLs 现从 segments 计算）
            let segmentsJSON: String? = {
                guard let ptr = sqlite3_column_text(stmt, 7) else { return nil }
                return String(cString: ptr)
            }()
            let pinned = sqlite3_column_int(stmt, 8) != 0
            let dispCount = Int(sqlite3_column_int(stmt, 9))
            let isHandoff = sqlite3_column_int(stmt, 10) != 0
            let rawFormatData: Data? = {
                guard let ptr = sqlite3_column_blob(stmt, 11),
                      sqlite3_column_bytes(stmt, 11) > 0
                else { return nil }
                let count = Int(sqlite3_column_bytes(stmt, 11))
                return Data(bytes: ptr, count: count)
            }()
            let rawFormatType: String? = {
                guard let ptr = sqlite3_column_text(stmt, 12) else { return nil }
                return String(cString: ptr)
            }()
            let isURL = sqlite3_column_int(stmt, 13) != 0
            let linkTitle: String? = {
                guard let ptr = sqlite3_column_text(stmt, 14) else { return nil }
                return String(cString: ptr)
            }()

            let sourceFormat = SourceFormat(storageKey: typeStr)
            let tags = ContentTags(
                isURL: isURL,
                hasSegments: segmentsJSON != nil,
                isMultiFile: sourceFormat == .fileURL && content.contains("\n"),
                isMissing: false
            )

            let item = ClipboardItem(
                id: UUID(uuidString: idStr) ?? UUID(),
                timestamp: Date(timeIntervalSince1970: timestamp),
                content: content,
                sourceFormat: sourceFormat,
                tags: tags,
                appName: appName,
                isHandoff: isHandoff,
                textAnnotation: textAnnotation,
                linkTitle: linkTitle,
                segmentsJSON: segmentsJSON,
                rawFormatData: rawFormatData,
                rawFormatType: rawFormatType,
                displayCount: dispCount,
                isPinned: pinned
            )
            items.append(item)
        }

        return items
    }

    /// 查询所有 image 类型条目的 content 路径（供缓存孤儿清理）
    func allImageContentPaths() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT content FROM clips WHERE content_type = 'image';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var paths = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            paths.insert(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return paths
    }

    /// 按需加载完整 content（列表查询只截断 256 字符，粘贴时取全文）
    func loadFullContent(id: UUID) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT content FROM clips WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let result = String(cString: sqlite3_column_text(stmt, 0))
        return result
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let db else { return false }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let err = errMsg.map { String(cString: $0) } ?? "unknown"
            log.error("SQLite 错误: \(err)\nSQL: \(sql)")
            sqlite3_free(errMsg)
            return false
        }
        return true
    }

    private func scalarInt(_ sql: String) -> Int {
        guard let db else { return 0 }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int(stmt, 0))
        }
        return 0
    }

    private var lastError: String {
        guard let db else { return "database is not open" }
        return String(cString: sqlite3_errmsg(db))
    }

    private var userVersion: Int {
        get { scalarInt("PRAGMA user_version;") }
        set { execute("PRAGMA user_version = \(newValue);") }
    }
}
