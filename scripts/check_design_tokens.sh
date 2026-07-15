#!/bin/bash
# 设计 token 防回潮检查：禁止在调用点新增颜色 / 字号 / 圆角字面量。
# 权威源：PastryPalette (SettingsChrome.swift) + UIConstants.swift；单文件布局值放各文件 private enum Local。
set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# 1. Color(red:) 只允许出现在颜色 token 权威源
hits=$(grep -rn 'Color(red:' Sources/Pastry --include='*.swift' \
    | grep -v 'Settings/SettingsChrome.swift' \
    | grep -v 'Utils/Constants.swift' || true)
if [[ -n "$hits" ]]; then
    echo "[FAIL] 调用点禁止新增 Color(red:) 字面量，请收敛到 PastryPalette："
    echo "$hits"
    fail=1
fi

# 2. 字号字面量 .font(.system(size: 13)) → 用 UIConstants.TypeSize 或文件内 Local
hits=$(grep -rEn '\.font\(\.system\(size: [0-9]' Sources/Pastry --include='*.swift' || true)
if [[ -n "$hits" ]]; then
    echo "[FAIL] 调用点禁止字号字面量，请使用 UIConstants.TypeSize 或文件内 Local："
    echo "$hits"
    fail=1
fi

# 3. 圆角字面量 cornerRadius: 9 → 用 UIConstants.Radius 或文件内 Local（0 豁免）
hits=$(grep -rEn 'cornerRadius: [1-9]' Sources/Pastry --include='*.swift' || true)
if [[ -n "$hits" ]]; then
    echo "[FAIL] 调用点禁止圆角字面量，请使用 UIConstants.Radius 或文件内 Local："
    echo "$hits"
    fail=1
fi

if [[ "$fail" -ne 0 ]]; then
    echo ""
    echo "设计 token 约定见 AGENTS.md「Design Tokens」与 docs/design-tokens.html"
    exit 1
fi

echo "设计 token 检查通过：无新增颜色 / 字号 / 圆角字面量"
