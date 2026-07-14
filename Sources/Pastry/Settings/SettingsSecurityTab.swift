import SwiftUI
import AppKit

// MARK: - Security Tab

extension SettingsSceneView {
    // MARK: - 安全 Tab

    var securityTab: some View {
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
                            title: L10n["settings.developer_diagnostics"],
                            help: L10n["settings.developer_diagnostics_hint"]
                        ) {
                            Toggle("", isOn: $performanceLoggingEnabled)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityIdentifier(AccessibilityIdentifiers.Settings.performanceLoggingToggle)
                        }

                        #if DEBUG
                        settingsDivider

                        settingsRow(
                            title: L10n["settings.development_onboarding"],
                            help: L10n["settings.development_onboarding_hint"]
                        ) {
                            Toggle("", isOn: $developmentShowOnboarding)
                                .labelsHidden()
                                .toggleStyle(SettingsSwitchStyle())
                                .accessibilityIdentifier(
                                    AccessibilityIdentifiers.Settings.developmentOnboardingToggle
                                )
                        }
                        #endif
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
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            excludedBundleIDs = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        }
    }

    var securityPermissionCard: some View {
        let model = AccessibilityPermissionRowModel.resolve(isTrusted: accessibilityTrusted)
        let badgeFill = accessibilityTrusted
            ? PastryPalette.successDeep
            : PastryPalette.warmAccent

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous)
                    .fill(badgeFill)
                Image(systemName: accessibilityTrusted ? "checkmark" : "exclamationmark")
                    .font(.system(size: UIConstants.TypeSize.title3, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: UIConstants.Badge.statusSize, height: UIConstants.Badge.statusSize)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                    .foregroundStyle(SettingsPalette.ink)
                Text(model.subtitle)
                    .font(.system(size: UIConstants.TypeSize.label))
                    .foregroundStyle(SettingsPalette.muted)
            }

            Spacer()

            Button(L10n["settings.accessibility_grant_btn"]) {
                openAccessibilitySettings()
            }
            .buttonStyle(SettingsPillButtonStyle(kind: .secondary))
            .accessibilityIdentifier(AccessibilityIdentifiers.Settings.accessibilityGrantButton)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCardChrome()
    }

    var excludedAppsSectionTitle: String {
        let count = installedExcludedBundleIDs.count
        guard count > 0 else { return L10n["settings.excluded_apps"] }
        return "\(L10n["settings.excluded_apps"]) \(count)"
    }

    var excludedEmptyRow: some View {
        Text(L10n["settings.excluded_empty"])
            .font(.system(size: UIConstants.TypeSize.label))
            .foregroundStyle(SettingsPalette.muted)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .padding(.horizontal, 10)
            .background(SettingsPalette.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
    }

    func excludedAppRow(_ bundleID: String) -> some View {
        HStack(spacing: 9) {
            appIcon(for: bundleID)
                .resizable()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous))

            Text(displayName(for: bundleID))
                .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
                .foregroundStyle(SettingsPalette.ink)
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
        .background(SettingsPalette.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: UIConstants.Radius.card, style: .continuous))
    }

    // MARK: - 辅助

    var accessibilityPermissionRow: some View {
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

    func refreshAccessibilityStatus() {
        accessibilityTrusted = AccessibilityPermissionChecker.shared.isTrusted()
    }

    func openAccessibilitySettings() {
        AccessibilityPermissionChecker.openSystemSettings()
    }

    // MARK: - 排除应用数据

    func addExcludedApp() {
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

    func removeExcludedApp(_ bundleID: String) {
        var current = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        current.removeAll { $0 == bundleID }
        UserDefaults.standard.set(current, forKey: UserDefaultsKeys.excludedBundleIDs)
        excludedBundleIDs = current
    }

    func isAppInstalled(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              FileManager.default.fileExists(atPath: url.path) else { return false }
        return true
    }

    var installedExcludedBundleIDs: [String] {
        excludedBundleIDs.filter { isAppInstalled(bundleID: $0) }
    }

    func appIcon(for bundleID: String) -> Image {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path {
            return Image(nsImage: NSWorkspace.shared.icon(forFile: path))
        }
        return Image(systemName: "questionmark.app")
    }

    func displayName(for bundleID: String) -> String {
        if let path = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: path.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

}
