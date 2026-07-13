import AppKit
import SwiftUI

/// 把侧滚 delta 直接写进 SwiftUI `ScrollView` 背后的 `NSScrollView`，实现像素级跟手。
///
/// 放在横向 `LazyHStack` 的 background 里，向上找到 enclosing scroll view。
struct CardStripScrollDriver: NSViewRepresentable {
    var onHitEdge: (Bool) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        context.coordinator.onHitEdge = onHitEdge
        context.coordinator.attach(probe: view)
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        context.coordinator.onHitEdge = onHitEdge
        context.coordinator.attach(probe: nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var probe: ProbeView?
        var onHitEdge: ((Bool) -> Void)?
        private var scrollObserver: NSObjectProtocol?
        private var resetObserver: NSObjectProtocol?

        func attach(probe: ProbeView) {
            self.probe = probe
            if scrollObserver == nil {
                scrollObserver = NotificationCenter.default.addObserver(
                    forName: .overlayCardStripScroll,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    self?.handleScroll(note)
                }
            }
            if resetObserver == nil {
                resetObserver = NotificationCenter.default.addObserver(
                    forName: .overlayCardStripScrollToStart,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.scrollToStart()
                }
            }
        }

        private func handleScroll(_ note: Notification) {
            let delta = (note.userInfo?["delta"] as? CGFloat)
                ?? (note.userInfo?["delta"] as? Double).map { CGFloat($0) }
                ?? 0
            guard abs(delta) > 0.01 else { return }
            guard let probe, let scrollView = Self.resolveScrollView(from: probe) else { return }

            let clip = scrollView.contentView
            let origin = clip.bounds.origin
            let documentWidth = scrollView.documentView?.bounds.width
                ?? clip.documentRect.width
            let maxX = max(0, documentWidth - clip.bounds.width)
            let result = OverlayInteractionModel.applyStripPixelScroll(
                originX: origin.x,
                delta: delta,
                maxX: maxX
            )

            if abs(result.originX - origin.x) > 0.01 {
                clip.scroll(to: NSPoint(x: result.originX, y: origin.y))
                scrollView.reflectScrolledClipView(clip)
            }

            if result.hitLeading {
                onHitEdge?(false)
            } else if result.hitTrailing {
                onHitEdge?(true)
            }
        }

        private func scrollToStart() {
            guard let probe, let scrollView = Self.resolveScrollView(from: probe) else { return }
            let clip = scrollView.contentView
            let origin = clip.bounds.origin
            guard abs(origin.x) > 0.01 else { return }
            clip.scroll(to: NSPoint(x: 0, y: origin.y))
            scrollView.reflectScrolledClipView(clip)
        }

        /// SwiftUI 包装层有时让 `enclosingScrollView` 为空，向上爬并扫同级。
        private static func resolveScrollView(from probe: NSView) -> NSScrollView? {
            if let scrollView = probe.enclosingScrollView { return scrollView }
            var current: NSView? = probe
            for _ in 0..<16 {
                guard let view = current else { break }
                if let scrollView = view as? NSScrollView { return scrollView }
                if let parent = view.superview {
                    for sibling in parent.subviews {
                        if let scrollView = sibling as? NSScrollView { return scrollView }
                        if let nested = sibling.subviews.compactMap({ $0 as? NSScrollView }).first {
                            return nested
                        }
                    }
                }
                current = view.superview
            }
            return nil
        }

        deinit {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            if let resetObserver {
                NotificationCenter.default.removeObserver(resetObserver)
            }
        }
    }

    final class ProbeView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
