import SwiftUI

// MARK: - 关于窗口
struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            // 应用图标
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 28)
                .padding(.bottom, 16)

            // 名称 + 版本
            Text("Pastry")
                .font(.system(size: 18, weight: .semibold))
            Text("Version \(appVersion) (Build \(appBuild))")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Divider()
                .padding(.vertical, 16)
                .padding(.horizontal, 40)

            // 描述
            Text(L10n["about.description"])
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)

            Spacer(minLength: 12)

            // 版权
            Text(L10n["about.copyright"])
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.bottom, 20)
        }
        .frame(width: 360, height: 340)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - 帮助窗口
struct HelpView: View {
    @State private var selectedTopic: HelpTopic = .shortcuts

    enum HelpTopic: String, CaseIterable, Identifiable {
        case shortcuts = "快捷键"
        case usage = "基本用法"
        case tips = "小技巧"

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
        HStack(spacing: 0) {
            // 侧边栏
            VStack(alignment: .leading, spacing: 2) {
                ForEach(HelpTopic.allCases) { topic in
                    Button {
                        selectedTopic = topic
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: topic.icon)
                                .frame(width: 16)
                            Text(topic.rawValue)
                                .font(.system(size: 12))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        selectedTopic == topic
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear
                    )
                    .cornerRadius(4)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 140)
            .background(Color.primary.opacity(0.04))

            Divider()

            // 内容
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTopic {
                    case .shortcuts: shortcutsContent
                    case .usage: usageContent
                    case .tips: tipsContent
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 520, height: 380)
    }

    // MARK: - 快捷键

    private var shortcutsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("全局快捷键")
            shortcutRow("⌘ ⇧ V", "打开 / 关闭剪贴板面板")
            shortcutRow("⏎", "粘贴选中的条目")
            shortcutRow("⌫", "删除选中的条目")
            shortcutRow("⌘ A", "全选")
            shortcutRow("⌘ F", "搜索")
            shortcutRow("⎋", "关闭面板 / 取消搜索")

            sectionHeader("面板内快捷键")
                .padding(.top, 12)
            shortcutRow("↑ ↓", "方向键导航")
            shortcutRow("⇧ ↑ ↓", "扩展选中范围")
            shortcutRow("⌘ ← →", "横向滚动卡片")
            shortcutRow("⌘ 单击", "切换卡片选中")
            shortcutRow("⇧ 单击", "区间选中")
            shortcutRow("⌘ 1-9", "快速粘贴第 1-9 条")
        }
    }

    // MARK: - 基本用法

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("捕获")
            Text("""
            Pastry 自动监听系统剪贴板。复制任何内容 — \
            文本、图片、文件、链接、HTML — 都会出现在面板中。
            """)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .lineSpacing(4)

            sectionHeader("粘贴")
            Text("""
            单击卡片直接粘贴到当前应用。
            双击或按 ⏎ 同理。
            按住 ⌘ 可在卡片右下角看到数字角标，按 ⌘+数字 快速粘贴。
            """)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .lineSpacing(4)

            sectionHeader("管理")
            Text("""
            右键卡片可钉选（pin）、预览、分享、删除。
            钉选的条目在「已钉选」标签页中始终可见，不受历史清理影响。
            """)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .lineSpacing(4)

            sectionHeader("筛选")
            Text("""
            搜索框支持实时过滤。筛选按钮可按类型（文本/链接/图片等）、\
            来源应用、时间范围筛选，多个条件可叠加。
            """)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .lineSpacing(4)
        }
    }

    // MARK: - 小技巧

    private var tipsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            tipRow("💡", "拖拽卡片到桌面或 Finder 可直接保存文件")
            tipRow("💡", "Cmd+点击多个卡片可批量 Pin 或删除")
            tipRow("💡", "从 iPhone/iPad 复制的内容会标记为 Handoff 来源")
            tipRow("💡", "链接卡片会自动抓取网页标题和缩略图")
            tipRow("💡", "在设置中可切换中英文界面，即时生效")
            tipRow("💡", "右键「预览」可用 Quick Look 查看文件内容")
        }
    }

    // MARK: - 辅助

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.bottom, 4)
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.08))
                )
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    private func tipRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(icon)
                .font(.system(size: 14))
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
}
