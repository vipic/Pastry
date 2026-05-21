import SwiftUI

// MARK: - 通知
extension Notification.Name {
    static let overlayRequestDismiss  = Notification.Name("overlayRequestDismiss")
    static let overlayDidHide        = Notification.Name("overlayDidHide")
    static let overlaySelectAll      = Notification.Name("overlaySelectAll")
    static let overlayDeleteSelected = Notification.Name("overlayDeleteSelected")
    static let overlayAlertActive    = Notification.Name("overlayAlertActive")
    static let overlayCloseSearch    = Notification.Name("overlayCloseSearch")
    static let overlayOpenSearch     = Notification.Name("overlayOpenSearch")
    static let overlayOpenSearchImmediate = Notification.Name("overlayOpenSearchImmediate")
    static let overlayMoveUp         = Notification.Name("overlayMoveUp")
    static let overlayMoveDown       = Notification.Name("overlayMoveDown")
    static let overlayMoveLeft       = Notification.Name("overlayMoveLeft")
    static let overlayMoveRight      = Notification.Name("overlayMoveRight")
    static let overlayConfirmPaste   = Notification.Name("overlayConfirmPaste")
    static let overlayAlertConfirm   = Notification.Name("overlayAlertConfirm")
    static let overlayCmdPaste       = Notification.Name("overlayCmdPaste")
    static let overlayCmdStateChanged = Notification.Name("overlayCmdStateChanged")
    static let overlaySearchEnterPaste = Notification.Name("overlaySearchEnterPaste")
}

// MARK: - 覆盖层主视图
struct OverlayView: View {

    @EnvironmentObject private var store: StoreManager

    @State private var cardVisible = false
    @State private var selection = SelectionState()
    @State private var renderedIds: Set<UUID> = []    // 当前已渲染（可见）的卡片 ID
    @State private var showDeleteConfirm = false
    @State private var showSearch = false
    @State private var showFilterPopover = false
    @State private var hoverSearch = false
    @State private var hoverFilter = false
    @State private var hoverGear = false
    @State private var hoverTab: StoreManager.PinTab? = nil
    @State private var cmdDown = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyHandler = KeyboardEventHandler()

    private let cardSpacing: CGFloat = 10
    private let bottomInset: CGFloat = 12
    private let animationDuration = 0.20

    // MARK: - Body

    var body: some View {
        applyModifiers(overlayContent)
    }

    private var overlayContent: some View {
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
    }

    private func applyModifiers<Content: View>(_ content: Content) -> AnyView {
        let step1 = AnyView(
            content
                .onAppear {
                    resetAllState()
                    keyHandler.installMouseMonitor()
                    withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
                        cardVisible = true
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayRequestDismiss)) { _ in
                    dismiss()
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayCloseSearch)) { note in
                    let clear = (note.userInfo?["clearFilter"] as? Bool) ?? true
                    closeSearch(clearFilter: clear)
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayOpenSearch)) { _ in
                    withAnimation { showSearch = true }
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayOpenSearchImmediate)) { _ in
                    withAnimation { showSearch = true }
                    isSearchFocused = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlaySelectAll)) { _ in
                    let ids = Set(visibleItems.map { $0.id })
                    withAnimation(.easeInOut(duration: 0.1)) { selection.selectedIds = ids }
                }
                .onReceive(store.$items) { items in
                    // 删除后自动清掉已不存在的选中 ID
                    let existing = Set(items.map { $0.id })
                    selection.selectedIds = selection.selectedIds.intersection(existing)
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayMoveUp)) { note in
                    handleArrowNotify(delta: -1, note: note)
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayMoveDown)) { note in
                    handleArrowNotify(delta: 1, note: note)
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayMoveLeft)) { note in
                    handleArrowNotify(delta: -1, note: note)
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayMoveRight)) { note in
                    handleArrowNotify(delta: 1, note: note)
                }
        )
        let step2 = AnyView(
            step1
                .onReceive(NotificationCenter.default.publisher(for: .overlayConfirmPaste)) { _ in
                    let ids = selection.selectedIds
                    guard !ids.isEmpty else { return }
                    let selected = visibleItems.filter { ids.contains($0.id) }
                    if selected.count == 1 {
                        Task { await OverlayPanelManager.shared.hideAndPaste(selected[0]) }
                    } else {
                        OverlayPanelManager.shared.hideAndPasteMultiple(selected)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayDeleteSelected)) { _ in
                    guard !selection.selectedIds.isEmpty else { return }
                    showDeleteConfirm = true
                }
                .alert(L10n["delete.confirm_title"], isPresented: $showDeleteConfirm) {
                    Button(L10n["delete.confirm_cancel"], role: .cancel) {}
                    Button(L10n["delete.confirm_ok"], role: .destructive) { deleteSelected() }
                } message: {
                    Text(String(format: L10n["delete.confirm_msg"], selection.selectedIds.count))
                }
                .onChange(of: showDeleteConfirm) {
                    NotificationCenter.default.post(name: .overlayAlertActive,
                                                    object: nil,
                                                    userInfo: ["active": showDeleteConfirm])
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayAlertConfirm)) { _ in
                    deleteSelected()
                    showDeleteConfirm = false
                }
        )
        return AnyView(
            step2
                .onReceive(NotificationCenter.default.publisher(for: .overlayCmdStateChanged)) { note in
                    cmdDown = (note.userInfo?["cmdDown"] as? Bool) ?? false
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayCmdPaste)) { note in
                    guard let idx = note.userInfo?["index"] as? Int,
                          idx > 0, idx <= visibleItems.count else { return }
                    let item = visibleItems[idx - 1]
                    Task { await OverlayPanelManager.shared.hideAndPaste(item) }
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlaySearchEnterPaste)) { _ in
                    // 搜索栏聚焦时按 Enter → 粘贴第一条可见卡片
                    guard let first = visibleItems.first else { return }
                    Task { await OverlayPanelManager.shared.hideAndPaste(first) }
                }
                .onChange(of: showSearch) { onShowSearchChanged() }
        )
    }

    private func onShowSearchChanged() {
        OverlayPanelManager.shared.isSearchActive = showSearch
        if showSearch {
            selection.reset()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        } else {
            isSearchFocused = false
            showFilterPopover = false
            // clearFilters 由 closeSearch(clearFilter:) 控制，不在这里自动清
        }
    }

    // MARK: - 状态重置

    private func resetAllState() {
        showSearch = false
        showFilterPopover = false
        isSearchFocused = false
        OverlayPanelManager.shared.isSearchActive = false
        store.clearFilters()
        selection.reset()
        renderedIds = []
    }

    // MARK: - 退场

    private func dismiss() {
        guard cardVisible else { return }
        keyHandler.uninstall()
        showSearch = false
        showFilterPopover = false
        isSearchFocused = false
        OverlayPanelManager.shared.isSearchActive = false
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
            cardVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            OverlayPanelManager.shared.hide()
        }
    }

    private func closeSearch(clearFilter: Bool) {
        guard showSearch else { return }
        if clearFilter { store.clearFilters() }
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
        store.deleteSelected(selection.selectedIds)
        selection.reset()
    }

    // MARK: - 搜索框（内联在 header 中）

    private var inlineSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.white.opacity(0.4))
                .font(.system(size: 12))

            TextField(L10n["search.placeholder"], text: $store.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(.white)
                .focused($isSearchFocused)
                .frame(maxWidth: 400)

            Button {
                store.searchQuery = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .opacity(store.searchQuery.isEmpty ? 0 : 1)
            .allowsHitTesting(!store.searchQuery.isEmpty)
            .onHover { hovering in
                if hovering { NSCursor.arrow.push() } else { NSCursor.arrow.pop() }
            }
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

    // MARK: - 筛选按钮

    private var filterButton: some View {
        Image(systemName: "line.3.horizontal.decrease")
            .font(.system(size: 13))
            .foregroundColor(showFilterPopover || hasActiveTimeOrTypeFilter ? .white : .white.opacity(hoverFilter ? 0.7 : 0.35))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hoverFilter ? Color.white.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selection.reset()
                showFilterPopover.toggle()
            }
            .onHover { hovering in
                hoverFilter = hovering
                if hovering { NSCursor.arrow.push() } else { NSCursor.arrow.pop() }
            }
            .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                FilterPopoverContent(store: store, onFilterChange: { selection.reset() })
            }
    }

    private var hasActiveTimeOrTypeFilter: Bool {
        store.typeFilter != nil || store.timeFilter != .any || store.appFilter != nil
    }

    // MARK: - 卡片容器

    @ViewBuilder
    private var cardContainer: some View {
        let displayItems = store.filteredItems

        VStack(spacing: 0) {
            headerRow

            VStack(spacing: 0) {
                if displayItems.isEmpty {
                    emptyState
                } else {
                    cardList(displayItems)
                        .padding(3)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.top, 10)
            .frame(minHeight: 262)  // 240 card + 6 LazyStack padding + 6 outer padding + 10 top
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(
            GlassBackground(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection.reset() }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Spacer()

            // 居中：搜索按钮/框 | tab 组
            if showSearch {
                // 搜索框展开 — 占用空间，tab 被挤到右侧
                inlineSearchField
                filterButton
                    .padding(.trailing, 6)

                tabButton(tab: .all, icon: "tray.full", label: L10n["tab.all"], isSelected: store.pinTab == .all)
                    .padding(.trailing, 6)
                tabButton(tab: .pinned, icon: "pin.fill", label: L10n["tab.pinned"], isSelected: store.pinTab == .pinned)
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

                filterButton
                    .padding(.trailing, 6)

                tabButton(tab: .all, icon: "tray.full", label: L10n["tab.all"], isSelected: store.pinTab == .all)
                    .padding(.trailing, 6)
                tabButton(tab: .pinned, icon: "pin.fill", label: L10n["tab.pinned"], isSelected: store.pinTab == .pinned)
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
        .overlay(alignment: .leading) {
            if selection.selectedIds.count > 1 {
                Text(L10n["toolbar.selected_count", selection.selectedIds.count])
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.leading, 12)
            }
        }
        .padding(.horizontal, 8)
    }

    private func tabButton(tab: StoreManager.PinTab, icon: String, label: String, isSelected: Bool) -> some View {
        Button {
            selection.reset()
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

    @State private var isHorizontalLayout: Bool = {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        return (screen?.frame.width ?? NSScreen.main?.frame.width ?? 1440) > 1200
    }()

    @ViewBuilder
    private func cardList(_ items: [ClipboardItem]) -> some View {
        if isHorizontalLayout {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: cardSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            cardView(item, index: idx)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.trailing, 8)
                }
                .animation(nil, value: items.count)
                .onChange(of: selection.cursorIndex) { oldIdx, newIdx in
                    guard let idx = newIdx, idx < items.count else { return }
                    let rendered = renderedIds.contains(items[idx].id)
                    let downward = (oldIdx ?? 0) < idx
                    let neighborIdx = downward ? idx + 1 : idx - 1
                    let neighborMissing = neighborIdx >= 0 && neighborIdx < items.count
                        && !renderedIds.contains(items[neighborIdx].id)
                    guard !rendered || neighborMissing else { return }
                    // 滚动目标：边缘时滚动邻卡（露出下一张），否则滚动当前卡
                    let scrollId = neighborMissing ? items[neighborIdx].id : items[idx].id
                    let anchor: UnitPoint = isHorizontalLayout
                        ? (downward ? .trailing : .leading)
                        : (downward ? .bottom : .top)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(scrollId, anchor: anchor)
                    }
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: cardSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            cardView(item, index: idx)
                                .frame(maxWidth: 400)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: 520)
                .animation(nil, value: items.count)
                .onChange(of: selection.cursorIndex) { oldIdx, newIdx in
                    guard let idx = newIdx, idx < items.count else { return }
                    let rendered = renderedIds.contains(items[idx].id)
                    let downward = (oldIdx ?? 0) < idx
                    let neighborIdx = downward ? idx + 1 : idx - 1
                    let neighborMissing = neighborIdx >= 0 && neighborIdx < items.count
                        && !renderedIds.contains(items[neighborIdx].id)
                    guard !rendered || neighborMissing else { return }
                    let scrollId = neighborMissing ? items[neighborIdx].id : items[idx].id
                    let anchor: UnitPoint = isHorizontalLayout
                        ? (downward ? .trailing : .leading)
                        : (downward ? .bottom : .top)
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(scrollId, anchor: anchor)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardView(_ item: ClipboardItem, index: Int) -> some View {
        ClipboardCardView(
            item: item,
            isSelected: selection.selectedIds.contains(item.id),
            cmdBadgeIndex: cmdDown && index < 9 ? index + 1 : nil,
            selectedIds: Binding(
                get: { selection.selectedIds },
                set: { selection.selectedIds = $0 }
            ),
            onTap: { tapped in
                handleCardTap(tapped)
            },
            onPin: { tapped, ids in
                if ids.contains(tapped.id), ids.count > 1 {
                    store.setPinForSelected(ids, pinned: !tapped.isPinned)
                } else {
                    store.togglePin(tapped)
                }
            },
            onDelete: { deleted in
                if selection.selectedIds.contains(deleted.id), selection.selectedIds.count > 1 {
                    deleteSelected()
                } else {
                    store.deleteItem(deleted)
                }
            }
        )
        .id(item.id)
        .onAppear { renderedIds.insert(item.id) }
        .onDisappear { renderedIds.remove(item.id) }
        .onDrag {
            OverlayPanelManager.shared.beginDragThrough()
            let ids = selection.selectedIds
            if ids.count > 1, ids.contains(item.id) {
                let selected = visibleItems.filter { ids.contains($0.id) }
                return DragPayloadBuilder.providerForSelection(selected) { item in
                    DatabaseManager.shared.loadFullContent(id: item.id)
                }
            } else {
                return DragPayloadBuilder.provider(for: item) { item in
                    DatabaseManager.shared.loadFullContent(id: item.id)
                }
            }
        }
        .overlay {
            MultiURLDragSourceView(urls: multiURLDragURLs(for: item))
        }
    }

    // MARK: - 选择交互

    private func multiURLDragURLs(for item: ClipboardItem) -> [URL] {
        let ids = selection.selectedIds
        guard ids.count > 1, ids.contains(item.id) else { return [] }

        let selected = visibleItems.filter { ids.contains($0.id) }
        let urls = selected.flatMap { DragPayloadBuilder.webURLs(in: $0) }
        return urls.count > 1 ? urls : []
    }

    /// 卡片单击：委托给 SelectionState
    private func handleCardTap(_ item: ClipboardItem) {
        selection.handleTap(
            item: item,
            cmdDown: keyHandler.lastMouseModifiers.contains(.command),
            shiftDown: keyHandler.lastMouseModifiers.contains(.shift),
            visibleItems: visibleItems
        )
    }

    // MARK: - 键盘事件

    /// 获取当前显示中的 items
    private var visibleItems: [ClipboardItem] {
        store.filteredItems
    }

    /// 处理通知发来的方向键事件
    private func handleArrowNotify(delta: Int, note: Notification) {
        guard !showSearch else { return }
        let extend = note.userInfo?["extend"] as? Bool ?? false
        moveCursor(delta: delta, extend: extend)
    }

    /// 方向键导航：委托给 SelectionState
    private func moveCursor(delta: Int, extend: Bool) {
        selection.moveCursor(delta: delta, extend: extend, visibleItems: visibleItems)
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
            message = L10n["empty.no_pins"]
        } else if isFiltered {
            icon = "magnifyingglass"
            message = L10n["empty.no_results"]
        } else {
            icon = "clipboard"
            message = L10n["empty.no_history"]
        }

        return VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.6))
            Text(message)
                .font(.body)
                .foregroundColor(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, minHeight: 252)  // 240 card + 6 Lazy + 6 outer = 252
    }
}

// MARK: - 键盘/鼠标事件处理器（类实例，避免 struct 捕获问题）
private final class KeyboardEventHandler: ObservableObject {
    var lastMouseModifiers: NSEvent.ModifierFlags = []  // 最近一次鼠标点击时的修饰键
    private var mouseMonitor: Any?

    func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.lastMouseModifiers = event.modifierFlags
            return event
        }
    }

    func uninstall() {
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }
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
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题栏
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
