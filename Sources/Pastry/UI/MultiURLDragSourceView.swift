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

        let dragItems = urls.map { url in
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(url.absoluteString, forType: .URL)
            pasteboardItem.setString(url.absoluteString, forType: .string)

            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
            draggingItem.setDraggingFrame(bounds, contents: dragImage)
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

    private var dragImage: NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()
        return image
    }
}
