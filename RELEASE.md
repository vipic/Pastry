# Pastry 发布流程

本文档记录本项目当前的本地发布流程。项目目前没有开发者账号签名和公证，因此产物是自签名应用，不做 notarization。

## 前置条件

- macOS 26+
- Xcode Command Line Tools
- `gh` CLI：仅 `--publish` 发布 GitHub Release 时需要
- 固定代码签名证书：默认使用作者级证书 `Nekutai`，也可通过 `CODESIGN_IDENTITY` 指定自己的自签名或开发者账号证书名

创建证书（已有同名作者证书可直接复用，多个应用可以共用同一张代码签名证书）：

```text
Keychain Access -> 证书助理 -> 创建证书
名称: Nekutai
身份类型: 自签名根
证书类型: 代码签名
```

如果证书名不是 `Nekutai`，通过环境变量覆盖：

```bash
export CODESIGN_IDENTITY="Nekutai"
```

Pastry 需要辅助功能授权，必须使用稳定代码身份。没有匹配证书或签名失败时脚本会直接停止；显式设置 `CODESIGN_IDENTITY="-"` 也会被拒绝。不要使用 ad-hoc 签名，因为每次构建都可能破坏辅助功能授权，导致用户反复重新授权。

## 版本号规则

发布命令传裸版本号：

```bash
./release.sh 1.2.3
```

脚本内部会自动生成 Git tag `v1.2.3`。如果传入 `v1.2.3`，脚本也会先剥掉前缀 `v`，避免应用内更新检查出现 `vv1.2.3`。

## 本地构建 DMG

```bash
./release.sh 1.2.3
```

脚本会执行：

- `swift test`
- 注入 `AppVersion`
- release 编译
- 去除调试符号
- 组装 `.app`
- 固定作者级证书签名
- 打包 DMG
- DMG 烟测
- 输出 SHA256

产物在：

```text
dist/Pastry-1.2.3.dmg
```

## 发布到 GitHub Releases

```bash
./release.sh 1.2.3 --publish
```

发布模式要求：

- 当前分支是 `main`
- 工作区干净
- 当前 commit 没有不匹配的 tag
- `gh auth status` 可用

脚本会推送 tag `v1.2.3` 并创建 GitHub Release。

## 发布耗时与本地日志

`release.sh` 会为每次执行创建独立日志，记录 workflow、stage、command 的开始时间、耗时和退出码，并保留构建工具的完整输出：

```text
.local/logs/release/<run-id>.log
.local/logs/publish/<run-id>.log
```

`latest.log` 指向最近一次执行。快速查看耗时摘要或完整输出：

```bash
scripts/diagnostics.sh command release
scripts/diagnostics.sh command publish
scripts/diagnostics.sh command publish --full
```

一次本机基线中，本地 release 总计约 36 秒：测试约 5 秒、release 编译约 20 秒、DMG 约 11 秒，签名与组装不足 1 秒。历史 GitHub asset 时间戳曾显示约 132 秒的创建到更新间隔，这只能说明远端上传或处理可能是 publish 变慢的主要部分；新的命令日志会直接记录 `git push`、`gh release create/upload` 的真实耗时，后续无需再靠时间戳推断。

日志只保存在本机 `.local/logs/`，该目录已被 Git 忽略，不会自动上传。应用运行日志的隐私边界和联合排查方式见 [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md)。

## GitHub Actions 构建 Artifact

仓库里有两个 workflow：

- `Tests`：`main` 分支 push 和 pull request 自动触发，执行脚本语法检查、`swift test` 和 release build。
- `Release Artifact`：只支持手动触发，不会因为 push、tag 或 PR 自动运行。

手动构建 DMG artifact：

1. 打开 GitHub 仓库的 **Actions**
2. 选择 **Release Artifact**
3. 点击 **Run workflow**
4. 输入裸版本号，例如 `1.2.3`

该 workflow 会执行：

```bash
./release.sh "1.2.3" --force
```

然后校验 DMG、校验 `CFBundleShortVersionString`，并上传：

```text
Pastry-1.2.3.dmg
```

作为 workflow artifact。它只生成 artifact，不会创建 GitHub Release，也不会推送 tag。

## 没有开发者账号时的限制

当前发布产物没有 notarization。用户首次打开时可能遇到 Gatekeeper 提示，需要在系统设置中允许打开。

这不是脚本错误，而是 Apple 对非公证应用的限制。拿到开发者账号后，后续应补充：

- 开发者账号签名
- 公证上传
- stapler 固定票据
- CI 发布链路中的公证校验

## 自动更新失败日志

应用内自动更新会生成 helper 脚本并替换 `.app`。如果安装失败，日志写入：

```text
/tmp/pastry_update.log
```

如果是 Bundle ID、版本号、签名或安装校验失败，helper 还会写入面向用户的错误原因：

```text
/tmp/pastry_update_error.txt
```

旧 App 被重新打开后会读取该文件并弹出更新错误窗口。排查时优先查看 `pastry_update.log`，需要确认用户看到的错误文案时再查看 `pastry_update_error.txt`。安装脚本会先备份旧版本，再复制新版本；复制失败时会恢复旧 App。

## 发布前检查清单

```bash
git status --short
swift test
swift build -c release -Xswiftc -Osize
./release.sh 1.2.3
```

确认 DMG 可以挂载，拖入 `/Applications` 后应用可启动，再执行 `--publish`。
