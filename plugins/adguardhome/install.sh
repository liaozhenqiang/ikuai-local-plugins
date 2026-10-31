#!/bin/bash
#
# install.sh —— 框架在"安装/升级"动作时执行, 必须幂等。
#
set -u
ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/adguardhome}"
BIN="$ROOT/bin/adgctl"
LOG=/etc/log/adguardhome/adguardhome.log

mkdir -p "$ROOT/data" "$(dirname "$LOG")" 2>/dev/null
echo "$(date '+%F %T') [install] action=${PLUGIN_ACTION:-?} version=${PLUGIN_VERSION:-?} root=$ROOT" >> "$LOG"

# 防御: bin/ 与 share/ 不像 function/ 那样会被框架 chmod
chmod +x "$ROOT"/bin/* "$ROOT"/share/* 2>/dev/null

[ -x "$BIN" ] || { echo "[adguardhome] 缺少可执行文件: $BIN" >&2; exit 1; }

"$BIN" init    >> "$LOG" 2>&1   # 幂等: 生成初始 AdGuardHome.yaml + apply 上游(自动检测 OpenClash)
"$BIN" restart >> "$LOG" 2>&1   # 重启: 升级时让新代码/新上游生效; 未运行则等同 start
echo "$(date '+%F %T') [install] 状态: $("$BIN" status 2>/dev/null)" >> "$LOG"
exit 0
