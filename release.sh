#!/bin/bash
# Pastry Release — 生产发布
# 流程：release 编译 → 去除符号 → DMG 打包 → 签名
# 用法: ./release.sh [version]
#   ./release.sh 1.0.1        # 指定版本号
#   ./release.sh              # 自动取 git tag，没有则用 1.0
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Pastry"
BUILD_DIR="$PROJECT_DIR/.build/release"
STAGING="$PROJECT_DIR/.release_staging"
BUNDLE_ID="com.nekutai.pastry"
VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo '1.0')}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
IDENTITY="${CODESIGN_IDENTITY:--}"  # 默认 ad-hoc，设环境变量覆盖

echo "🏭 Building $APP_NAME $VERSION (release)..."
echo ""

cd "$PROJECT_DIR"

# ── 1. Release 编译（启用优化，去除 assert） ──
echo "━━━ 1/5 Release 编译 ━━━"
swift build -c release -Xswiftc -Osize 2>&1 | tail -3

BIN="$BUILD_DIR/$APP_NAME"
test -f "$BIN" || { echo "❌ 构建失败"; exit 1; }

# ── 2. 去除符号 ──
echo ""
echo "━━━ 2/5 去除调试符号 ━━━"
BIN_SIZE_BEFORE=$(stat -f%z "$BIN")
strip -S "$BIN" 2>/dev/null || true
BIN_SIZE_AFTER=$(stat -f%z "$BIN")
echo "   二进制: $(numfmt --to=iec $BIN_SIZE_BEFORE 2>/dev/null || echo "${BIN_SIZE_BEFORE}") → $(numfmt --to=iec $BIN_SIZE_AFTER 2>/dev/null || echo "${BIN_SIZE_AFTER}")"

# ── 3. 组装 .app ──
echo ""
echo "━━━ 3/5 组装 .app bundle ━━━"
rm -rf "$STAGING"
mkdir -p "$STAGING/$APP_NAME.app/Contents/MacOS"
mkdir -p "$STAGING/$APP_NAME.app/Contents/Resources"

# 二进制
cp "$BIN" "$STAGING/$APP_NAME.app/Contents/MacOS/$APP_NAME"

# 资源
cp "$PROJECT_DIR/Resources/Copy.aiff"    "$STAGING/$APP_NAME.app/Contents/Resources/" 2>/dev/null || true
cp "$PROJECT_DIR/Resources/Paste.aiff"   "$STAGING/$APP_NAME.app/Contents/Resources/" 2>/dev/null || true
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$STAGING/$APP_NAME.app/Contents/Resources/" 2>/dev/null || true

# Info.plist
cat > "$STAGING/$APP_NAME.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Pastry 需要辅助功能权限以监听全局快捷键。</string>
</dict>
</plist>
PLIST

# ── 4. 代码签名 ──
echo ""
echo "━━━ 4/5 代码签名 ━━━"
if [ "$IDENTITY" = "-" ]; then
    echo "   使用 ad-hoc 签名（本地可用，无法分发）"
    echo "   分发时请设置: CODESIGN_IDENTITY='Developer ID Application: ...' ./release.sh"
else
    echo "   签名身份: $IDENTITY"
fi
codesign --force --deep --sign "$IDENTITY" "$STAGING/$APP_NAME.app" 2>&1

# ── 5. DMG 打包 ──
echo ""
echo "━━━ 5/5 DMG 打包 ━━━"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

# 创建临时 DMG 目录
DMG_SRC="$STAGING/dmg_root"
mkdir -p "$DMG_SRC"
cp -R "$STAGING/$APP_NAME.app" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications" 2>/dev/null || true

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_SRC" \
    -ov -format UDZO \
    "$DMG_PATH" 2>&1 | grep -E "created|failed" || true

# 清理
rm -rf "$STAGING"

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  ✅ Release $VERSION 完成              ║"
echo "╠══════════════════════════════════════╣"
printf "║  📦 %-32s ║\n" "$DMG_NAME"
BIN_KB=$((BIN_SIZE_AFTER / 1024))
DMG_SIZE=$(stat -f%z "$DMG_PATH" 2>/dev/null || echo 0)
DMG_MB=$((DMG_SIZE / 1048576))
printf "║  📏 二进制: %d KB  DMG: %d MB      ║\n" $BIN_KB $DMG_MB
echo "╚══════════════════════════════════════╝"
