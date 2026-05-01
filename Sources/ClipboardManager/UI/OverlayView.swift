import SwiftUI

// MARK: - 覆盖层主视图
struct OverlayView: View {

    @EnvironmentObject private var store: StoreManager

    private let cardSpacing: CGFloat = 10
    private let bottomInset: CGFloat = 64

    var body: some View {
        ZStack {
            // 半透明黑色蒙层
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // 可交互内容区
            VStack(spacing: 0) {
                // 顶部空白 — 点击关闭
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        OverlayPanelManager.shared.hide()
                    }

                // 浅色圆角容器包裹卡片列表
                cardContainer
                    .padding(.horizontal, 28)
                    .padding(.bottom, bottomInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 卡片容器（浅色圆角背景）
    @ViewBuilder
    private var cardContainer: some View {
        let displayItems = store.items

        if displayItems.isEmpty {
            emptyHint
        } else {
            cardList(displayItems)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        }
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
                        ClipboardCardView(item: item) { tapped in
                            OverlayPanelManager.shared.hideAndPaste(tapped)
                        }
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
                        ClipboardCardView(item: item) { tapped in
                            OverlayPanelManager.shared.hideAndPaste(tapped)
                        }
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
        .padding(.bottom, 140)
    }
}
