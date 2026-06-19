# Mise 命令速查

Pastry 仍然以现有 shell 脚本作为真实执行入口。`mise` 只做一层统一命令面板：把 `deploy.sh`、`release.sh`、`smoke.sh`、Swift 测试和版本计算收束到同一个 `mise run ...` 入口。

## 准备

安装 `mise` 后，在仓库根目录执行：

```bash
brew install mise
mise trust
mise tasks
```

`mise tasks` 会列出当前项目支持的全部任务。

## 日常开发

```bash
mise run build
mise run test
mise run test:coverage
mise run coverage
mise run check
```

- `build`：debug 编译。
- `test`：普通 Swift 单测。
- `test:coverage`：运行单测并生成 coverage 数据。
- `coverage`：检查最近一次 coverage 结果。临时调整门槛：`mise run coverage -- 25`。
- `check`：脚本语法检查、coverage 单测、coverage 检查、release 编译。

## CI 等价命令

```bash
mise run ci
```

这个任务对应 `.github/workflows/tests.yml` 的本地版本：

- shell 脚本语法检查
- `swift test --enable-code-coverage`
- `scripts/check_coverage.sh 20`
- `swift build -c release -Xswiftc -Osize`

## 应用工作流

```bash
mise run deploy
mise run smoke
mise run smoke -- --skip-deploy
mise run populate
```

- `deploy`：编译、签名并启动 `~/Applications/Pastry Dev.app`。
- `smoke`：运行本机 UI 冒烟检查。`smoke.sh` 参数放在 `--` 后面。
- `populate`：写入剪贴板样本，方便手动测试。

## Snapshot 和网络测试

```bash
mise run snapshot:test
mise run snapshot:record
mise run test:network
```

- `snapshot:test`：验证卡片 snapshot PNG 基线。
- `snapshot:record`：更新 snapshot PNG 基线。
- `test:network`：开启更新检查相关的真实网络测试。

## 性能

```bash
mise run bench
mise run bench -- --baseline
mise run bench -- --diff
mise run bench -- --report
```

`bench.sh` 的参数同样放在 `--` 后面。

## 版本号

```bash
mise run version:current
mise run version:next
```

- `version:current`：读取最近的 git tag。
- `version:next`：扫描最近 tag 到 `HEAD` 的 commit message，并按最高影响级别计算下一个 SemVer。

计算规则：

- `BREAKING CHANGE` 或 `type!`：major，例如 `1.4.16 -> 2.0.0`
- `feat`：minor，例如 `1.4.16 -> 1.5.0`
- `fix` 或 `perf`：patch，例如 `1.4.16 -> 1.4.17`
- 其他非空发布内容：默认 patch

如果多个 commit 同时包含 `feat` 和 `fix`，取更高影响级别，也就是 minor；只要有 breaking，就取 major。

## 发布

```bash
mise run release -- 1.4.17
mise run release -- 1.4.17 --force
mise run release-auto
mise run release-auto -- --force
mise run publish -- 1.4.17
mise run publish
```

- `release`：显式传版本号和参数给 `release.sh`。
- `release-auto`：先计算下一个版本号，再执行 `release.sh`。
- `publish`：执行 `release.sh <version> --publish`。不传版本号时，会先自动计算下一个版本。

凡是要传给底层脚本的参数，都放在 `--` 后面。
