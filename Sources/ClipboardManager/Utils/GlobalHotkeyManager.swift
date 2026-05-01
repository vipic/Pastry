import Cocoa
import Carbon
import OSLog

// MARK: - 全局快捷键管理器
// 使用 Carbon RegisterEventHotKey 注册系统级热键
// 即使 App 在后台也能响应 ⌘⇧V
final class GlobalHotkeyManager {

    static let shared = GlobalHotkeyManager()
    private let log = Logger(subsystem: "com.clipboardmanager", category: "hotkey")

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // 快捷键: ⌘⇧V
    private let keyCode: UInt32 = 9       // kVK_ANSI_V
    private let modifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)

    private init() {}

    // MARK: - 注册

    func register() {
        guard hotKeyRef == nil else { return }

        // 1. 注册热键
        let hotKeyID = EventHotKeyID(signature: 0x434C50, id: 1) // "CLP"
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            log.error("全局快捷键注册失败: \(status)")
            return
        }

        // 2. 安装事件处理器
        let eventSpec = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                          eventKind: OSType(kEventHotKeyPressed))
        ]

        InstallEventHandler(
            GetEventDispatcherTarget(),
            hotkeyHandler,
            1,
            eventSpec,
            nil,
            &eventHandler
        )

        log.info("全局快捷键 ⌘⇧V 已注册")
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        log.info("全局快捷键已注销")
    }

    // MARK: - 回调

    private let hotkeyHandler: EventHandlerProcPtr = { _, _, _ -> OSStatus in
        DispatchQueue.main.async {
            OverlayPanelManager.shared.toggle()
        }
        return noErr
    }
}
