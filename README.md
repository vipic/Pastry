# Pastry

macOS 剪贴板管理工具。轻量、纯原生、零依赖。

## 功能

- **自动记录**：复制操作自动记录，支持文本 / 图片 / 文件 / 链接
- **全局快捷键**：⌘⇧V 唤起全屏覆盖层，卡片式浏览历史
- **来源追踪**：记录每个条目的来源 App，截图也能正确识别
- **图文预览**：图片/链接自动预览，链接可选抓取网页标题
- **批量操作**：⌘A 全选，Delete 批量删除（带确认）
- **一键粘贴**：点击卡片自动粘贴回原 App
- **自定义音效**：Copy.aiff 替换系统提示音
- **右键菜单**：单条删除

## 构建

```bash
./build.sh
```

构建产物：`~/Applications/Pastry.app`，自动替换运行中的实例。

## 首次使用

1. 系统设置 → 隐私与安全性 → 辅助功能 → 勾选 Pastry
2. ⌘⇧V 唤起面板，再按关闭
3. 点击卡片粘贴，右键删除

## 设置

菜单栏图标 → 设置…：
- 开机启动（SMAppService 注册）
- 复制提示音开关
- 最大历史条数（100–2000）
- 清空历史 / 清空全部

## 项目结构

```
Sources/ClipboardManager/
  Core/           ClipboardMonitor, ClipboardItem
  Persistence/    StoreManager, DatabaseManager (SQLite FTS5)
  UI/             OverlayView, ClipboardCardView, OverlayPanelManager
  Utils/          AppIconProvider, GlobalHotkeyManager, Constants
build.sh          构建 + .app 打包 + 签名（preserves TCC）
```

## 技术要点

- **纯 Swift**，无 Xcode，`swift build -c release`
- **NSPasteboard 轮询** changeCount 检测变化
- **SQLite FTS5** 全文索引
- **NSPanel** 全屏非激活覆盖层（screenSaver level，不抢焦点）
- **CGEventPost** `.cgSessionEventTap` 模拟 ⌘V（无需辅助功能权限）
- **Carbon RegisterEventHotKey** 注册全局 ⌘⇧V
- **TCC 持久**：自定义 codesign requirement 锚定 bundle ID 而非 CDHash
