import XCTest
@testable import Pastry

// MARK: - StoreManager 测试套件
// 测试筛选、搜索、状态管理逻辑（CRUD 由 DatabaseManagerTests 覆盖）

@MainActor
final class StoreManagerTests: XCTestCase {

    var store: StoreManager!

    override func setUp() async throws {
        // 每个测试自己创建 StoreManager
    }

    override func tearDown() async throws {
        store = nil
    }

    // MARK: - 辅助方法

    private func makeStoreWithItems(_ specs: [(content: String, type: SourceFormat, app: String?, pinned: Bool, daysAgo: Int)]) -> StoreManager {
        let cal = Calendar.current
        let now = Date()
        let items: [ClipboardItem] = specs.map { spec in
            let date = cal.date(byAdding: .day, value: -spec.daysAgo, to: now)!
            return ClipboardItem(
                timestamp: date,
                content: spec.content,
                sourceFormat: spec.type,
                appName: spec.app,
                isPinned: spec.pinned
            )
        }
        return StoreManager(items: items)
    }

    // MARK: - PinTab 筛选

    func testPinTabAllShowsEverything() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", true, 0),
            ("B", .text, "Chrome", false, 0),
        ])

        store.pinTab = .all
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    func testPinTabPinnedOnlyShowsPinned() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", true, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Xcode", true, 0),
        ])

        store.pinTab = .pinned
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy { $0.isPinned })
    }

    // MARK: - 类型筛选

    func testTypeFilterText() {
        store = makeStoreWithItems([
            ("text a", .text, "Safari", false, 0),
            ("img 1", .image, "Preview", false, 0),
            ("text b", .text, "Chrome", false, 0),
        ])

        store.typeFilter = .text
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy { $0.sourceFormat == .text })
    }

    func testTypeFilterImage() {
        store = makeStoreWithItems([
            ("text a", .text, "Safari", false, 0),
            ("img 1", .image, "Preview", false, 0),
        ])

        store.typeFilter = .image
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].sourceFormat, .image)
    }

    func testTypeFilterNilShowsAll() {
        store = makeStoreWithItems([
            ("text a", .text, "Safari", false, 0),
            ("img 1", .image, "Preview", false, 0),
        ])

        store.typeFilter = nil
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    // MARK: - App 筛选

    func testAppFilter() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Safari", false, 0),
        ])

        store.appFilter = "Safari"
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.allSatisfy { $0.appName == "Safari" })
    }

    func testAppFilterNilShowsAll() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
        ])

        store.appFilter = nil
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    // MARK: - 时间筛选

    func testTimeFilterToday() {
        // "A" 是 2 天前，"B" 是今天
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 2),
            ("B", .text, "Chrome", false, 0),
        ])

        store.timeFilter = .today
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "B")
    }

    func testTimeFilterAny() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 10),
            ("B", .text, "Chrome", false, 5),
        ])

        store.timeFilter = .any
        XCTAssertEqual(store.filteredItems.count, 2)
    }

    func testTimeFilterLast30Days() {
        store = makeStoreWithItems([
            ("old", .text, "Safari", false, 35),
            ("recent", .text, "Chrome", false, 10),
            ("today", .text, "Xcode", false, 0),
        ])

        store.timeFilter = .last30Days
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertFalse(store.filteredItems.contains { $0.content == "old" })
    }

    // MARK: - 组合筛选

    func testCombinedFilters() {
        store = makeStoreWithItems([
            ("pinned text safari", .text, "Safari", true, 0),
            ("pinned img safari", .image, "Safari", true, 0),
            ("normal text safari", .text, "Safari", false, 0),
            ("pinned text chrome", .text, "Chrome", true, 0),
            ("pinned text safari old", .text, "Safari", true, 35),  // >30 天，应被筛掉
        ])

        store.pinTab = .pinned
        store.typeFilter = .text
        store.appFilter = "Safari"
        store.timeFilter = .last30Days

        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "pinned text safari")
    }

    // MARK: - hasActiveFilters

    func testHasActiveFiltersFalseByDefault() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        XCTAssertFalse(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenSearchSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.searchQuery = "A"
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenTypeSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.typeFilter = .image
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenPinTabPinned() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.pinTab = .pinned
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenAppSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.appFilter = "Safari"
        XCTAssertTrue(store.hasActiveFilters)
    }

    func testHasActiveFiltersWhenTimeSet() {
        store = makeStoreWithItems([("A", .text, nil, false, 0)])
        store.timeFilter = .today
        XCTAssertTrue(store.hasActiveFilters)
    }

    // MARK: - clearFilters

    func testClearFiltersResetsAll() {
        store = makeStoreWithItems([("A", .text, "Safari", false, 0)])
        store.searchQuery = "A"
        store.typeFilter = .text
        store.appFilter = "Safari"
        store.timeFilter = .today
        store.pinTab = .pinned

        store.clearFilters()

        XCTAssertEqual(store.searchQuery, "")
        XCTAssertNil(store.typeFilter)
        XCTAssertNil(store.appFilter)
        XCTAssertEqual(store.timeFilter, .any)
        XCTAssertEqual(store.pinTab, .all)
        XCTAssertFalse(store.hasActiveFilters)
    }

    // MARK: - History Retention

    func testApplyHistoryRetentionSettingsInvokesCleanup() {
        store = makeStoreWithItems([("A", .text, "Safari", false, 0)])
        var didEnforce = false

        store.applyHistoryRetentionSettings(
            enforce: { didEnforce = true },
            reloadFromDatabase: false
        )

        XCTAssertTrue(didEnforce)
    }

    // MARK: - togglePin

    func testTogglePinInMemory() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
        ])
        let item = store.filteredItems[0]

        store.togglePin(item)

        // 注意：togglePin 会调用 DatabaseManager.shared.togglePin
        // 在测试环境这里会失败（无真实 DB），但内存状态应更新
        XCTAssertTrue(store.filteredItems[0].isPinned)
    }

    func testTogglePinUnpinInMemory() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", true, 0),
        ])
        let item = store.filteredItems[0]

        store.togglePin(item)

        XCTAssertFalse(store.filteredItems[0].isPinned)
    }

    // MARK: - deleteItem

    func testDeleteItemRemovesFromFiltered() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
        ])
        let item = store.filteredItems[0]

        store.deleteItem(item)

        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "B")
    }

    // MARK: - deleteSelected

    func testDeleteSelectedSkipsPinned() {
        store = makeStoreWithItems([
            ("pinned", .text, "Safari", true, 0),
            ("normal", .text, "Chrome", false, 0),
        ])

        let ids = Set(store.filteredItems.map { $0.id })
        store.deleteSelected(ids)

        // pinned 应保留
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "pinned")
    }

    func testDeleteSelectedRemovesMultiple() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Xcode", false, 0),
        ])

        let ids = Set(store.filteredItems.prefix(2).map { $0.id })
        store.deleteSelected(ids)

        XCTAssertEqual(store.filteredItems.count, 1)
    }

    // MARK: - dedupKey 含 textAnnotation

    func testDedupKeyIncludesTextAnnotation() {
        let a = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "hello")
        let b = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "world")
        // 不同附注 → 不同 dedupKey
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySameWhenAnnotationSame() {
        let a = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "same")
        let b = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "same")
        XCTAssertEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeyNilAnnotation() {
        let a = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image)
        let b = ClipboardItem(content: "/tmp/img.png", sourceFormat: .image, textAnnotation: "has text")
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySeparatesTextAndFileURL() {
        let text = ClipboardItem(content: "/tmp/demo.txt", sourceFormat: .text)
        let file = ClipboardItem(content: "/tmp/demo.txt", sourceFormat: .fileURL)

        XCTAssertNotEqual(text.dedupKey, file.dedupKey)
    }

    func testDedupKeySeparatesFileURLAndImage() {
        let file = ClipboardItem(content: "/tmp/demo.png", sourceFormat: .fileURL)
        let image = ClipboardItem(content: "/tmp/demo.png", sourceFormat: .image)

        XCTAssertNotEqual(file.dedupKey, image.dedupKey)
    }

    // MARK: - dedupKey 含 segments

    func testDedupKeyIncludesSegments() {
        let a = ClipboardItem(content: "text", sourceFormat: .html, segments: [
            .image(url: "https://a.com/1.png"), .text("文字")
        ])
        let b = ClipboardItem(content: "text", sourceFormat: .html, segments: [
            .image(url: "https://a.com/2.png"), .text("文字")
        ])
        // 不同图片 URL → 不同 dedupKey
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySameSegmentsSame() {
        let segs: [ContentSegment] = [.text("A"), .image(url: "https://a.com/pic.png")]
        let a = ClipboardItem(content: "A", sourceFormat: .html, segments: segs)
        let b = ClipboardItem(content: "A", sourceFormat: .html, segments: segs)
        XCTAssertEqual(a.dedupKey, b.dedupKey)
    }

    func testDedupKeySegmentsNilVsSome() {
        let a = ClipboardItem(content: "text", sourceFormat: .html, segments: nil)
        let b = ClipboardItem(content: "text", sourceFormat: .html, segments: [.text("text")])
        XCTAssertNotEqual(a.dedupKey, b.dedupKey)
    }

    // MARK: - availableApps

    func testAvailableAppsDedupedAndSorted() {
        store = makeStoreWithItems([
            ("A", .text, "Safari", false, 0),
            ("B", .text, "Chrome", false, 0),
            ("C", .text, "Safari", false, 0),
            ("D", .text, "Xcode", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Chrome", "Safari", "Xcode"])
    }

    func testAvailableAppsExcludesFinder() {
        store = makeStoreWithItems([
            ("A", .text, "Finder", false, 0),
            ("B", .text, "Safari", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Safari"])
    }

    func testAvailableAppsExcludesLoginwindow() {
        store = makeStoreWithItems([
            ("A", .text, "loginwindow", false, 0),
            ("B", .text, "Safari", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Safari"])
    }

    func testAvailableAppsHandlesNilApp() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 0),
            ("B", .text, "Safari", false, 0),
        ])

        XCTAssertEqual(store.availableApps, ["Safari"])
    }

    // MARK: - 时间区间筛选（双向范围）

    func testYesterdayExcludesToday() {
        // yesterday: 1 天前；today: 0 天前 → yesterday 不应包含 today
        store = makeStoreWithItems([
            ("A", .text, nil, false, 1),
            ("B", .text, nil, false, 0),
        ])
        store.timeFilter = .yesterday
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "A")
    }

    func testYesterdayExcludesTwoDaysAgo() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 2),
            ("B", .text, nil, false, 1),
        ])
        store.timeFilter = .yesterday
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "B")
    }

    func testThisWeekRange() {
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date())
        // 本周一 = daysAgo = todayWeekday - 2 (假设周一=2)
        let daysSinceMonday = (todayWeekday - cal.firstWeekday + 7) % 7
        let lastMondayOffset = daysSinceMonday + 7

        store = makeStoreWithItems([
            ("A", .text, nil, false, daysSinceMonday),          // 本周一
            ("B", .text, nil, false, lastMondayOffset + 3),     // 上周
        ])
        store.timeFilter = .thisWeek
        XCTAssertTrue(store.filteredItems.contains { $0.content == "A" })
        XCTAssertFalse(store.filteredItems.contains { $0.content == "B" })
    }

    func testLastWeekExcludesThisWeek() {
        let cal = Calendar.current
        let todayWeekday = cal.component(.weekday, from: Date())
        let daysSinceMonday = (todayWeekday - cal.firstWeekday + 7) % 7
        let lastMondayOffset = daysSinceMonday + 7

        store = makeStoreWithItems([
            ("A", .text, nil, false, lastMondayOffset),         // 上周一
            ("B", .text, nil, false, daysSinceMonday),          // 本周一
        ])
        store.timeFilter = .lastWeek
        XCTAssertTrue(store.filteredItems.contains { $0.content == "A" })
        XCTAssertFalse(store.filteredItems.contains { $0.content == "B" })
    }

    func testTodayExcludesYesterday() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 1),
            ("B", .text, nil, false, 0),
        ])
        store.timeFilter = .today
        XCTAssertEqual(store.filteredItems.count, 1)
        XCTAssertEqual(store.filteredItems[0].content, "B")
    }

    func testLast30DaysIncludesNow() {
        store = makeStoreWithItems([
            ("A", .text, nil, false, 0),    // now
            ("B", .text, nil, false, 10),   // 10 天前
            ("C", .text, nil, false, 35),   // 35 天前
        ])
        store.timeFilter = .last30Days
        XCTAssertEqual(store.filteredItems.count, 2)
        XCTAssertTrue(store.filteredItems.contains { $0.content == "A" })
        XCTAssertTrue(store.filteredItems.contains { $0.content == "B" })
        XCTAssertFalse(store.filteredItems.contains { $0.content == "C" })
    }

    // MARK: - TimeFilter.label 本地化覆盖

    /// 所有时间筛选项都有非空标签
    func testTimeFilterAllLabelsNonEmpty() {
        for tf in StoreManager.TimeFilter.allCases {
            XCTAssertFalse(
                tf.label.isEmpty,
                "TimeFilter.\(tf) 的标签不应为空"
            )
        }
    }

    /// 所有时间筛选项标签互不相同
    func testTimeFilterLabelsAreUnique() {
        let labels = Set(StoreManager.TimeFilter.allCases.map { $0.label })
        XCTAssertEqual(
            labels.count,
            StoreManager.TimeFilter.allCases.count,
            "每个时间筛选项的标签应唯一"
        )
    }
}
