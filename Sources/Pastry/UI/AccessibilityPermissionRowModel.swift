import SwiftUI

struct AccessibilityPermissionRowModel: Equatable {
    let iconName: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let showsGrantButton: Bool

    static func resolve(isTrusted: Bool) -> AccessibilityPermissionRowModel {
        AccessibilityPermissionRowModel(
            iconName: isTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill",
            iconColor: isTrusted ? .green : .orange,
            title: isTrusted ? L10n["settings.accessibility_granted"] : L10n["settings.accessibility_denied"],
            subtitle: isTrusted ? L10n["settings.accessibility_paste_ok"] : L10n["settings.accessibility_paste_need"],
            showsGrantButton: !isTrusted
        )
    }
}
