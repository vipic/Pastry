import SwiftUI
import AppKit
import Carbon

// MARK: - Shortcut Tab

extension SettingsSceneView {
    // MARK: - 快捷键 Tab

    var shortcutTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsPaneHeader(
                title: L10n["settings.tab.shortcut"],
                subtitle: L10n["settings.shortcut.subtitle"]
            )

            shortcutHero

            settingsSection(title: L10n["shortcut.section_title"]) {
                settingsRow(
                    title: L10n["shortcut.overlay_shortcut"],
                    help: L10n["shortcut.applies_immediately"]
                ) {
                    Button {
                        shortcutPreviewKeyCode = nil
                        shortcutPreviewModifiers = 0
                        isRecordingShortcut = true
                    } label: {
                        Text(isRecordingShortcut ? L10n["hotkey.recording"] : L10n["shortcut.record_button"])
                            .frame(minWidth: 54)
                    }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(isRecordingShortcut)
                    .opacity(isRecordingShortcut ? 0.72 : 1)
                }

                ShortcutCaptureView(
                    isRecording: $isRecordingShortcut,
                    keyCode: $hotkeyKeyCode,
                    modifiers: $hotkeyModifiers,
                    onPreview: { keyCode, modifiers in
                        shortcutPreviewKeyCode = keyCode
                        shortcutPreviewModifiers = modifiers
                    },
                    onChange: {
                        GlobalHotkeyManager.shared.reregister()
                    },
                    onStartRecording: {
                        GlobalHotkeyManager.shared.unregister()
                    },
                    onCancelRecording: {
                        shortcutPreviewKeyCode = nil
                        shortcutPreviewModifiers = 0
                        GlobalHotkeyManager.shared.reregister()
                    }
                )
                .frame(width: 0, height: 0)
                .opacity(0.01)
                .accessibilityHidden(true)

                settingsDivider

                settingsRow(
                    title: L10n["shortcut.clear_shortcut"],
                    help: L10n["shortcut.clear_hint"]
                ) {
                    Button(L10n["shortcut.clear_button"]) {
                        clearShortcut()
                    }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer()
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var shortcutHero: some View {
        HStack {
            Spacer()
            HStack(spacing: 12) {
                ForEach(Array(shortcutHeroSegments.enumerated()), id: \.offset) { _, segment in
                    shortcutKeycap(segment)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                            .stroke(SettingsPalette.ink.opacity(0.14), lineWidth: UIConstants.Stroke.hairline)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 142)
        .settingsCardChrome(cornerRadius: UIConstants.Radius.cardLarge, fill: SettingsPalette.cardFillSoft)
    }

    func shortcutKeycap(_ segment: String) -> some View {
        Text(segment)
            .font(.system(size: UIConstants.TypeSize.title, weight: .bold, design: .rounded))
            .foregroundStyle(SettingsPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, segment.count > 1 ? 8 : 0)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                    // Physical keycap: top-lit face + raised edge, not flat chip chrome.
                    .fill(
                        LinearGradient(
                            colors: [
                                .white,
                                PastryPalette.keycapBottom
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                            .stroke(SettingsPalette.ink.opacity(0.14), lineWidth: UIConstants.Stroke.hairline)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.control, style: .continuous)
                            .stroke(.white.opacity(0.70), lineWidth: UIConstants.Stroke.hairline)
                            .padding(1)
                    )
                    .shadow(color: SettingsPalette.ink.opacity(0.12), radius: 0, x: 0, y: 2)
            )
    }

    var shortcutHeroSegments: [String] {
        if isRecordingShortcut {
            let preview = shortcutDisplayPreviewSegments(
                keyCode: shortcutPreviewKeyCode,
                modifiers: shortcutPreviewModifiers
            )
            return preview.isEmpty ? ["…"] : preview
        }
        guard hotkeyKeyCode >= 0 else {
            return ["--"]
        }
        return shortcutDisplaySegments(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    func clearShortcut() {
        hotkeyKeyCode = -1
        hotkeyModifiers = 0
        isRecordingShortcut = false
        shortcutPreviewKeyCode = nil
        shortcutPreviewModifiers = 0
        GlobalHotkeyManager.shared.reregister()
    }
}
