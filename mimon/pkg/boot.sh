#!/bin/bash
#
# boot.sh —— 每次开机执行（存在时优先于 install.sh）。
#
# 根分区每次重启从固件镜像还原、所有进程都已死亡，所以开机唯一要做的事
# 就是把 mimon 的守护进程重新拉起来。这里必须快且可失败，不能卡住开机。

set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/mimon}"
BIN="$ROOT/bin/mimon"
LOG=/etc/log/mimon.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null))" >> "$LOG"

[ -x "$BIN" ] || { echo "$(date '+%F %T') [boot] 缺少 $BIN, 跳过" >> "$LOG"; exit 0; }

"$BIN" init >> "$LOG" 2>&1
bash "$ROOT/share/menu_patch.sh" apply >> "$LOG" 2>&1
"$BIN" daemon-start >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
