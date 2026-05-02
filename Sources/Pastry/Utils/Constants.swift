import Foundation
import SwiftUI

// MARK: - 应用常量

enum Constants {
    static let appName = "ClipboardManager"
    static let appVersion = "1.0.0"

    // 数据库
    static let maxHistoryItems = 500
    static let maxDaysToKeep = 7
    static let displayLimit = 100

    // 轮询
    static let pollInterval: TimeInterval = 0.5

    // UI
    static let popupWidth: CGFloat = 360
    static let popupHeight: CGFloat = 500
    static let rowHeight: CGFloat = 44
    static let maxPreviewChars = 150
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
    static let launchAtLogin = "launch_at_login"
    static let maxHistory = "max_history"
    static let pollInterval = "poll_interval"
    static let soundEnabled = "sound_enabled"
    static let cleanupMaxDays = "cleanup_max_days"
    static let cleanupMaxItems = "cleanup_max_items"
    static let hotkeyKeyCode = "hotkey_keycode"
    static let hotkeyModifiers = "hotkey_modifiers"
}

// MARK: - 颜色

extension Color {
    static let clipBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let clipRowHover = Color(nsColor: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3))
    static let clipAccent = Color.accentColor
}
