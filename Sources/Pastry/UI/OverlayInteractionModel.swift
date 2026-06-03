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
}
