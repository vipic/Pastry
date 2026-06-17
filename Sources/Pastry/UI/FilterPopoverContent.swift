import SwiftUI

// MARK: - 筛选气泡内容（NSPopover 内嵌 SwiftUI）

struct FilterPopoverContent: View {
    @ObservedObject var store: StoreManager
    var onFilterChange: (() -> Void)?

    private var hasActiveFilter: Bool {
        store.typeFilter != nil || store.timeFilter != .any || store.appFilter != nil || store.handoffFilter
    }

    /// 是否有来自其他设备(Handoff)的卡片
    private var hasHandoffItems: Bool {
        store.items.contains { $0.isHandoff }
    }

    /// 三列网格配置
    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n["filter.title"])
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.90))
                Spacer()
                Button(L10n["filter.clear"]) {
                    if hasActiveFilter {
                        store.typeFilter = nil
                        store.appFilter = nil
                        store.handoffFilter = false
                        store.timeFilter = .any
                        onFilterChange?()
                    }
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.90, green: 0.70, blue: 0.40))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(filterClearButtonBackground)
                .opacity(hasActiveFilter ? 1 : 0)
                .allowsHitTesting(hasActiveFilter)
                .buttonStyle(.plain)
            }
            .frame(height: 28)

            if !store.availableApps.isEmpty || hasHandoffItems {
                filterSection(title: L10n["filter.source_app"]) {
                    LazyVGrid(columns: gridColumns, spacing: 6) {
                        filterChip(L10n["filter.all"], isSelected: store.appFilter == nil && !store.handoffFilter) {
                            store.appFilter = nil
                            store.handoffFilter = false
                            onFilterChange?()
                        }
                        ForEach(store.availableApps, id: \.self) { app in
                            AppFilterChip(app: app, isSelected: store.appFilter == app) {
                                store.appFilter = (store.appFilter == app) ? nil : app
                                store.handoffFilter = false
                                onFilterChange?()
                            }
                        }
                        if hasHandoffItems {
                            filterChip(L10n["filter.handoff"], iconName: "laptopcomputer.and.iphone", isSelected: store.handoffFilter) {
                                store.appFilter = nil
                                store.handoffFilter.toggle()
                                onFilterChange?()
                            }
                        }
                    }
                }
            }

            filterSection(title: L10n["filter.type"]) {
                LazyVGrid(columns: gridColumns, spacing: 6) {
                    ForEach(SourceFormat.allCases, id: \.rawValue) { format in
                        filterChip(format.label, iconName: format.iconName, isSelected: store.typeFilter == format) {
                            store.typeFilter = (store.typeFilter == format) ? nil : format
                            onFilterChange?()
                        }
                    }
                }
            }

            filterSection(title: L10n["filter.time"]) {
                LazyVGrid(columns: gridColumns, spacing: 6) {
                    ForEach(StoreManager.TimeFilter.allCases, id: \.rawValue) { tf in
                        filterChip(tf.label, isSelected: store.timeFilter == tf) {
                            store.timeFilter = tf
                            onFilterChange?()
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 370)
        .background(filterPanelBackground)
    }

    private func filterSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.62))
                .textCase(.uppercase)
            content()
        }
        .padding(10)
        .background(filterSectionBackground)
    }

    private func filterChip(_ label: String, iconName: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(chipForeground(isSelected: isSelected))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(chipBackground(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private var filterPanelBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.27, green: 0.30, blue: 0.31).opacity(0.76),
                                Color(red: 0.17, green: 0.20, blue: 0.21).opacity(0.70)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.16), .white.opacity(0.04), .black.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
            .shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 10)
    }

    private var filterSectionBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        .white.opacity(0.055),
                        .white.opacity(0.025)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.065), lineWidth: 1)
            )
    }

    private var filterClearButtonBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [.white.opacity(0.10), .white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            )
    }

    private func chipForeground(isSelected: Bool) -> Color {
        isSelected ? Color(red: 0.23, green: 0.15, blue: 0.06) : .white.opacity(0.72)
    }

    private func chipBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(chipFill(isSelected: isSelected))
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(chipBorder(isSelected: isSelected), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(isSelected ? 0.30 : 0.10), lineWidth: 1)
                        .padding(1)
                }
            )
            .shadow(color: chipShadow(isSelected: isSelected), radius: isSelected ? 3 : 1.5, x: 0, y: isSelected ? 2 : 1)
    }

    private func chipFill(isSelected: Bool) -> LinearGradient {
        let colors: [Color] = isSelected
            ? [
                Color(red: 0.88, green: 0.67, blue: 0.35),
                Color(red: 0.74, green: 0.46, blue: 0.18)
            ]
            : [
                .white.opacity(0.12),
                .white.opacity(0.055)
            ]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private func chipBorder(isSelected: Bool) -> Color {
        isSelected
            ? Color(red: 0.72, green: 0.45, blue: 0.15).opacity(0.52)
            : .white.opacity(0.10)
    }

    private func chipShadow(isSelected: Bool) -> Color {
        isSelected
            ? Color(red: 0.38, green: 0.20, blue: 0.08).opacity(0.24)
            : .black.opacity(0.08)
    }

    /// 带应用图标的筛选标签
    private struct AppFilterChip: View {
        let app: String
        let isSelected: Bool
        let action: () -> Void
        @State private var icon: NSImage?

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    appIcon
                    Text(app)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundColor(isSelected ? Color(red: 0.23, green: 0.15, blue: 0.06) : .white.opacity(0.72))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(AppFilterChipBackground(isSelected: isSelected))
            }
            .buttonStyle(.plain)
            .task(id: app) {
                await loadIcon()
            }
        }

        @ViewBuilder
        private var appIcon: some View {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14, height: 14)
            }
        }

        private func loadIcon() async {
            guard icon == nil else { return }
            let loaded = await Task.detached(priority: .utility) {
                AppIconProvider.shared.icon(for: app)
            }.value
            guard !Task.isCancelled else { return }
            icon = loaded
        }
    }
}

private struct AppFilterChipBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(border, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(isSelected ? 0.30 : 0.10), lineWidth: 1)
                        .padding(1)
                }
            )
            .shadow(color: shadow, radius: isSelected ? 3 : 1.5, x: 0, y: isSelected ? 2 : 1)
    }

    private var fill: LinearGradient {
        let colors: [Color] = isSelected
            ? [
                Color(red: 0.88, green: 0.67, blue: 0.35),
                Color(red: 0.74, green: 0.46, blue: 0.18)
            ]
            : [
                .white.opacity(0.12),
                .white.opacity(0.055)
            ]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var border: Color {
        isSelected
            ? Color(red: 0.72, green: 0.45, blue: 0.15).opacity(0.52)
            : .white.opacity(0.10)
    }

    private var shadow: Color {
        isSelected
            ? Color(red: 0.38, green: 0.20, blue: 0.08).opacity(0.24)
            : .black.opacity(0.08)
    }
}
