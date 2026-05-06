# Pastry

macOS 剪贴板管理工具 — 唤起面板、选中、粘贴，一气呵成。

![macOS](https://img.shields.io/badge/macOS-26.0-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![License](https://img.shields.io/badge/License-MIT-green)

## 特性

- **零操作延迟** — 复制后面板瞬间出现，选完即走
- **全键盘操作** — 方向键导航、Enter 粘贴、Esc 关闭，无需碰鼠标
- **右键菜单** — 钉选 / 打开 / 选择应用打开 / 预览 / 分享 / 删除
- **多选操作** — Shift 区间选择、Cmd 散选，批量粘贴或拖拽
- **拖拽到应用** — 图片拖文件、文本拖字符串，直接拖入目标应用
- **链接预览** — 复制的链接自动抓取标题、描述、缩略图
- **搜索过滤** — 打字即时搜索，Tab 在搜索框和卡片间切换焦点
- **预览弹窗** — 空格风格预览，带文件信息和控制按钮
- **钉选保护** — 重要内容钉住，批量删除时自动保留

## 构建

```bash
git clone https://github.com/vipic/Pastry.git
cd Pastry
swift build -c release
cp .build/release/Pastry ~/Applications/Pastry.app/Contents/MacOS/Pastry
codesign --force --sign - ~/Applications/Pastry.app
open ~/Applications/Pastry.app
```

零外部依赖，仅需 macOS 26+。

> 首次启动需要在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权 Pastry。

## 快捷键

### 面板操作

| 操作 | 按键 |
|---|---|
| 唤起 / 关闭面板 | 设定的全局快捷键（默认无，需在设置中录制） |
| 关闭面板 | `Esc` |
| 打开设置 | 菜单栏图标 → 设置… |

### 卡片导航

| 操作 | 按键 |
|---|---|
| 上 / 下移动 | `↑` `↓` |
| 选中当前卡片 | 单击 或 `Enter`（粘贴） |
| Shift 区间选择 | `Shift` + `↑` `↓` |
| Cmd 散选 / 取消 | `Cmd` + 单击 |
| Cmd 全选 | `Cmd` + `A` |
| Cmd 数字粘贴 | `Cmd` + `1` ~ `9`（粘贴对应序号卡片） |

### 搜索

| 操作 | 按键 |
|---|---|
| 搜索 | `Cmd` + `F` 或直接打字 |
| 搜索框 ↔ 卡片切换 | `Tab` |
| 关闭搜索（保留结果） | `Tab`（在搜索框时） |
| 关闭搜索（清空结果） | `Esc` |

### 删除

| 操作 | 按键 |
|---|---|
| 删除选中 | `Delete` 或 `⌫`（弹出确认） |
| 确认删除 | `Enter` |
| 右键菜单删除 | 右键 → 删除 |

### 预览

| 操作 | 方式 |
|---|---|
| 预览文件/链接 | 右键 → 预览 |
| 关闭预览 | `Esc` 或点击外部 |
| 预览中分享 | 弹窗右上角分享按钮 |
| 预览中定位文件 | 弹窗右下角 Finder 按钮 |

### 拖拽

| 操作 | 方式 |
|---|---|
| 拖拽单条 | 按住卡片拖到目标应用 |
| 拖拽多条 | 先多选，再拖任意一张 |

## 项目结构

```
Sources/Pastry/
├── Core/           # ClipboardItem 模型、剪贴板监听
├── Persistence/    # SQLite 数据库、StoreManager
├── UI/             # 面板、卡片、菜单、预览
└── Utils/          # 热键、图标、常量
```

完整架构说明见 [AGENTS.md](AGENTS.md)。

## 许可

MIT © [vipic](https://github.com/vipic)
