#!/bin/bash
#
# install.sh —— 框架在"安装/升级"动作时执行, 必须幂等。
#
# 框架注入: PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
#
# 职责: 初始化数据目录(生成默认 conf/nps.conf) + 拉起 nps, 让"装完立刻可用"。
# 开机自启靠同目录的 boot.sh。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/nps}"
BIN="$ROOT/bin/nps"
LOG=/etc/log/nps.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

# 防御: bin/ 与 share/ 不像 function/ 那样会被框架 chmod(见 lib/plugin.sh)
chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "[nps] 缺少可执行文件: $BIN" >&2; exit 1; }

"$BIN" init  >> "$LOG" 2>&1   # 幂等: 建数据目录 / 生成默认 nps.conf
"$BIN" start >> "$LOG" 2>&1   # 后台拉起 nps
echo "$(date '+%F %T') [install] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
