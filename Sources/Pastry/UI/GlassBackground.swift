import SwiftUI
import Cocoa

// MARK: - 托盘背景
struct GlassBackground: NSViewRepresentable {

    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = UIConstants.Radius.tray) {
        self.cornerRadius = cornerRadius
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        view.layer?.shadowOpacity = 0
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .withinWindow
        nsView.state = .active
        nsView.layer?.cornerRadius = cornerRadius
    }
}
