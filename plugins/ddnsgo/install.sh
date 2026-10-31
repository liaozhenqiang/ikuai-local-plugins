#!/bin/bash
#
# install.sh —— 框架在"安装/升级"动作时执行, 必须幂等。
#
# 框架注入环境变量: PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
#
# 职责: 初始化数据目录 + 拉起 ddns-go 守护进程, 让"装完立刻可用"(不用重启)。
# 开机自启不靠这里, 靠同目录的 boot.sh。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/ddnsgo}"
BIN="$ROOT/bin/ddnsgo"
LOG=/etc/log/ddnsgo.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

# 防御: bin/ 与 share/ 不像 function/ 那样会被框架 chmod(见 lib/plugin.sh),
# 万一 zip 权限位丢失(例如用 FAT 标记的 zip 打包), 这里自己补回执行位。
chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "[ddnsgo] 缺少可执行文件: $BIN" >&2; exit 1; }

"$BIN" init  >> "$LOG" 2>&1   # 幂等初始化(数据目录 / 环境文件)
"$BIN" start >> "$LOG" 2>&1   # 后台拉起 ddns-go
exit 0
