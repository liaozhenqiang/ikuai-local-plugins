#!/bin/bash
#
# boot.sh —— 每次开机执行(存在时优先于 install.sh)。
#
# 根分区每次重启还原、进程重启即死, 插件本体在持久盘不会丢,
# 所以开机唯一要做的事: 把 frpc 重新拉起。
#
# 要点: 串在开机流程里, 必须快且可失败 —— 单步失败打印日志后继续。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/frpc}"
BIN="$ROOT/bin/frpcctl"
CONFCTL="$ROOT/data/frpcctl.conf"
LOG=/etc/log/frpc/frpc.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime))" >> "$LOG"

chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "$(date '+%F %T') [boot] 缺少 $BIN, 跳过" >> "$LOG"; exit 0; }

"$BIN" init >> "$LOG" 2>&1

# 开机自启开关(默认开): 用户在插件页面关掉后, 这里就不再拉起 ——
# 否则"手动停止"了也会被下一次重启给重新拉起来。
# 直接读配置文件而不是调 `frpcctl autostart`: 后者不带参数只打印用法, 判断会失效。
if [ "$(sed -n 's/^autostart=//p' "$CONFCTL" 2>/dev/null | head -n1)" = "0" ]; then
    echo "$(date '+%F %T') [boot] 开机自启已关闭, 不启动" >> "$LOG"
    exit 0
fi

# 没填服务端地址就别白启动 —— frpc 会启动即退出, 还会刷一堆错误日志
if [ -z "$(sed -n 's/^serveraddr=//p' "$CONFCTL" 2>/dev/null | head -n1)" ]; then
    echo "$(date '+%F %T') [boot] 未配置服务端地址, 跳过启动" >> "$LOG"
    exit 0
fi

"$BIN" start >> "$LOG" 2>&1
echo "$(date '+%F %T') [boot] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
