import Foundation

enum UpdateInstallScriptBuilder {
    static func script(stableDMGPath: String, targetPath: String) -> String {
        """
        #!/bin/bash
        set -e
        sleep 1

        DMG="\(stableDMGPath)"
        TARGET="\(targetPath)"
        TARGET_PARENT=$(dirname "$TARGET")
        TARGET_NAME=$(basename "$TARGET")
        BACKUP="$TARGET_PARENT/.${TARGET_NAME}.update-backup-$(date +%s)"

        # 挂载 DMG
        MOUNT_OUTPUT=$(hdiutil attach -noverify -noautoopen -nobrowse "$DMG" 2>&1)
        VOLUME=$(echo "$MOUNT_OUTPUT" | grep '/Volumes/' | tail -1 | awk -F'\\t' '{print $NF}')

        if [ ! -d "$VOLUME/Pastry.app" ]; then
            echo "❌ DMG 挂载失败或缺少 Pastry.app" >&2
            open "$TARGET"
            exit 1
        fi

        CANDIDATE="$VOLUME/Pastry.app"
        CANDIDATE_BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)
        if [ "$CANDIDATE_BUNDLE" != "com.nekutai.pastry" ]; then
            echo "❌ 更新包 Bundle ID 不匹配: $CANDIDATE_BUNDLE" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        if ! /usr/bin/codesign --verify --deep --strict "$CANDIDATE" 2>/dev/null; then
            echo "❌ 更新包签名校验失败" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        CURRENT_REQ=$(/usr/bin/codesign -dr - "$TARGET" 2>&1 | sed -n 's/^.*designated => //p')
        if [ -z "$CURRENT_REQ" ]; then
            echo "❌ 无法读取当前 App 签名要求，拒绝自动更新" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi
        if ! /usr/bin/codesign --verify --deep --strict -R="designated => $CURRENT_REQ" "$CANDIDATE" 2>/dev/null; then
            echo "❌ 更新包签名身份与当前 App 不匹配" >&2
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
        fi

        # 替换整个 .app；先备份，复制失败时恢复旧版本
        mv "$TARGET" "$BACKUP"
        if ! cp -R "$CANDIDATE" "$TARGET"; then
            echo "❌ 更新包复制失败，已恢复旧版本" >&2
            rm -rf "$TARGET"
            mv "$BACKUP" "$TARGET"
            hdiutil detach "$VOLUME" -quiet || true
            open "$TARGET"
            exit 1
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
