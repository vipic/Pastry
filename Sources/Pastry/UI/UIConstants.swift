import SwiftUI

enum UIConstants {
    enum Card {
        static let size: CGFloat = 240
        static let cornerRadius: CGFloat = Radius.card
        static let headerHeight: CGFloat = 48
        static let appIconSize: CGFloat = 72
        static let contentHorizontalPadding: CGFloat = 10
        static let contentVerticalPadding: CGFloat = 6
        static let footerBottomPadding: CGFloat = 8
        /// 备注与 footer / hover 操作之间的间距
        static let favoriteNoteBottomPadding: CGFloat = 12
        static let idleBorderOpacity: CGFloat = 0.08
        static let hoverBorderOpacity: CGFloat = 0.15
        static let selectedBorderWidth: CGFloat = Stroke.emphasis
        static let animationDuration = Motion.fast
        static let pasteScale: CGFloat = 0.95
        /// Hover 轻操作：与 footer `caption2` 字阶协调
        static let hoverActionIconSize = TypeSize.caption2
        static let hoverActionSize: CGFloat = 18
        static let hoverActionSpacing: CGFloat = 2
        static let hoverActionCornerRadius = Radius.xs
        /// footer 右侧预留：3×size + 2×spacing + 余量
        static let hoverActionReserveWidth: CGFloat = 62
    }

    enum Overlay {
        static let cardSpacing: CGFloat = 10
        static let bottomInset: CGFloat = 12
        static let horizontalPadding: CGFloat = 28
        static let animationDuration = Motion.overlay
        static let emptyStateMinHeight: CGFloat = Card.size + 12
        static let compactListMaxWidth: CGFloat = 520
        static let compactCardMaxWidth: CGFloat = 400
        static let toolbarButtonSize: CGFloat = 32
        static let trayCornerRadius: CGFloat = Radius.tray
        static let overlaySurfaceTintOpacity: Double = 0.55
        /// 横排新卡入场：整带一次位移的距离 = 卡宽 + 间距
        static var cardInsertPushDistance: CGFloat { Card.size + cardSpacing }
    }

    enum Control {
        static let iconButtonSize: CGFloat = 28
        static let cornerRadius: CGFloat = Radius.control
    }

    /// 删除/清空确认对话框（与托盘同系深色玻璃）
    enum Confirmation {
        static let cardWidth: CGFloat = 360
        static let contentPadding: CGFloat = 18
        static let cornerRadius: CGFloat = Radius.panel
        static let buttonHeight: CGFloat = 30
        static let scrimOpacity: Double = 0.22
    }

    /// Count / status badge geometry. Colors stay on `PastryPalette` + `OnDark`.
    enum Badge {
        /// ⌘+数字、拖拽数量
        static let countSize: CGFloat = 24
        static let countPadding: CGFloat = 7
        static let countCornerRadius: CGFloat = Radius.button
        /// 工具栏「有筛选」状态点（类似未保存指示）
        static let indicatorDotSize: CGFloat = 7
        static let indicatorDotOffset: CGFloat = 3
        /// 搜索结果 n/m 胶囊
        static let capsuleHeight: CGFloat = 18
        static let capsuleHorizontalPadding: CGFloat = 6
        /// 设置页状态方块（版本 / 辅助功能）
        static let statusSize: CGFloat = 42
    }

    enum ContextMenu {
        static let cardMinimumWidth: CGFloat = 190
    }

    /// Corner radii used across overlay, cards, and settings (current visual values).
    enum Radius {
        static let xs: CGFloat = 3
        static let sm: CGFloat = 4
        static let control: CGFloat = 6
        static let button: CGFloat = 7
        static let chip: CGFloat = 8
        static let toolbar: CGFloat = 9
        static let card: CGFloat = 10
        static let panel: CGFloat = 12
        static let cardLarge: CGFloat = 14
        static let tray: CGFloat = 24
    }

    /// System font sizes used across the UI.
    enum TypeSize {
        static let micro: CGFloat = 8
        static let caption2: CGFloat = 9
        static let caption: CGFloat = 10
        static let label: CGFloat = 11
        static let callout: CGFloat = 12
        static let subhead: CGFloat = 14
        static let body: CGFloat = 13
        static let title: CGFloat = 15
        static let titleMedium: CGFloat = 16
        static let title2: CGFloat = 17
        static let title3: CGFloat = 18
        static let headline: CGFloat = 20
        static let display: CGFloat = 22
        static let displayLarge: CGFloat = 24
        static let heroIcon: CGFloat = 28
    }

    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let emphasis: CGFloat = 1.5
    }

    /// White-on-dark opacity ramps (overlay / filter / sidebar).
    enum OnDark {
        static let textPrimary: Double = 0.92
        static let textSecondary: Double = 0.72
        static let textTertiary: Double = 0.52
        static let fillSubtle: Double = 0.08
        static let fillHover: Double = 0.14
        static let stroke: Double = 0.12
    }

    enum Motion {
        static let instant = 0.10
        static let fast = 0.12
        static let short = 0.15
        static let note = 0.16
        static let overlay = 0.20
        static let soft = 0.22
        static let iconReveal = 0.25
        static let switchSpring = 0.28
        /// 新卡片入场（仅新卡自身，非整表位移）
        static let cardInsert = 0.14
    }
}
