# Development

本文档记录 Pastry 的本地开发、构建和签名要求。发布流程见 [RELEASE.md](../RELEASE.md)，测试命令见 [TESTING.md](TESTING.md)。

## 环境要求

- macOS 26+
- Swift 5.9+
- Xcode Command Line Tools

项目不依赖第三方包管理下载；SQLCipher 静态库已 vendored 到仓库内。

## 快速部署开发版

```bash
git clone https://github.com/vipic/Pastry.git
cd Pastry
./deploy.sh
```

`deploy.sh` 会编译 debug 版本、组装并签名 `~/Applications/Pastry Dev.app`，然后启动应用。

## 代码签名

macOS 的辅助功能权限绑定到应用签名。Pastry 必须使用稳定代码签名：自签名代码签名证书或开发者账号证书都可以；不要使用 ad-hoc 签名。ad-hoc 每次重新编译都可能改变代码身份，导致辅助功能授权反复失效。

脚本默认使用证书名 `Nekutai`。如果你想用自己的证书名，通过环境变量覆盖：

```bash
export CODESIGN_IDENTITY="Your Certificate Name"
```

创建自签名证书：

```text
Keychain Access -> 证书助理 -> 创建证书
名称: Nekutai
身份类型: 自签名根
证书类型: 代码签名
```

证书缺失、签名失败或显式设置 `CODESIGN_IDENTITY="-"` 时，`deploy.sh`、`release.sh` 和 `bench.sh` 会直接停止，不会改用 ad-hoc。

## 本地构建

只确认 debug 编译：

```bash
swift build
```

只确认 release 编译：

```bash
swift build -c release -Xswiftc -Osize
```

这只会生成 SwiftPM 可执行文件，不会组装 `.app` 或 DMG。完整发布包请使用：

```bash
./release.sh 1.2.3
```

## 本机冒烟

```bash
./smoke.sh
```

脚本会部署开发版、填充剪贴板样本、唤出面板，并把截图和日志保存到 `dist/smoke/`。它不进 CI，适合发布前人工确认菜单栏、面板和卡片行为。

## mise 入口

如果使用 `mise`，可以通过统一任务入口执行常用命令：

```bash
mise run check
mise run deploy
mise run release-auto
```

完整说明见 [MISE.md](MISE.md)。

## 项目结构

```text
Sources/Pastry/
├── Core/           # ClipboardItem 模型、剪贴板监听
├── Persistence/    # SQLite / SQLCipher 数据库、StoreManager
├── UI/             # 面板、卡片、菜单、预览
└── Utils/          # 热键、图标、常量、更新检查
```

更完整的架构、历史坑点和 Agent 约定见 [AGENTS.md](../AGENTS.md)。
