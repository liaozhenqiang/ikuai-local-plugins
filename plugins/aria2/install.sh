#!/bin/bash
#
# install.sh —— 框架在"安装"动作时执行, 必须幂等。
#
# aria2 是常驻服务: install 负责初始化配置 + 立即拉起, 让用户装完就能用。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/aria2}"
CTL="$ROOT/bin/aria2ctl"
LOG=/etc/log/aria2/aria2.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

if [ ! -x "$CTL" ]; then
    echo "[aria2] 缺少控制器: $CTL" >&2
    exit 1
fi

"$CTL" ensure    >> "$LOG" 2>&1
"$CTL" start     >> "$LOG" 2>&1
echo "$(date '+%F %T') [install] $("$CTL" status-json 2>/dev/null)" >> "$LOG"
exit 0
