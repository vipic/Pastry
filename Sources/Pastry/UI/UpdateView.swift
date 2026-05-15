import SwiftUI

// MARK: - 更新状态

enum UpdateState {
    case upToDate(version: String, build: String, lastCheckDate: Date?, lastReleaseNotes: String?)
    case updateAvailable(result: UpdateChecker.UpdateResult)
    case checking
    case error(String)
}

// MARK: - 更新窗口视图（Up-to-date / Update Available 两态共用）

struct UpdateView: View {
    @AppStorage("PastryLanguage") private var language = ""
    let state: UpdateState
    var onUpdate: (() -> Void)?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // App 图标
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
                .padding(.top, 28)
                .padding(.bottom, 16)

            // 标题行（状态文字 + 指示器）
            headingRow
                .padding(.bottom, 4)

            // 版本信息
            versionRow
                .padding(.bottom, 8)

            // 上次检查时间（仅 upToDate 显示）
            if case .upToDate(_, _, let lastCheck, _) = state, let date = lastCheck {
                lastCheckedRow(date)
                    .padding(.bottom, 16)
            } else {
                Color.clear.frame(height: 0)
                    .padding(.bottom, 16)
            }

            // 更新日志
            if case .updateAvailable(let result) = state {
                changelogSection(result.releaseNotes)
                    .padding(.bottom, 24)
            }
            if case .upToDate(_, _, _, let notes) = state, let notes = notes, !notes.isEmpty {
                changelogSection(notes)
                    .padding(.bottom, 24)
            }

            // 按钮区
            buttonRow
        }
        .padding(.horizontal, 40)
        .padding(.bottom, 28)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .id(language)
    }

    // MARK: - 标题行

    @ViewBuilder
    private var headingRow: some View {
        HStack(spacing: 8) {
            switch state {
            case .upToDate:
                Text(L10n["update.up_to_date"])
                    .font(.system(size: 17, weight: .semibold))
                ZStack {
                    Circle()
                        .fill(Color(red: 0.188, green: 0.82, blue: 0.345))
                        .frame(width: 18, height: 18)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }

            case .updateAvailable:
                Text(L10n["update.update_available"])
                    .font(.system(size: 17, weight: .semibold))
                Circle()
                    .fill(Color(red: 0.188, green: 0.82, blue: 0.345))
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(red: 0.188, green: 0.82, blue: 0.345).opacity(0.5), radius: 6)

            case .checking:
                Text(L10n["update.checking"])
                    .font(.system(size: 17, weight: .semibold))
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 18, height: 18)

            case .error:
                Text(L10n["update.check_failed"])
                    .font(.system(size: 17, weight: .semibold))
            }
        }
    }

    // MARK: - 上次检查时间

    private func lastCheckedRow(_ date: Date) -> some View {
        let formatter = RelativeDateTimeFormatter()
        let lang = UserDefaults.standard.string(forKey: "PastryLanguage") ?? ""
        formatter.locale = lang.hasPrefix("zh") ? Locale(identifier: "zh-Hans") : Locale(identifier: "en")
        let delta = Date().timeIntervalSince(date)
        let relative: String
        if abs(delta) < 3 {
            relative = lang.hasPrefix("zh") ? "刚刚" : "just now"
        } else {
            relative = formatter.localizedString(for: date, relativeTo: Date())
        }

        return Text(String(format: L10n["update.last_checked"], relative))
            .font(.system(size: 12))
            .foregroundColor(.secondary)
    }

    // MARK: - 版本行

    @ViewBuilder
    private var versionRow: some View {
        switch state {
        case .upToDate(let version, let build, _, _):
            Text("v\(version) · Build \(build)")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

        case .updateAvailable(let result):
            HStack(spacing: 6) {
                Text("v\(result.currentVersion)")
                    .foregroundColor(.secondary)
                Text("→")
                    .foregroundColor(.secondary.opacity(0.5))
                Text("v\(result.latestVersion)")
                    .fontWeight(.medium)
            }
            .font(.system(size: 13))

        case .checking:
            Text("Connecting to GitHub...")
                .font(.system(size: 13))
                .foregroundColor(.secondary)

        case .error(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 更新日志

    private func changelogSection(_ notes: String) -> some View {
        let items = parseChangelog(notes)

        return Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n["update.whats_new"])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6, height: 6)
                                    .padding(.top, 5)
                                Text(item)
                                    .font(.system(size: 13))
                                    .lineSpacing(2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
    }

    // MARK: - 按钮行

    @ViewBuilder
    private var buttonRow: some View {
        switch state {
        case .upToDate:
            HStack {
                Spacer()
                Button(L10n["update.ok"]) { onCancel?() }
                    .buttonStyle(SecondaryButtonStyle())
            }

        case .updateAvailable:
            HStack(spacing: 10) {
                Spacer()
                Button(L10n["update.cancel"]) { onCancel?() }
                    .buttonStyle(SecondaryButtonStyle())
                Button(L10n["update.update_btn"]) { onUpdate?() }
                    .buttonStyle(PrimaryButtonStyle())
            }

        case .checking:
            EmptyView()

        case .error:
            HStack {
                Spacer()
                Button(L10n["update.ok"]) { onCancel?() }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    // MARK: - 解析更新日志

    /// 将 GitHub Release body 解析为要点列表
    private func parseChangelog(_ body: String) -> [String] {
        let lines = body
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("-") || $0.hasPrefix("*") }
            .map { line -> String in
                var s = line
                // 去掉前缀 "- " / "* "
                if let idx = s.firstIndex(where: { $0 != "-" && $0 != "*" && $0 != " " }) {
                    s = String(s[idx...])
                }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }

        // 至少 1 条就显示
        return lines.count >= 1 ? lines : []
    }
}

// MARK: - 按钮样式

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.accentColor.opacity(0.2), radius: 3, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
