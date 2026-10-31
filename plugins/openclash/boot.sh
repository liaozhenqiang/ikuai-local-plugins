#!/bin/bash
#
# openclash 每次开机执行(优先于 install.sh)
#
# 注意: 本包已按 unix 权限位重新打包, 脚本可被正常执行; 万一权限位丢失,
# /etc/mnt/openclash-guard.sh(插件目录之外, cron 每分钟用 bash 调用)会兜底:
#   - 补权限位
#   - 重铺目录/软链(根分区每次重启还原)
#   - 内核不在就拉起, 规则丢了就补回
# 本脚本在"能被执行"时提前做一遍, 让开机后立刻可用, 不必等第一分钟。


ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/openclash}"
export PLUGIN_DIR="$ROOT"
OCTL="$ROOT/bin/occtl"
LOG_DIR=/etc/log/ikguard
LOG="$LOG_DIR/openclash-boot.log"
CRON_FILE=/etc/mnt/cron.d/openclash_guard
GUARD=/etc/mnt/openclash-guard.sh

mkdir -p "$LOG_DIR" "$ROOT/data/log" /etc/mnt/cron.d 2>/dev/null
echo "$(date '+%F %T') [boot] plugin=$PLUGIN_NAME version=$PLUGIN_VERSION" >> "$LOG"

# 权限位(必须在调用 occtl 之前)
chmod +x "$ROOT/bin/"* "$ROOT/function/"* "$ROOT"/*.sh 2>/dev/null
[ -f "$OCTL" ] || { echo "$(date '+%F %T') [boot] 缺少 $OCTL(插件不完整?)" >> "$LOG"; exit 0; }

# 目录/配置/渲染(用 bash 调用, 不依赖权限位)
bash "$OCTL" setup >> "$LOG" 2>&1

# 守护脚本 + cron(根分区每次重启还原, 需要重铺; 内容来自包内 share/openclash-guard.sh)
if [ -f "$ROOT/share/openclash-guard.sh" ]; then
    cp -f "$ROOT/share/openclash-guard.sh" "$GUARD" 2>/dev/null
    chmod +x "$GUARD" 2>/dev/null
fi
# crond_commit() 的真实实现是 `cat /etc/crontabs/cron.d/* > /etc/crontabs/root`,
# **只汇总 /etc/crontabs/cron.d/** —— 只写 /etc/mnt/cron.d/ 再调 commit 是汇总不到的。
# 框架 scripts/04 本应用软链把 /etc/mnt/cron.d/* 桥接过去, 实测在这台设备上没有生效
# (/etc/crontabs/cron.d/ 里 0 个软链, /etc/crontabs/root 里始终没有 guard 条目,
#  守护脚本因此从未执行过)。uninstall.sh 一直在删 /etc/crontabs/cron.d/openclash_guard,
# 说明本意就是要写那里的。所以两处都写: mnt 留持久副本, crontabs 给 commit 汇总。
CRON_ACTIVE=/etc/crontabs/cron.d/openclash_guard
mkdir -p /etc/crontabs/cron.d /etc/mnt/cron.d 2>/dev/null
cat > "$CRON_FILE" <<EOF
# OpenClash for iKuai: 内核存活 + 规则自愈 + 卸载残留清理(用 bash 调用, 不受权限位影响)
* * * * * /bin/bash $GUARD >/dev/null 2>&1
EOF
chmod 644 "$CRON_FILE" 2>/dev/null
cp -f "$CRON_FILE" "$CRON_ACTIVE" 2>/dev/null
chmod 644 "$CRON_ACTIVE" 2>/dev/null
for s in /usr/ikuai/include/crond.sh /usr/ikuai/script/utils/crond.sh; do
    if [ -f "$s" ]; then ( . "$s"; crond_commit >/dev/null 2>&1 ); break; fi
done

# 订阅定时更新: /etc/crontabs/root 每次开机还原, 所以开机也要重铺一次(内容由 occtl 按配置生成)
bash "$OCTL" sub-auto >> "$LOG" 2>&1

# 未开启自启就直接结束
[ "$(bash "$OCTL" conf-get enable)" = "1" ] || {
    echo "$(date '+%F %T') [boot] enable=0, 未启动内核" >> "$LOG"
    exit 0
}

# 红线(上游技能文档): boot.sh 串在开机流程里, **绝不能阻塞** —— 等 WAN 拨号(最多 90 秒)
# 与启动内核全部放后台子 shell。另外每分钟的守护脚本会兜底, 所以不需要在这里同步等待。
(
    trap '' HUP
    i=0
    while [ "$i" -lt 90 ]; do
        ip route show default 2>/dev/null | grep -q default && break
        i=$((i + 1))
        sleep 1
    done
    echo "$(date '+%F %T') [boot] 等待默认路由 ${i}s, 后台启动内核" >> "$LOG"
    bash "$OCTL" start >> "$LOG" 2>&1
    echo "$(date '+%F %T') [boot] 后台启动流程结束" >> "$LOG"
) &
echo "$(date '+%F %T') [boot] 已把启动排入后台(不阻塞开机流程)" >> "$LOG"
exit 0
