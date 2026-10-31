#!/bin/bash
#
# boot.sh —— 每次开机执行(存在时优先于 install.sh)。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/adguardhome}"
BIN="$ROOT/bin/adgctl"
LOG=/etc/log/adguardhome/adguardhome.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime))" >> "$LOG"

chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "$(date '+%F %T') [boot] 缺少 $BIN, 跳过" >> "$LOG"; exit 0; }

"$BIN" init >> "$LOG" 2>&1

# 开机自启开关(默认开): 用户在插件页面关掉后, 这里就不再拉起
if [ "$(sed -n 's/^autostart=//p' "$ROOT/data/adgctl.conf" 2>/dev/null | head -n1)" = "0" ]; then
    echo "$(date '+%F %T') [boot] 开机自启已关闭, 不启动" >> "$LOG"
    exit 0
fi

"$BIN" start >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
