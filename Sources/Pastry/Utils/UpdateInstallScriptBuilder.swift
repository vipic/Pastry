import Foundation

enum UpdateInstallScriptBuilder {
    static func script(stableDMGPath: String, targetPath: String, expectedVersion: String) -> String {
        """
        #!/bin/bash
        set -e

        DMG="\(stableDMGPath)"
        TARGET="\(targetPath)"
        EXPECTED_VERSION="\(expectedVersion)"
        LOG="/tmp/pastry_update.log"
        ERROR_FILE="/tmp/pastry_update_error.txt"
        exec >> "$LOG" 2>&1
        sleep 1
        echo "Pastry update started at $(date)"
        echo "Target: $TARGET"
        echo "Expected version: $EXPECTED_VERSION"
        TARGET_PARENT=$(dirname "$TARGET")
        TARGET_NAME=$(basename "$TARGET")
        BACKUP="$TARGET_PARENT/.${TARGET_NAME}.update-backup-$(date +%s)"
        rm -f "$ERROR_FILE"

        fail_update() {
            echo "❌ $1" >&2
            printf "%s\\n" "$1" > "$ERROR_FILE"
            if [ -n "${VOLUME:-}" ] && [ -d "$VOLUME" ]; then
                hdiutil detach "$VOLUME" -quiet || true
            fi
            open "$TARGET"
            exit 1
        }

        # 挂载 DMG
        MOUNT_OUTPUT=$(hdiutil attach -noverify -noautoopen -nobrowse "$DMG" 2>&1)
        VOLUME=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | tail -1 | awk -F'\\t' '{print $NF}')

        if [ ! -d "$VOLUME/Pastry.app" ]; then
            fail_update "DMG 挂载失败或缺少 Pastry.app"
        fi

        CANDIDATE="$VOLUME/Pastry.app"
        CANDIDATE_BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        CANDIDATE_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        if [ "$CANDIDATE_BUNDLE" != "com.nekutai.pastry" ]; then
            fail_update "更新包 Bundle ID 不匹配: $CANDIDATE_BUNDLE"
        fi
        if [ "$CANDIDATE_VERSION" != "$EXPECTED_VERSION" ]; then
            fail_update "更新包版本不匹配: $CANDIDATE_VERSION，期望 $EXPECTED_VERSION"
        fi

        if ! /usr/bin/codesign --verify --deep --strict "$CANDIDATE" 2>/dev/null; then
            fail_update "更新包签名校验失败"
        fi
        CANDIDATE_SIGNATURE=$(/usr/bin/codesign -dv "$CANDIDATE" 2>&1 || true)
        if echo "$CANDIDATE_SIGNATURE" | grep -q "Signature=adhoc"; then
            fail_update "更新包使用 ad-hoc 签名，拒绝自动更新"
        fi

        CURRENT_REQ=$(/usr/bin/codesign -dr - "$TARGET" 2>&1 | sed -n 's/^.*designated => //p')
        if [ -z "$CURRENT_REQ" ]; then
            echo "⚠️  无法读取当前 App 签名要求，跳过签名身份连续性校验" >&2
        else
            CANDIDATE_REQ=$(/usr/bin/codesign -dr - "$CANDIDATE" 2>&1 | sed -n 's/^.*designated => //p')
            if [ "$CANDIDATE_REQ" != "$CURRENT_REQ" ]; then
                fail_update "更新包签名身份与当前 App 不匹配，拒绝自动更新"
            fi
        fi

        # 替换整个 .app；先备份，复制失败时恢复旧版本
        mv "$TARGET" "$BACKUP"
        if ! cp -R "$CANDIDATE" "$TARGET"; then
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            fail_update "更新包复制失败，已恢复旧版本"
        fi
        INSTALLED_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist" 2>/dev/null || true)
        if [ "$INSTALLED_VERSION" != "$EXPECTED_VERSION" ]; then
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            fail_update "安装后版本仍为 $INSTALLED_VERSION，期望 $EXPECTED_VERSION，已恢复旧版本"
        fi
        rm -rf "$BACKUP"

        # 卸载 DMG
        hdiutil detach "$VOLUME" -quiet

        # 清理
        rm -f "$DMG" "$0"

        open "$TARGET"
        """
    }
}
