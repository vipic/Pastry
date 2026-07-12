import SwiftUI

struct ConfirmationOverlay: View {
    enum ButtonKind {
        case secondary
        case destructive
    }

    let title: String
    let message: String
    let cancelTitle: String
    let confirmTitle: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(UIConstants.Confirmation.scrimOpacity)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: UIConstants.Radius.cardLarge) {
                Text(title)
                    .font(.system(size: UIConstants.TypeSize.titleMedium, weight: .semibold))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textPrimary))

                Text(message)
                    .font(.system(size: UIConstants.TypeSize.body))
                    .foregroundColor(.white.opacity(UIConstants.OnDark.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: UIConstants.Card.footerBottomPadding) {
                    Spacer()

                    Button(cancelTitle, action: onCancel)
                        .buttonStyle(ConfirmationButtonStyle(kind: .secondary))

                    Button(confirmTitle, action: onConfirm)
                        .buttonStyle(ConfirmationButtonStyle(kind: .destructive))
                }
            }
            .padding(UIConstants.Confirmation.contentPadding)
            .frame(width: UIConstants.Confirmation.cardWidth)
            .background(confirmationCardChrome)
            .clipShape(RoundedRectangle(cornerRadius: UIConstants.Confirmation.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Confirmation.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(UIConstants.OnDark.stroke), lineWidth: UIConstants.Stroke.hairline)
            )
            .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 10)
            .shadow(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
        }
    }

    /// 与托盘同系：hud 磨砂 + overlaySurface 着色。
    private var confirmationCardChrome: some View {
        ZStack {
            GlassBackground(cornerRadius: UIConstants.Confirmation.cornerRadius)
            PastryPalette.overlaySurface.opacity(UIConstants.Overlay.overlaySurfaceTintOpacity)
        }
    }
}

private struct ConfirmationButtonStyle: ButtonStyle {
    let kind: ConfirmationOverlay.ButtonKind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: UIConstants.TypeSize.body, weight: .semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: UIConstants.Confirmation.buttonHeight)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                    .stroke(borderColor, lineWidth: UIConstants.Stroke.hairline)
            )
    }

    private var foregroundColor: Color {
        switch kind {
        case .secondary:
            return .white.opacity(UIConstants.OnDark.textSecondary)
        case .destructive:
            return .white
        }
    }

    private var borderColor: Color {
        switch kind {
        case .secondary:
            return .white.opacity(UIConstants.OnDark.stroke)
        case .destructive:
            return PastryPalette.dangerGlow.opacity(0.34)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .secondary:
            return Color.white.opacity(isPressed ? UIConstants.OnDark.fillHover : UIConstants.OnDark.fillSubtle)
        case .destructive:
            return PastryPalette.dangerStrong.opacity(isPressed ? 0.82 : 1.0)
        }
    }
}
