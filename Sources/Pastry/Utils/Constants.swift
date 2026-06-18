import Foundation
import SwiftUI

// MARK: - 应用常量

enum Constants {
    #if DEBUG
    static let appName = "Pastry Dev"
    #else
    static let appName = "Pastry"
    #endif
}

// MARK: - SF Symbols 封装

enum AppIcons {
    static let app = "clipboard"
    static let text = "text.alignleft"
    static let image = "photo"
    static let file = "folder"
    static let rtf = "doc.richtext"
    static let html = "chevron.left.forwardslash.chevron.right"
    static let search = "magnifyingglass"
    static let star = "star.fill"
    static let starEmpty = "star"
    static let paste = "arrow.right.doc.on.clipboard"
    static let delete = "trash"
    static let pin = "pin.fill"
    static let settings = "gearshape"
    static let clear = "clear"
    static let quit = "power"
}

// MARK: - UserDefaults Keys

enum UserDefaultsKeys {
    static let language = "PastryLanguage"
    static let launchAtLogin = "launch_at_login"
    static let soundEnabled = "sound_enabled"
    static let hotkeyKeyCode = "hotkey_keycode"
    static let hotkeyModifiers = "hotkey_modifiers"
    static let excludedBundleIDs = "excluded_bundle_ids"
    static let linkPreviewNetworkEnabled = "link_preview_network_enabled"
    static let historyMaxItems = "history_max_items"
    static let historyMaxAgeDays = "history_max_age_days"
    static let performanceLoggingEnabled = "performance_logging_enabled"
}

extension Notification.Name {
    static let pastryLanguageDidChange = Notification.Name("pastryLanguageDidChange")
}

// MARK: - 颜色

extension Color {
    static let clipBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let clipRowHover = Color(nsColor: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3))
    static let clipAccent = Color.accentColor
    static let pastryWarmAccent = Color(red: 0.741, green: 0.463, blue: 0.184)
    static let pastryWarmAccentTop = Color(red: 0.875, green: 0.667, blue: 0.345)
    static let pastryWarmAccentGradient = LinearGradient(
        colors: [.pastryWarmAccentTop, .pastryWarmAccent],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension NSColor {
    static let pastryWarmAccent = NSColor(calibratedRed: 0.741, green: 0.463, blue: 0.184, alpha: 1)
    static let pastryWarmAccentTop = NSColor(calibratedRed: 0.875, green: 0.667, blue: 0.345, alpha: 1)
}
