import ApplicationServices
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
}
