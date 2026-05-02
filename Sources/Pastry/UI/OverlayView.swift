import SwiftUI

// MARK: - 通知
extension Notification.Name {
    static let overlayRequestDismiss  = Notification.Name("overlayRequestDismiss")
    static let overlayDidHide        = Notification.Name("overlayDidHide")
    static let overlaySelectAll      = Notification.Name("overlaySelectAll")
    static let overlayDeleteSelected = Notification.Name("overlayDeleteSelected")
    static let overlayAlertActive    = Notification.Name("overlayAlertActive")
    static let overlayCloseSearch    = Notification.Name("overlayCloseSearch")
}

// MARK: - 覆盖层主视图
struct OverlayView: View {

    @EnvironmentObject private var store: StoreManager

    @State private var cardVisible = false
    @State private var selectedIds: Set<UUID> = []
    @State private var showDeleteConfirm = false
    @State private var showSearch = false
    @State private var showFilterPanel = false
    @State private var hoverSearch = false
    @State private var hoverGear = false
    @State private var hoverTab: StoreManager.PinTab? = nil
    @FocusState private var isSearchFocused: Bool

    private let cardSpacing: CGFloat = 10
    private let bottomInset: CGFloat = 20
    private let animationDuration = 0.20

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                Spacer()

                cardContainer
                    .padding(.horizontal, 28)
                    .padding(.bottom, bottomInset)
                    .offset(y: cardVisible ? 0 : 200)
                    .opacity(cardVisible ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: showSearch)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            resetAllState()
            withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
                cardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayRequestDismiss)) { _ in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayCloseSearch)) { _ in
            closeSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlaySelectAll)) { _ in
            let ids = Set(store.items.map { $0.id })
            withAnimation(.easeInOut(duration: 0.1)) { selectedIds = ids }
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayDeleteSelected)) { _ in
            guard !selectedIds.isEmpty else { return }
            showDeleteConfirm = true
        }
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { deleteSelected() }
        } message: {
            Text("确定要删除 \(selectedIds.count) 条选中的记录吗？Pinned 项将被保留。")
        }
        .onChange(of: showDeleteConfirm) { active in
            NotificationCenter.default.post(name: .overlayAlertActive,
                                            object: nil,
                                            userInfo: ["active": active])
        }
        .onChange(of: showSearch) { active in
            OverlayPanelManager.shared.isSearchActive = active
            if active {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
                showFilterPanel = false
                store.clearFilters()
            }
        }
    }

    // MARK: - 状态重置

    private func resetAllState() {
        showSearch = false
        showFilterPanel = false
        isSearchFocused = false
        OverlayPanelManager.shared.isSearchActive = false
        store.clearFilters()
        selectedIds = []
    }

    // MARK: - 退场

    private func dismiss() {
        guard cardVisible else { return }
        showSearch = false
        showFilterPanel = false
        isSearchFocused = false
        OverlayPanelManager.shared.isSearchActive = false
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
            cardVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            OverlayPanelManager.shared.hide()
        }
    }

    private func closeSearch() {
        guard showSearch else { return }
        withAnimation {
            showSearch = false
        }
    }

    // MARK: - 设置

    private func openSettingsFromOverlay() {
        OverlayPanelManager.shared.hide()
        store.clearFilters()
        DispatchQueue.main.async {
            AppDelegate.shared?.openSettingsWindow()
        }
    }

    // MARK: - 批量删除

    private func deleteSelected() {
        store.deleteSelected(selectedIds)
        selectedIds = []
    }

    // MARK: - 搜索框（内联在 header 中）

    private var inlineSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 12))

            TextField("搜索...", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($isSearchFocused)
                .frame(maxWidth: 400)

            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            Button {
                withAnimation { showFilterPanel.toggle() }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12))
                    .foregroundColor(showFilterPanel || hasActiveTimeOrTypeFilter ? .white : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.25))
        )
        .padding(.trailing, 6)
    }

    private var hasActiveTimeOrTypeFilter: Bool {
        store.typeFilter != nil || store.timeFilter != .any || store.appFilter != nil
    }

    // MARK: - 筛选面板

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !store.availableApps.isEmpty {
                filterSection(title: "来源应用") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                        filterChip("全部", isSelected: store.appFilter == nil) {
                            store.appFilter = nil
                        }
                        ForEach(store.availableApps, id: \.self) { app in
                            filterChip(app, isSelected: store.appFilter == app) {
                                store.appFilter = (store.appFilter == app) ? nil : app
                            }
                        }
                    }
                }
            }

            filterSection(title: "类型") {
                HStack(spacing: 6) {
                    ForEach(ClipType.allCases, id: \.storageKey) { type in
                        filterChip(type.label, isSelected: store.typeFilter == type) {
                            store.typeFilter = (store.typeFilter == type) ? nil : type
                        }
                    }
                }
            }

            filterSection(title: "时间") {
                HStack(spacing: 6) {
                    ForEach(StoreManager.TimeFilter.allCases, id: \.rawValue) { tf in
                        filterChip(tf.rawValue, isSelected: store.timeFilter == tf) {
                            store.timeFilter = tf
                        }
                    }
                }
            }

            if hasActiveTimeOrTypeFilter {
                HStack {
                    Spacer()
                    Button("清除筛选") {
                        store.typeFilter = nil
                        store.appFilter = nil
                        store.timeFilter = .any
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
        .padding(.bottom, 6)
    }

    private func filterSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .textCase(.uppercase)
            content()
        }
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white : Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 卡片容器

    @ViewBuilder
    private var cardContainer: some View {
        let displayItems = store.filteredItems

        VStack(spacing: 0) {
            headerRow

            // 筛选面板
            if showSearch && showFilterPanel {
                filterPanel
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Group {
                if displayItems.isEmpty {
                    emptyState
                } else {
                    cardList(displayItems)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .frame(minHeight: 208)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(
            GlassBackground(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Spacer()

            // 居中：搜索按钮/框 | tab 组
            if showSearch {
                // 搜索框展开 — 占用空间，tab 被挤到右侧
                inlineSearchField

                tabButton(tab: .all, icon: "tray.full", label: "全部", isSelected: store.pinTab == .all)
                    .padding(.trailing, 6)
                tabButton(tab: .pinned, icon: "pin.fill", label: "已钉选", isSelected: store.pinTab == .pinned)
            } else {
                // 搜索按钮 — 原位紧凑
                Button {
                    withAnimation { showSearch = true }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(hoverSearch ? 0.7 : 0.35))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(hoverSearch ? Color.white.opacity(0.1) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hoverSearch = $0 }
                .padding(.trailing, 6)

                tabButton(tab: .all, icon: "tray.full", label: "全部", isSelected: store.pinTab == .all)
                    .padding(.trailing, 6)
                tabButton(tab: .pinned, icon: "pin.fill", label: "已钉选", isSelected: store.pinTab == .pinned)
            }

            Spacer()

            // 齿轮
            Button {
                openSettingsFromOverlay()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(hoverGear ? 0.85 : 0.55))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(hoverGear ? Color.white.opacity(0.1) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .onHover { hoverGear = $0 }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private func tabButton(tab: StoreManager.PinTab, icon: String, label: String, isSelected: Bool) -> some View {
        Button {
            store.pinTab = tab
        } label: {
            let isHover = hoverTab == tab
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: showSearch ? 12 : 11))
                if !showSearch {
                    Text(label)
                        .font(.system(size: 11))
                }
            }
            .foregroundColor(isSelected || isHover ? .white : .white.opacity(0.4))
            .padding(.horizontal, showSearch ? 6 : 10)
            .padding(.vertical, 4)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.12) : (isHover ? Color.white.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoverTab = hovering ? tab : nil
        }
    }

    // MARK: - 卡片列表

    @State private var isHorizontalLayout = NSScreen.main?.frame.width ?? 0 > 1200

    @ViewBuilder
    private func cardList(_ items: [ClipboardItem]) -> some View {
        if isHorizontalLayout {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: cardSpacing) {
                    ForEach(items) { item in
                        cardView(item)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .animation(nil, value: items.count)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: cardSpacing) {
                    ForEach(items) { item in
                        cardView(item)
                            .frame(maxWidth: 400)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 520)
            .animation(nil, value: items.count)
        }
    }

    @ViewBuilder
    private func cardView(_ item: ClipboardItem) -> some View {
        ClipboardCardView(
            item: item,
            isSelected: selectedIds.contains(item.id),
            onTap: { tapped in
                OverlayPanelManager.shared.hideAndPaste(tapped)
            },
            onPin: { _ in
                store.togglePin(item)
            }
        )
        .id(item.id)
    }

    // MARK: - 空状态

    private var emptyState: some View {
        let isPinnedTab = store.pinTab == .pinned
        let isFiltered = !store.searchQuery.isEmpty
            || store.typeFilter != nil
            || store.appFilter != nil
            || store.timeFilter != .any

        let icon: String
        let message: String

        if isPinnedTab && !isFiltered {
            icon = "pin.slash"
            message = "还没有钉选的内容"
        } else if isFiltered {
            icon = "magnifyingglass"
            message = "没有匹配的结果"
        } else {
            icon = "clipboard"
            message = "还没有剪贴板历史"
        }

        return VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.6))
            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, minHeight: 208)
    }
}
