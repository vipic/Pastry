#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ClipboardManager"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
BUNDLE_ID="com.nekutai.clipboardmanager"

echo "🔨 Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release

# Quit running instance
if pgrep -f "$APP_NAME.app" > /dev/null 2>&1; then
    echo "🛑 Quitting running $APP_NAME..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
    sleep 0.5
fi

# Create bundle structure once (preserves inode → TCC permissions stay)
if [ ! -d "$MACOS_DIR" ]; then
    echo "📦 Creating .app bundle at $APP_DIR..."
    mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"
fi

# Replace binary in-place (never rm -rf the bundle!)
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy sound resource
cp "$PROJECT_DIR/Copy.aiff" "$CONTENTS/Resources/Copy.aiff"

# Info.plist (overwrite in-place)
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClipboardManager</string>
    <key>CFBundleIdentifier</key>
    <string>com.nekutai.clipboardmanager</string>
    <key>CFBundleName</key>
    <string>ClipboardManager</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 🔑 对整个 .app bundle 重新 ad-hoc 签名，用自定义 designated requirement
#    锚定在 bundle identifier 上（而非每次编译都会变的 CDHash），
#    这样 TCC 辅助功能授权在多次构建后依然有效。
codesign -s - --force --deep \
    -r='designated => identifier "com.nekutai.clipboardmanager"' \
    "$APP_DIR" 2>/dev/null || true

echo "🚀 Launching $APP_NAME..."
open "$APP_DIR"

echo ""
echo "✅ Done — app restarted."
