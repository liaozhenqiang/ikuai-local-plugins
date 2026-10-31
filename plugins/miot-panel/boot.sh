#!/bin/bash
#
# boot.sh —— 每次开机执行。根分区还原、进程都不在了，这里把面板重新拉起来。
#
# 注意：开机早期 /etc/mnt 上的文件可能还没完全就绪（实测第一次 exec 会报
# "can't execute python3"），所以这里不直接同步启动，而是交给一个后台
# 重试器：延迟 15 秒起，最多试 6 次，成功即退出。boot.sh 本身立即返回，
# 不拖慢开机。
#
set -u

ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/miot-panel}"
LOGDIR=/etc/log/miot-panel
LOG="$LOGDIR/install.log"

mkdir -p "$LOGDIR" 2>/dev/null
echo "$(date '+%F %T') [boot] 开机处理开始 (uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null))" >> "$LOG"

if [ ! -x "$ROOT/bin/miot-panel" ]; then
    echo "$(date '+%F %T') [boot] 缺少 $ROOT/bin/miot-panel，跳过" >> "$LOG"
    exit 0
fi

"$ROOT/bin/miot-panel" init >> "$LOG" 2>&1

( trap '' HUP
  sleep 15
  i=0
  while [ "$i" -lt 6 ]; do
      i=$((i + 1))
      if "$ROOT/bin/miot-panel" start >> "$LOG" 2>&1; then
          echo "$(date '+%F %T') [boot] 第 $i 次启动成功: $("$ROOT/bin/miot-panel" status 2>/dev/null)" >> "$LOG"
          exit 0
      fi
      echo "$(date '+%F %T') [boot] 第 $i 次启动失败 (python=$([ -x "$ROOT/runtime/python/bin/python3" ] && echo ok || echo missing) ld=$([ -x "$ROOT/runtime/lib/ld-linux-x86-64.so.2" ] && echo ok || echo missing) uptime=$(cut -d' ' -f1 /proc/uptime 2>/dev/null))" >> "$LOG"
      sleep 10
  done
  echo "$(date '+%F %T') [boot] 6 次重试均失败，请手动执行 miot-panel start" >> "$LOG"
) &

echo "$(date '+%F %T') [boot] 已交给后台重试器" >> "$LOG"
exit 0
