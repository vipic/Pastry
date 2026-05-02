import SwiftUI
import AppKit

// MARK: - 快捷键录制控件

/// macOS 原生风格的快捷键录制视图
/// 点击进入录制状态，按下组合键记录，ESC 取消
struct HotkeyRecorderView: NSViewRepresentable {

    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var isRecording: Bool
    var onStartRecording: () -> Void
    var onCommit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.coordinator = context.coordinator
        return field
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.displayString = shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
        nsView.isRecording = isRecording
        nsView.needsDisplay = true

        if isRecording {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    // MARK: - 显示字符串生成

    static func displayString(keyCode: Int, modifiers: Int) -> String {
        shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject {
        let parent: HotkeyRecorderView

        init(parent: HotkeyRecorderView) {
            self.parent = parent
            super.init()
        }
    }
}

// MARK: - AppKit 录制控件

final class HotkeyRecorderField: NSView {

    weak var coordinator: HotkeyRecorderView.Coordinator?

    var displayString = "" {
        didSet { needsDisplay = true }
    }

    var isRecording = false {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        isRecording = true
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return true
    }

    override func mouseDown(with event: NSEvent) {
        // 通知 SwiftUI 进入录制状态
        coordinator?.parent.onStartRecording()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        let code = Int(event.keyCode)
        let mods = Int(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)

        // ESC — 取消
        if code == 53 {
            window?.makeFirstResponder(nil)
            coordinator?.parent.onCancel()
            return
        }

        // 必须有至少一个修饰键（cmd/opt/ctrl/shift）
        let meaningfulMods = mods & 0xFFFF0000 >> 16
        if meaningfulMods == 0 {
            // 纯字母/数字不允许
            NSSound.beep()
            return
        }

        // 记录快捷键
        coordinator?.parent.keyCode = code
        coordinator?.parent.modifiers = mods

        window?.makeFirstResponder(nil)
        coordinator?.parent.onCommit()
    }

    override func flagsChanged(with event: NSEvent) {
        // 允许用户先按修饰键再按字母
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        // 背景
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)

        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        } else {
            NSColor.controlBackgroundColor.setFill()
        }
        bgPath.fill()

        // 边框
        if isRecording {
            NSColor.controlAccentColor.setStroke()
            bgPath.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            bgPath.lineWidth = 1
        }
        bgPath.stroke()

        // 文字
        let text = isRecording ? (displayString.isEmpty ? "按下快捷键…" : displayString) : displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: displayString.isEmpty
                ? NSColor.tertiaryLabelColor
                : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        text.draw(at: point, withAttributes: attrs)
    }
}

// MARK: - 快捷键显示字符串

func shortcutDisplayString(keyCode: Int, modifiers: Int) -> String {
    // 提取设备无关的修饰键标志
    let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        .intersection(.deviceIndependentFlagsMask)

    var parts: [String] = []
    if flags.contains(.control) { parts.append("⌃") }
    if flags.contains(.option)   { parts.append("⌥") }
    if flags.contains(.shift)    { parts.append("⇧") }
    if flags.contains(.command)  { parts.append("⌘") }

    // 按键名映射
    if let char = keyCodeToDisplayName(Int32(keyCode)) {
        parts.append(char)
    }

    return parts.joined()
}

/// 将 Carbon keyCode 映射为显示字符
private func keyCodeToDisplayName(_ code: Int32) -> String? {
    switch code {
    // 字母
    case 0:  return "A"; case 1:  return "S"; case 2:  return "D"; case 3:  return "F"
    case 4:  return "H"; case 5:  return "G"; case 6:  return "Z"; case 7:  return "X"
    case 8:  return "C"; case 9:  return "V"; case 11: return "B"; case 12: return "Q"
    case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
    case 17: return "T"; case 31: return "O"; case 32: return "U"; case 34: return "I"
    case 35: return "P"; case 37: return "L"; case 38: return "J"; case 40: return "K"
    case 45: return "N"; case 46: return "M"

    // 数字
    case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
    case 23: return "5"; case 22: return "6"; case 26: return "7"; case 28: return "8"
    case 25: return "9"; case 29: return "0"

    // 符号
    case 27: return "−"; case 24: return "="
    case 33: return "["; case 30: return "]"
    case 42: return "\\"; case 41: return ";"
    case 39: return "'"; case 43: return ","
    case 47: return "."; case 44: return "/"
    case 50: return "`"

    // 功能键
    case 122: return "F1";  case 120: return "F2";  case 99:  return "F3"
    case 118: return "F4";  case 96:  return "F5";  case 97:  return "F6"
    case 98:  return "F7";  case 100: return "F8";  case 101: return "F9"
    case 109: return "F10"; case 103: return "F11"; case 111: return "F12"

    // 特殊键
    case 36:  return "↩";      case 48:  return "⇥"
    case 49:  return "␣";      case 51:  return "⌫"
    case 117: return "⌦";      case 53:  return "⎋"
    case 115: return "↖";      case 119: return "↘"
    case 116: return "⇞";      case 121: return "⇟"
    case 123: return "←";      case 124: return "→"
    case 125: return "↓";      case 126: return "↑"

    default: return nil
    }
}
