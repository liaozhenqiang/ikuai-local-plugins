#!/bin/bash
#
# boot.sh —— 每次开机执行(存在时优先于 install.sh)。
#
# 根分区重启会还原, 插件本体在持久盘不会丢, 开机把服务拉起来即可。
# 超时/卡死会拖慢开机, 单步失败只记日志; 用户关掉"开机自启"时只初始化不启动。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/aria2}"
CTL="$ROOT/bin/aria2ctl"
LOG=/etc/log/aria2/aria2.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime))" >> "$LOG"

[ -x "$CTL" ] || { echo "$(date '+%F %T') [boot] 缺少 $CTL, 跳过" >> "$LOG"; exit 0; }

"$CTL" ensure >> "$LOG" 2>&1

if [ "$("$CTL" status-json 2>/dev/null | sed -n 's/.*"autostart":\([01]\).*/\1/p')" = "0" ]; then
    echo "$(date '+%F %T') [boot] 开机自启已关闭, 不启动" >> "$LOG"
    exit 0
fi

"$CTL" start >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] $("$CTL" status-json 2>/dev/null)" >> "$LOG"
exit 0
