import SwiftUI

// MARK: - Settings surface tokens + shared card chrome

enum SettingsPalette {
    static let ink = Color(red: 0.122, green: 0.145, blue: 0.161)
    static let muted = Color(red: 0.396, green: 0.443, blue: 0.478)
    static let cream = Color(red: 0.949, green: 0.933, blue: 0.886)
    static let sidebar = Color(red: 0.18, green: 0.20, blue: 0.21).opacity(0.92)
    static let cardFill = Color.white.opacity(0.56)
    static let cardFillSoft = Color.white.opacity(0.42)
    static let hairline = ink.opacity(0.10)
}

extension View {
    /// Single fill + hairline (+ optional clip). Prefer this over per-call-site shape stacks.
    @ViewBuilder
    func settingsCardChrome(
        cornerRadius: CGFloat = 12,
        fill: Color = SettingsPalette.cardFill,
        clip: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let styled = background(
            shape
                .fill(fill)
                .overlay(shape.stroke(SettingsPalette.hairline, lineWidth: 0.5))
        )
        if clip {
            styled.clipShape(shape)
        } else {
            styled
        }
    }
}
