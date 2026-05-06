# ADR-002: NSPanel Overlay vs SwiftUI Window

## 状态
已采纳

## 背景
Pastry 需要一个全局浮层显示剪贴板历史。该浮层需：
- 不抢 key focus（保持在前台应用活跃状态）
- 可拖拽到其他应用
- 支持原生 Cocoa 事件（右键菜单、beginDragThrough）
- 带模糊半透明材质背景

考察选项：
- **SwiftUI `Window`** — SwiftUI 原生窗口
- **SwiftUI `Menu`** — 系统菜单（纯 SwiftUI）
- **`NSPanel`** — AppKit 浮动面板

## 决策
使用 AppKit `NSPanel`（`.nonactivatingPanel` 风格）作为宿主容器，内部嵌入 SwiftUI 视图。

## 理由
- **不抢 key** — `.nonactivatingPanel` 风格确保面板弹出时目标应用不会失去焦点
- **完整 AppKit 事件链** — 右键菜单（NSMenu）、拖拽到其他应用（beginDragThrough）依赖 AppKit 事件系统
- **原生材质** — `NSVisualEffectView` 提供系统级模糊半透明效果，与 macOS 26 HUD 风格一致
- **精细生命周期控制** — `orderFront/orderOut` 精确控制显隐，避开了 SwiftUI Window 的 `onAppear/onDisappear` 不确定性
- **Esc 键链** — 可通过 `cancelOperation:` 实现层级关闭（预览 popover → 搜索栏 → 面板）

## 代价
- SwiftUI 视图通过 `NSHostingView` 桥接到 NSPanel 内容视图，增加一层间接
- 需要手动管理 SwiftUI 和 AppKit 之间的布局约束和尺寸计算
- 无法使用 SwiftUI 的 `.windowStyle()` 等修饰符

## 备选方案
- **SwiftUI Window** — 无法实现 `.nonactivatingPanel` 行为（会抢 key），右键菜单受限
- **SwiftUI Menu** — 无法自定义布局，无限滚动、搜索栏、多选等交互不可行
