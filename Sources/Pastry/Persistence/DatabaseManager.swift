import Foundation
import SQLite3
import OSLog

// MARK: - SQLite 数据库管理
// 使用原生 sqlite3 API，零外部依赖
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
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            log.error("无法获取 Application Support 目录")
            fatalError("Application Support directory is unavailable")
        }
        let dir = appSupport.appendingPathComponent(Constants.appName)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error("无法创建数据库目录: \(dir.path, privacy: .public), error: \(error.localizedDescription)")
        }

        dbPath = dir.appendingPathComponent("clips.db").path
        openDatabase()
        createTables()
        runMigrations()
    }

    /// 测试专用：使用临时数据库，不污染生产数据
    init(dbPath: String) {
        self.dbPath = dbPath
        openDatabase()
        createTables()
        runMigrations()
    }

    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }

    // MARK: - 数据库操作

    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            log.error("无法打开数据库: \(self.dbPath)")
            db = nil
        } else {
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
    }

    // MARK: - CRUD

    /// 插入新项（去重）
    @discardableResult
    func insert(_ item: ClipboardItem) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = item.dedupKey
        let now = Date()
        if key == lastKey, now.timeIntervalSince(lastKeyTime) < 5 { return false }

        let sql = """
        INSERT OR IGNORE INTO clips (id, timestamp, content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("INSERT prepare 失败: \(self.lastError)")
            return false
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
        sqlite3_bind_int(stmt, 9, item.isPinned ? 1 : 0)  // is_favorite
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

        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        guard rc == SQLITE_DONE else { return false }

        // 同步到 FTS 索引
        syncFTS(item)

        // 更新去重缓存
        lastKey = key
        lastKeyTime = now

        return true
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
               c.text_annotation, c.image_urls, c.segments, c.is_favorite, c.display_count, c.is_handoff, c.raw_format_data, c.raw_format_type
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
        SELECT id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type
        FROM clips
        WHERE content LIKE ?
        ORDER BY timestamp DESC
        LIMIT ?;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, nil)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        let results = readItems(from: stmt)
        sqlite3_finalize(stmt)
        return results
    }

    /// 最近历史
    func recent(limit: Int = 100) -> [ClipboardItem] {
        lock.lock()
        defer { lock.unlock() }
        let sql = """
        SELECT id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type, is_url
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
        SELECT id, timestamp, substr(content, 1, 256) AS content, content_type, app_name, text_annotation, image_urls, segments, is_favorite, display_count, is_handoff, raw_format_data, raw_format_type
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
        INSERT INTO clips_fts (rowid, content)
        VALUES ((SELECT rowid FROM clips WHERE id = ?), ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

        sqlite3_bind_text(stmt, 1, (item.id.uuidString as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 2, (item.content as NSString).utf8String, -1, nil)
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
        let sql = "SELECT content FROM clips WHERE source_format = 'image';"
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
        String(cString: sqlite3_errmsg(db))
    }

    private var userVersion: Int {
        get { scalarInt("PRAGMA user_version;") }
        set { execute("PRAGMA user_version = \(newValue);") }
    }
}
