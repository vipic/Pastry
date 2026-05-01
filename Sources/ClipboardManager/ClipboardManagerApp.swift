import SwiftUI
import OSLog
import ServiceManagement

// MARK: - 应用入口
@main
struct ClipboardManagerApp: App {

    @StateObject private var store = StoreManager.shared

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    private let log = Logger(subsystem: "com.clipboardmanager", category: "app")

    /// 设置窗口引用，避免重复创建
    @State private var settingsWindow: NSWindow?

    init() {
        // 同步 UserDefaults 中的设置与实际的登录项状态
        let isRegistered = SMAppService.mainApp.status == .enabled
        if launchAtLogin != isRegistered {
            launchAtLogin = isRegistered
        }

        // 🚀 立即启动剪贴板监听 + 注册全局快捷键 (⌘⇧V)
        store.start()
        GlobalHotkeyManager.shared.register()
        log.info("ClipboardManager 初始化，开机启动: \(isRegistered)")
    }

    var body: some Scene {
        // MARK: 菜单栏 (传统菜单风格)
        MenuBarExtra {
            menuItems
        } label: {
            Image(systemName: "clipboard")
        }
    }

    // MARK: - 菜单项

    private var menuItems: some View {
        Group {
            // 打开剪贴板覆盖层
            Button {
                OverlayPanelManager.shared.toggle()
            } label: {
                Label("打开剪贴板", systemImage: "rectangle.on.rectangle")
            }

            Divider()

            // 快速统计
            Text("共 \(store.stats.totalItems) 项 · 今日 \(store.stats.todayItems) 项")
                .font(.caption)
                .foregroundColor(.secondary)

            if store.stats.storageSizeKB > 0 {
                Text("占用 \(store.stats.storageSizeKB) KB")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            Button {
                store.clearHistory()
            } label: {
                Label("清空历史", systemImage: "trash")
            }
            .disabled(store.stats.totalItems == 0)

            Divider()

            // 设置 - 打开独立设置窗口
            Button {
                openSettingsWindow()
            } label: {
                Label("设置…", systemImage: "gearshape")
            }

            Divider()

            Button {
                OverlayPanelManager.shared.hide()
                GlobalHotkeyManager.shared.unregister()
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
        }
    }

    // MARK: - 设置窗口

    private func openSettingsWindow() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // 设置窗口需要激活 App 才能显示在最前
        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "设置"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsSceneView())
        window.makeKeyAndOrderFront(nil)
        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        // delegate 通过 selfRetain 保持自身存活（window.delegate 是 weak）
        delegate.selfRetain()

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }
}

// 关闭设置时恢复原来的激活策略（后台模式）
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    let savedPolicy: NSApplication.ActivationPolicy
    private var selfReference: SettingsWindowDelegate?

    init(savedPolicy: NSApplication.ActivationPolicy) {
        self.savedPolicy = savedPolicy
    }

    /// 用强引用保持自身存活（window.delegate 是 weak 属性）
    func selfRetain() {
        selfReference = self
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(savedPolicy)
        selfReference = nil  // 窗口关闭后释放自身
    }
}

// MARK: - 设置场景视图
struct SettingsSceneView: View {

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    @AppStorage(UserDefaultsKeys.soundEnabled)
    private var soundEnabled = false

    @AppStorage(UserDefaultsKeys.maxHistory)
    private var maxHistory = 500

    @State private var showingClearConfirm = false
    @State private var accessibilityTrusted = false

    var body: some View {
        Form {
            Section("通用") {
                Toggle("开机启动", isOn: $launchAtLogin)
                Toggle("复制提示音", isOn: $soundEnabled)
            }

            Section("权限") {
                accessibilityStatusView
            }

            Section("存储") {
                Stepper("最大历史: \(maxHistory) 条",
                        value: $maxHistory, in: 100...2000, step: 100)
            }

            Section("管理") {
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
        .frame(width: 380, height: 360)
        .onAppear {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            accessibilityTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }

    // MARK: - 辅助功能权限状态

    @ViewBuilder
    private var accessibilityStatusView: some View {
        HStack {
            Image(systemName: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(accessibilityTrusted ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessibilityTrusted ? "辅助功能权限：已授权 ✅" : "辅助功能权限：未授权 ⚠️")
                    .font(.body)
                Text(accessibilityTrusted
                     ? "模拟 ⌘V 粘贴功能可用"
                     : "粘贴功能需要此权限，授权后请重启应用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if !accessibilityTrusted {
                Button("去授权") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(.link)
                .help("打开系统设置 → 隐私与安全性 → 辅助功能")
            }
        }
    }
}
