import AppKit
import SwiftUI

struct MultiSelectionDragSourceView: NSViewRepresentable {
    let isActive: Bool
    let itemCount: Int
    let payloadText: String

    func makeNSView(context: Context) -> MultiSelectionDragSourceNSView {
        MultiSelectionDragSourceNSView()
    }

    func updateNSView(_ nsView: MultiSelectionDragSourceNSView, context: Context) {
        nsView.isActive = isActive
        nsView.itemCount = itemCount
        nsView.payloadText = payloadText
    }
}

final class MultiSelectionDragSourceNSView: NSView, NSDraggingSource {
    var isActive = false
    var itemCount = 0
    var payloadText = ""
    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        isActive ? super.hitTest(point) : nil
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didStartDrag, isActive else { return }
        didStartDrag = true

        let draggingItem = NSDraggingItem(pasteboardWriter: payloadText as NSString)
        draggingItem.setDraggingFrame(draggingFrame, contents: dragImage)

        guard let startEvent = mouseDownEvent ?? window?.currentEvent else { return }
        let session = beginDraggingSession(with: [draggingItem], event: startEvent, source: self)
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

    private var draggingFrame: NSRect {
        let side = min(max(min(bounds.width, bounds.height) * 0.72, 88), 128)
        return NSRect(
            x: bounds.midX - side / 2,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
    }

    private var dragImage: NSImage {
        let size = draggingFrame.size
        let image = NSImage(size: size)
        image.lockFocus()

        for index in stride(from: 1, through: 0, by: -1) {
            drawStackCard(index: index, size: size)
        }

        let badge = "\(itemCount)" as NSString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle,
        ]
        NSColor.controlAccentColor.setFill()
        let badgeRect = NSRect(x: size.width - 30, y: size.height - 30, width: 24, height: 24)
        NSBezierPath(ovalIn: badgeRect).fill()
        badge.draw(
            in: NSRect(x: badgeRect.minX, y: badgeRect.minY + 5, width: badgeRect.width, height: 14),
            withAttributes: badgeAttributes
        )

        image.unlockFocus()
        return image
    }

    private func drawStackCard(index: Int, size: NSSize) {
        let offset = CGFloat(index) * 7
        let rect = NSRect(
            x: 8 + offset,
            y: 8 - offset,
            width: size.width - 24,
            height: size.height - 24
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        NSColor.windowBackgroundColor.withAlphaComponent(0.72).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        path.lineWidth = 1
        path.stroke()

        NSColor.quaternaryLabelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX + 14, y: rect.maxY - 30, width: rect.width * 0.62, height: 8),
            xRadius: 4,
            yRadius: 4
        ).fill()
        NSBezierPath(
            roundedRect: NSRect(x: rect.minX + 14, y: rect.maxY - 46, width: rect.width * 0.44, height: 7),
            xRadius: 3.5,
            yRadius: 3.5
        ).fill()
    }
}
