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

    // MARK: - 左键点击模式

    func testCardClickModeDefaultsToEnhanced() {
        XCTAssertEqual(CardClickMode.default, .enhanced)
        XCTAssertEqual(CardClickMode.resolved(stored: nil), .enhanced)
        XCTAssertEqual(CardClickMode.resolved(stored: "bogus"), .enhanced)
        XCTAssertEqual(CardClickMode.resolved(stored: "speed"), .speed)
    }

    func testEnhancedModeClickMatrix() {
        // 单击 → 选中；双击 → 粘贴
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .enhanced, isDoubleClick: false, commandOrShift: false
            ),
            .select
        )
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .enhanced, isDoubleClick: true, commandOrShift: false
            ),
            .paste
        )
    }

    func testSpeedModeClickMatrix() {
        // 单击 → 粘贴；双击 → 忽略
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .speed, isDoubleClick: false, commandOrShift: false
            ),
            .paste
        )
        XCTAssertEqual(
            OverlayInteractionModel.cardClickAction(
                mode: .speed, isDoubleClick: true, commandOrShift: false
            ),
            .ignore
        )
    }

    func testCardClickModifiersAlwaysSelectInBothModes() {
        for mode in CardClickMode.allCases {
            for isDouble in [false, true] {
                XCTAssertEqual(
                    OverlayInteractionModel.cardClickAction(
                        mode: mode, isDoubleClick: isDouble, commandOrShift: true
                    ),
                    .select,
                    "⌘/⇧ 在 \(mode) 模式双击=\(isDouble) 时应多选"
                )
            }
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

    func testSearchCountWidthReserveKeepsStableDigitSlots() {
        // 10→9 时两侧仍按最大位数预留，避免徽标变窄
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 10, totalCount: 10),
            "00/00"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 9, totalCount: 10),
            "00/00"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountDisplayText(filteredCount: 9, totalCount: 10),
            "9/10"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 0, totalCount: 0),
            "0/0"
        )
        XCTAssertEqual(
            OverlayInteractionModel.searchCountWidthReserveText(filteredCount: 3, totalCount: 100),
            "000/000"
        )
    }

    func testShouldReselectFirstWhenVisibleIdsChange() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        XCTAssertTrue(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [a, b, c],
                newIds: [b, c]
            ),
            "删除后列表 ID 变化应重新选中第一张"
        )
        XCTAssertTrue(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [a, b, c],
                newIds: [a, c]
            ),
            "搜索/筛选结果变化应重新选中第一张"
        )
        XCTAssertFalse(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [a, b, c],
                newIds: [a, b, c]
            ),
            "ID 序列不变时不应打断当前键盘选择"
        )
        XCTAssertTrue(
            OverlayInteractionModel.shouldReselectFirstAfterVisibleIdsChange(
                oldIds: [],
                newIds: [a]
            )
        )
    }

    func testCommandBadgeIndexOnlyForFirstNineWhileCmdDown() {
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: false, itemIndex: 0))
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 0), 1)
        XCTAssertEqual(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 8), 9)
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: 9))
        XCTAssertNil(OverlayInteractionModel.commandBadgeIndex(cmdDown: true, itemIndex: -1))
    }

    // MARK: - 横向卡带滚轮策略

    func testPreferredCardStripDeltaUsesHorizontalAxis() {
        let delta = OverlayInteractionModel.preferredCardStripDelta(
            horizontalCandidates: [0, 3.5, -0.01],
            verticalCandidates: [100]
        )
        XCTAssertEqual(delta, 3.5)
    }

    func testPreferredCardStripDeltaIgnoresVerticalOnly() {
        let delta = OverlayInteractionModel.preferredCardStripDelta(
            horizontalCandidates: [0, 0.005],
            verticalCandidates: [12, -8]
        )
        XCTAssertNil(delta, "仅有竖轴位移时不得映射为卡带滚动")
    }

    func testPreferredCardStripDeltaPicksLargestAbsHorizontal() {
        let delta = OverlayInteractionModel.preferredCardStripDelta(
            horizontalCandidates: [2, -9, 4],
            verticalCandidates: []
        )
        XCTAssertEqual(delta, -9)
    }

    // MARK: - 卡带视口步进（与选中无关）

    func testConsumeStripScrollStepsAccumulatesAcrossEvents() {
        var acc: CGFloat = 0
        XCTAssertEqual(
            OverlayInteractionModel.consumeStripScrollSteps(accumulator: &acc, delta: -2),
            0
        )
        XCTAssertEqual(
            OverlayInteractionModel.consumeStripScrollSteps(accumulator: &acc, delta: -3),
            1,
            "累计越过 threshold 才步进"
        )
    }

    func testAdvanceStripScrollIndexContinuesPastPreviousSelection() {
        // 选中第 2 张后，视口已滚到 3；再滚应到 4，而不是又从 2 起算
        let first = OverlayInteractionModel.advanceStripScrollIndex(
            current: 2, steps: 1, itemCount: 10
        )
        XCTAssertEqual(first.index, 3)
        XCTAssertFalse(first.hitEdge)

        let second = OverlayInteractionModel.advanceStripScrollIndex(
            current: first.index, steps: 1, itemCount: 10
        )
        XCTAssertEqual(second.index, 4, "连续侧滚必须基于 strip 索引，不能重置到选中位")
        XCTAssertFalse(second.hitEdge)
    }

    func testAdvanceStripScrollIndexHitsEdge() {
        let result = OverlayInteractionModel.advanceStripScrollIndex(
            current: 9, steps: 1, itemCount: 10
        )
        XCTAssertEqual(result.index, 9)
        XCTAssertTrue(result.hitEdge)
    }

    func testAdvanceStripScrollIndexEmptyList() {
        let result = OverlayInteractionModel.advanceStripScrollIndex(
            current: 3, steps: 1, itemCount: 0
        )
        XCTAssertEqual(result.index, 0)
        XCTAssertFalse(result.hitEdge)
    }

    func testKeyboardEdgeGlowDirectionFromDelta() {
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forKeyboardDelta: 1),
            true,
            "向右/向后撞边 → trailing"
        )
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forKeyboardDelta: -1),
            false,
            "向左/向前撞边 → leading"
        )
        XCTAssertNil(OverlayInteractionModel.stripEdgeTowardHigherIndex(forKeyboardDelta: 0))
    }

    func testKeyboardEdgeGlowDirectionFromHomeEnd() {
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forAbsoluteTarget: 0, itemCount: 10),
            false,
            "Home 撞边 → leading"
        )
        XCTAssertEqual(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forAbsoluteTarget: 9, itemCount: 10),
            true,
            "End 撞边 → trailing"
        )
        XCTAssertNil(
            OverlayInteractionModel.stripEdgeTowardHigherIndex(forAbsoluteTarget: 0, itemCount: 0)
        )
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
