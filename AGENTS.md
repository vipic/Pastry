# Pastry — Agent Onboarding

> macOS 26+ 剪贴板管理器。Swift + SwiftUI，SQLCipher 静态库 vendored 到仓库内，无需包管理器拉第三方依赖。全屏半透明 overlay 面板 + 应用主题色卡片。

## Build & Deploy

### 快速开发部署

```bash
./deploy.sh   # debug 编译 → 签名 → 启动，部署到 ~/Applications/Pastry Dev.app
```

### 生产发布

```bash
./release.sh [version]   # 测试 → release 编译 → 签名 → DMG → 烟测，产物在 dist/
./release.sh [version] --publish   # 额外推 tag 并创建 GitHub Release
```

### 一次性设置：代码签名证书

为了让 TCC 权限（辅助功能等）在更新时不丢失，需要固定签名证书。当前脚本默认使用作者级共享证书 `Nekutai`，也可以通过 `CODESIGN_IDENTITY` 指定任意稳定的代码签名证书：自签名代码签名证书或开发者账号证书都可以。同一个作者的多个应用可以共用同一张证书。

| 脚本 | 证书名称 | Bundle ID |
|---|---|---|
| `deploy.sh` | `${CODESIGN_IDENTITY:-Nekutai}` | `com.nekutai.pastry.dev` |
| `release.sh` | `${CODESIGN_IDENTITY:-Nekutai}` | `com.nekutai.pastry` |

**创建方法（只需一次，30 秒）：**

1. 打开 **Keychain Access**（钥匙串访问）
2. 菜单 **钥匙串访问 → 证书助理 → 创建证书**
3. 名称填 `Nekutai`（或你自己的作者证书名）
4. 身份类型：**自签名根**
5. 证书类型：**代码签名**
6. 勾选 **覆盖默认**（覆盖默认值）
7. 点击「继续」→「创建」

Pastry 需要辅助功能授权，不能使用 ad-hoc 签名。证书缺失、签名失败或显式设置 `CODESIGN_IDENTITY="-"` 时，脚本会直接停止；请先创建自签名代码签名证书，或使用开发者账号证书。

### 手动命令（备用）

```bash
# 构建
swift build -c release

# 部署（必须 kill 旧进程，否则运行中的二进制不更新）
cp .build/release/Pastry ~/Applications/Pastry.app/Contents/MacOS/Pastry

# 重签
rm -rf ~/Applications/Pastry.app/Contents/_CodeSignature
codesign --force --sign "${CODESIGN_IDENTITY:-Nekutai}" ~/Applications/Pastry.app

# 重启
pkill -f Pastry; sleep 0.5; open ~/Applications/Pastry.app
```

## Architecture

```
Sources/Pastry/
├── PastryApp.swift                # @main + AppDelegate (LSUIElement)
├── SettingsView.swift             # 设置窗口（General / Shortcut / Security）
├── Core/
│   ├── ClipboardItem.swift        # Codable 数据模型 (SourceFormat + ContentTags)
│   ├── ClipboardMonitor.swift     # NSPasteboard 轮询引擎
│   ├── ClipboardMonitorReaders.swift # 文本/RTF/HTML/文件/图片读取器
│   └── ImageCacheManager.swift    # 图片缓存与原图映射
├── Persistence/
│   ├── DatabaseManager.swift      # SQLite3 C API + FTS5 全文搜索 + SQLCipher 全库加密
│   ├── DatabaseKeyManager.swift   # 数据库密钥文件 + 旧 Keychain 迁移
│   ├── DatabaseMigrator.swift     # 明文数据库 → SQLCipher 迁移
│   └── StoreManager.swift         # @MainActor ObservableObject 桥接
├── CSQLCipher/                    # SQLCipher 静态库（vendored，无需外部下载）
│   ├── libsqlcipher.a             # 预编译静态库（CommonCrypto 后端）
│   ├── include/shim.h             # 定义 SQLITE_HAS_CODEC + SQLCIPHER_CRYPTO_CC
│   ├── include/module.modulemap   # SPM module 定义
│   └── include/sqlite3.h          # SQLCipher 头文件
├── UI/
│   ├── OverlayPanelManager.swift  # NSPanel 全屏 overlay 管理
│   ├── OverlayView.swift          # SwiftUI 内容层（透明底 + 卡片托盘）
│   ├── ClipboardCardView.swift    # 卡片视图主体
│   ├── ClipboardCardActions.swift # 右键菜单、打开、预览、分享
│   ├── MultiSelectionDragSourceView.swift # 多选拖拽源（单 dragging item）
│   ├── LinkPreviewLoader.swift    # 链接预览抓取 + 图片选取
│   ├── RemoteThumbnail.swift      # 远程缩略图渲染
│   ├── FilePreviewContent.swift   # 文件/多文件卡片内容
│   ├── SelectionState.swift       # 多选状态机
│   ├── UpdateView.swift           # 更新检查窗口
│   ├── GlassBackground.swift      # NSVisualEffectView(.hudWindow) 托盘背景
│   ├── HotkeyRecorder.swift       # 快捷键录制器
│   └── MenuBarManager.swift       # NSStatusBar 菜单栏入口
└── Utils/
    ├── AppDirectories.swift       # 应用数据目录
    ├── AppIconProvider.swift      # 提取应用图标 + 主题色
    ├── AppVersionInfo.swift       # About / Settings 版本展示
    ├── Constants.swift            # SF Symbols、UserDefaults key、颜色
    ├── DragPayloadBuilder.swift   # 单选/多选拖拽载荷
    ├── GlobalHotkeyManager.swift  # Carbon RegisterEventHotKey 全局快捷键
    ├── HistoryRetentionPolicy.swift # 历史容量/保留周期策略
    ├── L10n.swift                 # 本地化读取
    ├── NetworkAccessPolicy.swift  # 远程预览 URL 安全过滤
    ├── PasteboardWriter.swift     # 写回剪贴板
    └── RemoteImageLoader.swift    # 远程图片下载 + 内存缓存

Tests/PastryTests/
├── ClipboardMonitorTests.swift    # 剪贴板读取/过滤
├── DatabaseManagerTests.swift     # SQLite CRUD + FTS + 迁移
├── StoreManagerTests.swift        # 存储层桥接
├── LinkPreviewLoaderTests.swift   # 链接预览抓取 + 图片选取逻辑
├── FilePreviewTests.swift         # 文件预览 + 拖拽载荷核心逻辑
├── PasteboardWriterTests.swift    # 写回剪贴板
├── SelectionStateTests.swift      # 多选状态机
├── UpdateCheckerTests.swift       # 更新检查/版本比较
└── 其他：目录、版本、图标、热键、本地化、网络策略、签名配置等
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

### 8. 授权懒加载（仅粘贴操作）

`CGEvent.tapCreate` **在 `ClipboardMonitor.start()` 时创建**（用于来源检测和 ⌘C/X 快速轮询），不会弹授权对话框——无权限时静默返回 nil。

`simulatePaste()` 中的 `CGEventSource(stateID: .privateState)` + `postToPid` 在首次粘贴时触发辅助功能授权检查。但来源检测的 event tap 独立于此——它使用 `.cgSessionEventTap`，不涉及 `postToPid`，权限要求更宽松。

### 9. git restore . 会丢弃未提交改动

`git restore .` 会丢弃所有未跟踪改动，包括之前特意保留的修复。需要先确认是否有需要保留的部分。

## SQLCipher 全库加密

### 架构

`clips.db` 使用 SQLCipher 全库加密，保护剪贴板历史不被直接读取。当前版本优先使用数据库旁的 `.key` 文件保存加密后的密钥；macOS Keychain（service: `com.nekutai.pastry.dbkey`）仅作为旧版本迁移来源，避免每次重新签名后反复弹出钥匙串授权。

- **密钥生成**：首次启动时 `SecRandomCopyBytes` 生成 256-bit 随机密钥，使用设备派生 KEK 加密后写入 `.key` 文件
- **旧密钥迁移**：如果 `.key` 不存在但 Keychain 里有旧密钥，会读取一次并迁移到 `.key`
- **加密激活**：`sqlite3_key()` 在打开数据库后立即调用
- **透明性**：FTS5 全文搜索正常工作，查询逻辑无变化
- **测试跳过**：`init(dbPath:)` 构造函数通过 `openDatabase(useEncryption: false)` 跳过加密

### 迁移流程

升级安装时，如果检测到旧明文数据库（`sqlite3_key` 后 SELECT 失败），自动执行：

1. 以只读方式打开明文数据库
2. 导出 schema + 全部数据为 SQL dump
3. 创建新加密数据库
4. 执行 schema + 数据导入
5. 删除明文数据库，重新打开加密数据库

迁移日志输出 `明文数据库迁移完成 → 加密`。

### 重新编译 libsqlcipher.a

当需要更新 SQLCipher 版本或启用新扩展时，重新编译静态库：

```bash
# 下载 SQLCipher 源码
curl -sL "https://github.com/sqlcipher/sqlcipher/archive/refs/tags/v4.6.1.tar.gz" -o sqlcipher.tar.gz
tar xzf sqlcipher.tar.gz && cd sqlcipher-4.6.1

# 配置（CommonCrypto 后端 + FTS5）
./configure --with-crypto-lib=commoncrypto \
  CFLAGS="-DSQLITE_HAS_CODEC -DSQLITE_ENABLE_FTS5 -DSQLITE_ENABLE_FTS5_PARENTHESIS -DSQLITE_TEMP_STORE=2 -DSQLCIPHER_CRYPTO_CC -O2"

# 编译对象文件
make -j8 2>&1  # 链接 CLI 工具会失败（缺少 framework 链接），但 sqlite3.o 已生成

# 打包静态库
ar rcs libsqlcipher.a sqlite3.o

# 复制到项目
cp libsqlcipher.a Sources/CSQLCipher/libsqlcipher.a
cp sqlite3.h sqlite3ext.h sqlite_cfg.h Sources/CSQLCipher/include/
```

编译标志说明：
- `SQLITE_HAS_CODEC`：启用加密 API（sqlite3_key）
- `SQLITE_ENABLE_FTS5`：启用 FTS5 全文搜索
- `SQLITE_ENABLE_FTS5_PARENTHESIS`：FTS5 支持括号分组查询
- `SQLCIPHER_CRYPTO_CC`：使用 Apple CommonCrypto（无外部依赖）
- `SQLITE_TEMP_STORE=2`：临时表存内存

## Testing Strategy

### 独立 Pasteboard（关键）

测试**绝不**使用 `NSPasteboard.general`。每个测试类使用独立 pasteboard：

```swift
let pasteboard = NSPasteboard.withUniqueName()  // "test.hermes.pastry.<uuid>"
```

原因：`NSPasteboard.general` 的写入会触发后台运行的 Pastry 的 `changeCount` 监听，导致复制提示音响起，干扰测试环境。

### 运行测试

```bash
swift test --enable-code-coverage
scripts/check_coverage.sh
```

完整命令速查（snapshot、coverage、smoke、release 前检查）见 `docs/TESTING.md`。

## Key Design Patterns

### App 来源检测（高频 AX 缓存 + CGEvent 四层兜底）

记录剪贴板来源时，四层策略（按优先级）：

1. **高频 AX 焦点缓存**（0.1s 刷新，0.15s 窗口）：0.1s 间隔持续轮询 `kAXFocusedApplicationAttribute` 并缓存。浮动面板（1Password Quick Open）关闭后才触发 poll——此缓存保存关闭前的焦点
2. **CGEvent 按键目标进程**（0.5s 窗口）：Event tap 在按键瞬间捕获 `eventTargetUnixProcessID`
3. **实时 Accessibility 焦点**：poll 触发时浮动面板尚未关闭的兜底
4. **前台 App**（`NSWorkspace.shared.frontmostApplication`）：终级回退

核心创新是 Layer 1 的高频缓存——将 Accessibility 查询与剪贴板 poll 解耦，0.1s 间隔独立运行，在浮动面板存活期间捕获焦点。

### 剪贴板清除策略

删除路径的不同行为：
- **菜单栏「清空历史」** → 清空非收藏记录，收藏保留，并清空系统剪贴板
- **设置页「清空全部记录」** → 清空全部记录，并清空系统剪贴板
- **面板内批量删除** → 删除选中记录，并清空系统剪贴板
- **单条右键删除** → 只删历史记录，不动系统剪贴板（用户可继续 ⌘V）

### 多选拖拽策略

多选拖拽使用 `MultiSelectionDragSourceView` 的单个 `NSDraggingItem`，避免 macOS 对多个 dragging item 自动叠加系统数量角标。自定义拖拽图固定显示两张重叠卡片和 Pastry 自绘数量角标。

`DragPayloadBuilder.payloadForSelection` 同时计算三类载荷：
- `text`：文本、RTF、HTML、链接和文件路径拼接为多行文本
- `webURLs`：仅当所选条目全部是链接时记录 URL 列表；拖拽 pasteboard 只暴露首个 URL flavor，保证编辑器优先接收多行文本
- `fileURLs`：多选中存在本地文件或图片时，记录存在于磁盘的文件 URL；单个 dragging item 只能稳定暴露首个 file URL

当前取舍：多选链接拖到桌面不再生成多个 `.webloc`，而是和多选文本一样生成一个包含多行链接的文本剪贴内容；拖到编辑器则插入多行链接文本。

### 链接预览图片选取

优先级：`og:image` → `twitter:image` → 语义排序（黑名单过滤 avatar/logo/icon 等噪音关键词，尺寸过滤 <100px，语义加分 hero/featured 等）→ 保底最大图。支持 `data-src` 懒加载降级。

### 链接预览骨架图

卡片加载中使用 SwiftUI `.redacted(reason: .placeholder)` 实现骨架屏，利用已知缩略图尺寸避免布局抖动。不用 ProgressView 转圈。

### 提示音时机

- **复制提示音**：`changeCount` 变化瞬间响（不等 debounce/去重）
- **粘贴提示音**：`simulatePaste()` 方法第一行响

### 自动关闭面板

面板失焦通过 `NSWindow.didResignKeyNotification` 自动收起。拖拽开始时调用 `beginDragThrough()`，先 `orderOut` 面板并临时允许鼠标事件穿透，避免覆盖层截断目标应用的拖拽接收。

## GitHub Actions

- `.github/workflows/tests.yml`：`main` push 和 pull request 自动触发，执行脚本语法检查、`swift test --enable-code-coverage`、`scripts/check_coverage.sh 20`、`swift build -c release -Xswiftc -Osize`
- `.github/workflows/release-artifact.yml`：仅 `workflow_dispatch` 手动触发，输入裸版本号，执行 `./release.sh "${{ inputs.version }}" --force` 并上传 DMG artifact；不会自动创建 tag 或 GitHub Release

## macOS 26 Specifics

- **LaunchPad 已更名 Apps**：路径 `/System/Applications/Apps.app`
- **Liquid Glass API**：`NSGlassEffectView` 当前 beta 阶段在透明 NSPanel 中渲染异常，降级用 `NSVisualEffectView(.hudWindow)`
- **辅助功能授权**：macOS 26 强制要求跨进程键盘事件授权，只有 `.privateState` + `postToPid` 是最小权限方案
