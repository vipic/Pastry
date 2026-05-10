import SwiftUI
import OSLog
import ServiceManagement

// MARK: - 设置视图

struct SettingsSceneView: View {

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    @AppStorage(UserDefaultsKeys.soundEnabled)
    private var soundEnabled = false

    // 快捷键
    @AppStorage(UserDefaultsKeys.hotkeyKeyCode)
    private var hotkeyKeyCode = Int(GlobalHotkeyManager.defaultKeyCode)
    @AppStorage(UserDefaultsKeys.hotkeyModifiers)
    private var hotkeyModifiers = Int(GlobalHotkeyManager.defaultModifiers)

    @State private var showingClearConfirm = false
    @State private var accessibilityTrusted = false
    @State private var selectedTab: SettingsTab? = .general
    @State private var selectedLanguage: Language
    @State private var excludedBundleIDs: [String] = []

    enum Language: String, CaseIterable, Identifiable {
        case system
        case zhHans = "zh-Hans"
        case en

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return L10n["lang.system"]
            case .zhHans: return L10n["lang.zh_hans"]
            case .en:     return L10n["lang.en"]
            }
        }
    }

    init() {
        // Clean up stale AppleLanguages from previous version (would pollute Locale.preferredLanguages)
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        let pref = UserDefaults.standard.string(forKey: "PastryLanguage") ?? ""
        _selectedLanguage = State(initialValue: Language(rawValue: pref) ?? .system)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general
        case shortcut
        case security

        var id: String { rawValue }

        var label: String {
            switch self {
            case .general:  return L10n["settings.tab.general"]
            case .shortcut: return L10n["settings.tab.shortcut"]
            case .security: return L10n["settings.tab.security"]
            }
        }

        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .shortcut: return "command"
            case .security: return "shield"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.label, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            if let tab = selectedTab {
                detail(for: tab)
            }
        }
        .id(selectedLanguage.rawValue) // force full re-render on language change
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
                    Picker(L10n["lang.label"], selection: Binding<Language>(
                        get: { selectedLanguage },
                        set: { lang in
                            selectedLanguage = lang
                            switch lang {
                            case .system:
                                UserDefaults.standard.removeObject(forKey: "PastryLanguage")
                            default:
                                UserDefaults.standard.set(lang.rawValue, forKey: "PastryLanguage")
                            }
                        }
                    )) {
                        ForEach(Language.allCases) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    Toggle(L10n["settings.launch_at_login"], isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                Logger(subsystem: "com.nekutai.pastry", category: "settings")
                                    .error("开机启动切换失败: \\(error.localizedDescription)")
                            }
                        }
                    Toggle(L10n["settings.sound_enabled"], isOn: $soundEnabled)
                }
                Section(L10n["settings.accessibility_section"]) {
                    HStack {
                        Image(systemName: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(accessibilityTrusted ? .green : .orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(accessibilityTrusted ? L10n["settings.accessibility_granted"] : L10n["settings.accessibility_denied"])
                                .font(.body)
                            Text(accessibilityTrusted
                                 ? L10n["settings.accessibility_paste_ok"]
                                 : L10n["settings.accessibility_paste_need"])
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if !accessibilityTrusted {
                            Button(L10n["settings.accessibility_grant_btn"]) {
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
                Section {
                    Button(role: .destructive) {
                        showingClearConfirm = true
                    } label: {
                        Label(L10n["settings.clear_all"], systemImage: "trash")
                    }
                    .alert(L10n["settings.clear_confirm_title"], isPresented: $showingClearConfirm) {
                        Button(L10n["settings.clear_cancel"], role: .cancel) {}
                        Button(L10n["settings.clear_btn"], role: .destructive) {
                            StoreManager.shared.clearAll()
                        }
                    } message: {
                        Text(L10n["settings.clear_warning"])
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)

        case .shortcut:
            shortcutTab

        case .security:
            securityTab
        }
    }

    // MARK: - 快捷键 Tab

    private var shortcutTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n["shortcut.label"])
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
                         ? L10n["shortcut.hint_set"]
                         : L10n["shortcut.hint_empty"])
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Divider()

                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text(L10n["shortcut.effective_immediately"])
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text(L10n["shortcut.section_title"])
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - 安全 Tab

    private var securityTab: some View {
        Form {
            Section(L10n["settings.excluded_apps"]) {
                excludedAppsContent
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private func refreshAccessibilityStatus() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    // MARK: - 排除应用

    /// 从 bundleID 取 App 名称
    private func displayName(for bundleID: String) -> String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: path.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n["settings.excluded_add"]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            if let bundle = Bundle(url: url),
               let id = bundle.bundleIdentifier {
                var current = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
                if !current.contains(id) {
                    current.append(id)
                    UserDefaults.standard.set(current, forKey: UserDefaultsKeys.excludedBundleIDs)
                    excludedBundleIDs = current
                }
            }
        }
    }

    private func removeExcludedApp(_ bundleID: String) {
        var current = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        current.removeAll { $0 == bundleID }
        UserDefaults.standard.set(current, forKey: UserDefaultsKeys.excludedBundleIDs)
        excludedBundleIDs = current
    }

    /// 检查 bundleID 对应的 App 是否已安装
    private func isAppInstalled(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// 当前已安装的排除应用（从未安装的不显示）
    private var installedExcludedBundleIDs: [String] {
        excludedBundleIDs.filter { isAppInstalled(bundleID: $0) }
    }

    private var excludedAppsContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if installedExcludedBundleIDs.isEmpty {
                Text(L10n["settings.excluded_empty"])
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(installedExcludedBundleIDs, id: \.self) { bundleID in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile:
                            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path ?? ""))
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(displayName(for: bundleID))
                            .font(.body)
                        Spacer()
                        Button {
                            removeExcludedApp(bundleID)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button(action: addExcludedApp) {
                Label(L10n["settings.excluded_add"], systemImage: "plus")
            }

            Text(L10n["settings.excluded_hint"])
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 2)
        }
        .onAppear {
            excludedBundleIDs = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        }
    }
}
