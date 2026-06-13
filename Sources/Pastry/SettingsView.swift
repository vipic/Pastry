import SwiftUI
import OSLog

// MARK: - 设置视图

struct SettingsSceneView: View {

    @AppStorage(UserDefaultsKeys.launchAtLogin)
    private var launchAtLogin = false

    @AppStorage(UserDefaultsKeys.soundEnabled)
    private var soundEnabled = false

    @AppStorage(UserDefaultsKeys.linkPreviewNetworkEnabled)
    private var linkPreviewNetworkEnabled = false
    @AppStorage(UserDefaultsKeys.performanceLoggingEnabled)
    private var performanceLoggingEnabled = false
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
            settingsSidebar
                .navigationSplitViewColumnWidth(min: 206, ideal: 206, max: 206)
        } detail: {
            ZStack(alignment: .topLeading) {
                settingsDetailBackground
                detail(for: selectedTab ?? .general)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .toolbarVisibility(.hidden, for: .windowToolbar)
        .background(settingsWindowBackground)
        .ignoresSafeArea(.container, edges: .top)
        .background(SettingsWindowChromeConfigurator())
        .accessibilityIdentifier(AccessibilityIdentifiers.Settings.root)
        .id(selectedLanguage.rawValue)
        .onAppear { refreshAccessibilityStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.24), radius: 10, x: 0, y: 5)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pastry")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text("Clipboard settings")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }
            .padding(.horizontal, 6)

            VStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarTabButton(tab)
                }
            }
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.sidebar)

            Spacer()

            Text("Local-first clipboard history. Network previews stay off until enabled.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.46))
                .lineSpacing(1)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 52)
        .padding(.bottom, 14)
        .frame(width: 206)
        .background(
            ZStack {
                Color(red: 0.18, green: 0.20, blue: 0.21).opacity(0.88)
                LinearGradient(
                    colors: [.white.opacity(0.08), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
            }
        )
        .ignoresSafeArea(.container, edges: .top)
    }

    private func sidebarTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? Color(red: 0.24, green: 0.17, blue: 0.08) : .white.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color(red: 0.86, green: 0.62, blue: 0.28) : .white.opacity(0.09))
                    )
                Text(tab.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                Spacer()
            }
            .padding(.horizontal, 9)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.16) : .clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? .white.opacity(0.10) : .clear, lineWidth: 0.5)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var settingsDetailBackground: some View {
        ZStack {
            Color(red: 0.949, green: 0.933, blue: 0.886).opacity(0.88)
            LinearGradient(
                colors: [Color.white.opacity(0.42), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            LinearGradient(
                colors: [Color(red: 0.851, green: 0.616, blue: 0.263).opacity(0.10), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private var settingsWindowBackground: some View {
        Color(red: 0.949, green: 0.933, blue: 0.886).opacity(0.88)
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
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.languagePicker)
                Toggle(L10n["settings.launch_at_login"], isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLoginManager.shared.setEnabled(enabled)
                        } catch {
                            Logger(subsystem: "com.nekutai.pastry", category: "settings")
                                .error("开机启动切换失败: \(error.localizedDescription)")
                        }
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.launchAtLoginToggle)
                Toggle(L10n["settings.sound_enabled"], isOn: $soundEnabled)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.soundToggle)
            }

            HistoryRetentionSettingsView(
                maxItems: $historyMaxItems,
                maxAgeDays: $historyMaxAgeDays,
                onPolicyChange: { StoreManager.shared.applyHistoryRetentionSettings() }
            )

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
                        .accessibilityIdentifier(AccessibilityIdentifiers.Settings.clearAllButton)
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
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: 680, alignment: .topLeading)
        .padding(.vertical, 24)
        .padding(.leading, 28)
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: 680, alignment: .topLeading)
        .padding(.vertical, 24)
        .padding(.leading, 28)
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.linkPreviewNetworkToggle)
                Text(L10n["settings.link_preview_network_hint"])
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Toggle(L10n["settings.performance_logging"], isOn: $performanceLoggingEnabled)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Settings.performanceLoggingToggle)
                Text(L10n["settings.performance_logging_hint"])
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text(L10n["settings.diagnostics_section"])
                    .font(.system(size: 11, weight: .medium))
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
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.excludedAddButton)
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
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: 680, alignment: .topLeading)
        .padding(.vertical, 24)
        .padding(.leading, 28)
        .padding(.trailing, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            excludedBundleIDs = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        }
    }

    // MARK: - 辅助

    private var accessibilityPermissionRow: some View {
        let model = AccessibilityPermissionRowModel.resolve(isTrusted: accessibilityTrusted)
        return HStack {
            Image(systemName: model.iconName)
                .foregroundColor(model.iconColor).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.title).font(.body)
                Text(model.subtitle)
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if model.showsGrantButton {
                Button(L10n["settings.accessibility_grant_btn"]) {
                    openAccessibilitySettings()
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.accessibilityGrantButton)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier(AccessibilityIdentifiers.Settings.accessibilityRow)
    }

    private func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermissionChecker.shared.isTrusted()
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

private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        configureWhenReady(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWhenReady(from: view)
    }

    private func configureWhenReady(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                configureWhenReady(from: view)
                return
            }

            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar?.isVisible = false
            window.toolbar = nil
        }
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
