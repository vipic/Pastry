enum AccessibilityIdentifiers {
    enum Overlay {
        static let root = "overlay.root"
        static let cardContainer = "overlay.card-container"
        static let searchButton = "overlay.search-button"
        static let searchField = "overlay.search-field"
        static let clearSearchButton = "overlay.clear-search-button"
        static let filterButton = "overlay.filter-button"
        static let allTab = "overlay.tab.all"
        static let pinnedTab = "overlay.tab.pinned"
        static let settingsButton = "overlay.settings-button"
        static let emptyState = "overlay.empty-state"
        static func card(_ id: String) -> String { "overlay.card.\(id)" }
    }

    enum Settings {
        static let root = "settings.root"
        static let sidebar = "settings.sidebar"
        static let languagePicker = "settings.language-picker"
        static let launchAtLoginToggle = "settings.launch-at-login-toggle"
        static let soundToggle = "settings.sound-toggle"
        static let linkPreviewNetworkToggle = "settings.link-preview-network-toggle"
        static let performanceLoggingToggle = "settings.performance-logging-toggle"
        static let clearAllButton = "settings.clear-all-button"
        static let accessibilityRow = "settings.accessibility-row"
        static let accessibilityGrantButton = "settings.accessibility-grant-button"
        static let excludedAddButton = "settings.excluded-add-button"
    }
}
