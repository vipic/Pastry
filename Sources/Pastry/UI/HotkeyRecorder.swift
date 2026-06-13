import SwiftUI
import AppKit
import Carbon

// MARK: - 快捷键录制控件

/// 三态自绘控件：未设置 / 已设置（带清除按钮）/ 录制中
/// 点击文字区域进入录制，点击 ✕ 清除快捷键
struct HotkeyRecorderView: NSViewRepresentable {

    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: () -> Void
    var onStartRecording: () -> Void   // 进入录制时调用（暂停旧快捷键）
    var onCancelRecording: () -> Void  // ESC 取消录制时调用（恢复旧快捷键）

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.coordinator = context.coordinator
        return field
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.configure(keyCode: keyCode, modifiers: modifiers)
    }

    final class Coordinator: NSObject {
        let parent: HotkeyRecorderView
        init(parent: HotkeyRecorderView) {
            self.parent = parent
            super.init()
        }
    }
}

// MARK: - 录制状态

private enum RecorderState {
    case unset
    case set
    case recording
}

// MARK: - AppKit 录制控件（NSControl 子类 — 原生支持鼠标事件和 firstResponder）

final class HotkeyRecorderField: NSControl {

    weak var coordinator: HotkeyRecorderView.Coordinator?

    private var state: RecorderState = .unset
    private var displayKeyCode: Int = -1
    private var displayModifiers: Int = 0
    private var isHovered = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        ))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        needsDisplay = true
    }

    func configure(keyCode: Int, modifiers: Int) {
        if state != .recording {
            displayKeyCode = keyCode
            displayModifiers = modifiers
            state = keyCode >= 0 ? .set : .unset
            needsDisplay = true
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        state = .recording
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        if state == .recording {
            state = displayKeyCode >= 0 ? .set : .unset
        }
        needsDisplay = true
        return true
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clearRect = NSRect(x: bounds.width - 30, y: 0, width: 30, height: bounds.height)

        if state == .set && NSPointInRect(point, clearRect) {
            clearShortcut()
        } else {
            coordinator?.parent.onStartRecording()
            window?.makeFirstResponder(self)
        }
    }

    private func clearShortcut() {
        coordinator?.parent.keyCode = -1
        coordinator?.parent.modifiers = 0
        coordinator?.parent.onChange()
        state = .unset
        displayKeyCode = -1
        displayModifiers = 0
        needsDisplay = true
    }

    // MARK: - 键盘

    override func keyDown(with event: NSEvent) {
        guard state == .recording else {
            super.keyDown(with: event)
            return
        }

        let code = Int(event.keyCode)

        if code == 53 {  // ESC — 取消，恢复旧快捷键
            coordinator?.parent.onCancelRecording()
            window?.makeFirstResponder(nil)
            return
        }

        // 必须有至少一个修饰键（NSEvent 格式检查）
        let nseventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !nseventMods.contains(.command) && !nseventMods.contains(.option)
            && !nseventMods.contains(.control) && !nseventMods.contains(.shift) {
            NSSound.beep()
            return
        }

        // 转换为 Carbon 修饰键位（cmdKey=0x0100, shiftKey=0x0200, optionKey=0x0800, controlKey=0x1000）
        let carbonMods = nseventModifiersToCarbon(nseventMods)

        coordinator?.parent.keyCode = code
        coordinator?.parent.modifiers = Int(carbonMods)
        coordinator?.parent.onChange()

        displayKeyCode = code
        displayModifiers = Int(carbonMods)
        state = .set

        window?.makeFirstResponder(nil)
    }

    override func flagsChanged(with event: NSEvent) {
        needsDisplay = true
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)

        switch state {
        case .recording:
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        default:
            if isHovered {
                NSColor.controlBackgroundColor.blended(withFraction: 0.06, of: .secondaryLabelColor)?.setFill()
                    ?? NSColor.controlBackgroundColor.setFill()
            } else {
                NSColor.controlBackgroundColor.setFill()
            }
        }
        bgPath.fill()

        switch state {
        case .recording:
            NSColor.controlAccentColor.setStroke()
            bgPath.lineWidth = 2
        default:
            NSColor.separatorColor.setStroke()
            bgPath.lineWidth = 1
        }
        bgPath.stroke()

        switch state {
        case .unset:
            drawText(L10n["hotkey.not_set"], color: .disabledControlTextColor, centered: true)
        case .set:
            drawShortcutText(keyCode: displayKeyCode, modifiers: displayModifiers, color: .secondaryLabelColor)
            drawClearButton()
        case .recording:
            drawText(L10n["hotkey.recording"], color: .tertiaryLabelColor, centered: true)
        }
    }

    private func drawText(_ text: String, color: NSColor, centered: Bool) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color
        ]
        let size = text.size(withAttributes: attrs)
        let textRect: NSRect
        if centered {
            textRect = NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        } else {
            textRect = NSRect(
                x: 8,
                y: bounds.midY - size.height / 2,
                width: min(size.width, bounds.width - 32),
                height: size.height
            )
        }
        text.draw(in: textRect, withAttributes: attrs)
    }

    private func drawShortcutText(keyCode: Int, modifiers: Int, color: NSColor) {
        let segments = shortcutDisplaySegments(keyCode: keyCode, modifiers: modifiers)
        guard !segments.isEmpty else { return }

        let symbolAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: color
        ]
        let keyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold),
            .foregroundColor: color
        ]
        let spacing: CGFloat = 5

        let measured = segments.map { segment -> (text: String, attrs: [NSAttributedString.Key: Any], size: NSSize, yOffset: CGFloat) in
            let isModifier = segment.count == 1 && "⌃⌥⇧⌘".contains(segment)
            let attrs = isModifier ? symbolAttrs : keyAttrs
            return (segment, attrs, segment.size(withAttributes: attrs), isModifier ? 0 : -0.35)
        }

        let totalWidth = measured.reduce(CGFloat(0)) { $0 + $1.size.width }
            + spacing * CGFloat(max(0, measured.count - 1))
        let maxHeight = measured.map(\.size.height).max() ?? 0
        var x = bounds.midX - totalWidth / 2
        let baseY = bounds.midY - maxHeight / 2

        for item in measured {
            let rect = NSRect(
                x: x,
                y: baseY + (maxHeight - item.size.height) / 2 + item.yOffset,
                width: item.size.width,
                height: item.size.height
            )
            item.text.draw(in: rect, withAttributes: item.attrs)
            x += item.size.width + spacing
        }
    }

    private func drawClearButton() {
        let clearRect = NSRect(x: bounds.width - 28, y: 0, width: 28, height: bounds.height)
        let cross = "✕" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let size = cross.size(withAttributes: attrs)
        let point = NSPoint(
            x: clearRect.midX - size.width / 2,
            y: clearRect.midY - size.height / 2
        )
        cross.draw(at: point, withAttributes: attrs)
    }
}

// MARK: - 快捷键显示字符串

func shortcutDisplayString(keyCode: Int, modifiers: Int) -> String {
    shortcutDisplaySegments(keyCode: keyCode, modifiers: modifiers).joined(separator: " ")
}

func shortcutDisplaySegments(keyCode: Int, modifiers: Int) -> [String] {
    shortcutDisplaySegments(keyCode: keyCode, modifiers: modifiers, includeKey: true)
}

func shortcutDisplayPreviewSegments(keyCode: Int?, modifiers: Int) -> [String] {
    shortcutDisplaySegments(keyCode: keyCode ?? -1, modifiers: modifiers, includeKey: keyCode != nil)
}

private func shortcutDisplaySegments(keyCode: Int, modifiers: Int, includeKey: Bool) -> [String] {
    let mods = UInt32(modifiers)
    var parts: [String] = []
    if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
    if mods & UInt32(optionKey)  != 0 { parts.append("⌥") }
    if mods & UInt32(shiftKey)   != 0 { parts.append("⇧") }
    if mods & UInt32(cmdKey)     != 0 { parts.append("⌘") }

    if includeKey, let char = keyCodeToDisplayName(Int32(keyCode)) {
        parts.append(char)
    }

    return parts
}

/// NSEvent.ModifierFlags → Carbon 修饰键位
func nseventModifiersToCarbon(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var carbon: UInt32 = 0
    if flags.contains(.command) { carbon |= UInt32(cmdKey) }
    if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
    if flags.contains(.option)  { carbon |= UInt32(optionKey) }
    if flags.contains(.control) { carbon |= UInt32(controlKey) }
    return carbon
}

func keyCodeToDisplayName(_ code: Int32) -> String? {
    switch code {
    case 0:  return "A"; case 1:  return "S"; case 2:  return "D"; case 3:  return "F"
    case 4:  return "H"; case 5:  return "G"; case 6:  return "Z"; case 7:  return "X"
    case 8:  return "C"; case 9:  return "V"; case 11: return "B"; case 12: return "Q"
    case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
    case 17: return "T"; case 31: return "O"; case 32: return "U"; case 34: return "I"
    case 35: return "P"; case 37: return "L"; case 38: return "J"; case 40: return "K"
    case 45: return "N"; case 46: return "M"
    case 18: return "1"; case 19: return "2"; case 20: return "3"; case 21: return "4"
    case 23: return "5"; case 22: return "6"; case 26: return "7"; case 28: return "8"
    case 25: return "9"; case 29: return "0"
    case 27: return "−"; case 24: return "="
    case 33: return "["; case 30: return "]"
    case 42: return "\\"; case 41: return ";"
    case 39: return "'"; case 43: return ","
    case 47: return "."; case 44: return "/"
    case 50: return "`"
    case 122: return "F1";  case 120: return "F2";  case 99:  return "F3"
    case 118: return "F4";  case 96:  return "F5";  case 97:  return "F6"
    case 98:  return "F7";  case 100: return "F8";  case 101: return "F9"
    case 109: return "F10"; case 103: return "F11"; case 111: return "F12"
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
