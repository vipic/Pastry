import SwiftUI
import AppKit

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
    static let overlayMoveHome       = Notification.Name("overlayMoveHome")
    static let overlayMoveEnd        = Notification.Name("overlayMoveEnd")
    static let overlayMovePageUp     = Notification.Name("overlayMovePageUp")
    static let overlayMovePageDown   = Notification.Name("overlayMovePageDown")
    static let overlayMoveCursor     = Notification.Name("overlayMoveCursor")
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
    @State private var iconPrefetchTask: Task<Void, Never>?

    @State private var cachedMultiSelectDrag: DragPayloadBuilder.SelectionPayload?

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
                    .padding(.horizontal, UIConstants.Overlay.horizontalPadding)
                    .padding(.bottom, UIConstants.Overlay.bottomInset)
                    .offset(y: cardVisible ? 0 : 200)
                    .opacity(cardVisible ? 1 : 0)
            }
            .animation(.easeInOut(duration: 0.2), value: showSearch)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.root)
    }

    private func applyModifiers<Content: View>(_ content: Content) -> AnyView {
        let step1 = AnyView(
            content
                .onAppear {
                    resetAllState()
                    keyHandler.installMouseMonitor()
                    prefetchAvailableAppIcons()
                    withAnimation(.spring(response: UIConstants.Overlay.animationDuration, dampingFraction: 0.82)) {
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
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                    updateLayoutForCurrentScreen()
                }
                .onChange(of: selection.selectedIds) { _, _ in
                    cachedMultiSelectDrag = nil
                }
                .onReceive(store.$items) { items in
                    let existing = Set(items.map(\.id))
                    selection.selectedIds = selection.selectedIds.intersection(existing)
                    prefetchAvailableAppIcons()
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayMoveCursor)) { note in
                    handleCursorMove(note)
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayConfirmPaste)) { _ in
                    handleConfirmPaste()
                }
        )
        return AnyView(
            step1
                .onReceive(NotificationCenter.default.publisher(for: .overlayDeleteSelected)) { _ in
                    handleDeleteSelectedRequest()
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
                .onReceive(NotificationCenter.default.publisher(for: .overlayCmdStateChanged)) { note in
                    cmdDown = (note.userInfo?["cmdDown"] as? Bool) ?? false
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayCmdPaste)) { note in
                    handleCommandPaste(note)
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlaySearchEnterPaste)) { _ in
                    handleSearchEnterPaste()
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

    private func handleConfirmPaste() {
        let ids = selection.selectedIds
        guard !ids.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        let selected = OverlayInteractionModel.selectedItems(
            visibleItems: visibleItems,
            selectedIds: ids
        )
        if selected.count == 1 {
            Task { await OverlayPanelManager.shared.hideAndPaste(selected[0]) }
        } else {
            OverlayPanelManager.shared.hideAndPasteMultiple(selected)
        }
    }

    private func handleDeleteSelectedRequest() {
        guard !selection.selectedIds.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        showDeleteConfirm = true
    }

    private func handleCommandPaste(_ note: Notification) {
        guard let idx = note.userInfo?["index"] as? Int,
              idx > 0,
              idx <= visibleItems.count else {
            SoundFeedback.invalidAction()
            return
        }
        let item = visibleItems[idx - 1]
        Task { await OverlayPanelManager.shared.hideAndPaste(item) }
    }

    private func handleSearchEnterPaste() {
        guard let first = visibleItems.first else {
            SoundFeedback.invalidAction()
            return
        }
        Task { await OverlayPanelManager.shared.hideAndPaste(first) }
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
        iconPrefetchTask?.cancel()
        iconPrefetchTask = nil
        showSearch = false
        showFilterPopover = false
        isSearchFocused = false
        OverlayPanelManager.shared.isSearchActive = false
        withAnimation(.spring(response: UIConstants.Overlay.animationDuration, dampingFraction: 0.82)) {
            cardVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + UIConstants.Overlay.animationDuration) {
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
                .foregroundColor(.white.opacity(0.46))
                .font(.system(size: 12))

            ZStack(alignment: .leading) {
                if store.searchQuery.isEmpty {
                    Text(L10n["search.placeholder"])
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.68))
                        .allowsHitTesting(false)
                }

                TextField("", text: $store.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.92))
                    .focused($isSearchFocused)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.searchField)
            }
            .frame(maxWidth: 400)

            Button {
                store.searchQuery = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.clearSearchButton)
            .opacity(store.searchQuery.isEmpty ? 0 : 1)
            .allowsHitTesting(!store.searchQuery.isEmpty)
            .onHover { hovering in
                if hovering { NSCursor.arrow.push() } else { NSCursor.arrow.pop() }
            }

            if showSearch {
                Text(searchCountText)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.66))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.08))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(height: 32)
        .background(overlaySearchFieldBackground)
        .padding(.trailing, 6)
    }

    // MARK: - 筛选按钮

    private var filterButton: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(toolbarForeground(isActive: showFilterPopover || hasActiveTimeOrTypeFilter, isHovered: hoverFilter))
                .frame(width: 32, height: 32)

            if activeFilterCount > 0 {
                Text("\(activeFilterCount)")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundColor(Color(red: 0.23, green: 0.15, blue: 0.06))
                    .monospacedDigit()
                    .frame(minWidth: 14, minHeight: 14)
                    .background(
                        Circle()
                            .fill(Color(red: 0.90, green: 0.70, blue: 0.40))
                            .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                    )
                    .offset(x: 4, y: -4)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            }
        }
            .frame(width: 32, height: 32)
            .background(toolbarButtonBackground(isActive: showFilterPopover || hasActiveTimeOrTypeFilter, isHovered: hoverFilter))
            .contentShape(Rectangle())
            .onTapGesture {
                showFilterPopover.toggle()
                DispatchQueue.main.async {
                    selection.reset()
                }
            }
            .onHover { hovering in
                hoverFilter = hovering
                if hovering { NSCursor.arrow.push() } else { NSCursor.arrow.pop() }
            }
            .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                FilterPopoverContent(store: store, onFilterChange: { selection.reset() })
                    .presentationBackground(filterPopoverPresentationBackground)
            }
            .scaleEffect(toolbarHoverScale(isHovered: hoverFilter))
            .animation(.easeOut(duration: 0.10), value: hoverFilter)
            .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.filterButton)
    }

    private var filterPopoverPresentationBackground: Color {
        Color(red: 0.18, green: 0.21, blue: 0.22).opacity(0.92)
    }

    private var searchCountText: String {
        "\(store.filteredItems.count)/\(store.items.count)"
    }

    private var activeFilterCount: Int {
        [store.typeFilter != nil, store.timeFilter != .any, store.appFilter != nil, store.handoffFilter, store.urlFilter]
            .filter { $0 }
            .count
    }

    private var hasActiveTimeOrTypeFilter: Bool {
        activeFilterCount > 0
    }

    // MARK: - 卡片容器

    @ViewBuilder
    private var cardContainer: some View {
        let displayItems = store.filteredItems
        let multiSelectDrag = multiSelectionDragPayload(items: displayItems)

        VStack(spacing: 0) {
            headerRow

            VStack(spacing: 0) {
                if displayItems.isEmpty {
                    emptyState
                } else {
                    cardList(displayItems, multiSelectDrag: multiSelectDrag)
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
        .background(panelTrayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 30, x: 0, y: 20)
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture { selection.reset() }
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.cardContainer)
    }

    private var panelTrayBackground: some View {
        ZStack {
            GlassBackground(cornerRadius: 24)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.27, green: 0.30, blue: 0.31).opacity(0.72),
                            Color(red: 0.18, green: 0.21, blue: 0.22).opacity(0.66)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.13),
                            .white.opacity(0.04),
                            .black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.20),
                            .white.opacity(0.06),
                            .black.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
                .padding(1.5)
        }
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
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(toolbarForeground(isActive: false, isHovered: hoverSearch))
                        .frame(width: 32, height: 32)
                        .background(toolbarButtonBackground(isActive: false, isHovered: hoverSearch))
                }
                .buttonStyle(.plain)
                .scaleEffect(toolbarHoverScale(isHovered: hoverSearch))
                .animation(.easeOut(duration: 0.10), value: hoverSearch)
                .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.searchButton)
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(toolbarForeground(isActive: false, isHovered: hoverGear))
                    .frame(width: 32, height: 32)
                    .background(toolbarButtonBackground(isActive: false, isHovered: hoverGear))
            }
            .buttonStyle(.plain)
            .scaleEffect(toolbarHoverScale(isHovered: hoverGear))
            .animation(.easeOut(duration: 0.10), value: hoverGear)
            .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.settingsButton)
            .onHover { hoverGear = $0 }
        }
        .overlay(alignment: .leading) {
            if selection.selectedIds.count > 1 {
                Text(L10n["toolbar.selected_count", selection.selectedIds.count])
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.68))
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
            .padding(.horizontal, showSearch ? 6 : 10)
            .padding(.vertical, 4)
            .frame(height: 32)
            .foregroundColor(toolbarForeground(isActive: isSelected, isHovered: isHover))
            .background(toolbarButtonBackground(isActive: isSelected, isHovered: isHover))
        }
        .buttonStyle(.plain)
        .scaleEffect(toolbarHoverScale(isHovered: hoverTab == tab))
        .animation(.easeOut(duration: 0.10), value: hoverTab)
        .accessibilityIdentifier(tab == .all ? AccessibilityIdentifiers.Overlay.allTab : AccessibilityIdentifiers.Overlay.pinnedTab)
        .onHover { hovering in
            hoverTab = hovering ? tab : nil
        }
    }

    private var overlaySearchFieldBackground: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.34),
                        Color(red: 0.16, green: 0.18, blue: 0.19).opacity(0.24)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(.black.opacity(0.28), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                        .padding(1)
                }
            )
            .shadow(color: .black.opacity(0.28), radius: 0, x: 0, y: 1)
            .shadow(color: .white.opacity(0.08), radius: 0, x: 0, y: -1)
    }

    private func toolbarForeground(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return Color(red: 0.23, green: 0.15, blue: 0.06)
        }
        return .white.opacity(isHovered ? 0.86 : 0.62)
    }

    private func toolbarHoverScale(isHovered: Bool) -> CGFloat {
        showFilterPopover ? 1 : (isHovered ? 1.015 : 1)
    }

    private func toolbarButtonBackground(isActive: Bool, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(toolbarButtonFill(isActive: isActive, isHovered: isHovered))
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(toolbarButtonBorder(isActive: isActive), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(isActive ? 0.30 : 0.13), lineWidth: 1)
                        .padding(1)
                }
            )
            .shadow(color: toolbarButtonShadow(isActive: isActive), radius: isActive ? 3 : 2, x: 0, y: isActive ? 2 : 1)
            .shadow(color: .white.opacity(isActive ? 0.22 : 0.08), radius: 0, x: 0, y: 1)
    }

    private func toolbarButtonFill(isActive: Bool, isHovered: Bool) -> LinearGradient {
        let colors: [Color]
        if isActive {
            colors = [
                Color(red: 0.88, green: 0.67, blue: 0.35),
                Color(red: 0.74, green: 0.46, blue: 0.18)
            ]
        } else {
            colors = [
                .white.opacity(isHovered ? 0.16 : 0.10),
                .white.opacity(isHovered ? 0.08 : 0.045)
            ]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private func toolbarButtonBorder(isActive: Bool) -> Color {
        isActive
            ? Color(red: 0.72, green: 0.45, blue: 0.15).opacity(0.52)
            : .white.opacity(0.10)
    }

    private func toolbarButtonShadow(isActive: Bool) -> Color {
        isActive
            ? Color(red: 0.38, green: 0.20, blue: 0.08).opacity(0.18)
            : .black.opacity(0.12)
    }

    // MARK: - 卡片列表

    @State private var isHorizontalLayout: Bool = {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        return (screen?.frame.width ?? NSScreen.main?.frame.width ?? 1440) > 1200
    }()

    /// 屏幕配置变化时重新评估布局方向（用户拖面板到不同分辨率屏幕）
    private func updateLayoutForCurrentScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
        let useHorizontal = (screen?.frame.width ?? NSScreen.main?.frame.width ?? 1440) > 1200
        if useHorizontal != isHorizontalLayout {
            isHorizontalLayout = useHorizontal
        }
    }

    @ViewBuilder
    private func cardList(_ items: [ClipboardItem], multiSelectDrag: DragPayloadBuilder.SelectionPayload?) -> some View {
        if isHorizontalLayout {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: UIConstants.Overlay.cardSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            cardView(item, index: idx, multiSelectDrag: multiSelectDrag)
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
                    LazyVStack(spacing: UIConstants.Overlay.cardSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                            cardView(item, index: idx, multiSelectDrag: multiSelectDrag)
                                .frame(maxWidth: UIConstants.Overlay.compactCardMaxWidth)
                        }
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                }
                .frame(maxWidth: UIConstants.Overlay.compactListMaxWidth)
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
    private func cardView(_ item: ClipboardItem, index: Int, multiSelectDrag: DragPayloadBuilder.SelectionPayload?) -> some View {
        let isInMultiSelection = multiSelectDrag != nil && selection.selectedIds.contains(item.id)
        ClipboardCardView(
            item: item,
            isSelected: selection.selectedIds.contains(item.id),
            cmdBadgeIndex: OverlayInteractionModel.commandBadgeIndex(cmdDown: cmdDown, itemIndex: index),
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
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.card(item.id.uuidString))
        .onAppear { renderedIds.insert(item.id) }
        .onDisappear { renderedIds.remove(item.id) }
        .onDrag {
            if isInMultiSelection {
                let selected = visibleItems.filter { selection.selectedIds.contains($0.id) }
                return DragPayloadBuilder.providerForSelection(selected) { item in
                    DatabaseManager.shared.loadFullContent(id: item.id)
                }
            } else {
                OverlayPanelManager.shared.beginDragThrough()
                return DragPayloadBuilder.provider(for: item) { item in
                    DatabaseManager.shared.loadFullContent(id: item.id)
                }
            }
        }
        .overlay {
            if let drag = multiSelectDrag, isInMultiSelection {
                MultiSelectionDragSourceView(
                    isActive: true,
                    itemCount: selection.selectedIds.count,
                    payloadText: drag.text,
                    payloadWebURLs: drag.webURLs,
                    payloadFileURLs: drag.fileURLs
                )
            }
        }
    }

    // MARK: - 选择交互

    private func multiSelectionDragPayload(items: [ClipboardItem]) -> DragPayloadBuilder.SelectionPayload? {
        let ids = selection.selectedIds
        guard ids.count > 1 else {
            if cachedMultiSelectDrag != nil { cachedMultiSelectDrag = nil }
            return nil
        }
        if let cached = cachedMultiSelectDrag { return cached }
        let selected = items.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return nil }
        let payload = DragPayloadBuilder.payloadForSelection(selected) { item in
            DatabaseManager.shared.loadFullContent(id: item.id)
        }
        let result = payload.isEmpty ? nil : payload
        cachedMultiSelectDrag = result
        return result
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

    private var pageNavigationStep: Int {
        isHorizontalLayout ? 3 : 4
    }

    /// 处理键盘导航通知：方向键、翻页、首尾跳转统一进入这里。
    private func handleCursorMove(_ note: Notification) {
        guard !showSearch else { return }
        let extend = note.userInfo?["extend"] as? Bool ?? false
        if let target = note.userInfo?["target"] as? String {
            switch target {
            case "home":
                moveCursor(to: 0, extend: extend)
            case "end":
                moveCursor(to: visibleItems.count - 1, extend: extend)
            default:
                SoundFeedback.invalidAction()
            }
            return
        }
        if let pageDelta = note.userInfo?["pageDelta"] as? Int {
            moveCursor(delta: pageDelta * pageNavigationStep, extend: extend)
            return
        }
        if let delta = note.userInfo?["delta"] as? Int {
            moveCursor(delta: delta, extend: extend)
        }
    }

    /// 方向键导航：委托给 SelectionState，触达边界时给出统一错误反馈。
    private func moveCursor(delta: Int, extend: Bool) {
        if selection.wouldHitBoundary(delta: delta, visibleItems: visibleItems) {
            SoundFeedback.invalidAction()
        }
        selection.moveCursor(delta: delta, extend: extend, visibleItems: visibleItems)
    }

    private func moveCursor(to targetIndex: Int, extend: Bool) {
        if selection.wouldHitBoundary(targetIndex: targetIndex, visibleItems: visibleItems) {
            SoundFeedback.invalidAction()
        }
        selection.moveCursor(to: targetIndex, extend: extend, visibleItems: visibleItems)
    }

    private func prefetchAvailableAppIcons() {
        let apps = store.availableApps
        guard !apps.isEmpty else { return }
        iconPrefetchTask?.cancel()
        iconPrefetchTask = Task.detached(priority: .utility) {
            for app in apps.prefix(24) {
                guard !Task.isCancelled else { return }
                _ = AppIconProvider.shared.icon(for: app)
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        let hasActiveFilters = OverlayInteractionModel.hasActiveFilters(
            searchQuery: store.searchQuery,
            typeFilter: store.typeFilter,
            appFilter: store.appFilter,
            timeFilter: store.timeFilter,
            urlFilter: store.urlFilter,
            handoffFilter: store.handoffFilter
        )
        let model = OverlayEmptyStateModel.resolve(
            isPinnedTab: store.pinTab == .pinned,
            hasActiveFilters: hasActiveFilters
        )

        let accent = emptyStateAccent(icon: model.icon)

        return VStack {
            Spacer(minLength: 0)

            VStack(spacing: 9) {
                ZStack {
                    emptyStateIconBackground(accent: accent)
                    Image(systemName: model.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(emptyStateIconColor(icon: model.icon))
                }
                .frame(width: 48, height: 48)
                .padding(.bottom, 2)

                Text(model.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(Color(red: 0.122, green: 0.145, blue: 0.161))

                Text(model.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.396, green: 0.443, blue: 0.478))
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                    .lineLimit(2)
                    .frame(maxWidth: 330)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(emptyStateCardBackground)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: UIConstants.Overlay.emptyStateMinHeight)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.emptyState)
    }

    private var emptyStateCardBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 1.0, green: 0.985, blue: 0.945).opacity(0.82),
                        Color(red: 0.94, green: 0.91, blue: 0.84).opacity(0.64)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.46), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
            .shadow(color: .white.opacity(0.32), radius: 0, x: 0, y: 1)
    }

    private func emptyStateIconBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accent.opacity(0.96),
                        accent.opacity(0.70)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.black.opacity(0.10), lineWidth: 1)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.34), lineWidth: 1)
                        .padding(1)
                }
            )
            .shadow(color: accent.opacity(0.18), radius: 10, x: 0, y: 5)
    }

    private func emptyStateIconColor(icon: String) -> Color {
        icon == "magnifyingglass"
            ? .white.opacity(0.92)
            : Color(red: 0.23, green: 0.15, blue: 0.06)
    }

    private func emptyStateAccent(icon: String) -> Color {
        switch icon {
        case "magnifyingglass":
            return emptyStateSearchAccent
        case "pin.slash":
            return Color(red: 0.85, green: 0.62, blue: 0.26)
        default:
            return Color(red: 0.88, green: 0.67, blue: 0.35)
        }
    }

    private var emptyStateSearchAccent: Color {
        Color(red: 0.30, green: 0.50, blue: 0.78)
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
