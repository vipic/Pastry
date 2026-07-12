import SwiftUI
import AppKit
import Carbon
import OSLog

extension Notification.Name {
    static let settingsSelectTab = Notification.Name("settingsSelectTab")
}

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
    @State private var selectedTab: SettingsTab?
    @State private var selectedLanguage: Language
    @State private var excludedBundleIDs: [String] = []
    @State private var versionUpdateState: UpdateState = .upToDate(
        version: AppVersion.displayCurrent,
        build: AppVersion.displayBuild,
        lastCheckDate: nil,
        lastReleaseNotes: nil
    )
    @State private var versionReleaseNotes: String?
    @State private var versionReleaseHistory: [UpdateChecker.ReleaseNote] = []
    @State private var versionCurrentVersion: String?
    @State private var versionLatestVersion: String?
    @State private var didAutoCheckVersionInCurrentWindow = false
    @State private var isVersionCheckInFlight = false
    @State private var isRecordingShortcut = false
    @State private var shortcutPreviewKeyCode: Int?
    @State private var shortcutPreviewModifiers = 0

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

    init(initialTab: SettingsTab = .general) {
        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        let pref = UserDefaults.standard.string(forKey: UserDefaultsKeys.language) ?? ""
        _selectedTab = State(initialValue: initialTab)
        _selectedLanguage = State(initialValue: Language(rawValue: pref) ?? .system)
    }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, shortcut, security, version, about
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:  return L10n["settings.tab.general"]
            case .shortcut: return L10n["settings.tab.shortcut"]
            case .security: return L10n["settings.tab.security"]
            case .version:  return L10n["settings.tab.version"]
            case .about:    return L10n["settings.tab.about"]
            }
        }
        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .shortcut: return "command"
            case .security: return "shield"
            case .version:  return "exclamationmark.circle"
            case .about:    return "info.circle"
            }
        }
        var usesSymbolIcon: Bool {
            true
        }
    }

    var body: some View {
        ZStack {
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
            .onAppear { refreshAccessibilityStatus() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshAccessibilityStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .settingsSelectTab)) { note in
                guard let rawValue = note.object as? String,
                      let tab = SettingsTab(rawValue: rawValue) else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    selectedTab = tab
                }
            }

            if showingClearConfirm {
                ConfirmationOverlay(
                    title: L10n["settings.clear_confirm_title"],
                    message: L10n["settings.clear_warning"],
                    cancelTitle: L10n["settings.clear_cancel"],
                    confirmTitle: L10n["settings.clear_btn"],
                    onCancel: { showingClearConfirm = false },
                    onConfirm: {
                        StoreManager.shared.clearAll()
                        showingClearConfirm = false
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                AppIconImageView(size: 40)
                    .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Pastry")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                    Text(L10n["settings.sidebar.subtitle"])
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

            sidebarFooterNote
        }
        .padding(.horizontal, 12)
        .padding(.top, 52)
        .padding(.bottom, 14)
        .frame(width: 206)
        .background(Color(red: 0.18, green: 0.20, blue: 0.21).opacity(0.92))
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebarFooterNote: some View {
        Text(L10n["settings.sidebar.footer"])
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white.opacity(0.52))
            .lineSpacing(2)
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.22))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
    }

    private func sidebarTabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.14)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 8) {
                sidebarTabGlyph(tab, isSelected: isSelected)
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

    @ViewBuilder
    private func sidebarTabGlyph(_ tab: SettingsTab, isSelected: Bool) -> some View {
        let foreground = isSelected ? Color(red: 0.24, green: 0.17, blue: 0.08) : .white.opacity(0.72)
        let background = isSelected ? Color(red: 0.86, green: 0.62, blue: 0.28) : .white.opacity(0.09)

        Group {
            if tab.usesSymbolIcon {
                Image(systemName: tab.icon)
                    .font(.system(size: 12, weight: .semibold))
            } else {
                Text(tab.icon)
                    .font(.system(size: 12, weight: .heavy))
            }
        }
        .foregroundStyle(foreground)
        .frame(width: 22, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
        )
    }

    private var settingsDetailBackground: some View {
        Color(red: 0.949, green: 0.933, blue: 0.886)
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
        case .version:  versionTab
        case .about:    aboutTab
        }
    }

    // MARK: - 通用 Tab

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsPaneHeader(
                    title: L10n["settings.tab.general"],
                    subtitle: L10n["settings.general.subtitle"]
                )

                HStack(spacing: 10) {
                    metricCard(
                        value: formattedHistoryMaxItems,
                        label: L10n["settings.general.metric_max_items"]
                    )
                    metricCard(
                        value: HistoryRetentionPolicy.maxAgeMetricLabel(HistoryRetentionPolicy.sanitizedMaxAgeDays(historyMaxAgeDays)),
                        label: L10n["settings.general.metric_retention_window"]
                    )
                    metricCard(
                        value: "v\(AppVersion.displayCurrent)",
                        label: L10n["settings.general.metric_current_version"]
                    )
                }

                HStack(alignment: .top, spacing: 12) {
                    settingsSection(title: L10n["settings.general.section_application"]) {
                        settingsRow(
                            title: L10n["lang.label"],
                            help: L10n["settings.general.language_help"]
                        ) {
                            Picker("", selection: languageBinding) {
                                ForEach(Language.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 124)
                            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.languagePicker)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.launch_at_login"],
                            help: L10n["settings.general.launch_help"]
                        ) {
                            Toggle("", isOn: $launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .onChange(of: launchAtLogin) { _, enabled in
                                    do {
                                        try LaunchAtLoginManager.shared.setEnabled(enabled)
                                    } catch {
                                        Logger(subsystem: "com.nekutai.pastry", category: "settings")
                                            .error("开机启动切换失败: \(error.localizedDescription)")
                                    }
                                }
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.launchAtLoginToggle)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.sound_enabled"],
                            help: L10n["settings.general.sound_help"]
                        ) {
                            Toggle("", isOn: $soundEnabled)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.soundToggle)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: generalSectionHeight, alignment: .top)

                    settingsSection(title: L10n["settings.history.section"]) {
                        settingsRow(
                            title: L10n["settings.general.maximum_history"],
                            help: L10n["settings.general.max_items_help"]
                        ) {
                            Picker("", selection: maxItemsBinding) {
                                ForEach(HistoryRetentionPolicy.maxItemsOptions, id: \.self) { value in
                                    Text(HistoryRetentionPolicy.maxItemsLabel(value)).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 112)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.general.keep_records_for"],
                            help: L10n["settings.general.keep_records_help"]
                        ) {
                            Picker("", selection: maxAgeBinding) {
                                ForEach(HistoryRetentionPolicy.maxAgeDayOptions, id: \.self) { value in
                                    Text(HistoryRetentionPolicy.maxAgeLabel(value)).tag(value)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 112)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.clear_all"],
                            help: L10n["settings.general.clear_all_help"],
                            danger: true
                        ) {
                            Button(L10n["settings.clear_btn"]) { showingClearConfirm = true }
                                .buttonStyle(SettingsPillButtonStyle(kind: .danger))
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.clearAllButton)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: generalSectionHeight, alignment: .top)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: 760, alignment: .topLeading)
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var formattedHistoryMaxItems: String {
        let value = HistoryRetentionPolicy.sanitizedMaxItems(historyMaxItems)
        return value.formatted(.number.grouping(.automatic))
    }

    private var languageBinding: Binding<Language> {
        Binding<Language>(
            get: { selectedLanguage },
            set: { lang in
                selectedLanguage = lang
                switch lang {
                case .system: UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.language)
                default:      UserDefaults.standard.set(lang.rawValue, forKey: UserDefaultsKeys.language)
                }
                NotificationCenter.default.post(name: .pastryLanguageDidChange, object: lang.rawValue)
            }
        )
    }

    private var maxItemsBinding: Binding<Int> {
        Binding(
            get: { HistoryRetentionPolicy.sanitizedMaxItems(historyMaxItems) },
            set: { value in
                historyMaxItems = value
                StoreManager.shared.applyHistoryRetentionSettings()
            }
        )
    }

    private var maxAgeBinding: Binding<Int> {
        Binding(
            get: { HistoryRetentionPolicy.sanitizedMaxAgeDays(historyMaxAgeDays) },
            set: { value in
                historyMaxAgeDays = value
                StoreManager.shared.applyHistoryRetentionSettings()
            }
        )
    }

    private func settingsPaneHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                    .lineSpacing(1)
                    .frame(maxWidth: 460, alignment: .leading)
            }

            Spacer()
        }
        .padding(.bottom, 6)
    }

    private func metricCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 9)

            Rectangle()
                .fill(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10))
                .frame(height: 1)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsRow<Control: View>(
        title: String,
        help: String? = nil,
        danger: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(danger ? .red : Color(red: 0.122, green: 0.145, blue: 0.161))
                if let help {
                    Text(help)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background(danger ? Color.red.opacity(0.055) : Color.clear)
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private var generalSectionHeight: CGFloat {
        244
    }

    // MARK: - 更新 Tab

    private var versionTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsPaneHeader(
                title: L10n["settings.tab.version"],
                subtitle: L10n["settings.version.subtitle"]
            )

            versionStatusCard

            versionReleaseNotesCard

            Spacer()
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .onAppear { autoCheckVersionIfNeeded() }
    }

    private var versionStatusCard: some View {
        HStack(alignment: .center, spacing: 14) {
            versionBadge

            VStack(alignment: .leading, spacing: 4) {
                Text(versionStatusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
                Text(versionStatusSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                    .lineLimit(2)
            }

            Spacer()

            versionPrimaryAction
        }
        .padding(14)
        .frame(maxWidth: 600, minHeight: 72, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(versionStatusTint)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private var versionBadge: some View {
        Text(versionBadgeText)
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(.white.opacity(0.94))
            .frame(width: 42, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(versionBadgeFill)
            )
    }

    @ViewBuilder
    private var versionPrimaryAction: some View {
        switch versionUpdateState {
        case .checking:
            Button {
            } label: {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
                    .scaleEffect(0.72)
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
            .disabled(true)
            .opacity(0.78)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        case .downloading(let progress):
            VStack(alignment: .trailing, spacing: 6) {
                progressBar(progress)
                    .frame(width: 118)
                Text("\(Int(min(max(progress, 0), 1) * 100))%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                    .monospacedDigit()
            }
        case .installing:
            ProgressView()
                .tint(.pastryWarmAccent)
                .controlSize(.small)
        case .updateAvailable(let result):
            Button(L10n["update.update_btn"]) {
                Task { await installVersionUpdate(result) }
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
        default:
            Button(L10n["settings.version.check_again"]) {
                Task { await checkVersionFromSettings(force: true, allowDevBuild: true, minimumCheckingDuration: 0.45) }
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .primary))
            .disabled(isVersionCheckInFlight)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private var versionReleaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(releaseNotesTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))

            if releaseNotesItems.isEmpty {
                Text(L10n["settings.version.no_release_notes"])
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                    .lineSpacing(3)
                    .textSelection(.enabled)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(releaseNotesItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            settingsDivider
                                .padding(.horizontal, -14)
                        }
                        releaseNoteRow(item, isLatest: index == 0)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 600, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private var versionStatusTitle: String {
        switch versionUpdateState {
        case .checking:
            return L10n["update.checking"]
        case .updateAvailable:
            return L10n["update.update_available"]
        case .downloading:
            return L10n["update.downloading"]
        case .installing:
            return L10n["update.installing_msg"]
        case .error:
            return L10n["update.check_failed"]
        case .upToDate:
            return L10n["settings.version.up_to_date"]
        }
    }

    private func releaseNoteRow(_ note: UpdateChecker.ReleaseNote, isLatest: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("v\(note.version)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
                if isLatest, case .updateAvailable = versionUpdateState {
                    Text(L10n["settings.version.available_badge"])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.pastryWarmAccent)
                        )
                }
                Spacer()
            }

            Text(releaseNoteBody(note))
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    private var versionStatusSubtitle: String {
        switch versionUpdateState {
        case .updateAvailable(let result):
            return "\(L10n["update.current"]) v\(UpdateChecker.displayVersion(result.currentVersion)) -> \(L10n["update.latest"]) v\(UpdateChecker.displayVersion(result.latestVersion))"
        case .downloading, .installing:
            if let current = versionCurrentVersion, let latest = versionLatestVersion {
                return "\(L10n["update.current"]) v\(UpdateChecker.displayVersion(current)) -> \(L10n["update.latest"]) v\(UpdateChecker.displayVersion(latest))"
            }
            return String(format: L10n["settings.version.current_build"], "v\(AppVersion.displayCurrent)", AppVersion.displayBuild)
        case .error(let message):
            return message
        default:
            return String(format: L10n["settings.version.current_build"], "v\(AppVersion.displayCurrent)", AppVersion.displayBuild)
        }
    }

    private var releaseNotesTitle: String {
        if case .updateAvailable = versionUpdateState {
            return L10n["update.whats_new"]
        }
        return L10n["settings.version.recent_changes"]
    }

    private var releaseNotesItems: [UpdateChecker.ReleaseNote] {
        let history = versionReleaseHistory.filter {
            !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if !history.isEmpty {
            return Array(history.prefix(3))
        }

        let notes = versionReleaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notes.isEmpty else { return [] }
        let version = versionLatestVersion ?? AppVersion.displayCurrent
        return [
            UpdateChecker.ReleaseNote(
                version: UpdateChecker.displayVersion(version),
                body: notes,
                publishedAt: "",
                htmlURL: ""
            )
        ]
    }

    private func releaseNoteBody(_ note: UpdateChecker.ReleaseNote) -> String {
        let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return body.isEmpty ? L10n["settings.version.no_release_notes"] : body
    }

    private var versionBadgeText: String {
        switch versionUpdateState {
        case .updateAvailable, .downloading, .installing:
            return "!"
        case .error:
            return "!"
        default:
            return "v"
        }
    }

    private var versionStatusTint: Color {
        switch versionUpdateState {
        case .updateAvailable, .downloading, .installing:
            return Color.pastryWarmAccent.opacity(0.10)
        case .error:
            return Color.red.opacity(0.06)
        default:
            return .white.opacity(0.72)
        }
    }

    private var versionBadgeFill: Color {
        switch versionUpdateState {
        case .updateAvailable, .downloading, .installing:
            return Color.pastryWarmAccent
        case .error:
            return Color(red: 0.74, green: 0.24, blue: 0.22)
        default:
            return Color.pastryWarmAccent
        }
    }

    private func progressBar(_ progress: Double) -> some View {
        let clamped = min(max(progress, 0), 1)
        let visible = max(clamped, 0.02)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10))
                    .frame(height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.pastryWarmAccent)
                    .frame(width: geo.size.width * CGFloat(visible), height: 6)
            }
        }
        .frame(height: 6)
    }

    private func loadVersionCache() {
        guard versionReleaseNotes == nil else { return }
        versionReleaseHistory = UpdateChecker.shared.cachedReleaseHistory()
        versionReleaseNotes = versionReleaseHistory.first?.body ?? UpdateChecker.shared.cachedReleaseNotes()
        let lastCheck = UserDefaults.standard.object(forKey: "PastryLastUpdateCheck") as? Date
        versionUpdateState = .upToDate(
            version: AppVersion.displayCurrent,
            build: AppVersion.displayBuild,
            lastCheckDate: lastCheck,
            lastReleaseNotes: versionReleaseNotes
        )
    }

    private func autoCheckVersionIfNeeded() {
        loadVersionCache()
        guard !didAutoCheckVersionInCurrentWindow else { return }
        didAutoCheckVersionInCurrentWindow = true
        Task { await checkVersionFromSettings(force: false, allowDevBuild: false, minimumCheckingDuration: 0) }
    }

    // MARK: - 关于 Tab

    private var aboutTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                settingsPaneHeader(
                    title: L10n["settings.tab.about"],
                    subtitle: L10n["settings.about.subtitle"]
                )

                aboutIdentitySection

                HStack(alignment: .top, spacing: 12) {
                    settingsSection(title: L10n["settings.about.section_product"]) {
                        settingsRow(
                            title: L10n["settings.about.created_by"],
                            help: "Nekutai"
                        ) {
                            EmptyView()
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.about.copyright"],
                            help: L10n["about.copyright"]
                        ) {
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    settingsSection(title: L10n["settings.about.section_resources"]) {
                        settingsRow(
                            title: L10n["settings.about.source_code"],
                            help: L10n["settings.about.source_code_help"]
                        ) {
                            Button(L10n["settings.about.open"]) {
                                openExternalURL("https://github.com/vipic/Pastry")
                            }
                            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.about.license"],
                            help: L10n["settings.about.license_help"]
                        ) {
                            EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: 760, alignment: .topLeading)
        }
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var aboutIdentitySection: some View {
        HStack(alignment: .center, spacing: 16) {
            AppIconImageView(size: 64)
                .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(appDisplayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
                Text(L10n["about.description"])
                    .font(.system(size: 12))
                    .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private var appDisplayName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "Pastry"
    }

    private func openExternalURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func checkVersionFromSettings(
        force: Bool = true,
        allowDevBuild: Bool = true,
        minimumCheckingDuration: TimeInterval = 0.45
    ) async {
        guard !isVersionCheckInFlight else { return }
        isVersionCheckInFlight = true
        let startedAt = Date()
        withAnimation(.easeOut(duration: 0.16)) {
            versionUpdateState = .checking
        }
        if let result = await UpdateChecker.shared.checkForUpdate(force: force, allowDevBuild: allowDevBuild) {
            await waitForMinimumCheckingDuration(startedAt: startedAt, minimumDuration: minimumCheckingDuration)
            versionReleaseNotes = result.releaseNotes
            versionReleaseHistory = result.releaseHistory
            versionCurrentVersion = result.currentVersion
            versionLatestVersion = result.latestVersion
            withAnimation(.easeOut(duration: 0.16)) {
                versionUpdateState = .updateAvailable(result: result)
            }
        } else {
            await waitForMinimumCheckingDuration(startedAt: startedAt, minimumDuration: minimumCheckingDuration)
            let cachedHistory = UpdateChecker.shared.cachedReleaseHistory()
            let cachedNotes = cachedHistory.first?.body ?? UpdateChecker.shared.cachedReleaseNotes()
            versionReleaseHistory = cachedHistory
            versionReleaseNotes = cachedNotes
            versionCurrentVersion = nil
            versionLatestVersion = nil
            let lastCheck = UserDefaults.standard.object(forKey: "PastryLastUpdateCheck") as? Date
            versionUpdateState = .upToDate(
                version: AppVersion.displayCurrent,
                build: AppVersion.displayBuild,
                lastCheckDate: lastCheck,
                lastReleaseNotes: cachedNotes
            )
        }
        isVersionCheckInFlight = false
    }

    private func waitForMinimumCheckingDuration(startedAt: Date, minimumDuration: TimeInterval) async {
        let remaining = minimumDuration - Date().timeIntervalSince(startedAt)
        guard remaining > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
    }

    @MainActor
    private func installVersionUpdate(_ result: UpdateChecker.UpdateResult) async {
        versionReleaseNotes = result.releaseNotes
        versionReleaseHistory = result.releaseHistory
        versionCurrentVersion = result.currentVersion
        versionLatestVersion = result.latestVersion
        versionUpdateState = .downloading(progress: 0)

        do {
            let tempURL = try await UpdateChecker.shared.downloadBinary(
                from: result.downloadURL,
                expectedSize: result.downloadSize,
                onProgress: { progress in
                    Task { @MainActor in
                        versionUpdateState = .downloading(progress: progress)
                    }
                }
            )
            versionUpdateState = .installing
            try UpdateChecker.shared.applyUpdate(dmgAt: tempURL, expectedVersion: result.latestVersion)
        } catch {
            versionUpdateState = .error(error.localizedDescription)
        }
    }

    // MARK: - 快捷键 Tab

    private var shortcutTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsPaneHeader(
                title: L10n["settings.tab.shortcut"],
                subtitle: L10n["settings.shortcut.subtitle"]
            )

            shortcutHero

            settingsSection(title: L10n["shortcut.section_title"]) {
                settingsRow(
                    title: L10n["shortcut.overlay_shortcut"],
                    help: L10n["shortcut.applies_immediately"]
                ) {
                    Button {
                        shortcutPreviewKeyCode = nil
                        shortcutPreviewModifiers = 0
                        isRecordingShortcut = true
                    } label: {
                        Text(isRecordingShortcut ? L10n["hotkey.recording"] : L10n["shortcut.record_button"])
                            .frame(minWidth: 54)
                    }
                    .buttonStyle(SettingsPillButtonStyle(kind: .primary))
                    .disabled(isRecordingShortcut)
                    .opacity(isRecordingShortcut ? 0.72 : 1)
                }

                ShortcutCaptureView(
                    isRecording: $isRecordingShortcut,
                    keyCode: $hotkeyKeyCode,
                    modifiers: $hotkeyModifiers,
                    onPreview: { keyCode, modifiers in
                        shortcutPreviewKeyCode = keyCode
                        shortcutPreviewModifiers = modifiers
                    },
                    onChange: {
                        GlobalHotkeyManager.shared.reregister()
                    },
                    onStartRecording: {
                        GlobalHotkeyManager.shared.unregister()
                    },
                    onCancelRecording: {
                        shortcutPreviewKeyCode = nil
                        shortcutPreviewModifiers = 0
                        GlobalHotkeyManager.shared.reregister()
                    }
                )
                .frame(width: 0, height: 0)
                .opacity(0.01)
                .accessibilityHidden(true)

                settingsDivider

                settingsRow(
                    title: L10n["shortcut.clear_shortcut"],
                    help: L10n["shortcut.clear_hint"]
                ) {
                    Button(L10n["shortcut.clear_button"]) {
                        clearShortcut()
                    }
                    .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                }
            }
            .frame(maxWidth: 600, alignment: .topLeading)

            Spacer()
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }

    private var shortcutHero: some View {
        HStack {
            Spacer()
            HStack(spacing: 12) {
                ForEach(Array(shortcutHeroSegments.enumerated()), id: \.offset) { _, segment in
                    shortcutKeycap(segment)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.14), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 3)
            )
            Spacer()
        }
        .frame(maxWidth: 600, minHeight: 142)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.42))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private func shortcutKeycap(_ segment: String) -> some View {
        Text(segment)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, segment.count > 1 ? 8 : 0)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.14), lineWidth: 0.5)
                    )
                    .shadow(color: Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), radius: 0, x: 0, y: 2)
            )
    }

    private var shortcutHeroSegments: [String] {
        if isRecordingShortcut {
            let preview = shortcutDisplayPreviewSegments(
                keyCode: shortcutPreviewKeyCode,
                modifiers: shortcutPreviewModifiers
            )
            return preview.isEmpty ? ["…"] : preview
        }
        guard hotkeyKeyCode >= 0 else {
            return ["--"]
        }
        return shortcutDisplaySegments(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    private func clearShortcut() {
        hotkeyKeyCode = -1
        hotkeyModifiers = 0
        isRecordingShortcut = false
        shortcutPreviewKeyCode = nil
        shortcutPreviewModifiers = 0
        GlobalHotkeyManager.shared.reregister()
    }

    // MARK: - 安全 Tab

    private var securityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                settingsPaneHeader(
                    title: L10n["settings.tab.security"],
                    subtitle: L10n["settings.security.subtitle"]
                )

                securityPermissionCard

                HStack(alignment: .top, spacing: 12) {
                    settingsSection(title: L10n["settings.security.privacy"]) {
                        settingsRow(
                            title: L10n["settings.link_preview_network"],
                            help: L10n["settings.link_preview_network_hint"]
                        ) {
                            Toggle("", isOn: $linkPreviewNetworkEnabled)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.linkPreviewNetworkToggle)
                        }

                        settingsDivider

                        settingsRow(
                            title: L10n["settings.performance_logging"],
                            help: L10n["settings.performance_logging_hint"]
                        ) {
                            Toggle("", isOn: $performanceLoggingEnabled)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.performanceLoggingToggle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)

                    settingsSection(title: excludedAppsSectionTitle) {
                        VStack(spacing: 8) {
                            if installedExcludedBundleIDs.isEmpty {
                                excludedEmptyRow
                            } else {
                                ForEach(installedExcludedBundleIDs, id: \.self) { bundleID in
                                    excludedAppRow(bundleID)
                                }
                            }

                            Button(action: addExcludedApp) {
                                Text(L10n["settings.excluded_add"])
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
                            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.excludedAddButton)
                        }
                        .padding(14)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 28)
            .frame(maxWidth: 820, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            excludedBundleIDs = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        }
    }

    private var securityPermissionCard: some View {
        let model = AccessibilityPermissionRowModel.resolve(isTrusted: accessibilityTrusted)
        let badgeFill = accessibilityTrusted
            ? Color(red: 0.180, green: 0.498, blue: 0.333)
            : Color.pastryWarmAccent

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(badgeFill)
                Image(systemName: accessibilityTrusted ? "checkmark" : "exclamationmark")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
                Text(model.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
            }

            Spacer()

            Button(L10n["settings.accessibility_grant_btn"]) {
                openAccessibilitySettings()
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.accessibilityGrantButton)
        }
        .padding(16)
        .frame(maxWidth: 600, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 0.5)
                )
        )
    }

    private var excludedAppsSectionTitle: String {
        let count = installedExcludedBundleIDs.count
        guard count > 0 else { return L10n["settings.excluded_apps"] }
        return "\(L10n["settings.excluded_apps"]) \(count)"
    }

    private var excludedEmptyRow: some View {
        Text(L10n["settings.excluded_empty"])
            .font(.system(size: 11))
            .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 10)
            .background(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func excludedAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 9) {
            appIcon(for: bundleID)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(displayName(for: bundleID))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
                .lineLimit(1)

            Spacer()

            Button(L10n["settings.excluded_remove"]) {
                removeExcludedApp(bundleID)
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
        }
        .padding(.leading, 7)
        .padding(.trailing, 10)
        .frame(height: 42)
        .background(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
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

private enum SettingsButtonKind {
    case primary
    case secondary
    case danger
}

private struct SettingsPillButtonStyle: ButtonStyle {
    var kind: SettingsButtonKind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(buttonBackground(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger:
            return .white
        case .secondary:
            return Color(red: 0.122, green: 0.145, blue: 0.161)
        }
    }

    @ViewBuilder
    private func buttonBackground(isPressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(fillColor.opacity(isPressed ? 0.88 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor, lineWidth: 0.5)
            )
    }

    private var fillColor: Color {
        switch kind {
        case .primary:
            return Color.pastryWarmAccent
        case .secondary:
            return Color.white.opacity(0.72)
        case .danger:
            return Color(red: 0.724, green: 0.267, blue: 0.247)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return Color(red: 0.718, green: 0.451, blue: 0.153).opacity(0.50)
        case .secondary:
            return Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.16)
        case .danger:
            return Color(red: 0.620, green: 0.194, blue: 0.176).opacity(0.50)
        }
    }
}

private struct SettingsSwitchStyle: ToggleStyle {
    private let switchAnimation = Animation.spring(response: 0.28, dampingFraction: 0.74, blendDuration: 0.08)

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(switchAnimation) {
                configuration.isOn.toggle()
            }
        } label: {
            EmptyView()
        }
        .buttonStyle(SettingsSwitchButtonStyle(isOn: configuration.isOn, animation: switchAnimation))
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}

private struct SettingsSwitchButtonStyle: ButtonStyle {
    let isOn: Bool
    let animation: Animation

    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitchBody(
            isOn: isOn,
            isPressed: configuration.isPressed,
            animation: animation
        )
    }
}

private struct SettingsSwitchBody: View {
    let isOn: Bool
    let isPressed: Bool
    let animation: Animation

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(trackFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(trackStroke, lineWidth: 0.5)
                )

            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(isPressed ? 0.12 : 0.16), radius: isPressed ? 1 : 2, x: 0, y: 1)
                .frame(width: 20, height: 20)
                .scaleEffect(isPressed ? 0.92 : 1)
                .padding(3)
        }
        .frame(width: 46, height: 26)
        .contentShape(Capsule(style: .continuous))
        .animation(animation, value: isOn)
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }

    private var trackFill: Color {
        isOn
            ? Color.pastryWarmAccent
            : Color(red: 0.780, green: 0.765, blue: 0.730)
    }

    private var trackStroke: Color {
        isOn
            ? Color(red: 0.718, green: 0.451, blue: 0.153).opacity(0.45)
            : Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.16)
    }
}

private struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onPreview: (Int?, Int) -> Void
    var onChange: () -> Void
    var onStartRecording: () -> Void
    var onCancelRecording: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutCaptureField {
        let field = ShortcutCaptureField()
        field.coordinator = context.coordinator
        return field
    }

    func updateNSView(_ nsView: ShortcutCaptureField, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        if isRecording {
            nsView.beginRecordingIfNeeded()
        } else {
            nsView.endRecordingIfNeeded()
        }
    }

    final class Coordinator: NSObject {
        var parent: ShortcutCaptureView

        init(parent: ShortcutCaptureView) {
            self.parent = parent
            super.init()
        }

        func preview(keyCode: Int?, modifiers: Int) {
            parent.onPreview(keyCode, modifiers)
        }

        func startRecording() {
            parent.onStartRecording()
        }

        func cancelRecording() {
            parent.isRecording = false
            parent.onCancelRecording()
        }

        func commit(keyCode: Int, modifiers: Int) {
            parent.keyCode = keyCode
            parent.modifiers = modifiers
            parent.onPreview(keyCode, modifiers)
            parent.onChange()
            parent.isRecording = false
        }
    }
}

private final class ShortcutCaptureField: NSControl {
    weak var coordinator: ShortcutCaptureView.Coordinator?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    func beginRecordingIfNeeded() {
        guard !recording else { return }
        recording = true
        coordinator?.startRecording()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    func endRecordingIfNeeded() {
        guard recording else { return }
        recording = false
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        let code = Int(event.keyCode)
        if code == 53 {
            cancelRecording()
            return
        }

        let nseventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard nseventMods.contains(.command) || nseventMods.contains(.option)
            || nseventMods.contains(.control) || nseventMods.contains(.shift)
        else {
            SoundFeedback.invalidAction()
            return
        }

        let carbonMods = Int(nseventModifiersToCarbon(nseventMods))
        coordinator?.preview(keyCode: code, modifiers: carbonMods)
        recording = false
        coordinator?.commit(keyCode: code, modifiers: carbonMods)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else {
            super.flagsChanged(with: event)
            return
        }

        let nseventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonMods = Int(nseventModifiersToCarbon(nseventMods))
        coordinator?.preview(keyCode: nil, modifiers: carbonMods)
    }

    override func resignFirstResponder() -> Bool {
        if recording {
            cancelRecording()
        }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        recording = false
        coordinator?.cancelRecording()
        window?.makeFirstResponder(nil)
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

            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if window.toolbar != nil {
                window.toolbar?.isVisible = false
                window.toolbar = nil
            }
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
