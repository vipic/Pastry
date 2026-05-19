#!/bin/bash
# Pastry Deploy — 快速开发部署
# 每次修改代码后执行：编译 → 打包 → 重启应用
# 用法: ./deploy.sh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Pastry"
BUILD_DIR="$PROJECT_DIR/.build/debug"
APP_DIR="$HOME/Applications/${APP_NAME} Dev.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
IDENTITY="${CODESIGN_IDENTITY:-}"

echo "⚡ Deploying $APP_NAME (debug)..."

# 确保代码签名证书存在（TCC 权限持久保留）
CERT_OK=true
if [ -n "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    :
elif [ -n "$IDENTITY" ]; then
    echo "⚠️  未找到 \"$IDENTITY\" 代码签名证书，回退 ad-hoc"
    CERT_OK=false
else
    CERT_OK=false
fi

cd "$PROJECT_DIR"

# 1. 编译
swift build 2>&1 | tail -3

# 2. 杀 dev 进程 + 等待退出（只杀 dev，不影响正式版）
pkill -f "Pastry Dev.app" 2>/dev/null || true
for i in $(seq 1 10); do
    if ! pgrep -f "Pastry Dev.app" > /dev/null 2>&1; then break; fi
    sleep 0.2
done

# 3. 确保 bundle 结构存在（保留 inode → TCC 权限不丢）
if [ ! -d "$MACOS_DIR" ]; then
    echo "📦 首次创建 .app bundle..."
    mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
fi

# 4. 替换二进制（原地覆盖，不删 bundle）
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# 5. 复制资源
cp "$PROJECT_DIR/Resources/Copy.aiff"    "$RESOURCES_DIR/Copy.aiff"    2>/dev/null || true
cp "$PROJECT_DIR/Resources/Paste.aiff"   "$RESOURCES_DIR/Paste.aiff"   2>/dev/null || true
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns" 2>/dev/null || true
cp "$PROJECT_DIR/Sources/Pastry/Resources/Localizable.xcstrings" "$RESOURCES_DIR/Localizable.xcstrings" 2>/dev/null || true

# 5. 版本号（semver: tag-dev+hash）和 git hash
DEPLOY_HASH=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD)
LATEST_TAG=$(cd "$PROJECT_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "1.0.0")
DEV_VERSION="${LATEST_TAG}-dev+${DEPLOY_HASH}"

# Info.plist — 首次创建模板，之后每次用 PlistBuddy 更新版本字段（不改变 inode → TCC 不丢）
if [ ! -f "$CONTENTS/Info.plist" ]; then
    cat > "$CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>Pastry</string>
    <key>CFBundleIdentifier</key>
    <string>com.nekutai.pastry.dev</string>
    <key>CFBundleName</key>
    <string>Pastry</string>
    <key>CFBundleDisplayName</key>
    <string>Pastry</string>
    <key>CFBundleVersion</key>
    <string>${DEPLOY_HASH}</string>
    <key>CFBundleShortVersionString</key>
    <string>${DEV_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST
else
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.nekutai.pastry.dev" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleName 'Pastry Dev'" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName 'Pastry Dev'" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${DEPLOY_HASH}" "$CONTENTS/Info.plist" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${DEV_VERSION}" "$CONTENTS/Info.plist" 2>/dev/null
fi

# 6. 清除残留签名（二进制替换后签名失效）并重签
rm -rf "$APP_DIR/_CodeSignature" 2>/dev/null || true
if $CERT_OK; then
    codesign --force --sign "$IDENTITY" "$APP_DIR" 2>/dev/null || true
else
    codesign --force --sign - "$APP_DIR" 2>/dev/null || true
    echo "⚠️  已用 ad-hoc 签名（TCC 权限不持久）"
fi

# 7. 启动
echo "🚀 启动 $APP_NAME..."
open "$APP_DIR"

echo "✅ Deploy 完成"
