# Testing Commands

Pastry 的测试命令分成三类：日常开发、UI/人工验证、发布验证。最常用的是第一组。

## 日常开发

改完代码后优先跑这一组：

```bash
swift test --enable-code-coverage
scripts/check_coverage.sh
swift build -c release -Xswiftc -Osize
```

说明：

- `swift test --enable-code-coverage`：运行全部单元测试并生成 coverage 数据。
- `scripts/check_coverage.sh`：检查线覆盖率门槛，默认 20%。必须紧跟 coverage 测试运行，之后如果又跑了普通 build/test，coverage 数据可能会过期。
- `swift build -c release -Xswiftc -Osize`：确认 release 编译可过。

只想快速跑单测时：

```bash
swift test
```

按测试类过滤：

```bash
swift test --filter StoreManagerTests
swift test --filter ClipboardCardSnapshotTests
swift test --filter UpdateCheckerTests
```

## 脚本语法检查

CI 会检查这些脚本是否有 shell 语法错误：

```bash
bash -n deploy.sh
bash -n release.sh
bash -n smoke.sh
bash -n populate_clipboard.sh
bash -n bench.sh
bash -n scripts/check_coverage.sh
```

## Coverage

生成并检查 coverage：

```bash
swift test --enable-code-coverage
scripts/check_coverage.sh
```

指定临时门槛：

```bash
scripts/check_coverage.sh 20
scripts/check_coverage.sh 25
```

当前 CI 门槛是 20%。这是防止明显倒退的保守门槛，不代表目标覆盖率上限。

## Snapshot Tests

普通 `swift test` 会跳过 snapshot。验证卡片 PNG 基线：

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache \
  PASTRY_SNAPSHOT_TESTS=1 \
  swift test --filter ClipboardCardSnapshotTests
```

更新 snapshot PNG 基线：

```bash
env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache \
  PASTRY_RECORD_SNAPSHOTS=1 \
  swift test --filter ClipboardCardSnapshotTests
```

基线文件在：

```text
Tests/PastryTests/__Snapshots__/*.png
```

如果验证失败，测试会写出：

```text
Tests/PastryTests/__Snapshots__/__Failures__/*.actual.png
Tests/PastryTests/__Snapshots__/__Failures__/*.expected.png
```

这些失败图片用于本地对比，不应提交。

## Network-Dependent Tests

更新下载相关的真实网络测试默认跳过。需要显式开启：

```bash
env PASTRY_NETWORK_TESTS=1 swift test --filter UpdateCheckerTests
```

这类测试依赖网络和远端响应，不适合作为每次本地必跑项。

## UI / Smoke

本机冒烟检查会部署开发版、填充剪贴板样本、尝试唤出面板并保存截图：

```bash
./smoke.sh
```

常用参数：

```bash
./smoke.sh --skip-deploy
./smoke.sh --skip-populate
./smoke.sh --skip-hotkey
```

产物位置：

```text
dist/smoke/<timestamp>/
```

`smoke.sh` 会自动检查 Pastry 进程、截图文件、截图尺寸，以及唤起前后画面是否发生变化。关键检查失败时脚本会以非 0 退出；通过后仍保留人工验证清单，用来确认卡片内容、右键菜单和菜单栏行为。

只填充剪贴板样本：

```bash
./populate_clipboard.sh
```

注意：`populate_clipboard.sh` 会写系统剪贴板；Pastry 运行中会捕获这些样本。

## Performance Checks

跑一次本机性能基准：

```bash
./bench.sh
```

保存或对比基线：

```bash
./bench.sh --baseline
./bench.sh --diff
```

从性能日志生成 p50/p95/p99：

```bash
./bench.sh --report
```

`--report` 依赖 `~/Library/Logs/Pastry/perf.log`。性能日志默认关闭，可在设置页 Security -> Diagnostics 打开“Record Performance Logs”，或在手动启动二进制时使用：

```bash
PASTRY_PERF_LOG=1 .build/release/Pastry
```

## Deploy And Release

开发版部署到 `~/Applications/Pastry Dev.app`：

```bash
./deploy.sh
```

生产 DMG：

```bash
./release.sh 1.2.3
```

跳过工作区/tag/分支保护检查的本地强制构建：

```bash
./release.sh 1.2.3 --force
```

发布到 GitHub Release：

```bash
./release.sh 1.2.3 --publish
```

`release.sh` 会执行测试、release 构建、签名、DMG 打包和烟测。`--publish` 还会推 tag 并创建 GitHub Release。

## CI Commands

`.github/workflows/tests.yml` 当前执行：

```bash
bash -n deploy.sh
bash -n release.sh
bash -n smoke.sh
bash -n populate_clipboard.sh
bash -n bench.sh
bash -n scripts/check_coverage.sh
swift test --enable-code-coverage
scripts/check_coverage.sh 20
swift build -c release -Xswiftc -Osize
```

`.github/workflows/release-artifact.yml` 手动触发，核心命令：

```bash
./release.sh <version> --force
```

然后验证 DMG、版本号和签名，并上传 artifact。

## Recommended Checklist

日常小改：

```bash
swift test --enable-code-coverage
scripts/check_coverage.sh
```

涉及 UI 卡片：

```bash
swift test --enable-code-coverage
scripts/check_coverage.sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache PASTRY_SNAPSHOT_TESTS=1 swift test --filter ClipboardCardSnapshotTests
```

发布前：

```bash
bash -n deploy.sh
bash -n release.sh
bash -n smoke.sh
bash -n populate_clipboard.sh
bash -n bench.sh
bash -n scripts/check_coverage.sh
swift test --enable-code-coverage
scripts/check_coverage.sh
env CLANG_MODULE_CACHE_PATH=/private/tmp/clang-module-cache PASTRY_SNAPSHOT_TESTS=1 swift test --filter ClipboardCardSnapshotTests
swift build -c release -Xswiftc -Osize
./smoke.sh
```
