import SwiftUI
import AppKit
import Carbon

enum SettingsButtonKind {
    case primary
    case secondary
    case danger
}

struct SettingsPillButtonStyle: ButtonStyle {
    var kind: SettingsButtonKind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: UIConstants.TypeSize.callout, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(minHeight: UIConstants.Control.iconButtonSize)
            .background(buttonBackground(isPressed: configuration.isPressed))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: UIConstants.Motion.instant), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger:
            return .white
        case .secondary:
            return PastryPalette.ink
        }
    }

    @ViewBuilder
    private func buttonBackground(isPressed: Bool) -> some View {
        RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
            .fill(fillColor.opacity(isPressed ? 0.88 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: UIConstants.Radius.button, style: .continuous)
                    .stroke(borderColor, lineWidth: UIConstants.Stroke.hairline)
            )
    }

    private var fillColor: Color {
        switch kind {
        case .primary:
            return PastryPalette.warmAccent
        case .secondary:
            return Color.white.opacity(0.72)
        case .danger:
            return PastryPalette.danger
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary:
            return PastryPalette.warmBorder.opacity(0.50)
        case .secondary:
            return PastryPalette.ink.opacity(0.16)
        case .danger:
            return PastryPalette.dangerBorder.opacity(0.50)
        }
    }
}

struct SettingsSwitchStyle: ToggleStyle {
    private let switchAnimation = Animation.spring(response: UIConstants.Motion.switchSpring, dampingFraction: 0.74, blendDuration: 0.08)

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(switchAnimation) {
                configuration.isOn.toggle()
            }
        } label: {
            EmptyView()
        }
        .buttonStyle(SettingsSwitchButtonStyle(isOn: configuration.isOn, animation: switchAnimation))
        .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
    }
}

struct SettingsSwitchButtonStyle: ButtonStyle {
    let isOn: Bool
    let animation: Animation

    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitchBody(
            isOn: isOn,
            isPressed: configuration.isPressed,
            animation: animation
        )
    }
}

struct SettingsSwitchBody: View {
    let isOn: Bool
    let isPressed: Bool
    let animation: Animation

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(trackFill)
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(trackStroke, lineWidth: UIConstants.Stroke.hairline)
                )

            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(isPressed ? 0.12 : 0.16), radius: isPressed ? 1 : 2, x: 0, y: 1)
                .frame(width: 20, height: 20)
                .scaleEffect(isPressed ? 0.92 : 1)
                .padding(3)
        }
        .frame(width: 46, height: 26)
        .contentShape(Capsule(style: .continuous))
        .animation(animation, value: isOn)
        .animation(.easeOut(duration: UIConstants.Motion.fast), value: isPressed)
    }

    private var trackFill: Color {
        isOn
            ? PastryPalette.warmAccent
            : PastryPalette.switchOff
    }

    private var trackStroke: Color {
        isOn
            ? PastryPalette.warmBorder.opacity(0.45)
            : PastryPalette.ink.opacity(0.16)
    }
}

struct ShortcutCaptureView: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onPreview: (Int?, Int) -> Void
    var onChange: () -> Void
    var onStartRecording: () -> Void
    var onCancelRecording: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> ShortcutCaptureField {
        let field = ShortcutCaptureField()
        field.coordinator = context.coordinator
        return field
    }

    func updateNSView(_ nsView: ShortcutCaptureField, context: Context) {
        context.coordinator.parent = self
        nsView.coordinator = context.coordinator
        if isRecording {
            nsView.beginRecordingIfNeeded()
        } else {
            nsView.endRecordingIfNeeded()
        }
    }

    final class Coordinator: NSObject {
        var parent: ShortcutCaptureView

        init(parent: ShortcutCaptureView) {
            self.parent = parent
            super.init()
        }

        func preview(keyCode: Int?, modifiers: Int) {
            parent.onPreview(keyCode, modifiers)
        }

        func startRecording() {
            parent.onStartRecording()
        }

        func cancelRecording() {
            parent.isRecording = false
            parent.onCancelRecording()
        }

        func commit(keyCode: Int, modifiers: Int) {
            parent.keyCode = keyCode
            parent.modifiers = modifiers
            parent.onPreview(keyCode, modifiers)
            parent.onChange()
            parent.isRecording = false
        }
    }
}

final class ShortcutCaptureField: NSControl {
    weak var coordinator: ShortcutCaptureView.Coordinator?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    func beginRecordingIfNeeded() {
        guard !recording else { return }
        recording = true
        coordinator?.startRecording()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    func endRecordingIfNeeded() {
        guard recording else { return }
        recording = false
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }

        let code = Int(event.keyCode)
        if code == 53 {
            cancelRecording()
            return
        }

        let nseventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard nseventMods.contains(.command) || nseventMods.contains(.option)
            || nseventMods.contains(.control) || nseventMods.contains(.shift)
        else {
            SoundFeedback.invalidAction()
            return
        }

        let carbonMods = Int(nseventModifiersToCarbon(nseventMods))
        coordinator?.preview(keyCode: code, modifiers: carbonMods)
        recording = false
        coordinator?.commit(keyCode: code, modifiers: carbonMods)
        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else {
            super.flagsChanged(with: event)
            return
        }

        let nseventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let carbonMods = Int(nseventModifiersToCarbon(nseventMods))
        coordinator?.preview(keyCode: nil, modifiers: carbonMods)
    }

    override func resignFirstResponder() -> Bool {
        if recording {
            cancelRecording()
        }
        return super.resignFirstResponder()
    }

    private func cancelRecording() {
        recording = false
        coordinator?.cancelRecording()
        window?.makeFirstResponder(nil)
    }
}

struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        configureWhenReady(from: view)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        configureWhenReady(from: view)
    }

    private func configureWhenReady(from view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else {
                configureWhenReady(from: view)
                return
            }

            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }
            if window.titleVisibility != .hidden {
                window.titleVisibility = .hidden
            }
            if !window.titlebarAppearsTransparent {
                window.titlebarAppearsTransparent = true
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
            if window.toolbar != nil {
                window.toolbar?.isVisible = false
                window.toolbar = nil
            }
        }
    }
}
