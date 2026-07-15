import SwiftUI

// MARK: - File-local layout (not shared design tokens)
private enum Local {
    enum About {
        static let chevronWidth: CGFloat = 16
        static let columnSpacing: CGFloat = 16
        static let contentPadding: CGFloat = 20
        static let rowSpacing: CGFloat = 8
    }
}

// MARK: - 帮助窗口
struct HelpView: View {
    @State private var selectedTopic: HelpTopic? = .shortcuts

    enum HelpTopic: String, CaseIterable, Identifiable {
        case shortcuts = "help.tab.shortcuts"
        case usage = "help.tab.usage"
        case tips = "help.tab.tips"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .shortcuts: return "command"
            case .usage: return "hand.point.up.left"
            case .tips: return "lightbulb"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selectedTopic) { topic in
                Label(L10n[topic.rawValue], systemImage: topic.icon)
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 140)
        } detail: {
            if let topic = selectedTopic {
                detailView(for: topic)
            }
        }
    }

    @ViewBuilder
    private func detailView(for topic: HelpTopic) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch topic {
                case .shortcuts: shortcutsContent
                case .usage: usageContent
                case .tips: tipsContent
                }
            }
            .padding(Local.About.contentPadding)
        }
    }

    // MARK: - 快捷键

    private var shortcutsContent: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: Local.About.columnSpacing) {
                sectionHeader(L10n["help.shortcuts.global"])
                shortcutRow("⌘ ⇧ V", L10n["help.shortcut.panel_toggle"])
                shortcutRow("⏎", L10n["help.shortcut.paste_selected"])
                shortcutRow("␣", L10n["help.shortcut.preview_cursor"])
                shortcutRow("⌘ C", L10n["help.shortcut.copy_selected"])
                shortcutRow("⌘ P", L10n["help.shortcut.toggle_favorite"])
                shortcutRow("⌫", L10n["help.shortcut.delete_selected"])
                shortcutRow("⌘ A", L10n["help.shortcut.select_all"])
                shortcutRow("⌘ F", L10n["help.shortcut.search"])
                shortcutRow("⎋", L10n["help.shortcut.close_panel"])
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: Local.About.columnSpacing) {
                sectionHeader(L10n["help.shortcuts.panel"])
                shortcutRow("↑ ↓", L10n["help.shortcut.arrow_nav"])
                shortcutRow("⇧ ↑ ↓", L10n["help.shortcut.extend_selection"])
                shortcutRow("⌘ ← →", L10n["help.shortcut.horizontal_scroll"])
                shortcutRow(L10n["help.shortcut.command_click"], L10n["help.shortcut.toggle_select"])
                shortcutRow(L10n["help.shortcut.shift_click"], L10n["help.shortcut.range_select"])
                shortcutRow("⌘ 1-9", L10n["help.shortcut.quick_paste"])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 基本用法

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: Local.About.columnSpacing) {
            sectionHeader(L10n["help.usage.capture"])
            Text(L10n["help.usage.capture_desc"])
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundColor(.secondary)
                .lineSpacing(4)

            sectionHeader(L10n["help.usage.paste"])
            Text(L10n["help.usage.paste_desc"])
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundColor(.secondary)
                .lineSpacing(4)

            sectionHeader(L10n["help.usage.manage"])
            Text(L10n["help.usage.manage_desc"])
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundColor(.secondary)
                .lineSpacing(4)

            sectionHeader(L10n["help.usage.filter"])
            Text(L10n["help.usage.filter_desc"])
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }

    // MARK: - 小技巧

    private var tipsContent: some View {
        VStack(alignment: .leading, spacing: Local.About.columnSpacing) {
            tipRow(L10n["help.tip.drag_save"])
            tipRow(L10n["help.tip.batch_pin"])
            tipRow(L10n["help.tip.handoff"])
            tipRow(L10n["help.tip.link_preview"])
            tipRow(L10n["help.tip.language"])
            tipRow(L10n["help.tip.quicklook"])
        }
    }

    // MARK: - 辅助

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: UIConstants.TypeSize.callout, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.bottom, 4)
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: Local.About.rowSpacing) {
            Text(key)
                .font(.system(size: UIConstants.TypeSize.label, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: UIConstants.Radius.xs)
                        .fill(Color.primary.opacity(UIConstants.OnLight.fillSoft))
                )
            Text(desc)
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundColor(.secondary)
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Local.About.rowSpacing) {
            Image(systemName: "lightbulb")
                .font(.system(size: UIConstants.TypeSize.callout, weight: .medium))
                .foregroundColor(.secondary)
                .frame(width: Local.About.chevronWidth)
            Text(text)
                .font(.system(size: UIConstants.TypeSize.callout))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
}
