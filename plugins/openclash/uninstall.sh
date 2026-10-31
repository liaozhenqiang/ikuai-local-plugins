#!/bin/bash
#
# openclash 卸载脚本: 停内核、清规则与守护、备份配置
#
# 注意: 设备 unzip 丢权限位时框架不会执行本脚本 —— 那种情况下由
# /etc/mnt/openclash-guard.sh(cron 每分钟)发现插件目录消失后自动清理:
# 撤 iptables 链、杀内核进程、删自身。也就是说"卸载残留导致断网"有双保险。

ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/openclash}"
export PLUGIN_DIR="$ROOT"
OCTL="$ROOT/bin/occtl"
LOG_DIR=/etc/log/ikguard
LOG="$LOG_DIR/openclash-install.log"
BAK="/etc/mnt/openclash-backup-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$LOG_DIR" 2>/dev/null
echo "$(date '+%F %T') [uninstall] 停止 OpenClash" >> "$LOG"

chmod +x "$ROOT/bin/"* "$ROOT"/*.sh 2>/dev/null

# 用 bash 调用, 不依赖权限位
if [ -f "$OCTL" ]; then
    bash "$OCTL" stop   >> "$LOG" 2>&1
    bash "$OCTL" unrules >> "$LOG" 2>&1
fi

# 摘掉 cron 守护(文件 + crontabs 里的软链), 并通知 crond 重新汇总
rm -f /etc/mnt/cron.d/openclash_guard 2>/dev/null
rm -f /etc/crontabs/cron.d/openclash_guard 2>/dev/null
for s in /usr/ikuai/include/crond.sh /usr/ikuai/script/utils/crond.sh; do
    if [ -f "$s" ]; then ( . "$s"; crond_commit >/dev/null 2>&1 ); break; fi
done

# 备份用户配置(尽量全: 配置 + 渲染结果 + 自定义配置 + 订阅 + 自定义规则)
if [ -d "$ROOT/data" ]; then
    mkdir -p "$BAK" 2>/dev/null
    cp -f "$ROOT/data/openclash.conf"        "$BAK/" 2>/dev/null
    cp -f "$ROOT/data/config.yaml"           "$BAK/" 2>/dev/null
    cp -f "$ROOT/data/config.custom.yaml"    "$BAK/" 2>/dev/null
    cp -f "$ROOT/data/cache/providers/sub.yaml" "$BAK/openclash-sub.yaml" 2>/dev/null
    cp -f "$ROOT/data/providers/sub.yaml"    "$BAK/openclash-sub.yaml" 2>/dev/null
    cp -f "$ROOT/data/sub/raw.txt"           "$BAK/sub-raw.txt" 2>/dev/null
    mkdir -p "$BAK/rules" 2>/dev/null
    cp -f "$ROOT/data/rules/custom.list" "$ROOT/data/rules/bypass.ips" "$BAK/rules/" 2>/dev/null
    echo "$(date '+%F %T') [uninstall] 配置已备份到 $BAK" >> "$LOG"
fi

# 残留软链(框架的 plugin_unlink 也会清, 这里双保险)
rm -f /usr/sbin/occtl /usr/sbin/mihomo 2>/dev/null
rm -f /usr/ikuai/function/openclash 2>/dev/null
rm -f /usr/ikuai/www/plugins/app/openclash.html /usr/ikuai/www/plugins/app/openclash.png 2>/dev/null
rmdir /usr/ikuai/www/plugins/openclash 2>/dev/null

# 守护脚本: 留着它会立刻自清理并自删(双保险), 这里也主动删一次
rm -f /etc/mnt/openclash-guard.sh 2>/dev/null

echo "$(date '+%F %T') [uninstall] 完成(配置备份: $BAK)" >> "$LOG"
echo "[openclash] 已卸载; 配置备份在 $BAK"

# 内核(59MB)可能被 core_dir 放在别的分区: 故意保留, 重装可直接复用, 不必再传 23MB
CORE_DIR="$(sed -n 's/^core_dir=//p' "$BAK/openclash.conf" 2>/dev/null | head -n1)"
if [ -n "$CORE_DIR" ] && [ -f "$CORE_DIR/mihomo" ]; then
    echo "[openclash] 提示: 内核仍保留在 $CORE_DIR/mihomo ($(wc -c < "$CORE_DIR/mihomo") 字节), 重装可直接复用"
    echo "[openclash]       如需彻底删除: rm -rf $CORE_DIR"
fi
exit 0
