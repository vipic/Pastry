import SwiftUI
import OSLog

// MARK: - 设置视图

struct SettingsSceneView: View {

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    @AppStorage(UserDefaultsKeys.soundEnabled)
    private var soundEnabled = false

    @AppStorage(UserDefaultsKeys.maxHistory)
    private var maxHistory = Constants.defaultMaxHistory
    @AppStorage(UserDefaultsKeys.cleanupMaxDays)
    private var cleanupMaxDays = Constants.defaultMaxDays
    @AppStorage(UserDefaultsKeys.cleanupMaxItems)
    private var cleanupMaxItems = Constants.defaultMaxItems

    // 快捷键
    @AppStorage(UserDefaultsKeys.hotkeyKeyCode)
    private var hotkeyKeyCode = Int(GlobalHotkeyManager.defaultKeyCode)
    @AppStorage(UserDefaultsKeys.hotkeyModifiers)
    private var hotkeyModifiers = Int(GlobalHotkeyManager.defaultModifiers)

    @State private var showingClearConfirm = false
    @State private var accessibilityTrusted = false
    @State private var selectedTab: SettingsTab? = .general

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general  = "通用"
        case shortcut = "快捷键"
        case storage  = "存储"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .shortcut: return "command"
            case .storage:  return "internaldrive"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
        } detail: {
            if let tab = selectedTab {
                detail(for: tab)
            }
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 520, minHeight: 380)
        .onAppear { refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    // MARK: - 详情内容

    @ViewBuilder
    private func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            Form {
                Section {
                    Toggle("开机启动", isOn: $launchAtLogin)
                    Toggle("复制提示音", isOn: $soundEnabled)
                }
                Section("辅助功能权限") {
                    HStack {
                        Image(systemName: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(accessibilityTrusted ? .green : .orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(accessibilityTrusted ? "已授权" : "未授权")
                                .font(.body)
                            Text(accessibilityTrusted
                                 ? "模拟 ⌘V 粘贴功能可用"
                                 : "粘贴功能需要此权限")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !accessibilityTrusted {
                            Button("去授权") {
                                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                                    Logger(subsystem: "com.nekutai.pastry", category: "settings").error("无法构造系统偏好设置 URL")
                                    return
                                }
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .padding(20)

        case .shortcut:
            shortcutTab

        case .storage:
            Form {
                Section("历史数量") {
                    Stepper("最大历史: \(maxHistory) 条",
                            value: $maxHistory, in: 100...2000, step: 100)
                }
                Section("自动清理") {
                    Stepper("保留天数: \(cleanupMaxDays) 天",
                            value: $cleanupMaxDays, in: 1...90, step: 1)
                    Text("超过此天数的记录将被自动删除")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Stepper("绝对上限: \(cleanupMaxItems) 条",
                            value: $cleanupMaxItems, in: 500...50000, step: 500)
                    Text("超过此数量的最旧记录将被裁剪")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("数据管理") {
                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Label("清空全部记录", systemImage: "trash")
                    }
                    .alert("确认清空？", isPresented: $showingClearConfirm) {
                        Button("取消", role: .cancel) {}
                        Button("清空", role: .destructive) {
                            StoreManager.shared.clearAll()
                        }
                    } message: {
                        Text("此操作不可撤销，所有剪贴板历史将被删除。")
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)
        }
    }

    // MARK: - 快捷键 Tab

    private var shortcutTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("唤醒快捷键")
                            .font(.body)
                        Spacer()

                        HotkeyRecorderView(
                            keyCode: $hotkeyKeyCode,
                            modifiers: $hotkeyModifiers,
                            onChange: {
                                GlobalHotkeyManager.shared.reregister()
                            },
                            onStartRecording: {
                                GlobalHotkeyManager.shared.unregister()
                            },
                            onCancelRecording: {
                                GlobalHotkeyManager.shared.reregister()
                            }
                        )
                        .frame(width: 160, height: 28)
                    }

                    Text(hotkeyKeyCode >= 0
                         ? "按下此快捷键可随时唤起 Pastry 面板"
                         : "点击方框录制新快捷键")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("修改后立即生效，无需重启")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("全局快捷键")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func refreshAccessibilityStatus() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
