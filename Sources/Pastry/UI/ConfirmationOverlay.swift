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
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: UIConstants.Radius.cardLarge) {
                Text(title)
                    .font(.system(size: UIConstants.TypeSize.titleMedium, weight: .semibold))
                    .foregroundColor(.white.opacity(0.96))

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
            .padding(18)
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.Radius.panel, style: .continuous)
                            .stroke(Color.white.opacity(UIConstants.OnDark.stroke), lineWidth: UIConstants.Stroke.hairline)
                    )
            )
            .shadow(color: .black.opacity(0.32), radius: 24, x: 0, y: 12)
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
            .frame(height: 30)
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
            return .white.opacity(0.86)
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
            return Color.white.opacity(isPressed ? 0.18 : 0.10)
        case .destructive:
            return PastryPalette.dangerStrong.opacity(isPressed ? 0.82 : 1.0)
        }
    }
}
