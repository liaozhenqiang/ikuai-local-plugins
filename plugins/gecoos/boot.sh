#!/bin/bash
#
# boot.sh —— 每次开机执行(存在时优先于 install.sh)。
#
# 根分区重启会还原, 插件本体在持久盘不会丢, 开机只要把进程重新拉起来即可。
# 重要: 超时/卡死会拖慢开机, 用 start-nowait(不等端口就绪), 单步失败只记日志。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/gecoos}"
CTL="$ROOT/bin/gecoosctl"
LOG=/etc/log/gecoos/gecoos.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime))" >> "$LOG"

[ -x "$CTL" ] || { echo "$(date '+%F %T') [boot] 缺少 $CTL, 跳过" >> "$LOG"; exit 0; }

"$CTL" ensure    >> "$LOG" 2>&1
# 公网封锁规则开机时无条件同步一次, 与"开机自启"无关:
# 自启关着但服务还在跑(手动起过)时同样需要保护; 服务没跑时这条规则也无害。
"$CTL" wan-sync  >> "$LOG" 2>&1

# 用户关掉"开机自启"时, 开机就只做初始化、不拉起进程
if [ "$("$CTL" status-json 2>/dev/null | sed -n 's/.*"autostart":\([01]\).*/\1/p')" = "0" ]; then
    echo "$(date '+%F %T') [boot] 开机自启已关闭, 不启动" >> "$LOG"
    exit 0
fi

"$CTL" start-nowait >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] $("$CTL" status-json 2>/dev/null)" >> "$LOG"
exit 0
