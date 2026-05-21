struct OverlayEmptyStateModel: Equatable {
    let icon: String
    let title: String
    let subtitle: String

    static func resolve(isPinnedTab: Bool, hasActiveFilters: Bool) -> OverlayEmptyStateModel {
        if isPinnedTab && !hasActiveFilters {
            return OverlayEmptyStateModel(
                icon: "pin.slash",
                title: L10n["empty.no_pins"],
                subtitle: L10n["empty.no_pins_hint"]
            )
        }
        if hasActiveFilters {
            return OverlayEmptyStateModel(
                icon: "magnifyingglass",
                title: L10n["empty.no_results"],
                subtitle: L10n["empty.no_results_hint"]
            )
        }
        return OverlayEmptyStateModel(
            icon: "clipboard",
            title: L10n["empty.no_history"],
            subtitle: L10n["empty.no_history_hint"]
        )
    }
}
