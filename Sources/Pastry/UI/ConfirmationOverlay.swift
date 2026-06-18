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

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white.opacity(0.96))

                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 13)
            .frame(height: 30)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
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
            return .white.opacity(0.12)
        case .destructive:
            return Color(red: 1.0, green: 0.36, blue: 0.34).opacity(0.34)
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .secondary:
            return Color.white.opacity(isPressed ? 0.18 : 0.10)
        case .destructive:
            return Color(red: 0.84, green: 0.12, blue: 0.10).opacity(isPressed ? 0.82 : 1.0)
        }
    }
}
