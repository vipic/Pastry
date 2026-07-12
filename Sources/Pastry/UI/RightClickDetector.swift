import Cocoa
import SwiftUI

// MARK: - NSMenu target-action 桥接
final class _MenuHandler: NSObject {
    private let action: (String, Any?) -> Void
    init(_ action: @escaping (String, Any?) -> Void) { self.action = action }
    @objc func invoke(_ sender: NSMenuItem) { action(sender.title, sender.representedObject) }
}

// MARK: - 右键检测器（hitTest 拦截 → NSMenu.popUp）
struct RightClickDetector: NSViewRepresentable {
    var onViewReady: ((NSView) -> Void)? = nil
    let onRightClick: (NSView, NSEvent) -> Void

    func makeNSView(context: Context) -> _DetectorView {
        let v = _DetectorView()
        v.onRightClick = onRightClick
        context.coordinator.view = v
        DispatchQueue.main.async { [weak v] in
            guard let v else { return }
            onViewReady?(v)
        }
        return v
    }

    func updateNSView(_ nsView: _DetectorView, context: Context) {
        nsView.onRightClick = onRightClick
        context.coordinator.view = nsView
        onViewReady?(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var view: _DetectorView?
    }
}

final class _DetectorView: NSView {
    var onRightClick: ((NSView, NSEvent) -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(self, event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let e = NSApp.currentEvent, e.type == .rightMouseDown { return self }
        return nil
    }
}
