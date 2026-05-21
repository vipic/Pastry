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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                if hasActiveFilter {
                    Button(L10n["filter.clear"]) {
                        store.typeFilter = nil
                        store.appFilter = nil
                        store.handoffFilter = false
                        store.timeFilter = .any
                        onFilterChange?()
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .buttonStyle(.plain)
                }
            }

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
        .padding(12)
        .frame(width: 360)
    }

    private func filterSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            content()
        }
    }

    private func filterChip(_ label: String, iconName: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 10))
                }
                Text(label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(isSelected ? .black : .primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? Color.white : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
    }

    /// 带应用图标的筛选标签
    private struct AppFilterChip: View {
        let app: String
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                let icon = AppIconProvider.shared.icon(for: app)
                HStack(spacing: 5) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text(app)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundColor(isSelected ? .black : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white : Color.primary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
    }
}
