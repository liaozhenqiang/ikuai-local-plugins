#!/bin/bash
#
# install.sh —— 安装时执行，必须幂等。
#
# 框架环境变量: PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
# 开机自启不靠这里，靠同目录的 boot.sh；这里只保证"装完立刻能用"。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/mimon}"
BIN="$ROOT/bin/mimon"
LOG=/etc/log/mimon.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

if [ ! -x "$BIN" ]; then
    echo "[mimon] 缺少可执行文件: $BIN" >&2
    exit 1
fi

"$BIN" init >> "$LOG" 2>&1
bash "$ROOT/share/menu_patch.sh" apply >> "$LOG" 2>&1
"$BIN" daemon-stop >> "$LOG" 2>&1
"$BIN" daemon-start >> "$LOG" 2>&1
exit 0
