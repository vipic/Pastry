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
    static let overlayAlertCancel    = Notification.Name("overlayAlertCancel")
    static let overlayCmdPaste       = Notification.Name("overlayCmdPaste")
    static let overlayCmdStateChanged = Notification.Name("overlayCmdStateChanged")
    static let overlaySearchEnterPaste = Notification.Name("overlaySearchEnterPaste")
    static let overlayCancelFavoriteNoteEditing = Notification.Name("overlayCancelFavoriteNoteEditing")
}

// MARK: - 覆盖层主视图
struct OverlayView: View {

    @EnvironmentObject private var store: StoreManager

    @State private var cardVisible = false
    @State private var selection = SelectionState()
    @State private var renderedIds: Set<UUID> = []    // 当前已渲染（可见）的卡片 ID
    @State private var showDeleteConfirm = false
    @State private var pendingDeleteIds: Set<UUID> = []
    @State private var pendingDeleteMode = DeleteRequestMode.selectionPreservingFavorites
    @State private var showSearch = false
    @State private var showFilterPopover = false
    @State private var hoverSearch = false
    @State private var hoverClearSearch = false
    @State private var hoverFilter = false
    @State private var hoverGear = false
    @State private var hoverTab: StoreManager.PinTab? = nil
    @State private var cmdDown = false
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyHandler = KeyboardEventHandler()
    @State private var iconPrefetchTask: Task<Void, Never>?

    @State private var cachedMultiSelectDrag: DragPayloadBuilder.SelectionPayload?

    private enum DeleteRequestMode {
        case selectionPreservingFavorites
        case direct
    }

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

            if showDeleteConfirm {
                deleteConfirmOverlay
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
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
                    withAnimation(searchExpansionAnimation) { showSearch = true }
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayOpenSearchImmediate)) { _ in
                    withAnimation(searchExpansionAnimation) { showSearch = true }
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
                .onChange(of: showDeleteConfirm) {
                    NotificationCenter.default.post(name: .overlayAlertActive,
                                                    object: nil,
                                                    userInfo: ["active": showDeleteConfirm])
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayAlertConfirm)) { _ in
                    confirmDeleteSelected()
                }
                .onReceive(NotificationCenter.default.publisher(for: .overlayAlertCancel)) { _ in
                    cancelDeleteConfirm()
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
                .onChange(of: isSearchFocused) { _, focused in
                    OverlayPanelManager.shared.keyboardOwner = focused ? .searchField : .overlayNavigation
                }
        )
    }

    private func onShowSearchChanged() {
        OverlayPanelManager.shared.isSearchActive = showSearch
        if showSearch {
            selection.reset()
            OverlayPanelManager.shared.keyboardOwner = .searchField
            focusSearchFieldAfterExpansion()
        } else {
            isSearchFocused = false
            showFilterPopover = false
            OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
            // clearFilters 由 closeSearch(clearFilter:) 控制，不在这里自动清
        }
    }

    private func focusSearchFieldAfterExpansion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard showSearch else { return }
            isSearchFocused = true
        }
    }

    private func handleConfirmPaste() {
        if showDeleteConfirm {
            confirmDeleteSelected()
            return
        }
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
        if showDeleteConfirm {
            return
        }
        guard !selection.selectedIds.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        requestDelete(ids: selection.selectedIds, mode: .selectionPreservingFavorites)
    }

    private func handleCommandPaste(_ note: Notification) {
        guard !showDeleteConfirm else { return }
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
        guard !showDeleteConfirm else { return }
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
        OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
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
        OverlayPanelManager.shared.keyboardOwner = .overlayNavigation
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
        withAnimation(searchExpansionAnimation) {
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
        let ids = pendingDeleteIds.isEmpty ? selection.selectedIds : pendingDeleteIds
        let deletedIds: Set<UUID>
        switch pendingDeleteMode {
        case .selectionPreservingFavorites:
            deletedIds = store.deleteSelected(ids, clearSystemClipboardWhenEmpty: true, preservePinned: true)
        case .direct:
            deletedIds = store.deleteSelected(ids, clearSystemClipboardWhenEmpty: false, preservePinned: false)
        }
        selection.selectedIds.subtract(deletedIds)
        if selection.selectedIds.isEmpty {
            selection.reset()
        }
    }

    private func confirmDeleteSelected() {
        guard !pendingDeleteIds.isEmpty else {
            showDeleteConfirm = false
            return
        }
        deleteSelected()
        showDeleteConfirm = false
        pendingDeleteIds = []
        pendingDeleteMode = .selectionPreservingFavorites
        NotificationCenter.default.post(name: .overlayAlertActive,
                                        object: nil,
                                        userInfo: ["active": false])
    }

    private func cancelDeleteConfirm() {
        showDeleteConfirm = false
        pendingDeleteIds = []
        pendingDeleteMode = .selectionPreservingFavorites
        NotificationCenter.default.post(name: .overlayAlertActive,
                                        object: nil,
                                        userInfo: ["active": false])
    }

    private func requestDelete(ids: Set<UUID>, mode: DeleteRequestMode) {
        guard !ids.isEmpty else {
            SoundFeedback.invalidAction()
            return
        }
        pendingDeleteIds = ids
        pendingDeleteMode = mode
        NotificationCenter.default.post(name: .overlayAlertActive,
                                        object: nil,
                                        userInfo: ["active": true])
        withAnimation(.easeOut(duration: 0.12)) {
            showDeleteConfirm = true
        }
    }

    private var deleteConfirmOverlay: some View {
        ConfirmationOverlay(
            title: deleteConfirmTitle,
            message: deleteConfirmMessage,
            cancelTitle: L10n["delete.confirm_cancel"],
            confirmTitle: L10n["delete.confirm_ok"],
            onCancel: cancelDeleteConfirm,
            onConfirm: confirmDeleteSelected
        )
        .animation(.easeOut(duration: 0.12), value: showDeleteConfirm)
    }

    private var deleteConfirmTitle: String {
        switch pendingDeleteMode {
        case .selectionPreservingFavorites:
            return L10n["delete.confirm_title"]
        case .direct:
            return L10n["delete.confirm_direct_title"]
        }
    }

    private var deleteConfirmMessage: String {
        switch pendingDeleteMode {
        case .selectionPreservingFavorites:
            return String(format: L10n["delete.confirm_msg"], pendingDeleteIds.count)
        case .direct:
            return String(format: L10n["delete.confirm_direct_msg"], pendingDeleteIds.count)
        }
    }

    // MARK: - 搜索框（内联在 header 中）

    private var searchExpansionAnimation: Animation {
        .spring(response: 0.24, dampingFraction: 0.86)
    }

    private var searchControlHeight: CGFloat {
        32
    }

    private var searchControlWidth: CGFloat {
        showSearch ? 430 : searchControlHeight
    }

    private var searchControl: some View {
        HStack(spacing: showSearch ? 6 : 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: showSearch ? 12 : 13, weight: .semibold))
                .foregroundColor(showSearch ? .white.opacity(0.46) : toolbarForeground(isActive: false, isHovered: hoverSearch))
                .frame(width: showSearch ? 12 : searchControlHeight, height: searchControlHeight)

            if showSearch {
                ZStack(alignment: .leading) {
                    if store.searchQuery.isEmpty {
                        Text(L10n["search.placeholder"])
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.68))
                            .allowsHitTesting(false)
                    }

                    TextField("", text: $store.searchQuery)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.92))
                        .focused($isSearchFocused)
                        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.searchField)
                        .onExitCommand {
                            closeSearch(clearFilter: true)
                        }
                }
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))

                Button {
                    store.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(hoverClearSearch ? Color.white.opacity(0.12) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(hoverClearSearch ? 0.72 : 0.40))
                .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.clearSearchButton)
                .opacity(store.searchQuery.isEmpty ? 0 : 1)
                .allowsHitTesting(!store.searchQuery.isEmpty)
                .onHover { hovering in
                    hoverClearSearch = hovering
                    if hovering { NSCursor.arrow.push() } else { NSCursor.pop() }
                }
                .animation(.easeOut(duration: 0.10), value: hoverClearSearch)

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
        .padding(.horizontal, showSearch ? 10 : 0)
        .padding(.vertical, showSearch ? 6 : 0)
        .frame(width: searchControlWidth, height: searchControlHeight, alignment: .leading)
        .background(searchControlBackground)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .scaleEffect(toolbarHoverScale(isHovered: !showSearch && hoverSearch))
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.searchButton)
        .onTapGesture {
            guard !showSearch else { return }
            withAnimation(searchExpansionAnimation) { showSearch = true }
        }
        .onHover { hovering in
            hoverSearch = hovering
        }
        .animation(searchExpansionAnimation, value: showSearch)
        .animation(.easeOut(duration: 0.10), value: hoverSearch)
        .padding(.trailing, 6)
    }

    @ViewBuilder
    private var searchControlBackground: some View {
        if showSearch {
            overlaySearchFieldBackground
        } else {
            toolbarButtonBackground(isActive: false, isHovered: hoverSearch)
        }
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
                    // One continuous surface for body + system arrow (no nested card chrome).
                    .presentationBackground(FilterPopoverStyle.surface)
                    .presentationCornerRadius(14)
            }
            .scaleEffect(toolbarHoverScale(isHovered: hoverFilter))
            .animation(.easeOut(duration: 0.10), value: hoverFilter)
            .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.filterButton)
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
            .clipped()
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 10)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .background(panelTrayBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.24), radius: 16, x: 0, y: 10)
        .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture { selection.reset() }
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.cardContainer)
    }

    private var panelTrayBackground: some View {
        ZStack {
            GlassBackground(cornerRadius: 24)

            // Single flat tint so the hud glass reads consistently without stacked washes.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(red: 0.20, green: 0.23, blue: 0.24).opacity(0.55))

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 0) {
            Spacer()

            // 居中：搜索按钮/框 | tab 组
            searchControl

            filterButton
                .padding(.trailing, 6)

            tabButton(tab: .all, icon: "tray.full", label: L10n["tab.all"], isSelected: store.pinTab == .all)
                .padding(.trailing, 6)
            tabButton(tab: .pinned, icon: "pin.fill", label: L10n["tab.pinned"], isSelected: store.pinTab == .pinned)

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
        .animation(searchExpansionAnimation, value: showSearch)
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
            .fill(Color.black.opacity(0.28))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
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

    /// Flat chip chrome: one fill, optional single hairline. No dual strokes / bevel shadows.
    private func toolbarButtonBackground(isActive: Bool, isHovered: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(toolbarButtonFill(isActive: isActive, isHovered: isHovered))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(toolbarButtonBorder(isActive: isActive, isHovered: isHovered), lineWidth: 0.5)
            )
    }

    private func toolbarButtonFill(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return Color.pastryWarmAccent
        }
        return .white.opacity(isHovered ? 0.14 : 0.08)
    }

    private func toolbarButtonBorder(isActive: Bool, isHovered: Bool) -> Color {
        if isActive {
            return Color.pastryWarmAccent.opacity(0.35)
        }
        // Idle: no visible border — fill alone defines the control.
        return .white.opacity(isHovered ? 0.08 : 0)
    }

    // MARK: - 卡片列表

    /// 横向/纵向布局切换，根据屏幕宽 > 1200 决定。
    /// 初始化时同步读取 NSEvent/NSScreen（SwiftUI body 在主线程，安全）。
    /// 若将来在此处引入后台调用，需改为主线程异步赋值。
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
                                .clipped()
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
                    requestDelete(ids: selection.selectedIds, mode: .direct)
                } else {
                    requestDelete(ids: [deleted.id], mode: .direct)
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

            VStack(spacing: 10) {
                ZStack {
                    emptyStateIconBackground(accent: accent)
                    Image(systemName: model.icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(emptyStateIconColor(icon: model.icon))
                }
                .frame(width: 48, height: 48)
                .padding(.bottom, 4)

                Text(model.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white.opacity(0.90))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)

                Text(model.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.56))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .lineLimit(2)
                    .frame(maxWidth: 330)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, minHeight: UIConstants.Overlay.emptyStateMinHeight)
        .accessibilityIdentifier(AccessibilityIdentifiers.Overlay.emptyState)
    }

    private func emptyStateIconBackground(accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 13, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        accent.opacity(0.80),
                        accent.opacity(0.46)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(.black.opacity(0.14), lineWidth: 0.5)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.22), lineWidth: 0.5)
                        .padding(1)
                }
            )
            .shadow(color: .black.opacity(0.14), radius: 8, x: 0, y: 5)
    }

    private func emptyStateIconColor(icon: String) -> Color {
        .white.opacity(icon == "magnifyingglass" ? 0.92 : 0.84)
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
