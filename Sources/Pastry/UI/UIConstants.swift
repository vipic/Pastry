import SwiftUI

enum UIConstants {
    enum Card {
        static let size: CGFloat = 240
        static let cornerRadius: CGFloat = 10
        static let headerHeight: CGFloat = 48
        static let appIconSize: CGFloat = 72
        static let contentHorizontalPadding: CGFloat = 10
        static let contentVerticalPadding: CGFloat = 6
        static let footerBottomPadding: CGFloat = 8
        static let idleBorderOpacity: CGFloat = 0.08
        static let hoverBorderOpacity: CGFloat = 0.15
        static let selectedBorderWidth: CGFloat = 2.5
        static let animationDuration = 0.12
        static let pasteScale: CGFloat = 0.95
    }

    enum Overlay {
        static let cardSpacing: CGFloat = 10
        static let bottomInset: CGFloat = 12
        static let horizontalPadding: CGFloat = 28
        static let animationDuration = 0.20
        static let emptyStateMinHeight: CGFloat = Card.size + 12
        static let compactListMaxWidth: CGFloat = 520
        static let compactCardMaxWidth: CGFloat = 400
    }

    enum Control {
        static let iconButtonSize: CGFloat = 28
        static let cornerRadius: CGFloat = 6
    }
}
