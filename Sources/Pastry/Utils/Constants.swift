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
    static let launchAtLogin = "launch_at_login"
    static let soundEnabled = "sound_enabled"
    static let hotkeyKeyCode = "hotkey_keycode"
    static let hotkeyModifiers = "hotkey_modifiers"
    static let excludedBundleIDs = "excluded_bundle_ids"
    static let linkPreviewNetworkEnabled = "link_preview_network_enabled"
}

// MARK: - 颜色

extension Color {
    static let clipBackground = Color(nsColor: NSColor.windowBackgroundColor)
    static let clipRowHover = Color(nsColor: NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3))
    static let clipAccent = Color.accentColor
}
