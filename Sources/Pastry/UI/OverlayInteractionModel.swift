import Foundation

enum OverlayInteractionModel {
    static func hasActiveFilters(
        searchQuery: String,
        typeFilter: SourceFormat?,
        appFilter: String?,
        timeFilter: StoreManager.TimeFilter,
        urlFilter: Bool,
        handoffFilter: Bool
    ) -> Bool {
        !searchQuery.isEmpty
            || typeFilter != nil
            || appFilter != nil
            || timeFilter != .any
            || urlFilter
            || handoffFilter
    }

    static func selectedItems(
        visibleItems: [ClipboardItem],
        selectedIds: Set<UUID>
    ) -> [ClipboardItem] {
        visibleItems.filter { selectedIds.contains($0.id) }
    }

    static func commandBadgeIndex(cmdDown: Bool, itemIndex: Int) -> Int? {
        guard cmdDown, itemIndex >= 0, itemIndex < 9 else { return nil }
        return itemIndex + 1
    }

    // MARK: - 鼠标多选（可单测的点击管线）

    /// 合并「当前点击事件」与「mouseDown monitor」两路修饰键。
    static func resolveCardTapModifiers(
        eventCommand: Bool,
        eventShift: Bool,
        monitoredCommand: Bool,
        monitoredShift: Bool
    ) -> (cmdDown: Bool, shiftDown: Bool) {
        (
            eventCommand || monitoredCommand,
            eventShift || monitoredShift
        )
    }

    /// 卡片单击完整管线：解析修饰键 → SelectionState.handleTap。
    /// OverlayView 与单测共用，避免 UI 层手误绕过逻辑。
    static func applyCardClick(
        selection: inout SelectionState,
        item: ClipboardItem,
        eventCommand: Bool,
        eventShift: Bool,
        monitoredCommand: Bool,
        monitoredShift: Bool,
        visibleItems: [ClipboardItem]
    ) {
        let mods = resolveCardTapModifiers(
            eventCommand: eventCommand,
            eventShift: eventShift,
            monitoredCommand: monitoredCommand,
            monitoredShift: monitoredShift
        )
        selection.handleTap(
            item: item,
            cmdDown: mods.cmdDown,
            shiftDown: mods.shiftDown,
            visibleItems: visibleItems
        )
    }

    /// 托盘空白点击是否应清空选择。
    ///
    /// 产品约定：空白 `onTapGesture` 清空；**绝不能**与卡片点击用
    /// `simultaneousGesture` 绑在一起——否则 ⌘/⇧ 多选会在同一击被 reset。
    /// 子视图吃掉卡片手势时，父级 `onTapGesture` 不会触发（这是正确路径）。
    static func shouldClearSelectionOnTrayBackgroundTap(
        cardClickHandledThisEvent: Bool
    ) -> Bool {
        !cardClickHandledThisEvent
    }
}
