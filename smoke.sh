#!/bin/bash
# Pastry 本机冒烟检查
# 用法:
#   ./smoke.sh                 # 部署开发版 → 填充样本 → 唤出面板 → 截图
#   ./smoke.sh --skip-deploy   # 使用当前已运行/已安装的应用
#   ./smoke.sh --skip-populate # 不改写剪贴板样本

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_DIR="$PROJECT_DIR/dist/smoke/$TIMESTAMP"
OVERLAY_SHOT="$ARTIFACT_DIR/overlay.png"
DESKTOP_SHOT="$ARTIFACT_DIR/desktop-before-overlay.png"
LOG_FILE="$ARTIFACT_DIR/smoke.log"

SKIP_DEPLOY=0
SKIP_POPULATE=0
SKIP_HOTKEY=0

usage() {
    sed -n '2,7p' "$0" | sed 's/^# //'
}

for arg in "$@"; do
    case "$arg" in
        --skip-deploy) SKIP_DEPLOY=1 ;;
        --skip-populate) SKIP_POPULATE=1 ;;
        --skip-hotkey) SKIP_HOTKEY=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数: $arg"; usage; exit 1 ;;
    esac
done

mkdir -p "$ARTIFACT_DIR"

log() {
    printf '%s\n' "$*" | tee -a "$LOG_FILE"
}

run_step() {
    local title="$1"
    shift
    log ""
    log "── $title ──"
    "$@" 2>&1 | tee -a "$LOG_FILE"
}

wait_for_pastry() {
    for _ in $(seq 1 30); do
        if pgrep -x Pastry >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

trigger_overlay() {
    osascript -e 'tell application "System Events" to keystroke "v" using {command down, shift down}'
}

log "══════════════════════════════════════"
log "  Pastry Smoke"
log "  artifacts: $ARTIFACT_DIR"
log "══════════════════════════════════════"

cd "$PROJECT_DIR"

if [[ "$SKIP_DEPLOY" -eq 0 ]]; then
    run_step "部署开发版" ./deploy.sh
else
    log ""
    log "── 部署开发版 ──"
    log "跳过（--skip-deploy）"
fi

if wait_for_pastry; then
    log "✓ Pastry 进程已运行"
else
    log "✗ 未检测到 Pastry 进程"
    log "  可手动启动后重试: ./smoke.sh --skip-deploy"
    exit 1
fi

if [[ "$SKIP_POPULATE" -eq 0 ]]; then
    run_step "填充剪贴板样本" ./populate_clipboard.sh
else
    log ""
    log "── 填充剪贴板样本 ──"
    log "跳过（--skip-populate）"
fi

if command -v screencapture >/dev/null 2>&1; then
    screencapture -x "$DESKTOP_SHOT" 2>/dev/null || true
fi

if [[ "$SKIP_HOTKEY" -eq 0 ]]; then
    log ""
    log "── 唤出面板 ──"
    if trigger_overlay 2>&1 | tee -a "$LOG_FILE"; then
        log "✓ 已发送 Command+Shift+V"
    else
        log "✗ 发送 Command+Shift+V 失败"
        log "  可手动按快捷键后检查。"
    fi
    sleep 0.8
else
    log ""
    log "── 唤出面板 ──"
    log "跳过（--skip-hotkey）"
fi

if command -v screencapture >/dev/null 2>&1; then
    if screencapture -x "$OVERLAY_SHOT" 2>/dev/null; then
        log "✓ 已保存截图: $OVERLAY_SHOT"
    else
        log "⚠ 截图失败，请手动检查屏幕"
    fi
else
    log "⚠ 未找到 screencapture，跳过截图"
fi

log ""
log "══════════════════════════════════════"
log "  请人工验证"
log "══════════════════════════════════════"
log "1. 面板是否已打开，且底部卡片托盘可见。"
log "2. 是否能看到 text / link / html / rtf / file / image 等样本卡片。"
log "3. 搜索、筛选、All/Favorites、设置按钮是否可见。"
log "4. 右键任意卡片，菜单是否可用。"
log "5. 右键菜单栏剪贴板图标，菜单是否可用；左键是否能打开面板。"
log ""
log "截图与日志位于:"
log "$ARTIFACT_DIR"
