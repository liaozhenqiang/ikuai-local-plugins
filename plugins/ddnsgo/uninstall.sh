#!/bin/bash
#
# uninstall.sh —— 框架在"卸载"动作时执行。
#
# 框架随后会删掉 /etc/mnt/plugins/ddnsgo 并清理所有指向它的软链,
# 所以这里只需把运行中的 ddns-go 进程停掉。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/ddnsgo}"
BIN="$ROOT/bin/ddnsgo"
LOG=/etc/log/ddnsgo.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 ddnsgo" >> "$LOG"

[ -x "$BIN" ] && "$BIN" stop >> "$LOG" 2>&1

echo "$(date '+%F %T') [uninstall] 完成" >> "$LOG"
exit 0
