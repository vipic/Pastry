import Foundation

/// 类型安全的本地化字符串包装器。
/// 用法：L10n["settings.tab.general"] → 根据设置语言返回对应翻译
/// 语言切换立即生效，无需重启。
enum L10n {
    nonisolated(unsafe) private static var catalog: [String: [String: String]] = loadCatalog()

    private static func loadCatalog() -> [String: [String: String]] {
        // 1. deployed app: ~/Applications/Pastry.app/Contents/Resources/
        // 2. SPM dev: Pastry_Pastry.bundle
        let url: URL?
        if let mainURL = Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings") {
            url = mainURL
        } else {
            url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
        }

        guard let url,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let strings = json["strings"] as? [String: [String: Any]]
        else { return [:] }

        var catalog: [String: [String: String]] = [:]
        for (key, value) in strings {
            var localizations: [String: String] = [:]
            if let locs = value["localizations"] as? [String: [String: Any]] {
                for (lang, locValue) in locs {
                    if let unit = locValue["stringUnit"] as? [String: Any],
                       let val = unit["value"] as? String {
                        localizations[lang] = val
                    }
                }
            }
            catalog[key] = localizations
        }
        return catalog
    }

    static subscript(_ key: String) -> String {
        let lang = currentLanguage()
        if let localizations = catalog[key] {
            if let value = localizations[lang] {
                return value
            }
            // Fallback to zh-Hans (source language)
            if let value = localizations["zh-Hans"] {
                return value
            }
        }
        return key
    }

    private static func currentLanguage() -> String {
        if let lang = UserDefaults.standard.string(forKey: "PastryLanguage"), !lang.isEmpty {
            return lang
        }
        // Fallback to system language — use autoupdating locale
        // (Locale.preferredLanguages reads from AppleLanguages which may have stale overrides)
        if let code = Locale.autoupdatingCurrent.language.languageCode?.identifier {
            if code == "zh" { return "zh-Hans" }
        }
        return "en"
    }
}
