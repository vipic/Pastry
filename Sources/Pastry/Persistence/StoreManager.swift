import Foundation
import Combine
import Cocoa
import CoreGraphics
import OSLog

// MARK: - 应用数据管理层
// 连接 ClipboardMonitor → DatabaseManager → SwiftUI
@MainActor
final class StoreManager: ObservableObject {

    static let shared = StoreManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "store")

    // MARK: Published

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var filteredItems: [ClipboardItem] = []

    /// 当前 pin tab
    @Published var pinTab: PinTab = .all {
        didSet { performSearchImmediate() }
    }

    /// 关键词搜索
    @Published var searchQuery = "" {
        didSet { performSearch() }
    }

    /// 类型筛选（nil = 全部）
    @Published var typeFilter: ClipType? = nil {
        didSet { performSearchImmediate() }
    }

    /// 来源 App 筛选（nil = 全部）
    @Published var appFilter: String? = nil {
        didSet { performSearchImmediate() }
    }

    /// 时间筛选
    @Published var timeFilter: TimeFilter = .any {
        didSet { performSearchImmediate() }
    }

    /// 从当前数据中提取的去重 App 名称列表（供筛选 popover 使用）
    @Published private(set) var availableApps: [String] = []

    @Published private(set) var stats = ClipboardStats(totalItems: 0, todayItems: 0,
                                                         favoriteCount: 0, storageSizeKB: 0)

    // MARK: 枚举

    enum PinTab: String, CaseIterable {
        case all    = "全部"
        case pinned = "已钉选"
    }

    enum TimeFilter: String, CaseIterable {
        case any        = "任何时间"
        case today      = "今天"
        case yesterday  = "昨天"
        case thisWeek   = "本周"
        case lastWeek   = "上周"
        case last30Days = "过去 30 天"

        var startDate: Date? {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .any:        return nil
            case .today:      return cal.startOfDay(for: now)
            case .yesterday:  return cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))
            case .thisWeek:   return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
            case .lastWeek:   return cal.date(byAdding: .weekOfYear, value: -1, to: cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!)
            case .last30Days: return cal.date(byAdding: .day, value: -30, to: now)
            }
        }
    }

    // MARK: 分类词 → 扩展名映射

    /// 搜索词中的分类词自动扩展为文件扩展名和类型匹配
    private static let categoryMappings: [String: [String]] = [
        "安装包": ["dmg", "pkg"],
        "图片":   ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp"],
        "文档":   ["pdf", "doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key"],
        "视频":   ["mp4", "mov", "mkv", "avi", "m4v"],
        "音频":   ["mp3", "wav", "aac", "m4a", "flac"],
        "压缩包": ["zip", "rar", "7z", "tar", "gz", "bz2"],
        "代码":   ["swift", "py", "js", "ts", "go", "rs", "java", "c", "cpp"],
    ]

    // MARK: 防抖

    private var searchTask: Task<Void, Never>?

    // MARK: 订阅

    private var cancellables = Set<AnyCancellable>()

    private init() {
        loadRecent()

        ClipboardMonitor.shared.onNewItem = { [weak self] item in
            self?.handleNewItem(item)
        }

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshStats()
            }
            .store(in: &cancellables)
    }

    /// 测试专用：直接注入剪贴板数据，不经过数据库
    init(items: [ClipboardItem]) {
        self.items = items
        performSearchImmediate()
        refreshAvailableApps()
    }

    // MARK: - 公开方法

    func start() {
        ClipboardMonitor.shared.start()
        refreshStats()
        log.info("Store 启动")
    }

    func pasteItem(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.contentType {
        case .text, .rtf, .html:
            pb.setString(item.content, forType: .string)
        case .fileURL:
            let urls = item.content
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) }
            pb.writeObjects(urls as [NSURL])
        case .image:
            if let image = NSImage(contentsOfFile: item.content) {
                pb.writeObjects([image])
            }
        }

        DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.simulatePaste()
        }
    }

    private static func simulatePaste() {
        // 首次粘贴时延迟初始化 CGEvent tap（避免启动时弹辅助功能授权）
        ClipboardMonitor.shared.setupEventTap()

        let vKey = CGKeyCode(9)
        guard let source = CGEventSource(stateID: .privateState) else {
            Logger(subsystem: "com.nekutai.pastry", category: "store").warning("CGEventSource 创建失败 — 可能缺少辅助功能权限")
            return
        }

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return
        }

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        cmdDown.postToPid(pid)
        cmdUp.postToPid(pid)
    }

    /// 切换 pin 状态
    func togglePin(_ item: ClipboardItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        DatabaseManager.shared.togglePin(id: item.id.uuidString)
        items[idx].isPinned.toggle()
        performSearchImmediate()
    }

    func deleteItem(_ item: ClipboardItem) {
        DatabaseManager.shared.delete(id: item.id.uuidString)
        items.removeAll { $0.id == item.id }
        performSearchImmediate()
        refreshAvailableApps()
    }

    /// 批量删除选中项 — pinned 跳过，仅在所有 items 清空时清系统剪贴板
    func deleteSelected(_ ids: Set<UUID>) {
        ClipboardMonitor.shared.suspend()
        for id in ids {
            if let item = items.first(where: { $0.id == id }), !item.isPinned {
                DatabaseManager.shared.delete(id: id.uuidString)
                items.removeAll { $0.id == id }
            }
        }

        if items.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.declareTypes([.string], owner: nil)
            pb.setString("", forType: .string)
            ClipboardMonitor.shared.syncChangeCount()
        }

        ClipboardMonitor.shared.resume()
        performSearchImmediate()
        refreshAvailableApps()
    }

    /// 清空除 pinned 外的所有记录（菜单栏使用）
    func clearNonPinned() {
        ClipboardMonitor.shared.suspend()
        clearNonPinnedWithClipboard()
        loadRecent()
        ClipboardMonitor.shared.resume()
    }

    /// 清空全部（含 pinned）
    func clearAll() {
        ClipboardMonitor.shared.suspend()
        DatabaseManager.shared.clearAll()
        items.removeAll()
        filteredItems.removeAll()
        refreshStats()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString("", forType: .string)
        ClipboardMonitor.shared.syncChangeCount()
        ClipboardMonitor.shared.resume()
    }

    /// 是否有活跃的筛选条件
    var hasActiveFilters: Bool {
        !(searchQuery.isEmpty && typeFilter == nil && appFilter == nil && timeFilter == .any && pinTab == .all)
    }

    /// 清除所有筛选条件
    func clearFilters() {
        searchQuery = ""
        typeFilter = nil
        appFilter = nil
        timeFilter = .any
        pinTab = .all
    }

    func refresh() {
        loadRecent()
        refreshStats()
    }

    // MARK: - 内部

    private func handleNewItem(_ item: ClipboardItem) {
        guard DatabaseManager.shared.insert(item) else { return }

        items.insert(item, at: 0)

        let noActiveFilters = searchQuery.isEmpty
            && typeFilter == nil
            && appFilter == nil
            && timeFilter == .any
            && pinTab == .all

        if noActiveFilters {
            filteredItems = items
        } else {
            performSearchImmediate()
        }

        refreshStats()
        refreshAvailableApps()
    }

    private func loadRecent() {
        items = DatabaseManager.shared.recent(limit: 500)
        performSearchImmediate()
        refreshAvailableApps()
    }

    /// 分类词映射：将搜索词中的中文分类词替换为文件扩展名 OR 子句
    static func expandQuery(_ raw: String) -> String {
        let terms = raw.split(separator: " ").map(String.init)
        var expanded: [String] = []

        for term in terms {
            var found = false
            for (keyword, extensions) in categoryMappings {
                if term == keyword {
                    // 保留原词 + 扩展名 OR 子句
                    expanded.append(term)
                    expanded.append("(" + extensions.joined(separator: " OR ") + ")")
                    found = true
                    break
                }
            }
            if !found {
                expanded.append(term)
            }
        }

        return expanded.joined(separator: " ")
    }

    private func performSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 防抖，仅搜索输入使用
            guard !Task.isCancelled else { return }
            executeSearch()
        }
    }

    private func performSearchImmediate() {
        searchTask?.cancel()
        executeSearch()
    }

    private func executeSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)

        // 确定基础数据源
        var base = items
        if pinTab == .pinned {
            base = items.filter { $0.isPinned }
        }

        // 关键词搜索（含分类词扩展）
        if !query.isEmpty {
            let expanded = Self.expandQuery(query)
            base = DatabaseManager.shared.search(query: expanded, limit: 200).filter { item in
                pinTab == .all || item.isPinned
            }
        }

        // 类型筛选
        if let type = typeFilter {
            base = base.filter { $0.contentType == type }
        }

        // App 筛选
        if let app = appFilter {
            base = base.filter { $0.appName == app }
        }

        // 时间筛选
        if let start = timeFilter.startDate {
            base = base.filter { $0.timestamp >= start }
        }

        guard !Task.isCancelled else { return }
        filteredItems = base
    }

    private func clearNonPinnedWithClipboard() {
        DatabaseManager.shared.clearNonPinned()
        items = items.filter { $0.isPinned }
        if items.isEmpty {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.declareTypes([.string], owner: nil)
            pb.setString("", forType: .string)
            ClipboardMonitor.shared.syncChangeCount()
        }
        performSearchImmediate()
        refreshStats()
    }

    private func refreshAvailableApps() {
        let apps = Set(items.compactMap { $0.appName }.filter { $0 != "Finder" && $0 != "loginwindow" })
        availableApps = apps.sorted()
    }

    private func refreshStats() {
        stats = DatabaseManager.shared.stats()
    }
}
