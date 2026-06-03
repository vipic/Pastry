import CSQLCipher
import Foundation
import OSLog

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
    private var insertionsSinceRetentionCleanup = 0
    private var retentionCleanupInterval = 25
    static var maxHistoryItemsForTesting: Int {
        HistoryRetentionPolicy.defaultMaxItems
    }

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

    /// 测试专用：控制插入时保留策略清理频率。
    func setRetentionCleanupIntervalForTesting(_ interval: Int) {
        retentionCleanupInterval = max(1, interval)
        insertionsSinceRetentionCleanup = 0
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - 数据库操作

    private static var prefersFileKeyStorage: Bool {
        DatabaseKeyManager.prefersFileKeyStorage
    }

    static var prefersFileKeyStorageForTesting: Bool {
        prefersFileKeyStorage
    }

    /// 用数据库密钥激活 SQLCipher 加密
    private func applyEncryptionKey() {
        let key = DatabaseKeyManager(dbPath: dbPath, log: log).getOrCreateKey()
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
            sqlite3_close(db)
            db = nil
            db = DatabaseMigrator(dbPath: dbPath, key: key, log: log).migratePlaintextOrCreateFresh()
        }
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

    /// 列表查询的公共列（不含 raw_format_data BLOB，该字段仅在粘贴时按需加载）
    private static let listColumns = """
        id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, \
        text_annotation, image_urls, segments, is_favorite, display_count, \
        is_handoff, is_url, link_title
        """

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

        syncFTS(item)
        enforceHistoryRetentionIfNeeded()

        // 更新去重缓存
        lastKey = key
        lastKeyTime = now

        if let oldID { return .replaced(oldID: oldID) }
        return .inserted
    }

    /// 插入热路径上节流执行历史保留策略，避免每次复制都触发 DELETE 查询。
    private func enforceHistoryRetentionIfNeeded() {
        insertionsSinceRetentionCleanup += 1
        guard insertionsSinceRetentionCleanup >= retentionCleanupInterval else { return }
        insertionsSinceRetentionCleanup = 0
        enforceHistoryRetention()
    }

    /// 自动淘汰过期或超出容量的非收藏记录，收藏项不计入上限。
    func enforceHistoryRetention(policy: HistoryRetentionPolicy = .current) {
        lock.lock()
        defer { lock.unlock() }

        if policy.maxAgeDays > 0 {
            let cutoff = Date().addingTimeInterval(-Double(policy.maxAgeDays) * 86_400).timeIntervalSince1970
            let ageSQL = "DELETE FROM clips WHERE is_favorite = 0 AND timestamp < ?;"
            var ageStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, ageSQL, -1, &ageStmt, nil) == SQLITE_OK {
                sqlite3_bind_double(ageStmt, 1, cutoff)
                sqlite3_step(ageStmt)
                sqlite3_finalize(ageStmt)
            } else {
                log.error("历史周期清理 prepare 失败: \(self.lastError)")
            }
        }

        let countSQL = """
        DELETE FROM clips
        WHERE is_favorite = 0
          AND id IN (
              SELECT id FROM clips
              WHERE is_favorite = 0
              ORDER BY timestamp DESC
              LIMIT -1 OFFSET ?
          );
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, countSQL, -1, &stmt, nil) == SQLITE_OK else {
            log.error("历史记录淘汰 prepare 失败: \(self.lastError)")
            return
        }
        sqlite3_bind_int(stmt, 1, Int32(policy.maxItems))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
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
               c.text_annotation, c.image_urls, c.segments, c.is_favorite, c.display_count, c.is_handoff, c.is_url, c.link_title
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
        SELECT \(Self.listColumns)
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
        SELECT \(Self.listColumns)
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
        SELECT \(Self.listColumns)
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
            // image_urls (col 6) 仅用于保留列位置（imageURLs 现从 segments 计算）
            let segmentsJSON: String? = {
                guard let ptr = sqlite3_column_text(stmt, 7) else { return nil }
                return String(cString: ptr)
            }()
            let pinned = sqlite3_column_int(stmt, 8) != 0
            let dispCount = Int(sqlite3_column_int(stmt, 9))
            let isHandoff = sqlite3_column_int(stmt, 10) != 0
            // raw_format_data / raw_format_type 不在列表查询中，粘贴时按需加载
            let isURL = sqlite3_column_int(stmt, 11) != 0
            let linkTitle: String? = {
                guard let ptr = sqlite3_column_text(stmt, 12) else { return nil }
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

    /// 按需加载 raw_format_data / raw_format_type（列表查询不含此 BLOB，粘贴时按需获取）
    func loadRawFormatData(id: UUID) -> (data: Data?, type: String?) {
        lock.lock()
        defer { lock.unlock() }
        let sql = "SELECT raw_format_data, raw_format_type FROM clips WHERE id = ? LIMIT 1;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (nil, nil) }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, (id.uuidString as NSString).utf8String, -1, nil)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return (nil, nil) }
        let data: Data? = {
            guard let ptr = sqlite3_column_blob(stmt, 0),
                  sqlite3_column_bytes(stmt, 0) > 0
            else { return nil }
            return Data(bytes: ptr, count: Int(sqlite3_column_bytes(stmt, 0)))
        }()
        let type: String? = {
            guard let ptr = sqlite3_column_text(stmt, 1) else { return nil }
            return String(cString: ptr)
        }()
        return (data, type)
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
