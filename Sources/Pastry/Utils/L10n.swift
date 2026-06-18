import Foundation

/// 类型安全的本地化字符串包装器。
/// 用法：L10n["settings.tab.general"] → 根据设置语言返回对应翻译
/// 语言切换立即生效，无需重启。
enum L10n {
    nonisolated(unsafe) private static var catalog: [String: [String: String]] = loadCatalog()

    private static func loadCatalog() -> [String: [String: String]] {
        let url = catalogURL()

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

    private static func catalogURL() -> URL? {
        // deploy.sh copies Localizable.xcstrings directly into Contents/Resources.
        if let mainURL = Bundle.main.url(forResource: "Localizable", withExtension: "xcstrings") {
            return mainURL
        }

        // release.sh copies the SwiftPM resource bundle into Contents/Resources.
        if let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("Pastry_Pastry.bundle")
            .appendingPathComponent("Localizable.xcstrings"),
           FileManager.default.fileExists(atPath: resourceURL.path) {
            return resourceURL
        }

        // SwiftPM development/test fallback. Access this last because Bundle.module
        // traps if the generated bundle cannot be found in a repackaged .app.
        return Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
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

    /// 参数化本地化字符串。占位符用 %@。
    /// 用法：L10n["toolbar.selected_count", selection.selectedIds.count]
    static subscript(_ key: String, _ args: CVarArg...) -> String {
        String(format: self[key], arguments: args)
    }

    static var currentLanguageIdentifier: String {
        currentLanguage()
    }

    private static func currentLanguage() -> String {
        if let lang = UserDefaults.standard.string(forKey: UserDefaultsKeys.language), !lang.isEmpty {
            return lang
        }
        // Fallback to system language — use autoupdating locale
        if let code = Locale.autoupdatingCurrent.language.languageCode?.identifier {
            if code.hasPrefix("zh") { return "zh-Hans" }
        }
        return "en"
    }

    /// 测试专用：强制重新加载 catalog（用于语言切换测试）
    static func reloadCatalogForTesting() {
        catalog = loadCatalog()
    }
}
