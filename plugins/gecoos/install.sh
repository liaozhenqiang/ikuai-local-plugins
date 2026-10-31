#!/bin/bash
#
# install.sh —— 框架在"安装"动作时执行, 必须幂等。
#
# "开机自启"不靠这里, 而靠同目录的 boot.sh; 本脚本只负责
# "装完这一刻立刻能用"(初始化 + 拉起进程), 让用户不用重启就能看到效果。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/gecoos}"
CTL="$ROOT/bin/gecoosctl"
LOG=/etc/log/gecoos/gecoos.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

if [ ! -x "$CTL" ]; then
    echo "[gecoos] 缺少控制器: $CTL" >&2
    exit 1
fi

"$CTL" ensure    >> "$LOG" 2>&1
"$CTL" start     >> "$LOG" 2>&1
echo "$(date '+%F %T') [install] $("$CTL" status-json 2>/dev/null)" >> "$LOG"
exit 0
