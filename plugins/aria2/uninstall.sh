#!/bin/bash
#
# uninstall.sh —— 框架在"卸载"动作时执行。
#
# 框架随后会删掉 /etc/mnt/plugins/aria2 并清掉软链。
# 注意: 下载目录里的文件是用户的, 一律不碰; 只停服务、清 pid/日志。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/aria2}"
CTL="$ROOT/bin/aria2ctl"
LOG=/etc/log/aria2/aria2.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 aria2" >> "$LOG"

[ -x "$CTL" ] && "$CTL" stop >> "$LOG" 2>&1

rm -f "$ROOT/data/aria2.pid" 2>/dev/null

echo "$(date '+%F %T') [uninstall] 完成(下载目录中的文件已保留)" >> "$LOG"
exit 0
