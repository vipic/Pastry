import Cocoa

enum OverlayKeyboardOwner: Equatable {
    case overlayNavigation
    case searchField
    case favoriteNoteEditor
}

final class OverlayKeyboardRouter {
    private var keyboardMonitor: Any?
    private var flagsChangedMonitor: Any?
    private var cmdWasDown = false

    private let isAlertActive: () -> Bool
    private let isSearchActive: () -> Bool
    private let keyboardOwner: () -> OverlayKeyboardOwner

    init(
        isAlertActive: @escaping () -> Bool,
        isSearchActive: @escaping () -> Bool,
        keyboardOwner: @escaping () -> OverlayKeyboardOwner
    ) {
        self.isAlertActive = isAlertActive
        self.isSearchActive = isSearchActive
        self.keyboardOwner = keyboardOwner
    }

    func install() {
        remove()

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }

        flagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event) ?? event
        }
    }

    func remove() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
        if let monitor = flagsChangedMonitor {
            NSEvent.removeMonitor(monitor)
            flagsChangedMonitor = nil
        }
        cmdWasDown = false
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let owner = keyboardOwner()

        // Esc：筛选气泡 → 预览 popover → 搜索栏 → 关闭面板（逐层收起）
        if event.keyCode == 53 {
            if isAlertActive() {
                NotificationCenter.default.post(name: .overlayAlertCancel, object: nil)
                return nil
            }
            if owner == .favoriteNoteEditor {
                NotificationCenter.default.post(name: .overlayCancelFavoriteNoteEditing, object: nil)
                return nil
            }
            if OverlayPanelManager.shared.isFilterPopoverActive {
                NotificationCenter.default.post(name: .overlayCloseFilter, object: nil)
                return nil
            }
            if QLPreviewHelper.shared.isShowing {
                QLPreviewHelper.shared.dismiss()
                return nil
            }
            if isSearchActive() {
                NotificationCenter.default.post(name: .overlayCloseSearch, object: nil)
                return nil
            }
            NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)
            return nil
        }

        // 弹窗活跃：Enter 确认删除 / Delete 静默消费 / 其他按键放行（Esc 已在上方处理）
        if isAlertActive() {
            if Self.isAlertConfirmKey(keyCode: event.keyCode) {
                NotificationCenter.default.post(name: .overlayAlertConfirm, object: nil)
                return nil
            }
            if Self.shouldConsumeAlertKeyDown(keyCode: event.keyCode) {
                return nil
            }
            return event
        }

        if owner == .favoriteNoteEditor {
            return event
        }

        if owner == .searchField {
            // 搜索框拥有键盘时，文本编辑快捷键（⌘A/Delete/方向键/Enter 等）
            // 都交给 TextField；只有面板级的 Tab / ⌘F 仍由 overlay 管理。
            if event.keyCode == 48,
               event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
                NotificationCenter.default.post(name: .overlayCloseSearch, object: nil,
                                                userInfo: ["clearFilter": false])
                return nil
            }
            if event.keyCode == 3, event.modifierFlags.contains(.command) {
                return nil
            }
            return event
        }

        // Tab — 搜索栏↔卡片焦点互相切换（无 Shift/⌘/⌥/⌃ 修饰）
        if event.keyCode == 48,
           event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty {
            if isSearchActive() {
                NotificationCenter.default.post(name: .overlayCloseSearch, object: nil,
                                                userInfo: ["clearFilter": false])
            } else {
                NotificationCenter.default.post(name: .overlayOpenSearchImmediate, object: nil)
            }
            return nil
        }

        // ⌘F 搜索
        if event.keyCode == 3, event.modifierFlags.contains(.command) {
            if !isSearchActive() {
                NotificationCenter.default.post(name: .overlayOpenSearch, object: nil)
            }
            return nil
        }

        // ⌘A 全选卡片；文本输入拥有键盘时已在上方放行。
        if event.keyCode == 0, event.modifierFlags.contains(.command) {
            NotificationCenter.default.post(name: .overlaySelectAll, object: nil)
            return nil
        }

        // Delete / Forward Delete — 若焦点在文本输入框则放行
        if event.keyCode == 51 || event.keyCode == 117 {
            if Self.isTextInputFocused() { return event }
            NotificationCenter.default.post(name: .overlayDeleteSelected, object: nil)
            return nil
        }

        let extend = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 126: // 上
            if isSearchActive() { return event }
            postCursorMove(delta: -1, extend: extend)
            return nil
        case 125: // 下
            if isSearchActive() { return event }
            postCursorMove(delta: 1, extend: extend)
            return nil
        case 123: // 左
            if isSearchActive() { return event }
            postCursorMove(delta: -1, extend: extend)
            return nil
        case 124: // 右
            if isSearchActive() { return event }
            postCursorMove(delta: 1, extend: extend)
            return nil
        case 115: // Home
            if isSearchActive() { return event }
            postCursorMove(target: "home", extend: extend)
            return nil
        case 119: // End
            if isSearchActive() { return event }
            postCursorMove(target: "end", extend: extend)
            return nil
        case 116: // Page Up
            if isSearchActive() { return event }
            postCursorMove(pageDelta: -1, extend: extend)
            return nil
        case 121: // Page Down
            if isSearchActive() { return event }
            postCursorMove(pageDelta: 1, extend: extend)
            return nil
        case 36: // Enter
            if Self.shouldAllowEnterForIME() {
                return event
            }
            if isSearchActive() {
                NotificationCenter.default.post(name: .overlaySearchEnterPaste, object: nil)
                return nil
            }
            NotificationCenter.default.post(name: .overlayConfirmPaste, object: nil)
            return nil
        case let kc where event.modifierFlags.contains(.command):
            if let idx = Self.cmdNumberIndex(keyCode: kc) {
                NotificationCenter.default.post(name: .overlayCmdPaste, object: nil,
                                                userInfo: ["index": idx])
                return nil
            }
            fallthrough
        default:
            if isSearchActive() {
                return event
            }
            if Self.shouldFocusSearch(
                chars: event.characters,
                isSearchActive: isSearchActive(),
                modifierFlags: event.modifierFlags
            ) {
                NotificationCenter.default.post(name: .overlayOpenSearchImmediate, object: nil)
                return nil
            }
            return event
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) -> NSEvent {
        let shouldShowCmdBadges = event.modifierFlags.contains(.command)
            && keyboardOwner() == .overlayNavigation
        if shouldShowCmdBadges != cmdWasDown {
            cmdWasDown = shouldShowCmdBadges
            NotificationCenter.default.post(name: .overlayCmdStateChanged, object: nil,
                                            userInfo: ["cmdDown": shouldShowCmdBadges])
        }
        return event
    }

    private func postCursorMove(delta: Int? = nil, pageDelta: Int? = nil, target: String? = nil, extend: Bool) {
        var userInfo: [String: Any] = ["extend": extend]
        if let delta { userInfo["delta"] = delta }
        if let pageDelta { userInfo["pageDelta"] = pageDelta }
        if let target { userInfo["target"] = target }
        NotificationCenter.default.post(name: .overlayMoveCursor, object: nil, userInfo: userInfo)
    }

    private static let cmdNumberMap: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9
    ]

    static func cmdNumberIndex(keyCode: UInt16) -> Int? {
        cmdNumberMap[keyCode]
    }

    static func isAlertConfirmKey(keyCode: UInt16) -> Bool {
        keyCode == 36
    }

    static func shouldConsumeAlertKeyDown(keyCode: UInt16) -> Bool {
        keyCode == 51 || keyCode == 117
    }

    /// 检查当前焦点是否在文本输入框内（搜索框等）
    static func isTextInputFocused() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder.isKind(of: NSTextView.self) { return true }
        if responder.isKind(of: NSTextField.self) { return true }
        if responder.isKind(of: NSSearchField.self) { return true }
        return false
    }

    /// 当前输入框是否有 IME 正在拼写（中文拼音等）。
    /// Enter 键在 marked text 期间应放行给输入法确认上屏，不应被面板拦截。
    static func shouldAllowEnterForIME() -> Bool {
        guard NSApp != nil,
              let window = NSApp.keyWindow,
              let fr = window.firstResponder as? NSTextView else { return false }
        return fr.hasMarkedText()
    }

    /// 判断字符串首字符是否应重定向到搜索栏（字母/数字/符号/标点/空格）
    static func isRedirectableChar(_ chars: String) -> Bool {
        guard let first = chars.first else { return false }
        return first.isLetter || first.isNumber || first.isSymbol || first.isPunctuation || first.isWhitespace
    }

    /// 判断按键是否应触发搜索栏聚焦（综合字符、状态、修饰键）
    static func shouldFocusSearch(
        chars: String?,
        isSearchActive: Bool,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Bool {
        guard !isSearchActive,
              !modifierFlags.contains(.command),
              !modifierFlags.contains(.control),
              let chars,
              !chars.isEmpty,
              isRedirectableChar(chars) else {
            return false
        }
        return true
    }

    deinit {
        remove()
    }
}
