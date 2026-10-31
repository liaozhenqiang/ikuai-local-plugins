#!/bin/bash
#
# uninstall.sh —— 框架在"卸载"动作时执行。
#
# 框架随后会删掉 /etc/mnt/plugins/frps 并清理所有指向它的软链,
# 所以这里只需把运行中的 frps 停掉。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/frps}"
BIN="$ROOT/bin/frpsctl"
LOG=/etc/log/frps/frps.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 frps" >> "$LOG"

[ -x "$BIN" ] && "$BIN" stop >> "$LOG" 2>&1

echo "$(date '+%F %T') [uninstall] 完成" >> "$LOG"
exit 0
