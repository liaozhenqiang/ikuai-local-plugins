#!/bin/bash
#
# devmon 本地冒烟：假 ARP / 假 ping / 假 iKuai 终端列表
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$HERE/pkg/bin/devmon"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/devmon-smoke.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

command -v sqlite3 >/dev/null 2>&1 || { echo "需要 sqlite3 在 PATH 里" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "需要 jq 在 PATH 里" >&2; exit 2; }

export DEVMON_DATA="$TMP/data"
export DEVMON_DB="$TMP/data/devmon.db"
export DEVMON_LOG="$TMP/devmon.log"
export DEVMON_ARP_FILE="$TMP/arp"
export DEVMON_PING="$TMP/ping"
export DEVMON_TERM_JSON="$TMP/term.json"
mkdir -p "$DEVMON_DATA"

cat > "$TMP/arp" <<'EOF'
IP address       HW type     Flags       HW address            Mask     Device
192.168.9.50     0x1         0x2         aa:bb:cc:00:00:50     *        br-lan
192.168.9.51     0x1         0x2         aa:bb:cc:00:00:51     *        br-lan
192.168.9.52     0x1         0x2         aa:bb:cc:00:00:52     *        br-lan
192.168.9.53     0x1         0x2         aa:bb:cc:00:00:53     *        br-lan
EOF
cat > "$TMP/term.json" <<'EOF'
{"data":[
 {"mac":"AA:BB:CC:00:00:50","ip_addr":"192.168.9.50","hostname":"cam-1","client_device":"Hikvision","client_model":"摄像头 DS-2CD3T46","client_type":"Linux","client_typeid":109002009,"comment":"门口摄像头","apname":"客厅","ssid":"test","signal":"-40"},
 {"mac":"AA:BB:CC:00:00:51","ip_addr":"192.168.9.51","hostname":"sw-1","client_device":"H3C","client_model":"交换机 S5130","client_type":"Unknown","client_typeid":0,"comment":"弱电箱交换机","apname":"","ssid":"","signal":""},
 {"mac":"AA:BB:CC:00:00:52","ip_addr":"192.168.9.52","hostname":"printer-1","client_device":"HP","client_model":"打印机 M404","client_type":"Unknown","client_typeid":0,"comment":"办公室打印机","apname":"","ssid":"","signal":""}
]}
EOF
cat > "$TMP/ping" <<EOF
#!/bin/bash
ip="\${@: -1}"
grep -qx "\$ip" "$TMP/up" 2>/dev/null && exit 0
exit 1
EOF
chmod +x "$TMP/ping"
printf '192.168.9.50\n192.168.9.51\n192.168.9.52\n' > "$TMP/up"

PASS=0
pass() { PASS=$((PASS + 1)); echo "  ok  $1"; }
fail() { echo "  FAIL $1" >&2; tail -20 "$DEVMON_LOG" 2>/dev/null >&2 || true; exit 1; }
eq() { [ "$1" = "$2" ] && pass "$3" || fail "$3 (got '$1', want '$2')"; }
jqget() { printf '%s' "$1" | jq -r "$2"; }
run() { bash "$BIN" "$@"; }

echo "== 1. 手动添加与清单 =="
run init >/dev/null
run save aa:bb:cc:00:00:50 192.168.9.50 camera 门口摄像头 Hikvision "摄像头 DS-2CD3T46" cam-1 门口 "门禁旁" http://192.168.9.50 80,554 1 >/dev/null
DEVS="$(run devices all)"
eq "$(printf '%s' "$DEVS" | jq 'length')" "1" "添加一台设备"
eq "$(jqget "$DEVS" '.[0].category')" "camera" "类别 camera"
eq "$(jqget "$DEVS" '.[0].model')" "摄像头 DS-2CD3T46" "型号保存"
eq "$(jqget "$DEVS" '.[0].url')" "http://192.168.9.50" "链接保存"

echo "== 2. 局域网发现 =="
CAND="$(run scan)"
eq "$(printf '%s' "$CAND" | jq 'length')" "4" "ARP + 终端列表共 4 台"
eq "$(jqget "$CAND" '.[] | select(.mac=="aa:bb:cc:00:00:50") | .managed')" "true" "已管理标记"
eq "$(jqget "$CAND" '.[] | select(.mac=="aa:bb:cc:00:00:51") | .model')" "交换机 S5130" "终端列表型号"
eq "$(jqget "$CAND" '.[] | select(.mac=="aa:bb:cc:00:00:51") | .online')" "true" "终端列表在线"
eq "$(jqget "$CAND" '.[] | select(.mac=="aa:bb:cc:00:00:53") | .model')" "" "ARP-only 型号为空"

echo "== 3. 导入交换机/打印机 =="
run save aa:bb:cc:00:00:51 192.168.9.51 switch 弱电箱交换机 H3C "交换机 S5130" sw-1 弱电箱 "" http://192.168.9.51 22,80 1 >/dev/null
run save aa:bb:cc:00:00:52 192.168.9.52 peripheral 办公室打印机 HP "打印机 M404" printer-1 办公室 "" "" "" 1 >/dev/null
DEVS="$(run devices all)"
eq "$(printf '%s' "$DEVS" | jq 'length')" "3" "三台设备入库"
eq "$(jqget "$DEVS" '[.[] | select(.category=="switch")] | length')" "1" "交换机类别"
eq "$(jqget "$DEVS" '[.[] | select(.category=="peripheral")] | length')" "1" "周边设备类别"

echo "== 4. 在线检测 =="
run observe >/dev/null
ST="$(run status)"
eq "$(jqget "$ST" '.online')" "3" "三台在线"
eq "$(jqget "$ST" '.camera')" "1" "状态分类 camera"
run set offline_after 2 >/dev/null
printf '192.168.9.50\n192.168.9.52\n' > "$TMP/up"
cat > "$TMP/term.json" <<'EOF'
{"data":[
 {"mac":"AA:BB:CC:00:00:50","ip_addr":"192.168.9.50","hostname":"cam-1","client_device":"Hikvision","client_model":"摄像头 DS-2CD3T46","client_type":"Linux","client_typeid":109002009,"comment":"门口摄像头","apname":"客厅","ssid":"test","signal":"-40"},
 {"mac":"AA:BB:CC:00:00:52","ip_addr":"192.168.9.52","hostname":"printer-1","client_device":"HP","client_model":"打印机 M404","client_type":"Unknown","client_typeid":0,"comment":"办公室打印机","apname":"","ssid":"","signal":""}
]}
EOF
run observe >/dev/null
run observe >/dev/null
eq "$(jqget "$(run devices all)" '.[] | select(.mac=="aa:bb:cc:00:00:51") | .online')" "false" "连续 2 轮无响应后离线"
EV="$(run events 20)"
[ "$(printf '%s' "$EV" | jq '[.[] | select(.type=="offline")] | length')" -ge 1 ] && pass "产生 offline 事件" || fail "缺少 offline 事件"

echo "== 5. 暂停/删除/参数校验 =="
run toggle aa:bb:cc:00:00:52 0 >/dev/null
eq "$(jqget "$(run status)" '.paused')" "1" "暂停计数"
run forget aa:bb:cc:00:00:52 >/dev/null
eq "$(printf '%s' "$(run devices all)" | jq 'length')" "2" "删除成功"
if run save aa:bb:cc:00:00:53 192.168.9.53 badge x >/dev/null 2>&1; then fail "非法类别应失败"; else pass "非法类别被拒绝"; fi
if run save aa:bb:cc:00:00:53 192.168.9.53 camera x v m h l n u 80,abc 1 >/dev/null 2>&1; then fail "非法端口应失败"; else pass "非法端口被拒绝"; fi
if run save not-a-mac 192.168.9.53 camera x >/dev/null 2>&1; then fail "非法 MAC 应失败"; else pass "非法 MAC 被拒绝"; fi

echo "== 6. 自动收录 =="
# .53 是终端列表里没见过的新设备；.52 刚被删除，应留在忽略名单里
cat > "$TMP/term.json" <<'EOF'
{"data":[
 {"mac":"AA:BB:CC:00:00:50","ip_addr":"192.168.9.50","hostname":"cam-1","client_device":"Hikvision","client_model":"摄像头 DS-2CD3T46","client_type":"Linux","client_typeid":109002009,"comment":"门口摄像头","apname":"客厅","ssid":"test","signal":"-40"},
 {"mac":"AA:BB:CC:00:00:51","ip_addr":"192.168.9.51","hostname":"sw-1","client_device":"H3C","client_model":"交换机 S5130","client_type":"Unknown","client_typeid":0,"comment":"弱电箱交换机","apname":"","ssid":"","signal":""},
 {"mac":"AA:BB:CC:00:00:52","ip_addr":"192.168.9.52","hostname":"printer-1","client_device":"HP","client_model":"打印机 M404","client_type":"Unknown","client_typeid":0,"comment":"办公室打印机","apname":"","ssid":"","signal":""},
 {"mac":"AA:BB:CC:00:00:53","ip_addr":"192.168.9.53","hostname":"ap-1","client_device":"Xiaomi","client_model":"路由器 AX3000","client_type":"Linux","client_typeid":0,"comment":"客厅AP","apname":"","ssid":"","signal":""}
]}
EOF
printf '192.168.9.50\n192.168.9.51\n192.168.9.52\n192.168.9.53\n' > "$TMP/up"
run observe >/dev/null
DEVS="$(run devices all)"
eq "$(printf '%s' "$DEVS" | jq 'length')" "3" "新设备入库、已删除设备不复活"
eq "$(jqget "$DEVS" '.[] | select(.mac=="aa:bb:cc:00:00:53") | .category')" "peripheral" "自动收录为周边设备"
eq "$(jqget "$DEVS" '.[] | select(.mac=="aa:bb:cc:00:00:53") | .name')" "客厅AP" "自动取名称（终端备注优先）"
eq "$(jqget "$DEVS" '.[] | select(.mac=="aa:bb:cc:00:00:53") | .source')" "auto" "来源标记 auto"
[ "$(printf '%s' "$(run events 30)" | jq '[.[] | select(.type=="new" and .detail=="auto")] | length')" -ge 1 ] && pass "产生 auto 新增事件" || fail "缺少 auto 新增事件"

run set auto_add 0 >/dev/null
cat > "$TMP/term.json" <<'EOF'
{"data":[
 {"mac":"AA:BB:CC:00:00:50","ip_addr":"192.168.9.50","hostname":"cam-1","client_device":"Hikvision","client_model":"摄像头 DS-2CD3T46","client_type":"Linux","client_typeid":109002009,"comment":"门口摄像头","apname":"客厅","ssid":"test","signal":"-40"},
 {"mac":"AA:BB:CC:00:00:54","ip_addr":"192.168.9.54","hostname":"nas-1","client_device":"Unknown","client_model":"","client_type":"Linux","client_typeid":0,"comment":"","apname":"","ssid":"","signal":""}
]}
EOF
printf '192.168.9.50\n192.168.9.54\n' > "$TMP/up"
run observe >/dev/null
eq "$(printf '%s' "$(run devices all)" | jq 'length')" "3" "关掉开关后不再自动收录"
run set auto_add 1 >/dev/null
run observe >/dev/null
eq "$(printf '%s' "$(run devices all)" | jq '[.[] | select(.mac=="aa:bb:cc:00:00:54")] | length')" "1" "重新打开后继续收录"
eq "$(jqget "$(run devices all)" '.[] | select(.mac=="aa:bb:cc:00:00:54") | .name')" "nas-1" "无备注时退回 hostname"

# .55 手工加了但品牌/型号/名称留空，观察一轮应由终端列表补全（不覆盖已有值）
run save aa:bb:cc:00:00:55 192.168.9.55 camera "" "" "" "" "" "" "" "" 1 >/dev/null
cat > "$TMP/term.json" <<'EOF'
{"data":[
 {"mac":"AA:BB:CC:00:00:55","ip_addr":"192.168.9.55","hostname":"cam-2","client_device":"Uniview","client_model":"IPC-H2","client_type":"Linux","client_typeid":0,"comment":"车库摄像头","apname":"","ssid":"","signal":""}
]}
EOF
printf '192.168.9.55\n' > "$TMP/up"
run observe >/dev/null
D55="$(jq -c '.[] | select(.mac=="aa:bb:cc:00:00:55")' <<< "$(run devices all)")"
eq "$(printf '%s' "$D55" | jq -r '.vendor')" "Uniview" "补全空品牌"
eq "$(printf '%s' "$D55" | jq -r '.name')" "车库摄像头" "补全空名称"
eq "$(printf '%s' "$D55" | jq -r '.category')" "camera" "补全时不改类别"

echo "== 7. 守护进程 =="
run daemon-start >/dev/null
sleep 1
eq "$(jqget "$(run status)" '.daemon_running')" "true" "守护进程已启动"
run daemon-stop >/dev/null
eq "$(jqget "$(run status)" '.daemon_running')" "false" "守护进程已停止"

echo
echo "全部通过（$PASS 项）"
