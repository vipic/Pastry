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
    var launchAtLogin = false

    @AppStorage(UserDefaultsKeys.soundEnabled)
    var soundEnabled = false

    @AppStorage(UserDefaultsKeys.cardClickMode)
    var cardClickModeRaw = CardClickMode.default.rawValue

    @AppStorage(UserDefaultsKeys.linkPreviewNetworkEnabled)
    var linkPreviewNetworkEnabled = false
    @AppStorage(UserDefaultsKeys.performanceLoggingEnabled)
    var performanceLoggingEnabled = false
    @AppStorage(UserDefaultsKeys.historyMaxItems)
    var historyMaxItems = HistoryRetentionPolicy.defaultMaxItems
    @AppStorage(UserDefaultsKeys.historyMaxAgeDays)
    var historyMaxAgeDays = HistoryRetentionPolicy.defaultMaxAgeDays

    @AppStorage(UserDefaultsKeys.hotkeyKeyCode)
    var hotkeyKeyCode = Int(GlobalHotkeyManager.defaultKeyCode)
    @AppStorage(UserDefaultsKeys.hotkeyModifiers)
    var hotkeyModifiers = Int(GlobalHotkeyManager.defaultModifiers)

    @State var showingClearConfirm = false
    @State var accessibilityTrusted = false
    @State var selectedTab: SettingsTab?
    @State var selectedLanguage: Language
    @State var excludedBundleIDs: [String] = []
    @State var versionUpdateState: UpdateState = .upToDate(
        version: AppVersion.displayCurrent,
        build: AppVersion.displayBuild,
        lastCheckDate: nil,
        lastReleaseNotes: nil
    )
    @State var versionReleaseNotes: String?
    @State var versionReleaseHistory: [UpdateChecker.ReleaseNote] = []
    @State var versionCurrentVersion: String?
    @State var versionLatestVersion: String?
    @State var didAutoCheckVersionInCurrentWindow = false
    @State var isVersionCheckInFlight = false
    @State var isRecordingShortcut = false
    @State var shortcutPreviewKeyCode: Int?
    @State var shortcutPreviewModifiers = 0

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
                detail(for: selectedTab ?? .general)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(SettingsPalette.cream)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(removing: .sidebarToggle)
            .toolbarVisibility(.hidden, for: .windowToolbar)
            .background(SettingsPalette.cream)
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

    var settingsSidebar: some View {
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
        .background(SettingsPalette.sidebar)
        .ignoresSafeArea(.container, edges: .top)
    }

    var sidebarFooterNote: some View {
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

    func sidebarTabButton(_ tab: SettingsTab) -> some View {
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
    func sidebarTabGlyph(_ tab: SettingsTab, isSelected: Bool) -> some View {
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


    // MARK: - 详情内容

    @ViewBuilder
    func detail(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:  generalTab
        case .shortcut: shortcutTab
        case .security: securityTab
        case .version:  versionTab
        case .about:    aboutTab
        }
    }

    func settingsPaneHeader(title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(SettingsPalette.ink)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(SettingsPalette.muted)
                    .lineSpacing(1)
                    .frame(maxWidth: 460, alignment: .leading)
            }

            Spacer()
        }
        .padding(.bottom, 6)
    }

    func metricCard(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(SettingsPalette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(SettingsPalette.muted)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .settingsCardChrome(fill: SettingsPalette.cardFillSoft)
    }

    func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(SettingsPalette.muted)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 9)

            Rectangle()
                .fill(SettingsPalette.ink.opacity(0.10))
                .frame(height: 1)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .settingsCardChrome(clip: true)
    }

    func settingsRow<Control: View>(
        title: String,
        help: String? = nil,
        danger: Bool = false,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(danger ? .red : SettingsPalette.ink)
                if let help {
                    Text(help)
                        .font(.system(size: 11))
                        .foregroundStyle(SettingsPalette.muted)
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

    var settingsDivider: some View {
        Rectangle()
            .fill(SettingsPalette.ink.opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }
}

