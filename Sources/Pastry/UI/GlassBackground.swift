import SwiftUI
import Cocoa

// MARK: - Liquid Glass 背景
/// 纯玻璃背景层 — 内容在 SwiftUI 层渲染，玻璃在底层提供穿透效果
struct GlassBackground: NSViewRepresentable {

    let style: NSGlassEffectView.Style
    let cornerRadius: CGFloat

    init(style: NSGlassEffectView.Style = .regular, cornerRadius: CGFloat = 0) {
        self.style = style
        self.cornerRadius = cornerRadius
    }

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.style = style
        glass.cornerRadius = cornerRadius
        // 消除 NSGlassEffectView 自带的阴影
        glass.wantsLayer = true
        glass.layer?.shadowOpacity = 0
        glass.layer?.masksToBounds = true
        // 透明内容视图 — 玻璃材质本身可见，穿透到桌面
        let clear = NSView()
        clear.wantsLayer = true
        glass.contentView = clear
        return glass
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.style = style
        nsView.cornerRadius = cornerRadius
    }
}
