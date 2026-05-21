import AppKit
import SwiftUI

struct MultiURLDragSourceView: NSViewRepresentable {
    let urls: [URL]

    func makeNSView(context: Context) -> DragSourceNSView {
        DragSourceNSView()
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.urls = urls
    }
}

final class DragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL] = []
    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        urls.count > 1 ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, urls.count > 1 else { return }
        didStartDrag = true

        let dragItems = urls.enumerated().map { index, url in
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            draggingItem.setDraggingFrame(draggingFrame(for: index), contents: dragImage(for: index))
            return draggingItem
        }

        guard let startEvent = mouseDownEvent ?? window?.currentEvent else { return }
        let session = beginDraggingSession(with: dragItems, event: startEvent, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false

        Task { @MainActor in
            OverlayPanelManager.shared.beginDragThrough()
        }
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
        didStartDrag = false
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    private func draggingFrame(for index: Int) -> NSRect {
        let visibleIndex = min(index, 3)
        let xOffset = CGFloat(visibleIndex) * 8
        let yOffset = CGFloat(visibleIndex) * -8
        let width = min(max(bounds.width * 0.82, 180), 280)
        let height: CGFloat = 72
        return NSRect(
            x: bounds.midX - width / 2 + xOffset,
            y: bounds.midY - height / 2 + yOffset,
            width: width,
            height: height
        )
    }

    private func dragImage(for index: Int) -> NSImage {
        let size = draggingFrame(for: index).size
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        path.lineWidth = 1
        path.stroke()

        let badge = "\(index + 1)" as NSString
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        NSColor.controlAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 12, y: size.height - 32, width: 22, height: 22)).fill()
        badge.draw(
            in: NSRect(x: 12, y: size.height - 28, width: 22, height: 14),
            withAttributes: badgeAttributes
        )

        let title = urls.indices.contains(index) ? urls[index].host(percentEncoded: false) ?? urls[index].absoluteString : ""
        let subtitle = urls.indices.contains(index) ? urls[index].absoluteString : ""
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        (title as NSString).draw(
            in: NSRect(x: 44, y: size.height - 29, width: size.width - 56, height: 17),
            withAttributes: titleAttributes
        )
        (subtitle as NSString).draw(
            in: NSRect(x: 44, y: 15, width: size.width - 56, height: 15),
            withAttributes: subtitleAttributes
        )

        image.unlockFocus()
        return image
    }
}
