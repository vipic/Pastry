#!/bin/bash
# Pastry 性能基准测试
# 用法: ./bench.sh              # 跑一次输出指标
#       ./bench.sh --baseline    # 保存为基线（覆盖上一次基线）
#       ./bench.sh --diff        # 对比当前与基线
#       ./bench.sh --report      # 从 perf.log 生成 p50/p95/p99 统计

set -euo pipefail
cd "$(dirname "$0")"
BASELINE_FILE=".bench_baseline"
APP_BIN="$HOME/Applications/Pastry.app/Contents/MacOS/Pastry"
BUILD_BIN=".build/release/Pastry"
PERF_LOG="$HOME/Library/Logs/Pastry/perf.log"

# macOS 毫秒时间戳
now_ms() { python3 -c 'import time; print(int(time.time()*1000))'; }

# ── 性能日志分析 ──
do_report() {
    if [[ ! -f "$PERF_LOG" ]]; then
        echo "❌ 无 perf.log 文件 ($PERF_LOG)"
        echo "   请先运行 Pastry 并使用面板和粘贴功能生成日志。"
        exit 1
    fi

    python3 << 'PYEOF'
import re, sys
from collections import defaultdict

log_path = "/Users/mason/Library/Logs/Pastry/perf.log"
with open(log_path) as f:
    lines = [line.strip() for line in f if line.strip()]

def stats(values, label):
    if not values:
        return
    s = sorted(values)
    n = len(s)
    p50 = s[int(n * 0.50)] if n > 0 else 0
    p95 = s[int(n * 0.95)] if n > 1 else s[0]
    p99 = s[int(n * 0.99)] if n > 1 else s[0]
    mean = sum(s) // n
    rng = f"{s[0]}–{s[-1]}"
    print(f"  {label}: n={n}  p50={p50}ms  p95={p95}ms  p99={p99}ms  avg={mean}ms  range={rng}")

# Parse each line by type
groups = defaultdict(lambda: defaultdict(list))
type_counts = defaultdict(int)

for line in lines:
    fields = {}
    parts = line.split(" | ")
    for p in parts[1:]:  # skip date
        if ": " in p:
            k, v = p.split(": ", 1)
            # extract numeric ms values
            if v.endswith("ms"):
                try:
                    fields[k] = int(v[:-2])
                except ValueError:
                    fields[k] = v
            else:
                try:
                    fields[k] = int(v)
                except ValueError:
                    fields[k] = v

    t = fields.get("type", "unknown")
    type_counts[t] += 1

    if t == "panel":
        for key in ("hotkeyDispatch", "panelInit", "overlayView", "hostingInit",
                     "hostingLayout", "orderFront", "total"):
            if key in fields:
                groups[t][key].append(fields[key])
    elif t == "paste":
        for key in ("clipboardWrite", "activateApp", "orderOut", "simulatePaste", "total"):
            if key in fields:
                groups[t][key].append(fields[key])
    elif t == "pasteMulti":
        for key in ("writeText", "activateApp", "orderOut", "simulatePaste", "total"):
            if key in fields:
                groups[t][key].append(fields[key])

print()
print("═══ 性能统计（perf.log）═══")
print()
print(f"总条目: {len(lines)}  (panel: {type_counts.get('panel',0)}, paste: {type_counts.get('paste',0)}, pasteMulti: {type_counts.get('pasteMulti',0)})")
print()

for t in ("panel", "paste", "pasteMulti"):
    if t not in groups:
        continue
    g = groups[t]
    label_map = {
        "panel": "面板启动",
        "paste": "卡片粘贴",
        "pasteMulti": "多选粘贴",
    }
    field_labels = {
        "hotkeyDispatch":  "  快捷键→主线程调度",
        "panelInit":       "  NSPanel 创建",
        "overlayView":     "  OverlayView 构建",
        "hostingInit":     "  NSHostingView 初始化",
        "hostingLayout":   "  NSHostingView 布局",
        "orderFront":      "  orderFront+makeKey",
        "clipboardWrite":  "  写剪贴板",
        "writeText":       "  拼接+写文本",
        "activateApp":     "  激活目标 App",
        "orderOut":        "  面板隐藏",
        "simulatePaste":   "  ⌘V 模拟",
        "total":           "  总耗时",
    }
    print(f"── {label_map.get(t, t)} ──")
    # always show total first
    if "total" in g:
        stats(g["total"], field_labels["total"])
    for key in g:
        if key == "total":
            continue
        stats(g[key], field_labels.get(key, f"  {key}"))
    print()

print("注：p50/p95/p99 基于运行中自然产生的数据，非受控基准测试。")
PYEOF
}

# ── 若为 --report 模式，直接跑报告并退出 ──
if [[ "${1:-}" == "--report" ]]; then
    do_report
    exit 0
fi

# ── 1. 编译时间 ──
echo "═══ 编译时间 ═══"
BUILD_START=$(now_ms)
swift build -c release 2>&1 | tail -1
BUILD_END=$(now_ms)
BUILD_MS=$((BUILD_END - BUILD_START))
echo "编译耗时: ${BUILD_MS}ms"

# ── 2. 二进制体积 ──
echo ""
echo "═══ 二进制体积 ═══"
BIN_SIZE=$(stat -f%z "$BUILD_BIN" 2>/dev/null || echo 0)
BIN_KB=$((BIN_SIZE / 1024))
echo "大小: ${BIN_KB} KB (${BIN_SIZE} bytes)"

# ── 3. 测试耗时（先于部署，避免签名替换中断测试）──
echo ""
echo "═══ 测试耗时 ═══"
TEST_START=$(now_ms)
TEST_OUTPUT=$(swift test 2>&1)
TEST_END=$(now_ms)
TEST_MS=$((TEST_END - TEST_START))
TEST_PASSED=$(echo "$TEST_OUTPUT" | grep -oE '[[:space:]]*Executed [0-9]+ tests' | tail -1 | sed 's/^[[:space:]]*//')
echo "${TEST_PASSED:-测试结果解析失败}"
echo "测试耗时: ${TEST_MS}ms"

# ── 4. 部署（--bench 需要从 app bundle 运行以获取 Info.plist 等资源）──
if [[ -f "$BUILD_BIN" ]]; then
    pkill -x Pastry 2>/dev/null || true
    sleep 0.3
    cp "$BUILD_BIN" "$APP_BIN" 2>/dev/null || true
    rm -rf "${APP_BIN%/Contents/MacOS/Pastry}/_CodeSignature" 2>/dev/null || true
    codesign --force --sign - "${APP_BIN%/Contents/MacOS/Pastry}" 2>/dev/null || true
fi

# ── 5. 启动耗时 ──
echo ""
echo "═══ 启动耗时 ═══"
if [[ -x "$APP_BIN" ]]; then
    LAUNCH_OUTPUT=$("$APP_BIN" --bench 2>/dev/null)
    LAUNCH_MS=$(echo "$LAUNCH_OUTPUT" | grep -o '[0-9]*' | head -1)
    echo "启动耗时: ${LAUNCH_MS:-?}ms"
else
    LAUNCH_MS=0
    echo "⚠  未找到 app bundle，跳过启动测试"
fi

# ── 汇总 ──
echo ""
echo "╔══════════════════════════════╗"
printf "║ 编译: %6dms               ║\n" $BUILD_MS
printf "║ 二进制: %5d KB             ║\n" $BIN_KB
printf "║ 启动: %6dms               ║\n" ${LAUNCH_MS:-0}
printf "║ 测试: %6dms               ║\n" $TEST_MS
echo "╚══════════════════════════════╝"

# ── 处理基线 ──
BASELINE_DATA="${BUILD_MS} ${BIN_KB} ${LAUNCH_MS:-0} ${TEST_MS}"
if [[ "${1:-}" == "--baseline" ]]; then
    echo "$BASELINE_DATA" > "$BASELINE_FILE"
    echo "✅ 基线已保存"
elif [[ "${1:-}" == "--diff" ]]; then
    if [[ -f "$BASELINE_FILE" ]]; then
        read -r B_BLD B_BIN B_LAUNCH B_TST < "$BASELINE_FILE"
        echo ""
        echo "═══ 与基线对比 ═══"
        printf "编译: %+dms\n" $((BUILD_MS - B_BLD))
        printf "二进制: %+d KB\n" $((BIN_KB - B_BIN))
        printf "启动: %+dms\n" $((LAUNCH_MS - B_LAUNCH))
        printf "测试: %+dms\n" $((TEST_MS - B_TST))
    else
        echo "❌ 无基线文件，先运行 ./bench.sh --baseline"
    fi
fi

# ── 提示可选 perf 报告 ──
if [[ -f "$PERF_LOG" ]]; then
    echo ""
    echo "💡 perf.log 存在，可运行 ./bench.sh --report 查看面板/粘贴统计"
fi
