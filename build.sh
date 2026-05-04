#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Pastry"
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
BUNDLE_ID="com.nekutai.pastry"

echo "🔨 Building $APP_NAME (release)..."
cd "$PROJECT_DIR"
swift build -c release

# Quit running instance (try both old and new bundle IDs)
pkill -f "Pastry" 2>/dev/null || true
pkill -f "ClipboardManager" 2>/dev/null || true
# 轮询等待进程完全退出（最多 5 秒）
for i in $(seq 1 10); do
    if ! pgrep -f "Pastry" > /dev/null 2>&1; then break; fi
    sleep 0.5
done

# Create bundle structure once (preserves inode → TCC permissions stay)
if [ ! -d "$MACOS_DIR" ]; then
    echo "📦 Creating .app bundle at $APP_DIR..."
    mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"
fi

# Replace binary in-place (never rm -rf the bundle!)
test -f "$BUILD_DIR/Pastry" || { echo "❌ 构建产物不存在: $BUILD_DIR/Pastry"; exit 1; }
cp "$BUILD_DIR/Pastry" "$MACOS_DIR/$APP_NAME"

# Copy sound resources
cp "$PROJECT_DIR/Resources/Copy.aiff" "$CONTENTS/Resources/Copy.aiff"
cp "$PROJECT_DIR/Resources/Paste.aiff" "$CONTENTS/Resources/Paste.aiff"

# Copy app icon
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Info.plist (overwrite in-place)
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleExecutable</key>
    <string>Pastry</string>
    <key>CFBundleIdentifier</key>
    <string>com.nekutai.pastry</string>
    <key>CFBundleName</key>
    <string>Pastry</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# 确保没有残留的 bundle 级签名（会让 TCC 失效）
rm -rf "$APP_DIR/_CodeSignature" 2>/dev/null || true

echo "🚀 Launching $APP_NAME..."
open "$APP_DIR"

echo ""
echo "✅ Done — app restarted."
