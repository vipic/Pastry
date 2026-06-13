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
    @State private var versionUpdateState: UpdateState = .upToDate(
        version: AppVersion.displayCurrent,
        build: AppVersion.displayBuild,
        lastCheckDate: nil,
        lastReleaseNotes: nil
    )
    @State private var versionReleaseNotes: String?
    @State private var versionCurrentVersion: String?
    @State private var versionLatestVersion: String?

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
        case general, shortcut, security, version
        var id: String { rawValue }
        var label: String {
            switch self {
            case .general:  return L10n["settings.tab.general"]
            case .shortcut: return L10n["settings.tab.shortcut"]
            case .security: return L10n["settings.tab.security"]
            case .version:  return L10n["settings.tab.version"]
            }
        }
        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .shortcut: return "command"
            case .security: return "shield"
            case .version:  return "v"
            }
        }
        var usesSymbolIcon: Bool {
            self != .version
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

            Text(L10n["settings.sidebar.footer"])
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
        case .version:  versionTab
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
                                .toggleStyle(.switch)
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
                                .toggleStyle(.switch)
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
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.clearAllButton)
                        }
                        .alert(L10n["settings.clear_confirm_title"], isPresented: $showingClearConfirm) {
                            Button(L10n["settings.clear_cancel"], role: .cancel) {}
                            Button(L10n["settings.clear_btn"], role: .destructive) { StoreManager.shared.clearAll() }
                        } message: {
                            Text(L10n["settings.clear_warning"])
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
                case .system: UserDefaults.standard.removeObject(forKey: "PastryLanguage")
                default:      UserDefaults.standard.set(lang.rawValue, forKey: "PastryLanguage")
                }
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
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 1)
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

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.56))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 1)
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

    // MARK: - 版本 Tab

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
        .onAppear { loadVersionCache() }
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
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.10), lineWidth: 1)
                )
        )
    }

    private var versionBadge: some View {
        Text(versionBadgeText)
            .font(.system(size: 18, weight: .heavy))
            .foregroundStyle(.white.opacity(0.94))
            .frame(width: 42, height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(versionBadgeGradient)
                    .shadow(color: Color(red: 0.45, green: 0.25, blue: 0.10).opacity(0.20), radius: 10, x: 0, y: 5)
            )
    }

    @ViewBuilder
    private var versionPrimaryAction: some View {
        switch versionUpdateState {
        case .checking:
            ProgressView()
                .controlSize(.small)
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
                .controlSize(.small)
        case .updateAvailable(let result):
            Button(L10n["update.update_btn"]) {
                Task { await installVersionUpdate(result) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.22, green: 0.50, blue: 0.83))
            .controlSize(.small)
        default:
            Button(L10n["settings.version.check_again"]) {
                Task { await checkVersionFromSettings() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.22, green: 0.50, blue: 0.83))
            .controlSize(.small)
        }
    }

    private var versionReleaseNotesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(releaseNotesTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0.122, green: 0.145, blue: 0.161))
            Text(releaseNotesBody)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.396, green: 0.443, blue: 0.478))
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: 600, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.34))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color(red: 0.122, green: 0.145, blue: 0.161).opacity(0.08), lineWidth: 1)
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

    private var releaseNotesBody: String {
        let notes = versionReleaseNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return notes.isEmpty ? L10n["settings.version.no_release_notes"] : notes
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
            return Color(red: 0.88, green: 0.94, blue: 1.0).opacity(0.62)
        case .error:
            return Color.red.opacity(0.08)
        default:
            return .white.opacity(0.56)
        }
    }

    private var versionBadgeGradient: LinearGradient {
        let colors: [Color] = switch versionUpdateState {
        case .updateAvailable, .downloading, .installing:
            [Color(red: 0.45, green: 0.68, blue: 1.0), Color(red: 0.22, green: 0.50, blue: 0.83)]
        case .error:
            [Color(red: 1.0, green: 0.48, blue: 0.45), Color(red: 0.74, green: 0.24, blue: 0.22)]
        default:
            [Color(red: 1.0, green: 0.88, blue: 0.65), Color(red: 0.85, green: 0.62, blue: 0.26)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
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
                    .fill(Color(red: 0.22, green: 0.50, blue: 0.83))
                    .frame(width: geo.size.width * CGFloat(visible), height: 6)
            }
        }
        .frame(height: 6)
    }

    private func loadVersionCache() {
        guard versionReleaseNotes == nil else { return }
        versionReleaseNotes = UpdateChecker.shared.cachedReleaseNotes()
        let lastCheck = UserDefaults.standard.object(forKey: "PastryLastUpdateCheck") as? Date
        versionUpdateState = .upToDate(
            version: AppVersion.displayCurrent,
            build: AppVersion.displayBuild,
            lastCheckDate: lastCheck,
            lastReleaseNotes: versionReleaseNotes
        )
    }

    @MainActor
    private func checkVersionFromSettings() async {
        versionUpdateState = .checking
        if let result = await UpdateChecker.shared.checkForUpdate(force: true) {
            versionReleaseNotes = result.releaseNotes
            versionCurrentVersion = result.currentVersion
            versionLatestVersion = result.latestVersion
            versionUpdateState = .updateAvailable(result: result)
        } else {
            let cachedNotes = UpdateChecker.shared.cachedReleaseNotes()
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
    }

    @MainActor
    private func installVersionUpdate(_ result: UpdateChecker.UpdateResult) async {
        versionReleaseNotes = result.releaseNotes
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
