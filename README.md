# Pastry

macOS 剪贴板管理工具。轻量、纯原生、纯 Swift，零 Xcode 依赖。

## 功能

- **自动记录** — 复制操作自动记录，支持文本 / RTF / HTML / 图片 / 文件 / 链接
- **图文混合** — 微信/QQ 同时复制图片和文字时自动提取附注文字，卡片显示图文，粘贴还原 RTFD 混排
- **可配置快捷键** — 自定义全局快捷键唤起面板，设置面板内直接录制替换
- **卡片式浏览** — 横向滚动卡片，图文/链接预览，应用图标 + 主题色来源标识
- **搜索与筛选** — 全文搜索 + 按类型/来源 App/时间段多维筛选
- **钉选** — 重要条目钉选保留，不受清空影响
- **来源追踪** — 基于用户 App 切换上下文识别来源，截图也能正确归属
- **一键粘贴** — 点击卡片自动切回原 App 并模拟 ⌘V
- **批量操作** — ⌘A 全选，Delete 批量删除（带确认）
- **右键菜单** — 单条钉选/删除
- **自定义音效** — Copy.aiff 替换系统提示音（可关闭）
- **菜单栏** — 左键打开面板，右键弹出菜单（含统计）

## 构建

```bash
./build.sh
```

产物 `~/Applications/Pastry.app`，原位替换二进制（保留 inode 以维持辅助功能授权）。

## 首次使用

1. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 Pastry
2. 默认快捷键 `⌘⇧V` 唤起面板，`Esc` 关闭
3. 点击卡片粘贴，右键钉选/删除

## 设置

菜单栏右键 → 设置…（⌘,），或面板右上角齿轮图标：
- **通用** — 开机启动（SMAppService）、复制提示音开关、辅助功能权限状态、清空全部记录
- **快捷键** — 录制/清除全局快捷键，修改立即生效

## 面板操作

| 操作 | 方式 |
|------|------|
| 唤起/关闭 | 全局快捷键 |
| 搜索 | 点击放大镜图标展开搜索框，或 ⌘F |
| 筛选 | 搜索框旁的筛选按钮 → 按类型/来源/时间过滤 |
| 钉选 | 右上角「已钉选」Tab，右键卡片钉选 |
| 全选 | ⌘A |
| 批量删除 | Delete → 确认 |
| 退出 | Esc（搜索框展开时先关搜索） |

## 清空策略

- **菜单「清空全部记录」** + **⌘A+Delete 批量删** → 一并清空系统剪贴板
- **单条右键删除** → 只删历史记录，保留系统剪贴板可继续 ⌘V

## 项目结构

```
Sources/Pastry/
  PastryApp.swift              入口：LSUIElement 后台模式，设置窗口
  SettingsView.swift            设置界面（NavigationSplitView）
  Core/
    ClipboardMonitor.swift      剪贴板轮询（changeCount + 来源上下文）
    ClipboardItem.swift         数据模型
  Persistence/
    StoreManager.swift          UI 数据层：搜索/筛选/统计
    DatabaseManager.swift       SQLite FTS5 全文索引
  UI/
    OverlayPanelManager.swift   NSPanel（popUpMenu 层级）+ 键盘事件 + 粘贴模拟
    OverlayView.swift           主视图：卡片列表 + 搜索框 + 筛选面板
    ClipboardCardView.swift     卡片视图：内容预览 + 应用图标 + 链接解析 + 右键菜单
    GlassBackground.swift       NSVisualEffectView(.hudWindow) 托盘背景
    HotkeyRecorder.swift        快捷键录制控件（NSEvent→Carbon 修饰键转换）
    MenuBarManager.swift        菜单栏：左键面板 / 右键菜单（含统计）
  Utils/
    AppIconProvider.swift       应用图标 + 主题色
    GlobalHotkeyManager.swift   Carbon RegisterEventHotKey
    Constants.swift             UserDefaults 键 + 默认值
Tests/PastryTests/              114 个测试用例
  DatabaseManagerTests.swift     CRUD / 去重 / Pin / 搜索 / textAnnotation
  StoreManagerTests.swift        筛选 / 搜索 / 状态管理 / dedupKey
  ClipboardMonitorTests.swift   微信 TencentAttributeStringType plist 解析
  ConstantsTests.swift           UserDefaults 键 / 颜色 / SF Symbol
  AppIconProviderTests.swift     图标获取（手动）
  HotkeyUtilsTests.swift         修饰键转换
build.sh                        构建 + 打包 + TCC 签名
```

## 技术要点

- **纯 Swift**，`swift build -c release`，无 Xcode
- **NSPasteboard 轮询** changeCount 检测变化（0.5s 间隔，`.common` run loop mode）
- **来源识别** — `didActivateApplicationNotification` 追踪用户上下文（10s 窗口），非前台进程
- **SQLite FTS5** 全文索引
- **NSPanel** `.popUpMenu` 层级 + `.nonactivatingPanel` — 不抢焦点，菜单栏可交互
- **CGEventPost** `.cgSessionEventTap` 模拟 ⌘V
- **Carbon RegisterEventHotKey** 注册全局快捷键
- **NSEvent→Carbon 修饰键转换** — 仅 `cmd/option/ctrl/shift` 四键参与（非 CGEventFlags 直转）
- **NSPanel 键盘事件** — `addLocalMonitorForEvents` 拦截 Esc / ⌘A / Delete
- **TCC 持久** — `build.sh` 原位替换二进制保留 inode，锚定 bundle ID 非 CDHash
- **NSVisualEffectView(.hudWindow)** — 托盘背景，无液态玻璃兼容问题
- **TencentAttributeStringType** — 微信/QQ 自定义剪贴板格式解析，提取图文混合内容中的文字
