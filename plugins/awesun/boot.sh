#!/bin/bash
# awesun 插件开机动作。
#
# 根分区每次开机还原（/etc 下的软链、/lib 下的库软链、身份配置全没了），
# 所以开机必须：还原身份 -> 重建运行环境 -> 重新拉起进程。
# 失败只打日志，不能卡住开机流程。
export PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT

LOG=/etc/log/awesun/boot.log
mkdir -p /etc/log/awesun 2>/dev/null

{
    echo "===== $(date '+%F %T') boot.sh (plugin=$PLUGIN_NAME v$PLUGIN_VERSION) ====="
    "$PLUGIN_DIR/bin/awesunctl" boot
    echo "rc=$?"
} >> "$LOG" 2>&1

# 无论如何都返回 0：boot 失败也不能影响路由器启动
exit 0
