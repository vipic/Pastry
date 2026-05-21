import Foundation

struct HistoryRetentionPolicy: Equatable {
    static let defaultMaxItems = 1_000
    static let defaultMaxAgeDays = 0
    static let maxItemsOptions = [100, 500, 1_000, 2_000, 5_000]
    static let maxAgeDayOptions = [0, 7, 30, 90, 365]

    let maxItems: Int
    let maxAgeDays: Int

    static var current: HistoryRetentionPolicy {
        HistoryRetentionPolicy(
            maxItems: sanitizedMaxItems(UserDefaults.standard.integer(forKey: UserDefaultsKeys.historyMaxItems)),
            maxAgeDays: sanitizedMaxAgeDays(UserDefaults.standard.integer(forKey: UserDefaultsKeys.historyMaxAgeDays))
        )
    }

    static func sanitizedMaxItems(_ value: Int) -> Int {
        maxItemsOptions.contains(value) ? value : defaultMaxItems
    }

    static func sanitizedMaxAgeDays(_ value: Int) -> Int {
        maxAgeDayOptions.contains(value) ? value : defaultMaxAgeDays
    }

    static func maxItemsLabel(_ value: Int) -> String {
        L10n["settings.history.max_items_value", value]
    }

    static func maxAgeLabel(_ days: Int) -> String {
        switch days {
        case 0: return L10n["settings.history.age_never"]
        case 365: return L10n["settings.history.age_one_year"]
        default: return L10n["settings.history.age_days", days]
        }
    }
}
