import XCTest
@testable import Pastry

/// 覆盖面板交互策略：鼠标多选管线、空白点击清空约定。
/// 用于防止「⌘/⇧ 多选被 simultaneous 空白手势 reset」这类回归。
final class OverlayInteractionModelTests: XCTestCase {

    private func makeItems(_ count: Int) -> [ClipboardItem] {
        (0..<count).map { i in
            ClipboardItem(
                timestamp: Date(),
                content: "item \(i)",
                sourceFormat: .text,
                appName: nil,
                isPinned: false
            )
        }
    }

    // MARK: - 修饰键解析

    func testResolveModifiersPrefersEventFlags() {
        let mods = OverlayInteractionModel.resolveCardTapModifiers(
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: true
        )
        XCTAssertTrue(mods.cmdDown)
        XCTAssertTrue(mods.shiftDown, "event 与 monitor 应 OR 合并")
    }

    func testResolveModifiersFallsBackToMonitor() {
        let mods = OverlayInteractionModel.resolveCardTapModifiers(
            eventCommand: false,
            eventShift: false,
            monitoredCommand: true,
            monitoredShift: true
        )
        XCTAssertTrue(mods.cmdDown)
        XCTAssertTrue(mods.shiftDown)
    }

    func testResolveModifiersNeitherPressed() {
        let mods = OverlayInteractionModel.resolveCardTapModifiers(
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false
        )
        XCTAssertFalse(mods.cmdDown)
        XCTAssertFalse(mods.shiftDown)
    }

    // MARK: - 过滤 / 选中列表 / ⌘ 角标

    func testHasActiveFiltersDetectsEachKind() {
        XCTAssertFalse(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "x",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: .image,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: "Safari",
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .today,
                urlFilter: false,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: true,
                handoffFilter: false
            )
        )
        XCTAssertTrue(
            OverlayInteractionModel.hasActiveFilters(
                searchQuery: "",
                typeFilter: nil,
                appFilter: nil,
                timeFilter: .any,
                urlFilter: false,
                handoffFilter: true
            )
        )
    }

    func testSelectedItemsPreservesVisibleOrder() {
        let items = makeItems(5)
        let selected = OverlayInteractionModel.selectedItems(
            visibleItems: items,
            selectedIds: [items[3].id, items[1].id]
        )
        XCTAssertEqual(selected.map(\.id), [items[1].id, items[3].id])
    }

    func testCommandBadgeIndexOnlyForFirstNineWhileCmdDown() {
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: false, itemIndex: 0))
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 0), 1)
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 8), 9)
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 9))
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: -1))
    }

    // MARK: - ⌘/⇧ 点击管线（与 SelectionState 组合）

    func testApplyCardClickCommandToggleMultiSelect() {
        var selection = SelectionState()
        let items = makeItems(5)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[2],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[4],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: true, // 仅 monitor 报 ⌘
            monitoredShift: false,
            visibleItems: items
        )

        XCTAssertEqual(
            selection.selectedIds,
            Set([items[0].id, items[2].id, items[4].id]),
            "连续 ⌘+点击应累积多选"
        )
    }

    func testApplyCardClickShiftRangeSelect() {
        var selection = SelectionState()
        let items = makeItems(6)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[1],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[4],
            eventCommand: false,
            eventShift: true,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )

        XCTAssertEqual(
            selection.selectedIds,
            Set([items[1].id, items[2].id, items[3].id, items[4].id])
        )
        XCTAssertEqual(selection.shiftAnchorIdx, 1)
    }

    func testApplyCardClickShiftUsesMonitorWhenEventFlagsMissing() {
        var selection = SelectionState()
        let items = makeItems(5)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[3],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: true,
            visibleItems: items
        )

        XCTAssertEqual(
            selection.selectedIds,
            Set([items[0].id, items[1].id, items[2].id, items[3].id]),
            "event 未带 ⇧ 时 monitor 应兜底区间选"
        )
    }

    // MARK: - 空白点击清空约定（防 simultaneous 回归）

    func testBackgroundClearOnlyWhenCardDidNotHandleClick() {
        XCTAssertTrue(
            OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
                cardClickHandledThisEvent: false
            ),
            "点空白应清空"
        )
        XCTAssertFalse(
            OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
                cardClickHandledThisEvent: true
            ),
            "卡片已处理的同一击不得再清空——simultaneousGesture + reset 会毁掉 ⌘/⇧ 多选"
        )
    }

    /// 回归：模拟「多选成功后同一击再 reset」会清空选择。
    /// UI 层必须用互斥的 onTapGesture（子视图吃掉卡片击），禁止 simultaneous reset。
    func testRegression_resetAfterCmdClickDestroysMultiSelect() {
        var selection = SelectionState()
        let items = makeItems(4)

        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[2],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        XCTAssertEqual(selection.selectedIds.count, 2)

        // 错误 UI：simultaneous 空白手势在同一击调用 reset
        if OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
            cardClickHandledThisEvent: false // 错误地当成空白
        ) {
            selection.reset()
        }
        XCTAssertTrue(
            selection.selectedIds.isEmpty,
            "证明：若把卡片击误判为空白并 reset，多选必丢——UI 不得 simultaneous reset"
        )

        // 正确路径：卡片击已处理 → 不 clear
        selection = SelectionState()
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[0],
            eventCommand: false,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        OverlayInteractionModel.applyCardClick(
            selection: &selection,
            item: items[2],
            eventCommand: true,
            eventShift: false,
            monitoredCommand: false,
            monitoredShift: false,
            visibleItems: items
        )
        if OverlayInteractionModel.shouldClearSelectionOnTrayBackgroundTap(
            cardClickHandledThisEvent: true
        ) {
            selection.reset()
        }
        XCTAssertEqual(selection.selectedIds.count, 2, "正确路径应保留 ⌘ 多选")
    }
}
