#!/bin/bash
#
# boot.sh —— 每次开机：建库、重打三个菜单入口、拉起守护进程
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/devmon}"
BIN="$ROOT/bin/devmon"
LOG=/etc/log/devmon.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null))" >> "$LOG"

[ -x "$BIN" ] || { echo "$(date '+%F %T') [boot] 缺少 $BIN, 跳过" >> "$LOG"; exit 0; }

"$BIN" init >> "$LOG" 2>&1
bash "$ROOT/share/menu_patch.sh" apply >> "$LOG" 2>&1
"$BIN" daemon-start >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
