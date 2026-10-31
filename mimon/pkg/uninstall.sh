#!/bin/bash
#
# uninstall.sh —— 卸载时执行；框架随后会删插件目录并清理软链。
# 只需要停掉进程（守护进程 + 可能的网段扫描）。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/mimon}"
BIN="$ROOT/bin/mimon"
LOG=/etc/log/mimon.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 mimon" >> "$LOG"

bash "$ROOT/share/menu_patch.sh" remove >> "$LOG" 2>&1
[ -x "$BIN" ] && "$BIN" daemon-stop >> "$LOG" 2>&1

echo "$(date '+%F %T') [uninstall] 完成" >> "$LOG"
exit 0
