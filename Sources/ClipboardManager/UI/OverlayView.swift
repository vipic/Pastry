import SwiftUI

// MARK: - 通知
extension Notification.Name {
    static let overlayRequestDismiss  = Notification.Name("overlayRequestDismiss")
    static let overlayDidHide        = Notification.Name("overlayDidHide")
    static let overlaySelectAll      = Notification.Name("overlaySelectAll")
    static let overlayDeleteSelected = Notification.Name("overlayDeleteSelected")
    static let overlayAlertActive    = Notification.Name("overlayAlertActive")
}

// MARK: - 覆盖层主视图
struct OverlayView: View {

    @EnvironmentObject private var store: StoreManager

    @State private var cardVisible: Bool? = nil
    @State private var selectedIds: Set<UUID> = []
    @State private var showDeleteConfirm = false

    private let cardSpacing: CGFloat = 10
    private let bottomInset: CGFloat = 40
    private let animationDuration = 0.20

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
                    .offset(y: (cardVisible == true) ? 0 : 200)
                    .opacity((cardVisible == true) ? 1 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
                cardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .overlayRequestDismiss)) { _ in
            dismiss()
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
            Text("确定要删除 \(selectedIds.count) 条选中的记录吗？此操作不可撤销。")
        }
        .onChange(of: showDeleteConfirm) { active in
            NotificationCenter.default.post(name: .overlayAlertActive,
                                            object: nil,
                                            userInfo: ["active": active])
        }
    }

    // MARK: - 退场

    private func dismiss() {
        guard cardVisible == true else { return }
        withAnimation(.spring(response: animationDuration, dampingFraction: 0.82)) {
            cardVisible = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
            OverlayPanelManager.shared.hide()
        }
    }

    // MARK: - 批量删除

    private func deleteSelected() {
        ClipboardMonitor.shared.suspend()
        for id in selectedIds {
            if let item = store.items.first(where: { $0.id == id }) {
                store.deleteItem(item)
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.declareTypes([.string], owner: nil)
        pb.setString("", forType: .string)
        ClipboardMonitor.shared.syncChangeCount()
        ClipboardMonitor.shared.resume()
        selectedIds = []
    }

    // MARK: - 卡片容器（浅色圆角背景）

    @ViewBuilder
    private var cardContainer: some View {
        let displayItems = store.items

        Group {
            if displayItems.isEmpty {
                emptyHint
            } else {
                cardList(displayItems)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - 卡片列表

    private var isHorizontalLayout: Bool {
        let screen = NSScreen.main?.frame ?? .zero
        return screen.width > 1200
    }

    @ViewBuilder
    private func cardList(_ items: [ClipboardItem]) -> some View {
        if isHorizontalLayout {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: cardSpacing) {
                    ForEach(items) { item in
                        ClipboardCardView(
                            item: item,
                            isSelected: selectedIds.contains(item.id),
                            onTap: { tapped in
                                OverlayPanelManager.shared.hideAndPaste(tapped)
                            }
                        )
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .animation(nil, value: items.count)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: cardSpacing) {
                    ForEach(items) { item in
                        ClipboardCardView(
                            item: item,
                            isSelected: selectedIds.contains(item.id),
                            onTap: { tapped in
                                OverlayPanelManager.shared.hideAndPaste(tapped)
                            }
                        )
                        .frame(maxWidth: 400)
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 520)
            .animation(nil, value: items.count)
        }
    }

    // MARK: - 空状态

    private var emptyHint: some View {
        VStack(spacing: 14) {
            Image(systemName: "clipboard")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.4))
            Text("还没有剪贴板历史")
                .font(.body)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
