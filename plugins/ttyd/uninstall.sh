#!/bin/bash
#
# uninstall.sh —— 框架在"卸载"动作时执行。
#
# 框架随后会删掉 /etc/mnt/plugins/<name> 并清掉软链,
# 所以这里只需要把"运行中的东西"停掉(不重启也干净)。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/ttyd}"
CTL="$ROOT/bin/ttydctl"
LOG=/etc/log/ttyd/ttyd.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 ttyd" >> "$LOG"

[ -x "$CTL" ] && "$CTL" stop >> "$LOG" 2>&1

# 兜底: 控制器坏了/pid 文件丢了, 也要按路径把残留进程清掉
for p in $(ps 2>/dev/null | grep "ttyd.*$ROOT/share/ttyd" | grep -v grep | awk '{print $1}'); do
    kill "$p" 2>/dev/null
done

echo "$(date '+%F %T') [uninstall] 完成" >> "$LOG"
exit 0
