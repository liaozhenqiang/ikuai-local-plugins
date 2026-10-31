#!/bin/bash
#
# uninstall.sh —— 卸载：恢复三个菜单入口、停守护进程
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/devmon}"
BIN="$ROOT/bin/devmon"
LOG=/etc/log/devmon.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 devmon" >> "$LOG"

bash "$ROOT/share/menu_patch.sh" remove >> "$LOG" 2>&1
[ -x "$BIN" ] && "$BIN" daemon-stop >> "$LOG" 2>&1

echo "$(date '+%F %T') [uninstall] 完成" >> "$LOG"
exit 0
