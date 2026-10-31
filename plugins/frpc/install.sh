#!/bin/bash
#
# install.sh —— 框架在"安装/升级"动作时执行, 必须幂等。
#
# 框架注入: PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
#
# 职责: 初始化数据目录(建空规则库 + 生成 frpc.toml)。
# 注意: frpc **不会**在安装后自动启动 —— 还没填服务端地址, 起来也是连不上。
#       用户在页面填好地址后自己点启动即可; 开机自启由 boot.sh 负责。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/frpc}"
BIN="$ROOT/bin/frpcctl"
LOG=/etc/log/frpc/frpc.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

# 防御: bin/ 与 share/ 不像 function/ 那样会被框架 chmod(见 lib/plugin.sh)
chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "[frpc] 缺少可执行文件: $BIN" >&2; exit 1; }

"$BIN" init >> "$LOG" 2>&1   # 幂等: 建数据目录 / 空规则库 / 生成 frpc.toml

# 升级场景: 之前在跑就继续跑(配置已在持久盘, 不会丢)
if [ -f "$ROOT/data/frpc.pid" ]; then
    "$BIN" start >> "$LOG" 2>&1
fi

echo "$(date '+%F %T') [install] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
