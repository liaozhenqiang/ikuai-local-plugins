#!/bin/bash
#
# uninstall.sh —— 框架在"卸载"动作时执行。
#
# 框架随后会删掉 /etc/mnt/plugins/<name> 并清掉它建立的所有软链
# (/usr/sbin、/usr/ikuai/function、/usr/ikuai/www/plugins 下指向插件的东西),
# 所以这里只需要把"运行中的东西"停掉。
#
# 注意: 设备根分区重启会还原, 所以"卸载后重启"本来就没有任何残留;
#       这里的清理是为了"不重启也干净"。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/alist}"
CTL="$ROOT/bin/alistctl"
DATA="$ROOT/data/alist"
LOG=/etc/log/alist/alist.log

mkdir -p "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 AList" >> "$LOG"

[ -x "$CTL" ] && "$CTL" stop >> "$LOG" 2>&1

# 兜底: 控制器坏了/pid 文件丢了, 也要按路径把残留进程清掉
for p in $(ps 2>/dev/null | grep "[s]erver --data $DATA" | awk '{print $1}'); do
    kill "$p" 2>/dev/null
done

echo "$(date '+%F %T') [uninstall] 完成" >> "$LOG"
exit 0
