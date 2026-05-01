import SwiftUI
import OSLog
import ServiceManagement

// MARK: - 应用委托
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: .openSettingsWindow, object: nil, queue: .main
        ) { [weak self] _ in
            self?.openSettingsWindow()
        }
    }

    func openSettingsWindow() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

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

    func selfRetain() {
        selfReference = self
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(savedPolicy)
        selfReference = nil
    }
}

// MARK: - 应用入口
@main
struct ClipboardManagerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @StateObject private var store = StoreManager.shared

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    private let log = Logger(subsystem: "com.clipboardmanager", category: "app")

    init() {
        let isRegistered = SMAppService.mainApp.status == .enabled
        if launchAtLogin != isRegistered {
            launchAtLogin = isRegistered
        }

        store.start()
        GlobalHotkeyManager.shared.register()
        MenuBarManager.shared.setup()

        log.info("Pastry 初始化，开机启动: \(isRegistered)")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
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
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    private func refreshAccessibilityStatus() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
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
