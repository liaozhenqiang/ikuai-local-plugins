#!/bin/bash
# 在设备上对隔离副本验证 menu_patch.sh：三入口(现状) -> 单入口 -> 幂等 -> 回滚
set -u
NEW=/tmp/mp_new.sh
IK=/tmp/mp/ikwww
ORIG=/tmp/mp/stock
DATA=/tmp/mp/data
EULA=/tmp/mp/eula

rm -rf /tmp/mp; mkdir -p "$IK/json" "$IK/static/js" "$IK/static/i18n" "$DATA"
printf 'accepted=1\n' > "$EULA"

LIVE_JS=$(ls /usr/ikuai/www/static/js/app.*.js.gz | head -1)
JSNAME=$(basename "$LIVE_JS")
cp -f "$LIVE_JS" "$IK/static/js/$JSNAME"
cp -f /usr/ikuai/www/index.html "$IK/index.html"
cp -f /usr/ikuai/www/json/menu.json "$IK/json/menu.json"
for b in zh-CN.json zh-TW.json en-US.json; do
    cp -f "/usr/ikuai/www/static/i18n/$b" "$IK/static/i18n/$b" 2>/dev/null
done
cp -a "$IK" "$ORIG"

export IK_WWW="$IK" DEVMON_DATA="$DATA" PLUGIN_EULA="$EULA" PLUGIN_DIR=/etc/mnt/plugins/devmon

P_CAM='name:"devmon-camera"'
P_SW='name:"devmon-switch"'
P_PER='name:"devmon-peripheral"'
P_SRC='src:"/plugins/app/devmon.html",'
P_OLD='devmon.html?cat='

cnt() { grep -Fc -- "$1" "$2" 2>/dev/null | head -n1; }
jsroutes() { printf 'cam=%s sw=%s per=%s old-cat-src=%s new-src=%s\n' \
    "$(cnt "$P_CAM" "$1")" "$(cnt "$P_SW" "$1")" "$(cnt "$P_PER" "$1")" "$(cnt "$P_OLD" "$1")" "$(cnt "$P_SRC" "$1")"; }
menustate() { printf 'cam=%s sw=%s per=%s kids=%s\n' \
    "$(jq '[..|objects|select(.label?=="system-setting.system-status.camera-monitoring")]|length' "$IK/json/menu.json")" \
    "$(jq '[..|objects|select(.label?=="system-setting.system-status.Switch-monitoring")]|length' "$IK/json/menu.json")" \
    "$(jq -r '[..|objects|select(.label?=="tools.instrumented")|.linkTo]|.[0]|tostring' "$IK/json/menu.json")" \
    "$(jq '[.[]|select(.label=="system-setting.system-status.system-status").children[]]|length' "$IK/json/menu.json")"; }

echo "== BEFORE (3 entries) =="
echo "menu: $(menustate)"
zcat "$IK/static/js/$JSNAME" > "$DATA/before.js"; echo "routes: $(jsroutes "$DATA/before.js")"

echo "== apply #1 =="
bash "$NEW" apply
echo "rc=$?"
zcat "$IK/static/js/$JSNAME" > "$DATA/after.js"; echo "routes: $(jsroutes "$DATA/after.js")"
echo "menu: $(menustate)"

echo "== apply #2 idempotent =="
bash "$NEW" apply
zcat "$IK/static/js/$JSNAME" > "$DATA/again.js"
echo "routes: $(jsroutes "$DATA/again.js")  same-as-#1: $(cmp -s "$DATA/after.js" "$DATA/again.js" && echo yes || echo no)"
echo "menu: $(menustate)"

echo "== remove rollback =="
bash "$NEW" remove
cmp -s "$ORIG/static/js/$JSNAME" "$IK/static/js/$JSNAME" && echo "app.js restored" || echo "app.js NOT restored"
cmp -s "$ORIG/json/menu.json" "$IK/json/menu.json" && echo "menu.json restored" || echo "menu.json NOT restored"
echo "menu: $(menustate)"

echo "== BACKUP (should be stock) =="
ls -l "$DATA/menu-backup" | tail -6
zcat "$DATA/menu-backup/app.js.gz" > "$DATA/bk.js" 2>/dev/null; echo "backup routes: $(jsroutes "$DATA/bk.js")"
echo "backup menu: $(jq '[..|objects|select(.linkTo?=="devmon-peripheral")]|length' "$DATA/menu-backup/menu.json")"
echo DONE
