import SwiftUI
import AppKit

// MARK: - Design color tokens + shared settings card chrome

/// App-wide color tokens. Prefer these over inline `Color(red:)` literals.
enum PastryPalette {
    // Settings surface
    static let ink = Color(red: 0.122, green: 0.145, blue: 0.161)
    static let muted = Color(red: 0.396, green: 0.443, blue: 0.478)
    static let cream = Color(red: 0.949, green: 0.933, blue: 0.886)
    static let sidebar = Color(red: 0.18, green: 0.20, blue: 0.21).opacity(0.92)
    static let cardFill = Color.white.opacity(0.56)
    static let cardFillSoft = Color.white.opacity(0.42)
    static let hairline = ink.opacity(0.10)

    // Brand / warm
    static let warmAccent = Color.pastryWarmAccent
    /// AppKit twin of `warmAccent` for NSView drawing.
    static let warmAccentNS = NSColor.pastryWarmAccent
    static let warmInk = Color(red: 0.23, green: 0.15, blue: 0.06)
    static let warmGold = Color(red: 0.86, green: 0.62, blue: 0.28)
    static let warmGoldSoft = Color(red: 0.90, green: 0.70, blue: 0.40)
    static let cardAccent = Color(red: 0.85, green: 0.62, blue: 0.26)
    static let warmBorder = Color(red: 0.718, green: 0.451, blue: 0.153)

    // Overlay / filter
    static let overlaySurface = Color(red: 0.20, green: 0.23, blue: 0.24)

    // Semantic
    static let danger = Color(red: 0.724, green: 0.267, blue: 0.247)
    static let dangerBorder = Color(red: 0.620, green: 0.194, blue: 0.176)
    static let dangerStrong = Color(red: 0.84, green: 0.12, blue: 0.10)
    static let dangerGlow = Color(red: 1.0, green: 0.36, blue: 0.34)
    static let dangerBadge = Color(red: 0.74, green: 0.24, blue: 0.22)
    static let success = Color(red: 0.188, green: 0.82, blue: 0.345)
    static let successDeep = Color(red: 0.180, green: 0.498, blue: 0.333)

    // Settings controls
    static let switchOff = Color(red: 0.780, green: 0.765, blue: 0.730)
    static let keycapBottom = Color(red: 0.925, green: 0.906, blue: 0.855)
}

/// Compatibility alias — prefer `PastryPalette` in new code.
typealias SettingsPalette = PastryPalette

extension View {
    /// Single fill + hairline (+ optional clip). Prefer this over per-call-site shape stacks.
    @ViewBuilder
    func settingsCardChrome(
        cornerRadius: CGFloat = UIConstants.Radius.panel,
        fill: Color = PastryPalette.cardFill,
        clip: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let styled = background(
            shape
                .fill(fill)
                .overlay(shape.stroke(PastryPalette.hairline, lineWidth: UIConstants.Stroke.hairline))
        )
        if clip {
            styled.clipShape(shape)
        } else {
            styled
        }
    }
}
