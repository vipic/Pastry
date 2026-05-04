# Pastry — Agent Onboarding

> macOS 26+ 剪贴板管理器。纯 Swift + SwiftUI，零第三方依赖。全屏半透明 overlay 面板 + 应用主题色卡片。

## Build & Deploy

```bash
# 构建
swift build -c release

# 部署（必须 kill 旧进程，否则运行中的二进制不更新）
cp .build/release/Pastry ~/Applications/Pastry.app/Contents/MacOS/Pastry

# codesign 必须重签，否则 kill:9 崩溃
rm -rf ~/Applications/Pastry.app/Contents/_CodeSignature
codesign --force --sign - ~/Applications/Pastry.app

# 重启
pkill -f Pastry; sleep 0.5; open ~/Applications/Pastry.app
```

**关键教训**：`swift build` 之后如果不 kill 旧进程，运行的仍是旧二进制。`pkill -f Pastry` 是必须的。

## Architecture

```
Sources/Pastry/                    （~4550 行）
├── PastryApp.swift                # @main + AppDelegate (LSUIElement)
├── Core/
│   ├── ClipboardItem.swift        # Codable 数据模型 (ClipType enum)
│   └── ClipboardMonitor.swift     # NSPasteboard 轮询引擎 (588 行)
├── Persistence/
│   ├── DatabaseManager.swift      # SQLite3 C API + FTS5 全文搜索
│   └── StoreManager.swift         # @MainActor ObservableObject 桥接
├── UI/
│   ├── OverlayPanelManager.swift  # NSPanel 全屏 overlay 管理
│   ├── OverlayView.swift          # SwiftUI 内容层（透明底 + 卡片托盘）
│   ├── ClipboardCardView.swift    # 卡片视图（920 行，最大文件，含 RemoteThumbnail + LinkPreviewLoader + ClipboardCardView）
│   ├── GlassBackground.swift      # NSVisualEffectView(.hudWindow) 托盘背景
│   ├── HotkeyRecorder.swift       # 快捷键录制器
│   └── MenuBarManager.swift       # NSStatusBar 菜单栏入口
└── Utils/
    ├── AppIconProvider.swift      # 提取应用图标 + 主题色
    ├── Constants.swift            # SF Symbols、UserDefaults key、颜色
    ├── GlobalHotkeyManager.swift  # Carbon RegisterEventHotKey 全局快捷键
    └── RemoteImageLoader.swift    # 远程图片下载 + 内存缓存

Tests/PastryTests/                 （~1820 行，179 个测试用例）
├── ClipboardMonitorTests.swift    # 剪贴板轮询逻辑
├── DatabaseManagerTests.swift     # SQLite CRUD + FTS
├── StoreManagerTests.swift        # 存储层桥接
├── LinkPreviewLoaderTests.swift   # 链接预览抓取 + 图片选取逻辑
├── FilePreviewTests.swift         # 文件缩略图生成
├── AppIconProviderTests.swift     # 图标提取
├── HotkeyUtilsTests.swift         # 快捷键工具
└── ConstantsTests.swift           # 常量验证
```

## Critical Pitfalls

以下是踩过的坑，Agent 接手时能省大量时间：

### 1. Timer 必须用 `.common` modes

```swift
// ❌ 错误 — 右键菜单 / 拖拽时 Timer 暂停，永不恢复
Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { ... }

// ✅ 正确
let timer = Timer(timeInterval: 0.5, repeats: true) { ... }
RunLoop.main.add(timer, forMode: .common)
```

macOS 进入 tracking mode（右键、拖拽、滚动）时，default mode 的 Timer 会暂停。

### 2. NSGlassEffectView 在透明 NSPanel 中渲染异常

macOS 26 的 `NSGlassEffectView` 在透明 NSPanel 中渲染为**白色半透明**，无法产生真实液态玻璃效果。当前使用 `NSVisualEffectView(.hudWindow)` 替代：

```swift
// GlassBackground.swift
view.material = .hudWindow       // 深色半透明磨砂，浅/深桌面都稳定
view.blendingMode = .withinWindow
view.state = .active
```

### 3. NSGlassEffectView 自带阴影需手动关闭

```swift
glass.wantsLayer = true          // 必须先设为 true
glass.layer?.shadowOpacity = 0   // 关闭圆角外暗色阴影
glass.layer?.masksToBounds = true
```

### 4. NSPanel 层级：用 `.popUpMenu`，不用 `.screenSaver`

```swift
panel.level = .popUpMenu  // 101，能承载 NSMenu 事件
// ❌ .screenSaver (1000) — 会截断 NSMenu 事件链，右键菜单全部无响应
```

正确的 `styleMask` 和激活策略：

```swift
panel.styleMask = [.borderless, .nonactivatingPanel]
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
panel.orderFrontRegardless()  // 不激活 app
panel.makeKey()               // 接收键盘事件但 app 保持后台
```

### 5. NSPanel Esc 关闭：通过通知 + 动画，不要直接 cleanup

```swift
// 键盘监听器发送通知
NotificationCenter.default.post(name: .overlayRequestDismiss, object: nil)

// OverlayView 监听并先播退出动画
.onReceive(NotificationCenter.default.publisher(for: .overlayRequestDismiss)) { _ in
    dismiss()  // 动画结束后调 OverlayPanelManager.hide()
}
```

### 6. `.frame(maxHeight:)` 必须配合 `.clipped()`

```swift
// ❌ 没有视觉效果 — 内容渲染超出 frame 边界
VStack { ... }
    .frame(maxHeight: 248)

// ✅
VStack { ... }
    .frame(maxHeight: 248)
    .clipped()
```

### 7. NavigationSplitView List(selection:) 侧边栏点击无效

SwiftUI macOS 26 的 `List(selection:)` 在 `NavigationSplitView` 侧边栏中点击不响应。解决方案：

```swift
Button(action: { selectedItem = item }) { ... }
    .buttonStyle(.plain)
    .listRowBackground(selectedItem == item ? Color.accentColor.opacity(0.1) : Color.clear)
```

### 8. 授权懒加载

`CGEvent.tapCreate` **不**在 `ClipboardMonitor.start()` 时调用。延迟到用户首次执行「粘贴」操作时才创建 event tap，避免启动时弹出辅助功能授权对话框。

```swift
// simulatePaste 首次调用时才初始化 CGEvent
private static func simulatePaste() {
    let source = CGEventSource(stateID: .privateState)
    // postToPid + .privateState：直接投递给前台进程
    CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)?
        .postToPid(pid)
}
```

### 9. git restore . 会丢弃未提交改动

`git restore .` 会丢弃所有未跟踪改动，包括之前特意保留的修复。需要先确认是否有需要保留的部分。

## Testing Strategy

### 独立 Pasteboard（关键）

测试**绝不**使用 `NSPasteboard.general`。每个测试类使用独立 pasteboard：

```swift
let pasteboard = NSPasteboard.withUniqueName()  // "test.hermes.pastry.<uuid>"
```

原因：`NSPasteboard.general` 的写入会触发后台运行的 Pastry 的 `changeCount` 监听，导致复制提示音响起，干扰测试环境。

### 运行测试

```bash
swift test
# 或详细输出
swift test -v 2>&1 | grep -E "(PASS|FAIL|test) "
```

## Key Design Patterns

### App 来源检测（上下文优先）

记录剪贴板来源时，**用用户工作上下文而非触发进程**。三层兜底：
1. `recentApps`（`didActivateApplicationNotification` 追踪，10s 窗口）
2. `previousFrontApp`（上轮轮询记录的前台 App）
3. `currentFront`（兜底）

### 剪贴板清除策略

三条删除路径的不同行为：
- **菜单「清空全部记录」** 和 **⌘A+Delete 批量删** → 一并清空系统剪贴板
- **单条右键删除** → 只删历史记录，不动系统剪贴板（用户可继续 ⌘V）

### 链接预览图片选取

优先级：`og:image` → `twitter:image` → 语义排序（黑名单过滤 avatar/logo/icon 等噪音关键词，尺寸过滤 <100px，语义加分 hero/featured 等）→ 保底最大图。支持 `data-src` 懒加载降级。

### 链接预览骨架图

卡片加载中使用 SwiftUI `.redacted(reason: .placeholder)` 实现骨架屏，利用已知缩略图尺寸避免布局抖动。不用 ProgressView 转圈。

### 提示音时机

- **复制提示音**：`changeCount` 变化瞬间响（不等 debounce/去重）
- **粘贴提示音**：`simulatePaste()` 方法第一行响

### 自动关闭面板

监听 `NSWorkspace.didActivateApplicationNotification`，非本 App 激活时自动关闭。但粘贴流程中（`isPasting = true`）跳过此规则。

## macOS 26 Specifics

- **LaunchPad 已更名 Apps**：路径 `/System/Applications/Apps.app`
- **Liquid Glass API**：`NSGlassEffectView` 当前 beta 阶段在透明 NSPanel 中渲染异常，降级用 `NSVisualEffectView(.hudWindow)`
- **辅助功能授权**：macOS 26 强制要求跨进程键盘事件授权，只有 `.privateState` + `postToPid` 是最小权限方案