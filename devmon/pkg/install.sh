#!/bin/bash
#
# install.sh —— 安装：建库、接管三个云控菜单入口、拉起守护进程（幂等）
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/devmon}"
BIN="$ROOT/bin/devmon"
LOG=/etc/log/devmon.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

if [ ! -x "$BIN" ]; then
    echo "[devmon] 缺少可执行文件: $BIN" >&2
    exit 1
fi

"$BIN" init >> "$LOG" 2>&1
bash "$ROOT/share/menu_patch.sh" apply >> "$LOG" 2>&1
"$BIN" daemon-stop >> "$LOG" 2>&1
"$BIN" daemon-start >> "$LOG" 2>&1
exit 0
