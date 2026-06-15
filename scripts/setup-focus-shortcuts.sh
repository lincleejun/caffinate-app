#!/usr/bin/env bash
# 安装「番茄钟 ↔ 系统 Focus 联动」所需的两个快捷指令。
#
# 快捷指令无法被静默创建（Apple 安全限制：添加快捷指令必须用户亲自确认）。
# 本脚本打开预置的 .shortcut 文件，你在弹出的「快捷指令」里点一下「添加快捷指令」即可。
# 已存在的会自动跳过，可反复运行。
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHORTCUTS_DIR="$DIR/Resources/shortcuts"
NAMES=("Caffinate Focus On" "Caffinate Focus Off")

missing=0
for name in "${NAMES[@]}"; do
    if shortcuts list 2>/dev/null | grep -qxF "$name"; then
        echo "✓ 已存在：$name"
        continue
    fi
    file="$SHORTCUTS_DIR/$name.shortcut"
    if [ -f "$file" ]; then
        echo "→ 打开「$name」，请在弹窗里点「添加快捷指令」"
        open "$file"
    else
        echo "⚠️ 缺少预置文件：$file"
        echo "   （在「快捷指令」里建好后，右键 → 共享 → 导出文件，存到上面的路径）"
        missing=1
    fi
done

echo
if [ "$missing" -eq 0 ]; then
    echo "完成后，在 Caffinate 设置打开「专注时静音通知」，或运行：caf set focus-link on"
fi
