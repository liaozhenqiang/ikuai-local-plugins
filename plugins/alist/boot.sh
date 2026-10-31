#!/bin/bash
#
# boot.sh —— 每次开机执行(存在时优先于 install.sh)。
#
# 为什么必须有: 设备根分区(/)每次重启都从固件镜像还原 —— /usr/sbin 软链、Web 页面
# 软链都会消失(框架会重新铺), 而"常驻进程"更是重启就没了。插件本体在持久盘
# /etc/mnt/plugins/<name>, 不会丢, 所以开机只要把进程重新拉起来即可。
#
# 重要: 超时/卡死会拖慢开机, 所以这里的动作要"快且可失败" ——
#       用 start-nowait(不等端口就绪), 单步失败打印日志后继续。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/alist}"
CTL="$ROOT/bin/alistctl"
LOG=/etc/log/alist/alist.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime))" >> "$LOG"

[ -x "$CTL" ] || { echo "$(date '+%F %T') [boot] 缺少 $CTL, 跳过" >> "$LOG"; exit 0; }

# 用户关掉"开机自启"时, 开机就只做初始化、不拉起进程
if [ "$("$CTL" status-json 2>/dev/null | sed -n 's/.*"autostart":\([01]\).*/\1/p')" = "0" ]; then
    echo "$(date '+%F %T') [boot] 开机自启已关闭, 不启动" >> "$LOG"
    exit 0
fi

"$CTL" ensure       >> "$LOG" 2>&1
"$CTL" start-nowait >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] $("$CTL" status-json 2>/dev/null)" >> "$LOG"
exit 0
