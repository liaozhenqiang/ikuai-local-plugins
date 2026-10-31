#!/bin/bash
#
# OpenClash for iKuai 守护脚本
#
# 由 install.sh / boot.sh / 后端自愈引导复制到 /etc/mnt/openclash-guard.sh,
# 再由 /etc/mnt/cron.d/openclash_guard 每分钟用 /bin/bash 调用(不依赖权限位)。
#
# 为什么放在插件目录之外:
#   设备 unzip 不还原权限位时, 框架会跳过 install.sh/boot.sh/uninstall.sh。
#   这会导致卸载后 iptables 三条链、内核进程、cron 全部残留 —— 规则指向无人监听
#   的端口 = 整网断流。本脚本发现插件目录已不存在时, 会把这一切清理干净并自删。

# IKST_GUARD_CRON
# 守护自身也保证 crontab 行存在(万一被框架重铺掉, 下一分钟靠这一行自愈)
if [ -f /etc/crontabs/root ]; then
    for g in /etc/mnt/openclash-guard.sh /etc/mnt/ikstorage-guard.sh; do
        [ -f "$g" ] || continue
        grep -qF "$g" /etc/crontabs/root 2>/dev/null || \
            echo "* * * * * /bin/bash $g >/dev/null 2>&1" >> /etc/crontabs/root
    done
fi

P=/etc/mnt/plugins/openclash

del_jumps() {   # 通用: 删掉所有指向某链的跳转规则(含 -i 网卡、-p 协议等变体)
    local tbl="$1" chain="$2" rule
    iptables -t "$tbl" -S 2>/dev/null | grep -E "^-A (PREROUTING|OUTPUT|FORWARD) .*-j $chain( |$)" | \
    while IFS= read -r rule; do
        iptables -t "$tbl" ${rule/-A /-D } 2>/dev/null
    done
}

cleanup_everything() {
    local c
    for c in OPENCLASH OPENCLASH_DNS OPENCLASH_MARK; do
        del_jumps nat "$c"
        del_jumps mangle "$c"
        iptables -t nat -F "$c" 2>/dev/null; iptables -t nat -X "$c" 2>/dev/null
        iptables -t mangle -F "$c" 2>/dev/null; iptables -t mangle -X "$c" 2>/dev/null
    done
    ip rule del fwmark 1 lookup 100 2>/dev/null
    # 不要 flush 整张表: iKuai 与其它插件可能共用 table 100
    # 内核可能位于包内 / data/bin / core_dir(卸载后文件已删, 但进程会继续运行),
    # 三个位置都要匹配(路径精确, 不会误杀无关进程)
    pkill -f '/etc/mnt/plugins/openclash/bin/mihomo' 2>/dev/null
    pkill -f '/etc/mnt/plugins/openclash/data/bin/mihomo' 2>/dev/null
    pkill -f '/etc/log/openclash/mihomo' 2>/dev/null
    rm -f /etc/crontabs/cron.d/openclash_guard 2>/dev/null
    rm -f /etc/mnt/cron.d/openclash_guard /etc/mnt/openclash-guard.sh 2>/dev/null
    logger -t openclash "插件已不存在: 已清理透明代理规则/内核进程/守护自身" 2>/dev/null
}

MISS=/etc/mnt/.openclash-guard.miss

if [ -d "$P" ]; then
    rm -f "$MISS" 2>/dev/null
    chmod +x "$P/bin/"* "$P/function/"* "$P"/*.sh 2>/dev/null
    if [ -f "$P/bin/occtl" ]; then
        /bin/bash "$P/bin/occtl" autostart
    fi
else
    # 插件目录不在: 不能立刻清理 —— 如果插件目录是软链/挂载到别的分区(例如把
    # 75MB 的完整包放到 /etc/log), 开机时目标分区可能还没挂上, 目录会短暂"消失"。
    # 连续 3 分钟都见不到才认定为"已卸载", 然后清规则/杀内核/自删。
    n=$(cat "$MISS" 2>/dev/null)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    n=$((n + 1))
    echo "$n" > "$MISS" 2>/dev/null
    if [ "$n" -ge 3 ]; then
        cleanup_everything
        rm -f "$MISS" 2>/dev/null
    fi
fi
