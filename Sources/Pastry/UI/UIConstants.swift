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
        static let idleBorderOpacity: CGFloat = 0.08
        static let hoverBorderOpacity: CGFloat = 0.15
        static let selectedBorderWidth: CGFloat = Stroke.emphasis
        static let animationDuration = Motion.fast
        static let pasteScale: CGFloat = 0.95
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
    }

    enum Control {
        static let iconButtonSize: CGFloat = 28
        static let cornerRadius: CGFloat = Radius.control
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
        static let emptyIcon: CGFloat = 13
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
    }
}
