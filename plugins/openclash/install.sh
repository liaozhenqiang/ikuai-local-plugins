#!/bin/bash
#
# openclash 插件安装脚本(由插件框架执行, 需要幂等)
#   环境变量: PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
#
# 重要前提: 框架 plugin_run 用 test -x 判断安装脚本。本包已按 unix 权限位重新打包
# (install.sh/boot.sh/uninstall.sh/bin/*/function/* 均为 0755), 脚本可被正常执行;
# 万一权限位在传输中再次丢失, 后端 function/openclash 里还有一份等价的自愈引导
# (ocd_bootstrap), 两者做同样的事, 谁先跑到算谁的。
#
# 步骤:
#   0) 补可执行位(必须在任何 "$OCTL" 调用之前)
#   1) 完整性自检(关键文件 + 强化版 MANIFEST 校验: 条目数 + 逐文件 SHA-256)
#   2) 建目录 / 初始化配置 / 渲染运行配置(逐步检查退出码)
#   3) 内核缺失时提示离线上传(不阻塞安装)
#   4) 写"守护脚本 + cron"(守护脚本放在插件目录之外, 插件被删后它会自清理防断网)
#   5) 内核在就启动

ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/openclash}"
export PLUGIN_DIR="$ROOT"
OCTL="$ROOT/bin/occtl"
LOG_DIR=/etc/log/ikguard
LOG="$LOG_DIR/openclash-install.log"
CRON_FILE=/etc/mnt/cron.d/openclash_guard
GUARD=/etc/mnt/openclash-guard.sh

mkdir -p "$LOG_DIR" "$ROOT/data/log" /etc/mnt/cron.d 2>/dev/null
echo "$(date '+%F %T') [install] action=$PLUGIN_ACTION version=$PLUGIN_VERSION dir=$ROOT" >> "$LOG"

say() { echo "[openclash] $*"; echo "$(date '+%F %T') [install] $*" >> "$LOG"; }

# ---------------------------------------------------------------- 0) 权限位
chmod +x "$ROOT/bin/"* "$ROOT/function/"* "$ROOT"/*.sh 2>/dev/null

# ---------------------------------------------------------------- 1) 完整性自检
MISSING=""
for f in Release bin/occtl function/openclash share/conf/template.yaml share/geo/Country.mmdb \
         www/plugins/openclash/openclash.json www/plugins/app/openclash.html www/plugins/app/openclash.png; do
    test -e "$ROOT/$f" || MISSING="$MISSING $f"
done
if [ -n "$MISSING" ]; then
    say "安装不完整, 缺少:$MISSING"
    say "请执行: ikplugin remove openclash; rm -rf $ROOT   然后重新上传插件包"
    exit 1
fi

if [ -f "$ROOT/MANIFEST.MF" ]; then
    BAD=""; N=0; FN=""; DG=""
    while IFS= read -r line; do
        case "$line" in
            "Name: "*) FN="${line#Name: }" ;;
            "SHA-256-Digest: "*) DG="${line#SHA-256-Digest: }" ;;
            *) continue ;;
        esac
        [ -n "$FN" ] && [ -n "$DG" ] || continue
        N=$((N + 1))
        AC="$(sha256sum "$ROOT/$FN" 2>/dev/null | cut -d' ' -f1)"
        [ "$AC" = "$DG" ] || BAD="$BAD $FN"
        FN=""; DG=""
    done < "$ROOT/MANIFEST.MF"
    # 实际文件数必须用括号分组再取反:
    #   find . -type f ! -name A ! -name B      <- 取反只作用于 B, A 根本没被排除
    #   find . -type f ! \( -name A -o -name B \) <- 正确
    # 写错会让计数永远比清单多 1(MANIFEST.MF 自己), 于是下面 N != FILE_N 恒成立,
    # 完整包也会被误判成"清单被截断"而整包拒绝安装。
    # 必须排除 data/: 升级安装时框架会先把上次的 data/ 挪回来再跑本脚本
    # (见框架 lib/plugin.sh), 里面全是运行期生成的配置/缓存/日志,
    # 数量远大于清单条目 -> 会误判"清单被截断"并 exit 1, 后续初始化全被跳过。
    FILE_N="$(find "$ROOT" -type f ! -path "$ROOT/data/*" ! \( -name MANIFEST.MF -o -name SIGNATURE.RSA \) 2>/dev/null | wc -l | tr -d ' ')"
    # 清单被截断/清空时逐条校验会"全部通过", 所以必须同时比对条目数与实际文件数
    if [ "$N" -lt 5 ] || [ "$N" != "$FILE_N" ]; then
        say "清单校验失败: 清单条目 $N != 实际文件 $FILE_N(清单可能被截断或缺失文件)"
        say "请重新上传官方插件包(或直接用 unzip 手工解到 $ROOT 后重跑本脚本)"
        exit 1
    fi
    if [ -n "$BAD" ]; then
        say "清单校验失败(文件缺失或被改动):$BAD"
        exit 1
    fi
    say "清单校验通过($N 个文件, 逐文件 SHA-256 一致)"
else
    # 我们的包一定带清单; 清单不在 = 解包被截断(根分区 /tmp 空间不足时 unzip 会
    # "成功"退出但只写一半)。以前这里只打一条警告, 于是半个插件被当成装好了。
    say "安装不完整: 缺少 MANIFEST.MF —— 解包被截断(常见原因: 根分区 /tmp 空间不足)"
    say "请把 zip 先放到持久分区再装: cp <包> /etc/mnt/ && ikplugin install /etc/mnt/<包>"
    say "或: ikplugin remove openclash; rm -rf $ROOT  然后重装"
    exit 1
fi

if [ ! -x "$OCTL" ]; then
    chmod +x "$OCTL" 2>/dev/null
    [ -x "$OCTL" ] || { say "引擎脚本不可执行/不存在: $OCTL"; exit 1; }
fi

# ---------------------------------------------------------------- 2) 目录/配置/渲染
for step in setup conf-init render; do
    if ! bash "$OCTL" "$step" >> "$LOG" 2>&1; then
        say "初始化步骤失败: $step(详见 $LOG)"
        exit 1
    fi
done
say "运行配置已生成: $ROOT/data/config.yaml"

# ---------------------------------------------------------------- 3) 内核
if [ ! -x "$ROOT/bin/mihomo" ]; then
    say "包内未包含内核: 请在插件页「工具 / 自检 → 离线安装内核」上传 mihomo 的 .gz,"
    say "或把内核文件传到设备后执行: occtl core-fetch /绝对路径/mihomo.gz"
else
    say "内核已就位($(wc -c < "$ROOT/bin/mihomo") 字节, 安装目录 $(bash "$OCTL" conf-get core_dir || echo "$ROOT/bin"))"
fi

# 可选数据提示
[ -f "$ROOT/share/geo/GeoSite.dat" ] || [ -f "$ROOT/data/cache/GeoSite.dat" ] || \
    say "提示: 没有 GeoSite.dat, GEOSITE 规则已自动降级(需要时用页面「离线安装 GEOSITE」或 occtl geo-import 导入)"
[ -f "$ROOT/share/ui/zashboard/index.html" ] || [ -f "$ROOT/data/cache/ui/zashboard/index.html" ] || \
    say "提示: 未包含面板资源, 需要时执行 occtl ui-fetch(可选, 墙内可能需镜像)"

# ---------------------------------------------------------------- 4) 守护脚本 + cron
# 守护脚本刻意放在插件目录**之外**(内容在包内 share/openclash-guard.sh, 这里复制出去):
# 插件被卸载(甚至 uninstall.sh 因权限位被跳过)之后, 它仍会被 cron 每分钟执行一次,
# 发现插件目录已不存在就清理 iptables 链/内核进程/自身, 避免整网断流。
if [ -f "$ROOT/share/openclash-guard.sh" ]; then
    cp -f "$ROOT/share/openclash-guard.sh" "$GUARD" 2>/dev/null
    chmod +x "$GUARD" 2>/dev/null
    say "守护脚本已就位: $GUARD"
else
    say "警告: 包内缺少 share/openclash-guard.sh, 卸载后可能残留规则"
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

# 立即提交 crontab(iKuai 的 crond 从 /etc/crontabs/root 执行, cron.d/* 需要汇总进去)
for s in /usr/ikuai/include/crond.sh /usr/ikuai/script/utils/crond.sh; do
    if [ -f "$s" ]; then
        ( . "$s"; crond_commit >/dev/null 2>&1 )
        say "cron 守护已提交($CRON_ACTIVE -> /etc/crontabs/root): $GUARD"
        break
    fi
done

# ---------------------------------------------------------------- 5) 启动
if [ -x "$ROOT/bin/mihomo" ]; then
    bash "$OCTL" bootstrap >> "$LOG" 2>&1
else
    say "内核未就位, 暂不启动(上传内核后点「启动」, 或等 cron 守护自动拉起)"
fi

say "安装完成: 版本 $PLUGIN_VERSION, 目录 $ROOT"
say "配置 $ROOT/data/openclash.conf   运行日志 $ROOT/data/log/openclash.log"
exit 0
