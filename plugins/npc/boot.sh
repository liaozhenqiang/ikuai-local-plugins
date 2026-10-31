#!/bin/bash
#
# boot.sh —— 每次开机执行(存在时优先于 install.sh)。
#
# 根分区每次重启还原、进程重启即死, 插件本体在持久盘不会丢,
# 所以开机唯一要做的事: 把 npc 重新拉起(前提是已配置 server/vkey)。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/npc}"
BIN="$ROOT/bin/npc"
LOG=/etc/log/npc.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime))" >> "$LOG"

chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "$(date '+%F %T') [boot] 缺少 $BIN, 跳过" >> "$LOG"; exit 0; }

"$BIN" init >> "$LOG" 2>&1

# 开机自启开关(默认开): 用户在插件页面关掉后, 这里就不再拉起 ——
# 否则"手动停止"了也会被下一次重启给重新拉起来。
if [ "$("$BIN" autostart 2>/dev/null)" = "0" ]; then
    echo "$(date '+%F %T') [boot] 开机自启已关闭, 不启动" >> "$LOG"
    exit 0
fi

if [ -n "$("$BIN" get server 2>/dev/null)" ] && [ -n "$("$BIN" get vkey 2>/dev/null)" ]; then
    "$BIN" start >> "$LOG" 2>&1
else
    echo "$(date '+%F %T') [boot] 尚未配置 server/vkey, 跳过启动" >> "$LOG"
fi
echo "$(date '+%F %T') [boot] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
