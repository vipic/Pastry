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

    /// 类型筛选（nil = 全部，按来源格式过滤）
    @Published var typeFilter: SourceFormat? = nil {
        didSet { performSearchImmediate() }
    }

    /// URL 筛选（独立于类型，匹配 isURL 标签）
    @Published var urlFilter: Bool = false {
        didSet { performSearchImmediate() }
    }

    /// 来源 App 筛选（nil = 全部）
    @Published var appFilter: String? = nil {
        didSet { performSearchImmediate() }
    }

    /// 来自其他设备的 Handoff 筛选
    @Published var handoffFilter: Bool = false {
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
        case pinned = "已收藏"
    }

    enum TimeFilter: String, CaseIterable {
        case any        = "任何时间"
        case today      = "今天"
        case yesterday  = "昨天"
        case thisWeek   = "本周"
        case lastWeek   = "上周"
        case last30Days = "过去 30 天"

        var label: String {
            switch self {
            case .any:        return L10n["filter.time.any"]
            case .today:      return L10n["filter.time.today"]
            case .yesterday:  return L10n["filter.time.yesterday"]
            case .thisWeek:   return L10n["filter.time.thisWeek"]
            case .lastWeek:   return L10n["filter.time.lastWeek"]
            case .last30Days: return L10n["filter.time.last30Days"]
            }
        }

        /// 时间区间（闭开：start ≤ t < end），any 返回 nil
        var dateRange: Range<Date>? {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .any:        return nil
            case .today:
                let start = cal.startOfDay(for: now)
                let end   = cal.date(byAdding: .day, value: 1, to: start)!
                return start ..< end
            case .yesterday:
                let start = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!
                let end   = cal.startOfDay(for: now)
                return start ..< end
            case .thisWeek:
                let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let end   = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
                return start ..< end
            case .lastWeek:
                let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                let start = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart)!
                return start ..< thisWeekStart
            case .last30Days:
                let start = cal.date(byAdding: .day, value: -30, to: now)!
                return start ..< cal.date(byAdding: .second, value: 1, to: now)!
            }
        }
    }


    // MARK: 防抖

    private var searchTask: Task<Void, Never>?

    // MARK: 订阅

    private var cancellables = Set<AnyCancellable>()
    private let usesDatabaseSearch: Bool

    private init() {
        usesDatabaseSearch = true
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
        usesDatabaseSearch = false
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

    func pasteItem(_ item: ClipboardItem) async {
        let result = await PasteboardWriter.write(item, options: .storeSingle)
        guard result == .written else { return }

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

    /// 更新链接预览标题（DB 持久化 + 内存同步）
    func updateLinkTitle(_ itemId: UUID, linkTitle: String?) {
        DatabaseManager.shared.updateLinkTitle(id: itemId.uuidString, linkTitle: linkTitle)
        guard let idx = items.firstIndex(where: { $0.id == itemId }) else { return }
        items[idx].linkTitle = linkTitle
        // 若正在显示筛选结果，刷新以反映变更
        if hasActiveFilters { performSearchImmediate() }
    }

    /// 批量设置选中项的 pin 状态
    func setPinForSelected(_ ids: Set<UUID>, pinned: Bool) {
        for id in ids {
            guard let idx = items.firstIndex(where: { $0.id == id }),
                  items[idx].isPinned != pinned else { continue }
            DatabaseManager.shared.setPin(id: id.uuidString, pinned: pinned)
            items[idx].isPinned = pinned
        }
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
            PasteboardWriter.clearSystemClipboard()
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
        PasteboardWriter.clearSystemClipboard()
        ClipboardMonitor.shared.resume()
    }

    /// 是否有活跃的筛选条件
    var hasActiveFilters: Bool {
        !(searchQuery.isEmpty && typeFilter == nil && appFilter == nil && timeFilter == .any && pinTab == .all && !urlFilter)
    }

    /// 清除所有筛选条件
    func clearFilters() {
        searchQuery = ""
        typeFilter = nil
        appFilter = nil
        timeFilter = .any
        pinTab = .all
        urlFilter = false
    }

    func refresh() {
        loadRecent()
        refreshStats()
    }

    func applyHistoryRetentionSettings() {
        DatabaseManager.shared.enforceHistoryRetention()
        loadRecent()
        refreshStats()
    }

    // MARK: - 内部

    private func handleNewItem(_ item: ClipboardItem) {
        let result = DatabaseManager.shared.insert(item)
        switch result {
        case .skippedDuplicate, .skipped:
            return
        case .replaced(let oldID):
            // 去重置顶：删内存中的旧条目
            if let oldUUID = UUID(uuidString: oldID) {
                items.removeAll { $0.id == oldUUID }
            }
        case .inserted:
            break
        }

        // 内存中的 items 数组截断 content 至 256 字符（DB 保留完整内容用于粘贴和 FTS）
        let truncatedContent = item.content.count > 256 ? String(item.content.prefix(256)) : item.content
        let listItem = ClipboardItem(
            id: item.id, timestamp: item.timestamp,
            content: truncatedContent, sourceFormat: item.sourceFormat, tags: item.tags,
            appName: item.appName, isHandoff: item.isHandoff,
            textAnnotation: item.textAnnotation,
            segmentsJSON: item.segmentsJSON,
            rawFormatData: item.rawFormatData, rawFormatType: item.rawFormatType,
            displayCount: item.displayCount, isPinned: item.isPinned
        )
        items.insert(listItem, at: 0)

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

    private func performSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms 防抖
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

        // 确定基础数据源：生产环境关键词搜索走 SQLite FTS，覆盖完整历史和长文本。
        let searchedInDatabase = usesDatabaseSearch && !query.isEmpty
        var base = searchedInDatabase
            ? DatabaseManager.shared.search(query: query, limit: 500)
            : items
        if pinTab == .pinned {
            base = base.filter { $0.isPinned }
        }

        // 测试注入数据和无数据库路径：content + appName 大小写不敏感子串匹配。
        if !query.isEmpty && !searchedInDatabase {
            base = base.filtered(by: query)
        } else if searchedInDatabase {
            // 保留旧交互：来源 App 名称也可命中。数据库 FTS 负责内容，最近内存列表补 App 名称。
            let existing = Set(base.map(\.id))
            let appMatches = items.filtered(by: query).filter { !existing.contains($0.id) }
            base.append(contentsOf: appMatches)
        }

        // 类型筛选（按来源格式）
        if let type = typeFilter {
            base = base.filter { $0.sourceFormat == type }
        }

        // URL 筛选（独立于类型）
        if urlFilter {
            base = base.filter { $0.tags.isURL }
        }

        // App 筛选
        if let app = appFilter {
            base = base.filter { $0.appName == app }
        }

        // 其他设备（Handoff）筛选
        if handoffFilter {
            base = base.filter { $0.isHandoff }
        }

        // 时间筛选
        if let range = timeFilter.dateRange {
            base = base.filter { range.contains($0.timestamp) }
        }

        guard !Task.isCancelled else { return }
        filteredItems = base
    }

    private func clearNonPinnedWithClipboard() {
        DatabaseManager.shared.clearNonPinned()
        items = items.filter { $0.isPinned }
        if items.isEmpty {
            PasteboardWriter.clearSystemClipboard()
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
