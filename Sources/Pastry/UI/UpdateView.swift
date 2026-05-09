import SwiftUI

// MARK: - 更新窗口
enum UpdateWindow {
    private static var window: NSWindow?

    /// 显示「已是新版本」
    static func showUpToDate() {
        showWindow {
            UpToDateView()
        }
    }

    /// 显示更新提示
    static func showUpdateAvailable(_ result: UpdateChecker.UpdateResult,
                                    onUpdate: @escaping () -> Void) {
        showWindow {
            UpdateAvailableView(result: result, onUpdate: onUpdate)
        }
    }

    /// 显示下载/安装进度
    static func showProgress() -> NSWindow {
        let w = createWindow()
        w.contentView = NSHostingView(rootView: UpdateProgressView())
        w.makeKeyAndOrderFront(nil)
        return w
    }

    /// 显示错误
    static func showError(_ message: String) {
        showWindow {
            UpdateErrorView(message: message)
        }
    }

    // MARK: - Private

    private static func showWindow<Content: View>(content: @escaping () -> Content) {
        if let existing = window {
            existing.contentView = NSHostingView(rootView: content())
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let w = createWindow()
        w.contentView = NSHostingView(rootView: content())
        w.makeKeyAndOrderFront(nil)
        window = w
    }

    private static func createWindow() -> NSWindow {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = L10n["update.title"]
        w.isReleasedWhenClosed = false
        w.center()
        return w
    }
}

// MARK: - 已是新版本

private struct UpToDateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text(L10n["update.uptodate"])
                .font(.system(size: 14, weight: .semibold))

            Text("Pastry \(appVersion)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - 有更新

private struct UpdateAvailableView: View {
    let result: UpdateChecker.UpdateResult
    let onUpdate: () -> Void

    @State private var isUpdating = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.blue)

            Text(L10n["update.available"])
                .font(.system(size: 14, weight: .semibold))

            HStack(spacing: 16) {
                VersionBadge(label: L10n["update.current"], version: result.currentVersion)
                VersionBadge(label: L10n["update.latest"], version: result.latestVersion)
            }

            if !result.releaseNotes.isEmpty {
                Text(result.releaseNotes)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if isUpdating {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(L10n["update.download_and_install"]) {
                    isUpdating = true
                    onUpdate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

private struct VersionBadge: View {
    let label: String
    let version: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(version)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
}

// MARK: - 下载中

private struct UpdateProgressView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()

            Text(L10n["update.downloading"])
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

// MARK: - 错误

private struct UpdateErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 36))
                .foregroundColor(.red)

            Text(L10n["update.failed"])
                .font(.system(size: 13, weight: .semibold))

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}
