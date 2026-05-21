import ApplicationServices
import Cocoa
import Combine
import OSLog

// MARK: - 剪贴板监听器
// 核心策略：轮询 NSPasteboard.changeCount，检测变化后立即读取
final class ClipboardMonitor: ObservableObject {

    // MARK: 单例
    nonisolated(unsafe) static let shared = ClipboardMonitor()

    // MARK: Published
    @Published private(set) var latestItem: ClipboardItem?
    @Published private(set) var isRunning = false

    // MARK: 回调
    var onNewItem: ((ClipboardItem) -> Void)?

    // MARK: 私有状态
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?
    private let pollInterval: TimeInterval = 0.2
    private let log = Logger(subsystem: "com.nekutai.pastry", category: "monitor")

    /// CGEvent tap：监听 ⌘C/⌘X/截图 按键，立即触发轮询（不等 timer，降低延迟）
    /// 同时追踪所有按键事件的目标进程 PID，用于精确来源检测（解决浮动面板场景）
    private var eventTap: CFMachPort?

    /// 最近一次按键事件的目标进程（由 CGEvent tap 在事件瞬间捕获，线程通过 DispatchQueue.main 保护）
    private var lastEventTargetPID: pid_t?
    private var lastEventTime: Date?

    /// 高频 Accessibility 焦点缓存（0.1s 间隔刷新）——在 poll 触发前持续记录焦点，
    /// 解决浮动面板（1Password Quick Open）在 poll 时已关闭导致焦点丢失的问题
    private var cachedAXBundleID: String?
    private var cachedAXFocusTime: Date?
    private var focusTrackingTimer: Timer?

    /// 自定义复制提示音
    private static let copySound: NSSound? = {
        guard let path = Bundle.main.path(forResource: "Copy", ofType: "aiff") else {
            Logger(subsystem: "com.nekutai.pastry", category: "monitor").warning("找不到 Copy.aiff")
            return nil
        }
        return NSSound(contentsOfFile: path, byReference: true)
    }()

    /// 暂停/恢复监听（仅主线程调用）
    private var suspendCount = 0
    var isSuspended: Bool { suspendCount > 0 }

    func suspend() {
        assert(Thread.isMainThread, "suspend() 必须在主线程调用")
        suspendCount += 1
    }

    func resume() {
        assert(Thread.isMainThread, "resume() 必须在主线程调用")
        guard suspendCount > 0 else { return }
        suspendCount -= 1
        if suspendCount == 0 {
            lastChangeCount = NSPasteboard.general.changeCount
        }
    }

    /// 清空剪贴板后同步计数器，避免监听器误检
    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private init() {}

    // MARK: - 生命周期

    func start() {
        guard !isRunning else { return }
        isRunning = true

        lastChangeCount = NSPasteboard.general.changeCount

        let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // 高频 Accessibility 焦点追踪：0.1s 间隔刷新缓存。
        // 浮动面板（1Password Quick Open）在 poll 触发时可能已关闭——此缓存保存关闭前的焦点。
        let ft = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.refreshAXFocusCache()
        }
        RunLoop.main.add(ft, forMode: .common)
        focusTrackingTimer = ft

        // CGEvent tap 延迟到首次需要时创建，避免启动时弹出辅助功能授权对话框。
        // 在 poll() 首次检测到剪贴板变化时调用 setupEventTap()。

        log.info("剪贴板监听已启动 (interval: \(self.pollInterval)s)")
    }

    /// ⌘C 事件监听：延迟到首次剪贴板变化时创建（避免启动时弹出辅助功能授权对话框）。
    /// 首次 ⌘C 的来源检测由 AX 缓存 + frontmostApp 兜底，后续自动切换为 event tap。
    func setupEventTap() {
        guard eventTap == nil else { return }

        let eventMask = CGEventMask(1 << CGEventType.keyUp.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyUp {
                    let monitor = Unmanaged<ClipboardMonitor>
                        .fromOpaque(refcon!).takeUnretainedValue()
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let flags = event.flags
                    let targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))

                    let isCopy       = keyCode == 8  && flags.contains(.maskCommand)                           // C
                    let isCut        = keyCode == 7  && flags.contains(.maskCommand)                           // X
                    let isScreenshot = (keyCode == 20 || keyCode == 21 || keyCode == 23)                       // 3/4/5
                                        && flags.contains(.maskCommand) && flags.contains(.maskShift)
                    let isCtrlCmdA   = keyCode == 0 && flags.contains(.maskCommand) && flags.contains(.maskControl)  // A

                    DispatchQueue.main.async {
                        // 追踪按键目标进程（用于精确来源检测：1Password Quick Open 等浮动面板）
                        if targetPID > 0 {
                            monitor.lastEventTargetPID = targetPID
                            monitor.lastEventTime = Date()
                        }
                        if isCopy || isCut || isScreenshot || isCtrlCmdA {
                            monitor.poll()
                        }
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(self).toOpaque()
            )
        )
        if let tap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(
                kCFAllocatorDefault, tap, 0
            )
            CFRunLoopAddSource(
                RunLoop.main.getCFRunLoop(), runLoopSource, .commonModes
            )
            CGEvent.tapEnable(tap: tap, enable: true)
            log.info("⌘C 事件监听已启动")
        } else {
            log.warning("CGEvent tap 创建失败 — 可能需要辅助功能权限")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        focusTrackingTimer?.invalidate()
        focusTrackingTimer = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isRunning = false
        log.info("剪贴板监听已停止")
    }

    // MARK: - 辅助功能焦点 App

    /// 通过 Accessibility API 获取当前拥有键盘焦点的进程。
    /// 能正确检测 1Password Quick Open、Alfred 等浮动面板——它们的键盘焦点在面板进程，
    /// 但 `frontmostApplication` 仍返回后台主 App（因为没有激活面板进程的菜单栏）。
    /// 返回 nil 表示辅助功能权限未授予或当前无焦点进程，调用方应回退到 `frontmostApplication`。
    private func focusedAppViaAccessibility() -> (name: String, bundleID: String)? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp
        )
        guard result == .success, let app = focusedApp else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(app as! AXUIElement, &pid) == .success, pid > 0 else { return nil }
        guard let runningApp = NSRunningApplication(processIdentifier: pid),
              let bundleID = runningApp.bundleIdentifier
        else { return nil }

        return (runningApp.localizedName ?? "", bundleID)
    }

    /// 高频刷新 Accessibility 焦点缓存（0.1s 间隔调用）。
    /// 当浮动面板（1Password Quick Open）获取焦点时立即记录，不依赖 poll 时机。
    private func refreshAXFocusCache() {
        guard let ax = focusedAppViaAccessibility() else { return }
        cachedAXBundleID = ax.bundleID
        cachedAXFocusTime = Date()
    }

    // MARK: - 轮询

    /// 来源检测（按优先级）：
    /// 1. 高频 AX 缓存（0.1s 刷新，0.15s 窗口）— 捕获浮动面板关闭前的焦点
    /// 2. 前台 App（`NSWorkspace.shared.frontmostApplication`）
    private func resolveSourceApp() -> (name: String?, bundleID: String?) {
        let frontApp = NSWorkspace.shared.frontmostApplication

        // Layer 1: 高频 AX 焦点缓存（独立 0.1s 轮询，与剪贴板 poll 解耦）
        if let cachedBundleID = cachedAXBundleID,
           let cachedTime = cachedAXFocusTime,
           Date().timeIntervalSince(cachedTime) < 0.15,
           cachedBundleID != frontApp?.bundleIdentifier,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == cachedBundleID }),
           let bundleID = app.bundleIdentifier {
            log.debug("来源覆盖(高频AX): 前台=\(frontApp?.localizedName ?? "nil"), 缓存焦点=\(app.localizedName ?? "?")")
            return (app.localizedName, bundleID)
        }

        // Layer 2: 前台 App
        return (frontApp?.localizedName, frontApp?.bundleIdentifier)
    }

    private func poll() {
        guard !isSuspended else { return }

        let pb = NSPasteboard.general
        let currentChange = pb.changeCount

        guard currentChange != lastChangeCount else { return }
        lastChangeCount = currentChange

        // 首次检测到剪贴板变化时延迟创建 event tap，避免应用启动时弹出辅助功能授权
        setupEventTap()

        var (capturedApp, capturedBundleID) = resolveSourceApp()

        // 1Password Quick Open 在 pasteboard 上写 com.agilebits.onepassword 自定义类型。
        // 用它覆写来源——比 AX 缓存和 frontmostApplication 更可靠。
        if let types = pb.types, types.contains(where: { $0.rawValue == "com.agilebits.onepassword" }) {
            capturedApp = "1Password"
            capturedBundleID = "com.agilebits.onepassword"
        }

        DispatchQueue.main.async {
            [weak self] in
            self?.processChange(capturedApp: capturedApp, capturedBundleID: capturedBundleID)
        }
    }

    // MARK: - 处理剪贴板变化

    private func processChange(capturedApp: String?, capturedBundleID: String?) {
        // 排除名单：密码管理器等敏感应用不保存剪贴板历史
        if let bundleID = capturedBundleID {
            let excluded = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
            if excluded.contains(bundleID) {
                return
            }
        }

        let pb = NSPasteboard.general

        // 排除敏感 pasteboard 类型
        if let pbTypes = pb.types {
            let ignoredRawTypes: Set<String> = [
                "org.nspasteboard.ConcealedType",
            ]
            let hasIgnored = pbTypes.contains(where: { ignoredRawTypes.contains($0.rawValue) })
            if hasIgnored {
                return
            }
        }

        guard let types = pb.types, !types.isEmpty else {
            return
        }

        // 类型非空，确认有效复制 → 播提示音
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.soundEnabled) {
            Self.copySound?.play()
        }

        // 检测 Handoff/通用剪贴板来源
        let isRemoteClipboard = types.contains(where: { $0.rawValue == "com.apple.is-remote-clipboard" })
        let effectiveApp = isRemoteClipboard ? nil : capturedApp  // Handoff 时不给 appName，之后 UI 层特殊处理

        // 文件 URL 优先：Finder 复制文件时剪贴板同时有图片数据，fileURL 更能代表用户意图
        if let item = readFileURLs(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            publish(item)
            return
        }

        // URL 链接：在图片之前检测，避免 http 字符串被当作纯文本
        if let item = readURL(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            publish(item)
            return
        }

        // 图片处理：主线程读取数据，后台任务生成缩略图并写入磁盘
        if let (image, data) = readImageData(from: pb) {
            let textAnnotation = readText(from: pb, appName: nil)?.content
            saveImageAndPublish(
                image: image,
                data: data,
                appName: effectiveApp,
                isHandoff: isRemoteClipboard,
                textAnnotation: textAnnotation
            )
            return
        }

        if let item = readHTML(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard)
            ?? readRTF(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard)
            ?? readText(from: pb, appName: effectiveApp, isHandoff: isRemoteClipboard) {
            publish(item)
        }
    }

    @MainActor
    private func publishOnMain(_ item: ClipboardItem) {
        latestItem = item
        onNewItem?(item)
    }

    private func publish(_ item: ClipboardItem) {
        DispatchQueue.main.async { [weak self] in
            self?.publishOnMain(item)
        }
    }

    private func saveImageAndPublish(
        image: NSImage,
        data: Data,
        appName: String?,
        isHandoff: Bool,
        textAnnotation: String?
    ) {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            guard let savedPath = ImageCacheManager.shared.save(image: image, data: data) else {
                self.log.error("图片缓存写入失败")
                return
            }
            let item = ClipboardItem(
                content: savedPath,
                sourceFormat: .image,
                appName: appName,
                isHandoff: isHandoff,
                textAnnotation: textAnnotation
            )
            await self.publishOnMain(item)
        }
    }

    // MARK: - 测试入口

    /// 供单元测试：检查 bundleID 是否在排除名单中
    static func isBundleIDExcludedForTesting(_ bundleID: String) -> Bool {
        let excluded = UserDefaults.standard.stringArray(forKey: UserDefaultsKeys.excludedBundleIDs) ?? []
        return excluded.contains(bundleID)
    }

    /// 供单元测试：检测 pasteboard types 是否含 ConcealedType
    static func hasConcealedTypeForTesting(from pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        return types.contains(where: { $0.rawValue == "org.nspasteboard.ConcealedType" })
    }

    /// 供单元测试：检测 pasteboard types 是否含 1Password 标记
    static func has1PasswordTypeForTesting(from pb: NSPasteboard) -> Bool {
        guard let types = pb.types else { return false }
        return types.contains(where: { $0.rawValue == "com.agilebits.onepassword" })
    }

}
