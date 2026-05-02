import Foundation
import Combine
import Cocoa
import CoreGraphics
import OSLog

// MARK: - 应用数据管理层
// 连接 ClipboardMonitor → DatabaseManager → SwiftUI
@MainActor
final class StoreManager: ObservableObject {

    /// 自定义复制提示音
    private static let copySound: NSSound? = {
        guard let path = Bundle.main.path(forResource: "Copy", ofType: "aiff") else {
            Logger(subsystem: "com.nekutai.pastry", category: "store").warning("找不到 Copy.aiff")
            return nil
        }
        return NSSound(contentsOfFile: path, byReference: true)
    }()

    static let shared = StoreManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "store")

    // MARK: Published

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var filteredItems: [ClipboardItem] = []
    @Published var searchQuery = "" {
        didSet {
            performSearch()
        }
    }
    @Published var selectedFilter: FilterMode = .all
    @Published private(set) var stats = ClipboardStats(totalItems: 0, todayItems: 0,
                                                         favoriteCount: 0, storageSizeKB: 0)

    // MARK: 枚举

    enum FilterMode: String, CaseIterable {
        case all      = "所有"
        case text     = "文本"
        case image    = "图片"
        case file     = "文件"

        var clipTypes: [ClipType]? {
            switch self {
            case .all:      return nil
            case .text:     return [.text, .rtf, .html]
            case .image:    return [.image]
            case .file:     return [.fileURL]
            }
        }
    }

    // MARK: 订阅

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // 从数据库加载最近记录
        loadRecent()

        // 监听新剪贴板项
        ClipboardMonitor.shared.onNewItem = { [weak self] item in
            self?.handleNewItem(item)
        }

        // 统计定时刷新
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshStats()
            }
            .store(in: &cancellables)
    }

    // MARK: - 公开方法

    func start() {
        ClipboardMonitor.shared.start()
        refreshStats()
        log.info("Store 启动")
    }

    func pasteItem(_ item: ClipboardItem) {
        // 1. 将内容写入系统剪贴板
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

        // 2. 更新计数
        DatabaseManager.shared.incrementDisplayCount(id: item.id.uuidString)

        // 3. 模拟 ⌘V 粘贴到当前应用
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.simulatePaste()
        }
    }

    /// 模拟 ⌘V 快捷键
    private static func simulatePaste() {
        let vKey = CGKeyCode(9)

        let source = CGEventSource(stateID: .privateState)

        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            return
        }

        cmdDown.flags = .maskCommand
        cmdUp.flags = .maskCommand

        cmdDown.post(tap: .cgSessionEventTap)
        cmdUp.post(tap: .cgSessionEventTap)
    }

    func deleteItem(_ item: ClipboardItem) {
        DatabaseManager.shared.delete(id: item.id.uuidString)
        items.removeAll { $0.id == item.id }
        performSearch()
    }

    func clearHistory() {
        ClipboardMonitor.shared.suspend()
        DatabaseManager.shared.clearNonFavorites()
        loadRecent()
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString("", forType: .string)
        ClipboardMonitor.shared.syncChangeCount()
        ClipboardMonitor.shared.resume()
    }

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

    func refresh() {
        loadRecent()
        refreshStats()
    }

    // MARK: - 内部

    private func handleNewItem(_ item: ClipboardItem) {
        guard DatabaseManager.shared.insert(item) else { return }

        items.insert(item, at: 0)

        // 保持上限 500 条在内存中
        if items.count > 500 {
            items = Array(items.prefix(500))
        }

        if searchQuery.isEmpty && selectedFilter == .all {
            filteredItems = items
        }

        // 🔔 播放复制提示音（如果用户开启了）
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            Self.copySound?.play()
        }

        refreshStats()
    }

    private func loadRecent() {
        items = DatabaseManager.shared.recent(limit: 500)
        performSearch()
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)

        if query.isEmpty {
            // 按筛选模式
            switch selectedFilter {
            case .all:
                filteredItems = items
            case .text:
                filteredItems = items.filter { $0.contentType == .text || $0.contentType == .rtf || $0.contentType == .html }
            case .image:
                filteredItems = items.filter { $0.contentType == .image }
            case .file:
                filteredItems = items.filter { $0.contentType == .fileURL }
            }
        } else {
            // 搜索 + 筛选
            let dbResults = DatabaseManager.shared.search(query: query, limit: 100)
            switch selectedFilter {
            case .all:
                filteredItems = dbResults
            case .text:
                filteredItems = dbResults.filter { $0.contentType == .text || $0.contentType == .rtf || $0.contentType == .html }
            case .image:
                filteredItems = dbResults.filter { $0.contentType == .image }
            case .file:
                filteredItems = dbResults.filter { $0.contentType == .fileURL }
            }
        }
    }

    private func refreshStats() {
        stats = DatabaseManager.shared.stats()
    }
}
