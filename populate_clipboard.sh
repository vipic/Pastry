#!/bin/bash
# 向剪贴板依次写入 Pastry 支持的所有类型
# 用法: ./populate_clipboard.sh
# Pastry 运行中会自动捕获每一项；运行前建议先在应用内"清空全部记录"
cd "$(dirname "$0")"

SLEEP=0.8
PBWRITE="$(dirname "$0")/pbwrite"

log()   { echo "→ $*"; }
err()   { echo "  ✗ $*"; }
ok()    { echo "  ✓"; }

echo "══════════════════════════════════════"
echo "  Pastry 剪贴板填充脚本"
echo "  将写入 7 种类型，共 10 条"
echo "  （多文件显示为 1 张卡片包含 3 个文件）"
echo "══════════════════════════════════════"
echo

# 编译 pbwrite（如需要）
if [[ ! -x "$PBWRITE" ]]; then
    echo "→ 正在编译 pbwrite…"
    swiftc pbwrite.swift -o pbwrite || { echo "✗ 编译失败"; exit 1; }
fi

# 选择存在的样本文件。.zprofile 在不少环境里不存在，优先用常见 dotfile 兜底。
SAMPLE_FILES=()
for f in "$HOME/.zshrc" "$HOME/.gitconfig" "$HOME/.zprofile" "$HOME/.zshenv" "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc"; do
    [[ -f "$f" ]] && SAMPLE_FILES+=("$f")
done
if (( ${#SAMPLE_FILES[@]} == 0 )); then
    echo "✗ 未找到可用的样本文件，跳过文件类条目"
fi

if ! pgrep -x Pastry >/dev/null 2>&1; then
    echo "⚠  Pastry 好像没在运行。按回车继续，Ctrl-C 退出。"
    read -r
fi

echo "3 秒后开始…"
sleep 3

# ── 1. 短文本 ──
log "text — 短文本"
echo "Hello, Pastry! 这是第一条剪贴板记录。" | pbcopy && ok || err "pbcopy 失败"
sleep "$SLEEP"

# ── 2. 长文本（多行）──
log "text — 长文本（多行）"
cat <<'EOF' | pbcopy
DeepSeek TUI 是一款运行在终端中的 AI 编程助手。

特性：
• 支持 Swift / Python / Rust 等多种语言
• 1M token 上下文窗口
• 内置沙箱 + 子代理并行执行
• macOS 26+ 原生体验

项目地址：https://github.com/nekutai/deepseek-tui

以上是 Pastry 性能打点的一部分背景 — 我们给 OverlayPanelManager 的
showPanel() 和 hideAndPaste() 加了 CFAbsoluteTime 分段计时，
数据写入 ~/Library/Logs/Pastry/perf.log，然后 bench.sh --report
可以拉出 p50/p95/p99 统计。
EOF
ok
sleep "$SLEEP"

# ── 2b. 纯 URL（整段为链接，Pastry 标记 isURL）──
log "text — 纯 URL（链接条目）"
"$PBWRITE" url "https://github.com/nekutai/pastry" && ok || err "URL 写入失败"
sleep "$SLEEP"

# ── 3. HTML ──
log "html — HTML 片段"
"$PBWRITE" html "<h2>Pastry 发布说明</h2><ul><li><b>v1.2</b> — 支持多选粘贴</li><li><b>v1.1</b> — SQLCipher 全库加密</li><li><b>v1.0</b> — 首个公开版本</li></ul><p style='color:#888'>macOS 26+ 剪贴板管理器</p>" && ok || err "HTML 写入失败"
sleep "$SLEEP"

# ── 4. RTF — 写临时文件再用 pbwrite 读取 ──
log "rtf — 富文本"
RTF_FILE=$(mktemp /tmp/pastry_rtf_XXXXXX.rtf)
cat > "$RTF_FILE" << 'RTFEOF'
{\rtf1\ansi\deff0
{\fonttbl{\f0 Helvetica;}{\f1 Helvetica-Oblique;}}
\f0\fs32\b Pastry\b0
\fs24 是 macOS 26+ 的原生剪贴板管理器。\par
\f1\i 支持：\i0 文本、RTF、HTML、图片、文件路径。\par
\f0 github.com/nekutai/pastry
}
RTFEOF
"$PBWRITE" rtf "$RTF_FILE" && ok || err "RTF 写入失败"
rm -f "$RTF_FILE"
sleep "$SLEEP"

# ── 5. 单文件路径 ──
if (( ${#SAMPLE_FILES[@]} >= 1 )); then
    log "fileURL — 单个文件"
    "$PBWRITE" file "${SAMPLE_FILES[0]}" && ok || err "单文件写入失败"
    sleep "$SLEEP"
fi

# ── 6. 多文件路径（3 个文件合并为 1 条）──
if (( ${#SAMPLE_FILES[@]} >= 2 )); then
    count=${#SAMPLE_FILES[@]}
    (( count > 3 )) && count=3
    log "fileURL — 多个文件（${count} 个合并为 1 条）"
    "$PBWRITE" file "${SAMPLE_FILES[@]:0:$count}" && ok || err "多文件写入失败"
    sleep "$SLEEP"
fi

# ── 7. 图片 — 纯色 ──
log "image — 纯色 (200×120, 蓝色)"
IMG_FILE=$(mktemp /tmp/pastry_img_XXXXXX.png)
python3 -c "
from PIL import Image
img = Image.new('RGB', (200, 120), color=(30, 100, 220))
img.save('$IMG_FILE', 'PNG')
" && "$PBWRITE" image "$IMG_FILE" && ok || err "纯色图片写入失败"
rm -f "$IMG_FILE"
sleep "$SLEEP"

# ── 8. 图片 — 渐变 ──
log "image — 渐变 (300×180, 绿→紫)"
IMG_FILE=$(mktemp /tmp/pastry_img_XXXXXX.png)
python3 -c "
from PIL import Image
w, h = 300, 180
img = Image.new('RGB', (w, h))
for x in range(w):
    r = int(40 + (180 - 40) * x / w)
    g = int(200 - (200 - 30) * x / w)
    b = int(80 + (220 - 80) * x / w)
    for y in range(h):
        img.putpixel((x, y), (r, g, b))
img.save('$IMG_FILE', 'PNG')
" && "$PBWRITE" image "$IMG_FILE" && ok || err "渐变图片写入失败"
rm -f "$IMG_FILE"
sleep "$SLEEP"

# ── 9. 短文本 ──
log "text — 短文本（测试排序）"
echo "第二条文本 — 测试历史列表排序 @pastry" | pbcopy && ok || err "pbcopy 失败"
sleep "$SLEEP"

echo
echo "══════════════════════════════════════"
echo "  完成！打开 Pastry 面板 (⌘⇧V) 查看。"
echo "══════════════════════════════════════"
