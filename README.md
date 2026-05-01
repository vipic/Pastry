# ClipboardManager - macOS 剪贴板管理工具

纯 Swift 原生开发，零外部依赖。MenuBarExtra 后台常驻，**⌘⇧V** 一键唤出全屏覆盖层，浏览、搜索、粘贴历史剪贴板内容。

---

## 功能一览

| 功能 | 说明 |
|------|------|
| **后台常驻** | MenuBarExtra 模式，无 Dock 图标，轻量常驻 |
| **全局快捷键** | `⌘⇧V` — 任何时候一键唤出/隐藏 |
| **全屏覆盖层** | 35% 半透明黑色蒙层 + 底部卡片面板 |
| **自动监听** | 0.5s 轮询 NSPasteboard，实时记录 |
| **多格式支持** | 文本、RTF、HTML、图片（缩略图缓存）、文件路径 |
| **一键粘贴** | 点击卡片 → 自动写入剪贴板 + 模拟 ⌘V 到当前应用 |
| **智能排序** | 粘贴过的条目自动移到最前，不产生重复 |
| **全文搜索** | SQLite FTS5 全文索引，实时搜索 |
| **应用识别** | 每条记录来源应用图标 + 主题色头部（20+ 应用预置色） |
| **删除条目** | 悬停卡片头部显示 × 按钮，可单条删除 |
| **收藏功能** | 待完善 UI 支持 |
| **复制提示音** | 可选系统音效反馈 |
| **隐私保护** | 纯数字短串（验证码/密码）自动跳过 |
| **自动清理** | 7 天前历史自动清理，数据库上限 500+ 条 |
| **开机启动** | 可选设置 |
| **统计面板** | 菜单栏显示总条目数、今日新增、存储占用 |

---

## 效果预览

### 主界面

```
┌──────────────────────────────────────────────┐
│   ░░░░░░ 35% 半透明黑色蒙层 ░░░░░░░░░░░░░░░  │
│                                               │
│                  🔍 搜索历史...                 │
│                                               │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│   │ 🖼 🗑️ 📎│  │ 📄 🗑️ 📎│  │ 📁 🗑️ 📎│   │
│   │ [图片]   │  │ [文本]   │  │ [文件]   │   │
│   │          │  │          │  │          │   │
│   │ 2分钟前  │  │ 10分钟前 │  │ 1小时前  │   │
│   └──────────┘  └──────────┘  └──────────┘   │
│                                               │
└──────────────────────────────────────────────┘
```

每张卡片：
- **顶部彩色条** — 来源应用主题色
- **右上角** — 来源应用图标
- **左上角** — 内容类型图标（文本/图片/文件）
- **悬停**时左上角显示 **× 删除按钮**
- **点击卡片** → 粘贴到当前活跃应用

---

## 安装

### 从源码编译

```bash
git clone <your-repo-url>
cd ClipboardManager
open .
```

在 Xcode 中选择你的 Team 签名后 ⌘R 运行。

### 首次使用

1. 从菜单栏点击 🗂️ 图标 → **打开剪贴板**
2. 使用 `⌘⇧V` 可快速唤出/隐藏覆盖层
3. 如果粘贴功能失效：
   - 去 **系统设置 → 隐私与安全性 → 辅助功能**
   - 添加 ClipboardManager
   - 重启应用

> **注意：** 如果用 Xcode 开发运行（⌘R），每次编译后的二进制哈希会变化，需要重新授权。建议用编译产物路径直接打开：
> ```bash
> open ~/Library/Developer/Xcode/DerivedData/ClipboardManager-*/Build/Products/Debug/ClipboardManager.app
> ```

---

## 使用方法

### 快捷键

| 操作 | 快捷键 |
|------|--------|
| 唤出/隐藏覆盖层 | `⌘⇧V` |
| 关闭覆盖层 | `Esc` |
| 点击空白区域 | 关闭覆盖层 |

### 菜单栏

| 菜单项 | 功能 |
|--------|------|
| 打开剪贴板 | 唤出覆盖层面板 |
| 统计信息 | 总条目 / 今日新增 / 存储占用 |
| 清空非收藏历史 | 删除所有非收藏条目 |
| 设置… | 开机启动 / 提示音 / 历史上限 |
| 退出 | 退出应用 |

---

## 项目结构

```
Sources/ClipboardManager/
├── ClipboardManagerApp.swift     # @main 入口
│                                 #   - MenuBarExtra + 菜单项
│                                 #   - 设置窗口 (NSWindow)
│                                 #   - 辅助功能权限检测
│
├── Core/
│   ├── ClipboardItem.swift       # 数据模型
│   │                             #   - ClipType (text/rtf/html/image/fileURL)
│   │                             #   - dedupKey 去重
│   │                             #   - ClipboardStats 统计结构
│   │
│   └── ClipboardMonitor.swift    # 剪贴板轮询引擎
│                                 #   - 0.5s 轮询 changeCount
│                                 #   - 多格式优先级读取 (fileURL→image→html→rtf→text)
│                                 #   - 敏感内容过滤
│                                 #   - suspend/resume 防自触发
│                                 #   - ImageCacheManager (图片缩略图缓存)
│
├── Persistence/
│   ├── DatabaseManager.swift     # SQLite 数据库 (原生 C API)
│   │                             #   - WAL 模式 / FTS5 全文索引
│   │                             #   - CRUD + 收藏 / 统计
│   │                             #   - bumpTimestamp (移动条目到最前)
│   │                             #   - 7 天自动清理触发器
│   │
│   └── StoreManager.swift        # 状态管理层 (ObservableObject)
│                                 #   - 连接 Monitor → Database → SwiftUI
│                                 #   - 搜索/筛选逻辑
│                                 #   - 模拟 ⌘V 粘贴
│
├── UI/
│   ├── OverlayPanelManager.swift # 全屏覆盖层面板
│   │                             #   - NSPanel nonactivating + .screenSaver
│   │                             #   - 键盘事件拦截 (Esc 关闭)
│   │                             #   - 点击卡片粘贴流程
│   │                             #   - 暂停监听 + bump 时间戳
│   │
│   ├── OverlayView.swift         # 覆盖层主视图 (SwiftUI)
│   │                             #   - 半透明蒙层 + 搜索栏 + 卡片列表
│   │                             #   - 横竖自适应布局
│   │                             #   - 空白区域点击关闭
│   │
│   ├── ClipboardCardView.swift   # 单条卡片视图
│   │                             #   - 彩色头部 (应用主题色)
│   │                             #   - 应用图标 / 内容预览
│   │                             #   - 悬停显示删除按钮
│   │                             #   - TopRoundedRect 形状
│   │
│   └── ClipboardOverlayPanel.swift # NSPanel 子类
│
├── Utils/
│   ├── Constants.swift           # 应用常量 + SF Symbols + Color 扩展
│   ├── GlobalHotkeyManager.swift # Carbon 全局快捷键
│   │                             #   - RegisterEventHotKey
│   │                             #   - EventHotKeyID + InstallEventHandler
│   │                             #   - ⌘⇧V → toggle 覆盖层
│   └── AppIconProvider.swift     # 应用图标/主题色提取缓存
│                                 #   - 20+ 应用固定颜色映射
│                                 #   - NSWorkspace 图标提取
│                                 #   - 图标主色提取 + 哈希稳定色
│
├── Info.plist                    # LSUIElement = YES (无 Dock 图标)
└── Package.swift                 # Swift 5.9 / macOS 13+ / 零依赖
```

---

## 技术架构

### 数据流

```
系统剪贴板
    │
    ▼
ClipboardMonitor (0.5s 轮询 changeCount)
    │
    ├── changeCount 变化？→ 读取内容
    │       ├── 敏感检测 → 跳过
    │       └── 正常 → 创建 ClipboardItem
    │
    ▼
StoreManager.handleNewItem()
    │
    ├── DatabaseManager.insert() → SQLite + FTS5
    └── items.insert(at: 0) → SwiftUI 自动刷新
```

### 粘贴流程

```
用户点击卡片
    │
    ▼
OverlayPanelManager.hideAndPaste()
    │
    ├── 1. 关闭覆盖层
    ├── 2. ClipboardMonitor.suspend() — 暂停监听
    ├── 3. 激活目标应用 (app.activate)
    ├── 4. 写入剪贴板 (NSPasteboard)
    ├── 5. DatabaseManager.bumpTimestamp() — 移到最前
    ├── 6. ClipboardMonitor.resume() — 恢复监听，跳过此次变化
    ├── 7. StoreManager.refresh() — 刷新列表
    └── 8. CGEventPost(.cgSessionEventTap) 模拟 ⌘V
```

### 关键技术点

- **全局快捷键**: Carbon `RegisterEventHotKey`（非 HotKeyCenter），无需辅助功能权限
- **覆盖层窗口**: NSPanel + `.nonactivatingPanel` + `.screenSaver` level，不干扰全屏应用
- **模拟粘贴**: `CGEventPost(.cgSessionEventTap)`，无需辅助功能权限
- **去重**: `changeCount:types` 组合 key + 内容摘要，避免重复记录
- **FTS5 搜索**: porter + unicode61 分词器，支持前缀匹配
- **事件隔离**: `suspend/resume` 计数机制，防止自写入触发新记录

---

## 开发

### 编译

```bash
cd ~/Documents/ClipboardManager
swift build          # 检查语法
swift build -c release  # 发布编译
```

### 在 Xcode 中打开

```bash
open ~/Documents/ClipboardManager
```

### 项目依赖

**零外部依赖。** 只用了 Apple 原生框架：
- SwiftUI / Cocoa / AppKit
- SQLite3 (C API)
- CoreGraphics / Carbon
- OSLog / ServiceManagement

---

## License

MIT
