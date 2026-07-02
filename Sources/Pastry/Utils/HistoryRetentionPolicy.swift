import Foundation
import OSLog

struct HistoryRetentionPolicy: Equatable {
    private static let log = Logger(subsystem: "com.nekutai.pastry", category: "retention")
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
        if maxItemsOptions.contains(value) { return value }
        if value > 0 {
            log.warning("无效的 historyMaxItems 值 \(value)，已重置为默认值 \(defaultMaxItems)")
        }
        return defaultMaxItems
    }

    static func sanitizedMaxAgeDays(_ value: Int) -> Int {
        if maxAgeDayOptions.contains(value) { return value }
        if value > 0 {
            log.warning("无效的 historyMaxAgeDays 值 \(value)，已重置为默认值 \(defaultMaxAgeDays)")
        }
        return defaultMaxAgeDays
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

    static func maxAgeMetricLabel(_ days: Int) -> String {
        switch days {
        case 0: return L10n["settings.history.age_metric_never"]
        case 365: return L10n["settings.history.age_metric_one_year"]
        default: return L10n["settings.history.age_metric_days", days]
        }
    }
}
