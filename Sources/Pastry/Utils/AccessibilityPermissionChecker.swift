import ApplicationServices
import AppKit
import Foundation

protocol AccessibilityPermissionChecking {
    func isTrusted(prompt: Bool) -> Bool
}

struct SystemAccessibilityPermissionChecker: AccessibilityPermissionChecking {
    func isTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}

struct AccessibilityPermissionChecker {
    static let shared = AccessibilityPermissionChecker(checker: SystemAccessibilityPermissionChecker())

    let checker: AccessibilityPermissionChecking

    func isTrusted(prompt: Bool = false) -> Bool {
        checker.isTrusted(prompt: prompt)
    }

    /// 粘贴前确保已获辅助功能授权。
    ///
    /// - 已授权：直接返回 `true`（不弹窗）。
    /// - 未授权：以 `prompt: true` 触发系统授权对话框（`CGEventSource`/`postToPid`
    ///   在 macOS 上可能静默失败、不会自行弹窗，故必须主动请求）。
    /// - 用户未授权则返回 `false`，调用方应中止粘贴并保持面板可见。
    func requestTrustedForPaste() -> Bool {
        if isTrusted(prompt: false) { return true }
        return isTrusted(prompt: true)
    }

    /// 打开系统「隐私与安全性 → 辅助功能」设置页。
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
