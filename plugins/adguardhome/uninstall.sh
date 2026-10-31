#!/bin/bash
#
# uninstall.sh —— 框架在"卸载"动作时执行。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/adguardhome}"
BIN="$ROOT/bin/adgctl"
LOG=/etc/log/adguardhome/adguardhome.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 AdGuardHome" >> "$LOG"

[ -x "$BIN" ] && "$BIN" stop >> "$LOG" 2>&1

echo "$(date '+%F %T') [uninstall] 完成" >> "$LOG"
exit 0
