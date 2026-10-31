#!/bin/bash
#
# ikuai_terminals.sh —— 从 iKuai 自己的终端列表取具体型号/品牌/备注/hostname
#
# 数据源: /usr/ikuai/function/monitor_lanip show TYPE=data（本机函数，无需 Web 登录/token）
# 输出: 每台终端一行，字段用 \x1f 分隔:
#   mac ip hostname brand model type typeid comment ap ssid signal
#
# 本地测试可用 MIMON_TERM_JSON=<file> 直接喂一份 JSON（结构 {"data":[...]}）。
#
set -u

FUNC="${IK_TERM_FUNC:-/usr/ikuai/function/monitor_lanip}"
TERM_JSON="${MIMON_TERM_JSON:-}"
TMP="$(mktemp)" || exit 0

if [ -n "$TERM_JSON" ] && [ -f "$TERM_JSON" ]; then
    cp -f "$TERM_JSON" "$TMP" 2>/dev/null || { rm -f "$TMP"; exit 0; }
elif [ -x "$FUNC" ]; then
    "$FUNC" show TYPE=data > "$TMP" 2>/dev/null || { rm -f "$TMP"; exit 0; }
else
    rm -f "$TMP"
    exit 0
fi

if command -v jq >/dev/null 2>&1; then
    jq -r '.data[]? | [
        (.mac // ""),
        (.ip_addr // ""),
        (.hostname // ""),
        (.client_device // ""),
        (.client_model // ""),
        (.client_type // ""),
        ((.client_typeid // 0) | tostring),
        (.comment // ""),
        (.apname // ""),
        (.ssid // ""),
        (.signal // "")
      ] | join("\u001f")' "$TMP" 2>/dev/null | tr -d '\r' | sed 's/%20/ /g'
fi

rm -f "$TMP"
