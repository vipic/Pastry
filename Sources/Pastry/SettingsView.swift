import SwiftUI
import OSLog
import ServiceManagement

// MARK: - 设置视图

struct SettingsSceneView: View {

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    @AppStorage(UserDefaultsKeys.soundEnabled)
    private var soundEnabled = false

    @AppStorage(UserDefaultsKeys.linkPreviewNetworkEnabled)
    private var linkPreviewNetworkEnabled = false
    @AppStorage(UserDefaultsKeys.historyMaxItems)
    private var historyMaxItems = HistoryRetentionPolicy.defaultMaxItems
    @AppStorage(UserDefaultsKeys.historyMaxAgeDays)
    private var historyMaxAgeDays = HistoryRetentionPolicy.defaultMaxAgeDays

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
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        let pref = UserDefaults.standard.string(forKey: "PastryLanguage") ?? ""
        _selectedLanguage = State(initialValue: Language(rawValue: pref) ?? .system)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, shortcut, security
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
                Label(tab.label, systemImage: tab.icon).tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            if let tab = selectedTab { detail(for: tab) }
        }
        .id(selectedLanguage.rawValue)
        .onAppear { refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    // MARK: - 详情内容

    @ViewBuilder
    private func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:  generalTab
        case .shortcut: shortcutTab
        case .security: securityTab
        }
    }

    // MARK: - 通用 Tab

    private var generalTab: some View {
        Form {
            Section {
                Picker(L10n["lang.label"], selection: Binding<Language>(
                    get: { selectedLanguage },
                    set: { lang in
                        selectedLanguage = lang
                        switch lang {
                        case .system: UserDefaults.standard.removeObject(forKey: "PastryLanguage")
                        default:      UserDefaults.standard.set(lang.rawValue, forKey: "PastryLanguage")
                        }
                    }
                )) {
                    ForEach(Language.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L10n["settings.launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else       { try SMAppService.mainApp.unregister() }
                        } catch {
                            Logger(subsystem: "com.nekutai.pastry", category: "settings")
                                .error("开机启动切换失败: \(error.localizedDescription)")
                        }
                    }
                Toggle(L10n["settings.sound_enabled"], isOn: $soundEnabled)
            }

            Section {
                Picker("历史容量", selection: Binding(
                    get: { HistoryRetentionPolicy.sanitizedMaxItems(historyMaxItems) },
                    set: { value in
                        historyMaxItems = value
                        StoreManager.shared.applyHistoryRetentionSettings()
                    }
                )) {
                    ForEach(HistoryRetentionPolicy.maxItemsOptions, id: \.self) { value in
                        Text(HistoryRetentionPolicy.maxItemsLabel(value)).tag(value)
                    }
                }

                Picker("清理周期", selection: Binding(
                    get: { HistoryRetentionPolicy.sanitizedMaxAgeDays(historyMaxAgeDays) },
                    set: { value in
                        historyMaxAgeDays = value
                        StoreManager.shared.applyHistoryRetentionSettings()
                    }
                )) {
                    ForEach(HistoryRetentionPolicy.maxAgeDayOptions, id: \.self) { value in
                        Text(HistoryRetentionPolicy.maxAgeLabel(value)).tag(value)
                    }
                }

                Text("超过容量或保留周期的普通历史会自动清理，收藏项目不受影响。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("历史记录")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Section {
                accessibilityPermissionRow
            }

            // 版本条目
            Section {
                HStack {
                    Text(L10n["menu.about"])
                    Spacer()
                    Button {
                        AppDelegate.shared?.showAboutWindow()
                    } label: {
                        Text("v\(AppVersion.displayCurrent)")
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(versionHovered ? Color.primary.opacity(0.06) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { versionHovered = $0 }
                }
            }

            // 清空全部记录（左文案右按钮）
            Section {
                HStack {
                    Text(L10n["settings.clear_all"]).font(.system(size: 12)).foregroundColor(.red)
                    Spacer()
                    Button(L10n["settings.clear_btn"]) { showingClearConfirm = true }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.small)
                }
                .alert(L10n["settings.clear_confirm_title"], isPresented: $showingClearConfirm) {
                    Button(L10n["settings.clear_cancel"], role: .cancel) {}
                    Button(L10n["settings.clear_btn"], role: .destructive) { StoreManager.shared.clearAll() }
                } message: {
                    Text(L10n["settings.clear_warning"])
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    // MARK: - 快捷键 Tab

    private var shortcutTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n["shortcut.label"]).font(.body)
                        Spacer()
                        HotkeyRecorderView(
                            keyCode: $hotkeyKeyCode, modifiers: $hotkeyModifiers,
                            onChange: { GlobalHotkeyManager.shared.reregister() },
                            onStartRecording: { GlobalHotkeyManager.shared.unregister() },
                            onCancelRecording: { GlobalHotkeyManager.shared.reregister() }
                        )
                        .frame(width: 160, height: 28)
                    }
                    Text(hotkeyKeyCode >= 0 ? L10n["shortcut.hint_set"] : L10n["shortcut.hint_empty"])
                        .font(.caption).foregroundColor(.secondary)
                    Divider()
                    HStack {
                        Image(systemName: "info.circle").foregroundColor(.secondary).font(.caption)
                        Text(L10n["shortcut.effective_immediately"]).font(.caption).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    @State private var versionHovered = false

    // MARK: - 安全 Tab

    private var securityTab: some View {
        Form {
            Section {
                accessibilityPermissionRow
            } header: {
                Text(L10n["settings.accessibility_section"])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle(L10n["settings.link_preview_network"], isOn: $linkPreviewNetworkEnabled)
                Text(L10n["settings.link_preview_network_hint"])
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                if installedExcludedBundleIDs.isEmpty {
                    Text(L10n["settings.excluded_empty"])
                        .font(.caption).foregroundColor(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(installedExcludedBundleIDs.indices, id: \.self) { idx in
                        HStack(spacing: 10) {
                            appIcon(for: installedExcludedBundleIDs[idx])
                                .resizable().frame(width: 28, height: 28)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                            Text(displayName(for: installedExcludedBundleIDs[idx])).font(.body)
                            Spacer()
                            Button(action: { removeExcludedApp(installedExcludedBundleIDs[idx]) }) {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                }

                Button(action: addExcludedApp) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 12))
                        Text(L10n["settings.excluded_add"]).font(.system(size: 13))
                    }
                }
                .buttonStyle(.plain).foregroundColor(.secondary)
            } header: {
                Text(L10n["settings.excluded_apps"])
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            } footer: {
                Text(L10n["settings.excluded_hint"])
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            excludedBundleIDs = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        }
    }

    // MARK: - 辅助

    private var accessibilityPermissionRow: some View {
        HStack {
            Image(systemName: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(accessibilityTrusted ? .green : .orange).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessibilityTrusted ? L10n["settings.accessibility_granted"] : L10n["settings.accessibility_denied"]).font(.body)
                Text(accessibilityTrusted ? L10n["settings.accessibility_paste_ok"] : L10n["settings.accessibility_paste_need"])
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !accessibilityTrusted {
                Button(L10n["settings.accessibility_grant_btn"]) {
                    openAccessibilitySettings()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func refreshAccessibilityStatus() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 排除应用数据

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false; panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L10n["settings.excluded_add"]
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
            var current = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
            if !current.contains(id) { current.append(id); UserDefaults.standard.set(current, forKey: UserDefaultsKeys.excludedBundleIDs); excludedBundleIDs = current }
        }
    }

    private func removeExcludedApp(_ bundleID: String) {
        var current = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        current.removeAll { $0 == bundleID }
        UserDefaults.standard.set(current, forKey: UserDefaultsKeys.excludedBundleIDs)
        excludedBundleIDs = current
    }

    private func isAppInstalled(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              FileManager.default.fileExists(atPath: url.path) else { return false }
        return true
    }

    private var installedExcludedBundleIDs: [String] {
        excludedBundleIDs.filter { isAppInstalled(bundleID: $0) }
    }
}

    private func appIcon(for bundleID: String) -> Image {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        }
        return Image(systemName: "questionmark.app")
    }

    private func displayName(for bundleID: String) -> String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: path.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    // MARK: - 辅助
