#!/bin/bash
#
# boot.sh —— 每次开机执行(存在时优先于 install.sh)。
#
# 根分区(/)每次重启从固件镜像还原, 常驻进程重启即死; 插件本体在持久盘
# /etc/mnt/plugins/ddnsgo 不会丢, 所以开机唯一要做的事: 把 ddns-go 重新拉起。
#
# 要点: 串在开机流程里, 必须快且可失败 —— 单步失败打印日志后继续, 不卡开机。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/ddnsgo}"
BIN="$ROOT/bin/ddnsgo"
LOG=/etc/log/ddnsgo.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime))" >> "$LOG"

# 防御: 补回 bin/ 与 share/ 的执行位(框架只对 function/ 做 chmod)
chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "$(date '+%F %T') [boot] 缺少 $BIN, 跳过" >> "$LOG"; exit 0; }

"$BIN" init  >> "$LOG" 2>&1
"$BIN" start >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
