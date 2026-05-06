import Cocoa
import SwiftUI

// MARK: - AppKit NSPopover 桥接（避免 SwiftUI .popover 的渲染 glitch）
struct FilterPopoverBridge: NSViewRepresentable {
    @Binding var isPresented: Bool
    let content: () -> FilterPopoverContent

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented, context.coordinator.popover == nil {
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = true
            let hosting = NSHostingView(rootView: content())
            hosting.translatesAutoresizingMaskIntoConstraints = false
            let vc = NSViewController()
            vc.view = hosting
            popover.contentViewController = vc
            popover.delegate = context.coordinator
            popover.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: .minY)
            context.coordinator.popover = popover
        } else if !isPresented, let popover = context.coordinator.popover {
            popover.close()
            context.coordinator.popover = nil
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    final class Coordinator: NSObject, NSPopoverDelegate {
        var popover: NSPopover?
        var isPresented: Binding<Bool>

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func popoverDidClose(_ notification: Notification) {
            popover = nil
            isPresented.wrappedValue = false
        }

        func popoverShouldClose(_ popover: NSPopover) -> Bool {
            true
        }
    }
}
