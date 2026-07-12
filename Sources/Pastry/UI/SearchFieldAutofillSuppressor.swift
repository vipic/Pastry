import AppKit
import SwiftUI

/// 压掉搜索框首次聚焦时系统 AutoFill / 自动补全空气泡
///（外形像输入法候选区，但是独立系统窗口，不会撑开托盘）。
struct SearchFieldAutofillSuppressor: NSViewRepresentable {
    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        context.coordinator.attach(probe: view)
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.attach(probe: nsView)
        context.coordinator.suppressNearbyFields()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var probe: ProbeView?
        private var editingObserver: NSObjectProtocol?

        func attach(probe: ProbeView) {
            self.probe = probe
            if editingObserver == nil {
                editingObserver = NotificationCenter.default.addObserver(
                    forName: NSControl.textDidBeginEditingNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] note in
                    self?.handleEditingBegan(note)
                }
            }
            suppressNearbyFields()
        }

        func suppressNearbyFields() {
            DispatchQueue.main.async { [weak self] in
                guard let probe = self?.probe else { return }
                for field in Self.nearbyTextFields(from: probe) {
                    Self.configure(field)
                }
            }
        }

        private func handleEditingBegan(_ note: Notification) {
            guard let control = note.object as? NSTextField,
                  let probe,
                  Self.nearbyTextFields(from: probe).contains(where: { $0 === control })
            else { return }

            Self.configure(control)
            if let editor = control.currentEditor() as? NSTextView {
                Self.configure(editor)
            }
        }

        private static func nearbyTextFields(from probe: NSView) -> [NSTextField] {
            var host: NSView? = probe.superview
            // 在 background 宿主附近找 TextField；向上多爬几层覆盖 SwiftUI 包装层。
            for _ in 0..<6 {
                guard let current = host else { break }
                let fields = textFields(in: current)
                if !fields.isEmpty { return fields }
                host = current.superview
            }
            return []
        }

        private static func textFields(in root: NSView) -> [NSTextField] {
            var result: [NSTextField] = []
            var stack: [NSView] = [root]
            while let view = stack.popLast() {
                if let field = view as? NSTextField {
                    result.append(field)
                }
                stack.append(contentsOf: view.subviews)
            }
            return result
        }

        private static func configure(_ field: NSTextField) {
            if field.isAutomaticTextCompletionEnabled {
                field.isAutomaticTextCompletionEnabled = false
            }
        }

        private static func configure(_ editor: NSTextView) {
            if editor.isAutomaticTextCompletionEnabled {
                editor.isAutomaticTextCompletionEnabled = false
            }
            editor.writingToolsBehavior = .none
        }

        deinit {
            if let editingObserver {
                NotificationCenter.default.removeObserver(editingObserver)
            }
        }
    }

    final class ProbeView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.suppressNearbyFields()
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
