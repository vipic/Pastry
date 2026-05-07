import Cocoa
import Carbon
import OSLog

// MARK: - 全局快捷键管理器
// 使用 Carbon RegisterEventHotKey 注册系统级热键
// 即使 App 在后台也能响应
final class GlobalHotkeyManager {

    nonisolated(unsafe) static let shared = GlobalHotkeyManager()
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "hotkey")

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    // 默认快捷键: ⌘⇧V
    static let defaultKeyCode: Int32 = 9       // kVK_ANSI_V
    static let defaultModifiers: UInt32 = UInt32(cmdKey) | UInt32(shiftKey)

    /// keyCode = -1 表示快捷键已禁用
    static let disabledSentinel: Int32 = -1

    /// 当前生效的快捷键 — 从 UserDefaults 读取
    private var currentKeyCode: Int32 {
        // object(forKey:) 区分「未设置」(nil) 与「设置为 0」(keyCode 0 是 A 键)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.hotkeyKeyCode) == nil {
            return Self.defaultKeyCode
        }
        let raw = UserDefaults.standard.integer(forKey: UserDefaultsKeys.hotkeyKeyCode)
        return Int32(raw)
    }

    private var currentModifiers: UInt32 {
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.hotkeyModifiers) == nil {
            return Self.defaultModifiers
        }
        let raw = UserDefaults.standard.integer(forKey: UserDefaultsKeys.hotkeyModifiers)
        return UInt32(raw)
    }

    private init() {
        // 监听 UserDefaults 变化，快捷键改变后自动重注册
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func defaultsDidChange() {
        reregister()
    }

    // MARK: - 注册

    func register() {
        guard hotKeyRef == nil else { return }

        let code = currentKeyCode

        // 禁用状态 — 不注册任何热键
        guard code >= 0 else {
            log.info("全局快捷键未配置，跳过注册")
            return
        }

        let mods = currentModifiers

        // 1. 注册热键
        let hotKeyID = EventHotKeyID(signature: 0x434C50, id: 1) // "CLP"
        let status = RegisterEventHotKey(
            UInt32(code),
            mods,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr else {
            log.error("全局快捷键注册失败: \(status) (keyCode=\(code), modifiers=\(mods))")
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

        let display = shortcutDisplayString(keyCode: Int(code), modifiers: Int(mods))
        log.info("全局快捷键 \(display) 已注册")
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

    /// 先注销再注册 — 快捷键配置变更时调用
    func reregister() {
        unregister()
        register()
    }

    // MARK: - 回调

    private let hotkeyHandler: EventHandlerProcPtr = { _, _, _ -> OSStatus in
        DispatchQueue.main.async {
            OverlayPanelManager.shared.toggle()
        }
        return noErr
    }
}
