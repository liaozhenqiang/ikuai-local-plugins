#!/bin/bash
#
# 本地冒烟测试：假 ARP / 假 ping / 假 miIO JSON，验证发现、在线状态机、
# 型号分类、手动编辑与打包前的数据面。不接触真机、不写系统路径。
#
# 依赖: sqlite3, jq
# 用法: bash tests/smoke.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$HERE/pkg/bin/mimon"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mimon-smoke.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

command -v sqlite3 >/dev/null 2>&1 || { echo "需要 sqlite3 在 PATH 里" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "需要 jq 在 PATH 里" >&2; exit 2; }

export MIMON_DATA="$TMP/data"
export MIMON_DB="$TMP/data/mimon.db"
export MIMON_LOG="$TMP/mimon.log"
export MIMON_ARP_FILE="$TMP/arp"
export MIMON_ROUTE_FILE="$TMP/route"
export MIMON_PING="$TMP/ping"
export MIMON_MIIO_JSON="$TMP/miio.json"
export MIMON_TERM_JSON="$TMP/term.json"
mkdir -p "$MIMON_DATA"

cat > "$TMP/arp" <<'EOF'
IP address       HW type     Flags       HW address            Mask     Device
192.168.9.10     0x1         0x2         34:ce:00:11:22:33     *        br-lan
192.168.9.11     0x1         0x2         64:09:80:aa:bb:cc     *        br-lan
192.168.9.12     0x1         0x2         00:11:22:33:44:55     *        br-lan
192.168.9.13     0x1         0x0         34:ce:00:dd:ee:ff     *        br-lan
EOF
cat > "$TMP/route" <<'EOF'
Iface	Destination	Gateway 	Flags	RefCnt	Use	Metric	Mask		MTU	Window	IRTT
br-lan	0009A8C0	00000000	0001	0	0	0	00FFFFFF	0	0	0
wan1	00000000	0102A8C0	0003	0	0	0	00000000	0	0	0
EOF
cat > "$TMP/ping" <<EOF
#!/bin/bash
ip="\${@: -1}"
grep -qx "\$ip" "$TMP/up" 2>/dev/null && exit 0
exit 1
EOF
chmod +x "$TMP/ping"
printf '192.168.9.10\n192.168.9.11\n' > "$TMP/up"
printf '{"devices":[]}\n' > "$TMP/miio.json"
printf '{"data":[]}\n' > "$TMP/term.json"

PASS=0
pass() { PASS=$((PASS + 1)); echo "  ok  $1"; }
fail() { echo "  FAIL $1" >&2; echo "--- log ---" >&2; tail -20 "$MIMON_LOG" 2>/dev/null >&2 || true; exit 1; }
eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', want '$2')"; }
jqget() { printf '%s' "$1" | jq -r "$2"; }

run() { bash "$BIN" "$@"; }

echo "== 1. 首次发现 =="
run init >/dev/null
run set sweep_enabled 0 >/dev/null
run set miio 0 >/dev/null
OUT="$(run scan)"
eq "$(jqget "$OUT" '.devices')" "2" "只收录小米 OUI 且 ARP 完整的设备"
eq "$(jqget "$OUT" '.new')" "2" "首次发现 2 台"
DEVS="$(run devices)"
eq "$(printf '%s' "$DEVS" | jq 'length')" "2" "devices 返回 2 条"
eq "$(jqget "$DEVS" '.[0].online')" "true" "设备在线"
eq "$(printf '%s' "$DEVS" | jq '[.[] | select(.kind=="unknown")] | length')" "2" "未收到 miIO 前类型为 unknown"

echo "== 2. 离线阈值与重新上线 =="
printf '192.168.9.11\n' > "$TMP/up"
run scan >/dev/null
run scan >/dev/null
OUT="$(run scan)"
eq "$(jqget "$OUT" '.online')" "1" "连续 3 轮无响应后离线"
eq "$(jqget "$(run devices)" '.[] | select(.mac=="34:ce:00:11:22:33") | .online')" "false" "该设备 online=false"
EV="$(run events 20)"
[ "$(printf '%s' "$EV" | jq '[.[] | select(.type=="offline")] | length')" -ge 1 ] && pass "产生 offline 事件" || fail "缺少 offline 事件"
printf '192.168.9.10\n192.168.9.11\n' > "$TMP/up"
OUT="$(run scan)"
eq "$(jqget "$OUT" '.online')" "2" "恢复响应后重新在线"

echo "== 3. miIO 型号分类与新建 =="
run set miio 1 >/dev/null
cat > "$TMP/miio.json" <<'EOF'
{"devices":[
 {"did":"111","model":"xiaomi.router.r4","ip":"192.168.9.10","mac":"34:CE:00:11:22:33"},
 {"did":"222","model":"yeelink.light.color3","ip":"192.168.9.11","mac":"64:09:80:AA:BB:CC"},
 {"did":"333","model":"chuangmi.plug.v3","ip":"192.168.9.14","mac":"AA:BB:CC:DD:EE:FF"},
 {"did":"444","model":"","ip":"192.168.9.15","mac":"34:CE:00:AA:AA:AA"}
],
 "tsv":"111\u001fxiaomi.router.r4\u001f192.168.9.10\u001f34:CE:00:11:22:33\n222\u001fyeelink.light.color3\u001f192.168.9.11\u001f64:09:80:AA:BB:CC\n333\u001fchuangmi.plug.v3\u001f192.168.9.14\u001fAA:BB:CC:DD:EE:FF\n444\u001f\u001f192.168.9.15\u001f34:CE:00:AA:AA:AA"}
EOF
printf '192.168.9.10\n192.168.9.11\n192.168.9.14\n192.168.9.15\n' > "$TMP/up"
cat > "$TMP/term.json" <<'EOF'
{"data":[
 {"mac":"34:CE:00:11:22:33","ip_addr":"192.168.9.10","hostname":"xiaomi-router-test","client_device":"Xiaomi","client_model":"小米路由器 AX6000","client_type":"Linux","client_typeid":0,"comment":"主路由","apname":"客厅","ssid":"test","signal":"-30"},
 {"mac":"64:09:80:AA:BB:CC","ip_addr":"192.168.9.11","hostname":"yeelink-light-test","client_device":"Xiaomi","client_model":"米家台灯","client_type":"Unknown","client_typeid":0,"comment":"卧室灯","apname":"客厅","ssid":"test","signal":"-40"},
 {"mac":"AA:BB:CC:DD:EE:FF","ip_addr":"192.168.9.14","hostname":"MiAiSoundbox-test","client_device":"Xiaomi","client_model":"小米AI音箱","client_type":"Android","client_typeid":105002002,"comment":"小爱音箱","apname":"客厅","ssid":"test","signal":"-50"}
]}
EOF
OUT="$(run scan)"
eq "$(jqget "$OUT" '.miio')" "4" "收到 4 个 miIO 应答"
eq "$(jqget "$OUT" '.devices')" "4" "miIO 新设备入库"
DEVS="$(run devices)"
eq "$(jqget "$DEVS" '.[] | select(.mac=="34:ce:00:11:22:33") | .kind')" "router" "型号识别为路由器"
eq "$(jqget "$DEVS" '.[] | select(.mac=="64:09:80:aa:bb:cc") | .kind')" "iot" "型号识别为米家设备"
eq "$(jqget "$DEVS" '.[] | select(.mac=="aa:bb:cc:dd:ee:ff") | .vendor')" "miio" "新设备来源标记 miio"
eq "$(jqget "$DEVS" '.[] | select(.mac=="34:ce:00:aa:aa:aa") | .model')" "" "型号为空时字段不错位"
eq "$(jqget "$DEVS" '.[] | select(.mac=="64:09:80:aa:bb:cc") | .model')" "米家台灯" "型号来自 iKuai 终端列表"
eq "$(jqget "$DEVS" '.[] | select(.mac=="64:09:80:aa:bb:cc") | .name')" "卧室灯" "iKuai 备注作为名称"
eq "$(jqget "$DEVS" '.[] | select(.mac=="34:ce:00:11:22:33") | .hostname')" "xiaomi-router-test" "hostname 入库"
eq "$(jqget "$DEVS" '.[] | select(.mac=="aa:bb:cc:dd:ee:ff") | .kind')" "terminal" "AI 音箱按型号归为终端"

echo "== 4. 手动类型保护 =="
run edit 34:ce:00:11:22:33 '客厅 路由' terminal >/dev/null
eq "$(jqget "$(run devices)" '.[] | select(.mac=="34:ce:00:11:22:33") | .kind')" "terminal" "手动改为 terminal"
run scan >/dev/null
eq "$(jqget "$(run devices)" '.[] | select(.mac=="34:ce:00:11:22:33") | .kind')" "terminal" "miIO 不覆盖手动类型"
run edit 34:ce:00:11:22:33 '客厅路由器' auto >/dev/null
eq "$(jqget "$(run devices)" '.[] | select(.mac=="34:ce:00:11:22:33") | .kind')" "router" "auto 重新按型号分类"

echo "== 5. 手动添加/删除/参数校验 =="
run add 12-34-56-78-9a-bc '手动 设备' terminal >/dev/null
eq "$(printf '%s' "$(run devices)" | jq 'length')" "5" "手动添加成功"
run forget 12:34:56:78:9a:bc >/dev/null
eq "$(printf '%s' "$(run devices)" | jq 'length')" "4" "删除成功"
if run add not-a-mac >/dev/null 2>&1; then fail "非法 MAC 应失败"; else pass "非法 MAC 被拒绝"; fi
if run set interval 5 >/dev/null 2>&1; then fail "非法间隔应失败"; else pass "非法间隔被拒绝"; fi

echo "== 6. 状态 JSON、事件、网段扫描 =="
ST="$(run status)"
printf '%s' "$ST" | jq -e . >/dev/null && pass "status 是合法 JSON"
eq "$(jqget "$ST" '.interval')" "60" "默认间隔 60"
RUN="$(run scan --sweep)"
[ "$(jqget "$(run status)" '.last_sweep')" -gt 0 ] && pass "网段扫描写入 last_sweep" || fail "last_sweep 未更新"
[ "$(jqget "$RUN" '.devices')" = "4" ] && pass "--sweep 后设备数稳定" || fail "--sweep 后设备数异常"

echo "== 7. 守护进程 =="
run daemon-start >/dev/null
sleep 1
eq "$(jqget "$(run status)" '.daemon_running')" "true" "守护进程已启动"
run daemon-stop >/dev/null
eq "$(jqget "$(run status)" '.daemon_running')" "false" "守护进程已停止"

echo
echo "全部通过（$PASS 项）"
