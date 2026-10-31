#!/bin/bash
#
# install.sh —— 框架在"安装/升级"动作时执行, 必须幂等。
#
# 框架注入: PLUGIN_NAME PLUGIN_VERSION PLUGIN_DIR PLUGIN_ROOT PLUGIN_ACTION IK_SYSROOT
#
# 注意: 装完这一刻不一定能连上(还没填 -server/-vkey), 这属于正常情况;
#       在插件页面填好服务端地址与密钥后点"保存并启动"即可。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/npc}"
BIN="$ROOT/bin/npc"
LOG=/etc/log/npc.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

# 防御: bin/ 与 share/ 不像 function/ 那样会被框架 chmod(见 lib/plugin.sh)
chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "[npc] 缺少可执行文件: $BIN" >&2; exit 1; }

"$BIN" init >> "$LOG" 2>&1        # 幂等: 建数据目录 / 配置文件
# 只有在已经配好 server/vkey 时才尝试启动, 否则不必拉起一个必然失败的服务
if [ -n "$("$BIN" get server 2>/dev/null)" ] && [ -n "$("$BIN" get vkey 2>/dev/null)" ]; then
    "$BIN" start >> "$LOG" 2>&1
else
    echo "$(date '+%F %T') [install] 尚未配置 server/vkey, 跳过启动" >> "$LOG"
fi
exit 0
