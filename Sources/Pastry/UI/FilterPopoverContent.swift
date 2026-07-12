import SwiftUI

// MARK: - 筛选气泡共用表面色

/// 气泡本体与系统 popover 三角（`presentationBackground`）必须同一实色，
/// 否则箭头会和面板发色不一致。
enum FilterPopoverStyle {
    static let surface = PastryPalette.overlaySurface
}

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
        GridItem(.flexible(), spacing: UIConstants.Card.contentVerticalPadding),
        GridItem(.flexible(), spacing: UIConstants.Card.contentVerticalPadding),
        GridItem(.flexible(), spacing: UIConstants.Card.contentVerticalPadding)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Overlay.cardSpacing) {
            HStack {
                Text(L10n["filter.title"])
                    .font(.system(size: UIConstants.TypeSize.body, weight: .bold))
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
                .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                .foregroundColor(PastryPalette.warmGoldSoft)
                .padding(.horizontal, UIConstants.Card.footerBottomPadding)
                .frame(height: 24)
                .background(filterClearButtonBackground)
                .opacity(hasActiveFilter ? 1 : 0)
                .allowsHitTesting(hasActiveFilter)
                .buttonStyle(.plain)
            }
            .frame(height: UIConstants.Control.iconButtonSize)

            if !store.availableApps.isEmpty || hasHandoffItems {
                filterSection(title: L10n["filter.source_app"]) {
                    LazyVGrid(columns: gridColumns, spacing: UIConstants.Card.contentVerticalPadding) {
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
                LazyVGrid(columns: gridColumns, spacing: UIConstants.Card.contentVerticalPadding) {
                    ForEach(SourceFormat.allCases, id: \.rawValue) { format in
                        filterChip(format.label, iconName: format.iconName, isSelected: store.typeFilter == format) {
                            store.typeFilter = (store.typeFilter == format) ? nil : format
                            onFilterChange?()
                        }
                    }
                }
            }

            filterSection(title: L10n["filter.time"]) {
                LazyVGrid(columns: gridColumns, spacing: UIConstants.Card.contentVerticalPadding) {
                    ForEach(StoreManager.TimeFilter.allCases, id: \.rawValue) { tf in
                        filterChip(tf.label, isSelected: store.timeFilter == tf) {
                            store.timeFilter = tf
                            onFilterChange?()
                        }
                    }
                }
            }
        }
        .padding(UIConstants.Radius.cardLarge)
        .frame(width: 370)
        // 表面与三角由调用方 `.presentationBackground` 提供。
        // 不做内容层 fade/scale，以免叠在系统 popover 动画上。
        .drawingGroup(opaque: false)
    }

    private func filterSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: UIConstants.Card.footerBottomPadding) {
            Text(title)
                .font(.system(size: UIConstants.TypeSize.caption, weight: .bold))
                .foregroundColor(.white.opacity(0.62))
                .textCase(.uppercase)
            content()
        }
        .padding(UIConstants.Overlay.cardSpacing)
        .background(filterSectionBackground)
    }

    private func filterChip(_ label: String, iconName: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let iconName {
                    Image(systemName: iconName)
                        .font(.system(size: UIConstants.TypeSize.caption, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(FilterChipChrome.foreground(isSelected: isSelected))
            .padding(.horizontal, UIConstants.Card.footerBottomPadding)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(FilterChipChrome.background(isSelected: isSelected))
        }
        .buttonStyle(.plain)
    }

    private var filterSectionBackground: some View {
        RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
            .fill(Color.white.opacity(0.04))
    }

    private var filterClearButtonBackground: some View {
        RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
            .fill(Color.white.opacity(UIConstants.OnDark.fillSubtle))
    }

    /// 带应用图标的筛选标签
    private struct AppFilterChip: View {
        let app: String
        let isSelected: Bool
        let action: () -> Void
        @State private var icon: NSImage?

        init(app: String, isSelected: Bool, action: @escaping () -> Void) {
            self.app = app
            self.isSelected = isSelected
            self.action = action
            // 预取命中时首帧即有图标，避免打开动画中途批量 @State 刷新掉帧
            _icon = State(initialValue: AppIconProvider.shared.cachedIcon(for: app))
        }

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    appIcon
                    Text(app)
                        .font(.system(size: UIConstants.TypeSize.label, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundColor(FilterChipChrome.foreground(isSelected: isSelected))
                .padding(.horizontal, UIConstants.Card.footerBottomPadding)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .background(FilterChipChrome.background(isSelected: isSelected))
            }
            .buttonStyle(.plain)
            .task(id: app) {
                guard icon == nil else { return }
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
                Text(appInitial)
                    .font(.system(size: UIConstants.TypeSize.micro, weight: .heavy, design: .rounded))
                    .foregroundColor(.white.opacity(0.78))
                    .background(
                        Circle()
                            .fill(.white.opacity(UIConstants.OnDark.stroke))
                            .frame(width: 14, height: 14)
                    )
                    .frame(width: 14, height: 14)
            }
        }

        private var appInitial: String {
            app.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "A"
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

/// Shared chip fill/border/foreground for text chips and app chips.
enum FilterChipChrome {
    static func foreground(isSelected: Bool) -> Color {
        isSelected ? PastryPalette.warmInk : .white.opacity(UIConstants.OnDark.textSecondary)
    }

    static func background(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: UIConstants.Radius.chip, style: .continuous)
            .fill(isSelected ? PastryPalette.warmAccent : Color.white.opacity(UIConstants.OnDark.fillSubtle))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.chip, style: .continuous)
                    .stroke(
                        isSelected ? PastryPalette.warmAccent.opacity(0.35) : Color.clear,
                        lineWidth: UIConstants.Stroke.hairline
                    )
            )
    }
}
