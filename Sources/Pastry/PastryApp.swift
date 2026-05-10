import SwiftUI
import OSLog
import ServiceManagement

// MARK: - 应用委托
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 静态引用 — 避免依赖 NSApp.delegate 的时机不确定性
    nonisolated(unsafe) static private(set) weak var shared: AppDelegate?

    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var helpWindow: NSWindow?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: - NSApplicationDelegate

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 替换系统"关于"菜单项 → 自定义 About 窗口
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu {
            if let aboutItem = appMenu.items.first(where: {
                $0.action == #selector(NSApplication.orderFrontStandardAboutPanel(_:))
            }) {
                aboutItem.action = #selector(showAboutWindow)
                aboutItem.target = self
            }

            // 替换"设置…"（⌘,）→ 自定义设置窗口
            if let prefsItem = appMenu.items.first(where: { $0.keyEquivalent == "," }) {
                prefsItem.action = #selector(openSettingsWindow)
                prefsItem.target = self
            }

            // 替换"帮助"菜单项 → 自定义 Help 窗口
            if let helpMenu = NSApp.mainMenu?.items.last(where: { $0.title == L10n["menu.help"] })?.submenu {
                if let helpItem = helpMenu.items.first {
                    helpItem.action = #selector(showHelpWindow)
                    helpItem.target = self
                }
            }
        }

        // 初次启动：写入常见密码管理器的默认排除名单
        seedDefaultExcludedApps()
    }

    @MainActor
    @objc func openSettingsWindow() {
        // 先关闭面板，否则面板层级高于设置窗口会遮挡
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        let appName = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Pastry"
        window.title = appName
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsSceneView())

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        delegate.selfRetain()
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    @objc func showAboutWindow() {
        if let existing = aboutWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(L10n["menu.about"]) Pastry"
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AboutView())

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        delegate.selfRetain()
        aboutWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @MainActor
    @objc private func showHelpWindow() {
        if let existing = helpWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let savedPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 380),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n["menu.help"]
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HelpView())

        let delegate = SettingsWindowDelegate(savedPolicy: savedPolicy)
        window.delegate = delegate
        delegate.selfRetain()
        helpWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 默认排除名单

    /// 初次启动时，检测已安装的常见密码管理器，写入排除名单。
    /// 未安装的应用不写入，避免在设置界面显示无效条目。
    private func seedDefaultExcludedApps() {
        let seededKey = "excluded_apps_seeded"
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        UserDefaults.standard.set(true, forKey: seededKey)

        let candidates: [String] = [
            "com.1password.1password",           // 1Password
            "com.bitwarden.desktop",             // Bitwarden
            "com.apple.keychainaccess",           // 钥匙串访问
            "org.keepassxc.keepassxc",            // KeePassXC
            "com.lastpass.lastpass",              // LastPass
            "com.dashlane.dashlane",              // Dashlane
            "com.agilebits.onepassword7",        // 1Password 7
        ]

        let installed = candidates.filter { id in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                return false
            }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }

        guard !installed.isEmpty else { return }

        var current = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        for id in installed where !current.contains(id) {
            current.append(id)
        }
        UserDefaults.standard.set(current, forKey: UserDefaultsKeys.excludedBundleIDs)

        let joined = installed.joined(separator: ", ")
        Logger(subsystem: "com.nekutai.pastry", category: "app")
            .info("默认排除名单已写入: \(joined)")
    }
}

// 关闭设置时恢复后台模式
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    let savedPolicy: NSApplication.ActivationPolicy
    private var selfReference: SettingsWindowDelegate?

    init(savedPolicy: NSApplication.ActivationPolicy) {
        self.savedPolicy = savedPolicy
    }

    func selfRetain() { selfReference = self }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(savedPolicy)
        selfReference = nil
    }
}

// MARK: - 应用入口
@main
struct PastryApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @StateObject private var store = StoreManager.shared

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    private let log = Logger(subsystem: "com.nekutai.pastry", category: "app")

    /// 性能基准模式：`Pastry --bench` 跑完初始化输出耗时后退出
    private static let isBenchmark = CommandLine.arguments.contains("--bench")

    init() {
        let benchStart = Self.isBenchmark ? CFAbsoluteTimeGetCurrent() : 0

        store.start()

        if Self.isBenchmark {
            let elapsed = Int((CFAbsoluteTimeGetCurrent() - benchStart) * 1000)
            print("启动耗时: \(elapsed)ms")
            exit(0)
        }

        GlobalHotkeyManager.shared.register()
        MenuBarManager.shared.setup()

        log.info("Pastry 初始化完成")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
