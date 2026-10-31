#!/bin/bash
#
# uninstall.sh —— 框架卸载前执行：停进程。data/ 由框架随后删除。
#
set -u

ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/miot-panel}"
LOGDIR=/etc/log/miot-panel

[ -x "$ROOT/share/menu_patch.sh" ] && "$ROOT/share/menu_patch.sh" remove >> "$LOGDIR/install.log" 2>&1

if [ -x "$ROOT/bin/miot-panel" ]; then
    "$ROOT/bin/miot-panel" stop >> "$LOGDIR/install.log" 2>&1
fi
echo "$(date '+%F %T') [uninstall] 已停止" >> "$LOGDIR/install.log" 2>/dev/null
exit 0
