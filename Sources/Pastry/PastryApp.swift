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
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 完全接管系统菜单，避免 SwiftUI Settings 场景干扰
        buildAppMenu()
    }

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // app menu 已在 willFinishLaunching 中构建，无需再做
    }

    // MARK: - 系统菜单

    @MainActor
    private func buildAppMenu() {
        let mainMenu = NSMenu()

        // ── Pastry 菜单 ──
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 关于
        appMenu.addItem(withTitle: L10n["menu.about"],
                        action: #selector(showAboutWindow),
                        keyEquivalent: "").target = self

        appMenu.addItem(.separator())

        // 检查更新…
        appMenu.addItem(withTitle: L10n["menu.check_update"],
                        action: #selector(checkUpdateFromSystemMenu),
                        keyEquivalent: "").target = self

        appMenu.addItem(.separator())

        // 设置…
        let prefsItem = appMenu.addItem(withTitle: L10n["menu.settings"],
                                         action: #selector(openSettingsWindow),
                                         keyEquivalent: ",")
        prefsItem.target = self

        appMenu.addItem(.separator())

        // 服务
        let servicesMenu = NSMenu()
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())

        // 隐藏 / 隐藏其他 / 显示全部
        appMenu.addItem(withTitle: L10n["menu.hide_pastry"],
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")

        let hideOthersItem = appMenu.addItem(withTitle: L10n["menu.hide_others"],
                                              action: #selector(NSApplication.hideOtherApplications(_:)),
                                              keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(withTitle: L10n["menu.show_all"],
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")

        appMenu.addItem(.separator())

        // 退出
        appMenu.addItem(withTitle: L10n["menu.quit"],
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        NSApp.mainMenu = mainMenu
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

    // MARK: - 检查更新

    @MainActor
    @objc private func checkUpdateFromSystemMenu() {
        let progressWindow = UpdateWindow.showProgress()

        Task {
            let result = await UpdateChecker.shared.checkForUpdate(force: true)
            progressWindow.close()

            if let update = result {
                UpdateWindow.showUpdateAvailable(update) {
                    Task {
                        do {
                            let binaryURL = try await UpdateChecker.shared.downloadBinary(from: update.downloadURL)
                            try UpdateChecker.shared.applyUpdate(binaryAt: binaryURL)
                        } catch {
                            UpdateWindow.showError(error.localizedDescription)
                        }
                    }
                }
            } else {
                UpdateWindow.showUpToDate()
            }
        }
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
        // 不依赖 SwiftUI 的 Settings/WindowGroup — 菜单栏应用自己管理窗口和菜单
        _EmptyScene()
    }
}
