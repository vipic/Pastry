#!/bin/bash
# Pastry 性能基准测试
# 用法: ./bench.sh           # 跑一次输出指标
#       ./bench.sh --baseline # 保存为基线（覆盖上一次基线）
#       ./bench.sh --diff     # 对比当前与基线

set -euo pipefail
cd "$(dirname "$0")"
BASELINE_FILE=".bench_baseline"
APP_BIN="$HOME/Applications/Pastry.app/Contents/MacOS/Pastry"
BUILD_BIN=".build/release/Pastry"

# macOS 毫秒时间戳
now_ms() { perl -MTime::HiRes -e 'printf("%d", time*1000)'; }

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

# ── 部署（--bench 需要从 app bundle 运行以获取 Info.plist 等资源）──
if [[ -f "$BUILD_BIN" ]]; then
    cp "$BUILD_BIN" "$APP_BIN" 2>/dev/null || true
    # 清除旧签名 + ad-hoc 重签（二进制替换后签名会失效）
    rm -rf "${APP_BIN%/Contents/MacOS/Pastry}/_CodeSignature" 2>/dev/null || true
    codesign --force --sign - "${APP_BIN%/Contents/MacOS/Pastry}" 2>/dev/null || true
fi

# ── 3. 启动耗时 ──
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

# ── 4. 测试耗时 ──
echo ""
echo "═══ 测试耗时 ═══"
TEST_START=$(now_ms)
TEST_OUTPUT=$(swift test 2>&1)
TEST_END=$(now_ms)
TEST_MS=$((TEST_END - TEST_START))
TEST_PASSED=$(echo "$TEST_OUTPUT" | grep -o "Executed [0-9]* tests, with 0 failures" | tail -1)
echo "${TEST_PASSED:-测试结果解析失败}"
echo "测试耗时: ${TEST_MS}ms"

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
