#!/bin/bash
#
# menu_patch.sh —— 把「米家面板」挂进爱快左侧「高级应用」菜单，点开即用。
#
# 做三件事（都可幂等重复执行）：
#   1) app.<hash>.js.gz 里插入一条 iframe 路由 miot-panel
#   2) menu.json 的 advanced.advanced 子项里，"插件管理" 后面插一条 miot.miot-panel
#   3) i18n 三个语言文件补上 left-menu.miot.miot-panel 与 page-title.miot.panel
#
# 根分区每次重启还原，所以 boot.sh 会重新 apply；备份写在 data/menu-backup（只写一次，
# 永远是 stock 版本），卸载时整体恢复。
#
# 与其它插件（如 devmon）共存：两边都插在同一个路由锚点前，各自只删自己的路由，
# 互不影响；备份各存各的。
#
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PLUGIN_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
DATA="${MIOT_PANEL_DATA:-$ROOT/data}"
IK_WWW="${IK_WWW:-/usr/ikuai/www}"
MENU="$IK_WWW/json/menu.json"
I18N_DIR="$IK_WWW/static/i18n"
JS_DIR="$IK_WWW/static/js"
BACKUP="$DATA/menu-backup"

MODE="${1:-apply}"

ANCHOR='{path:"system-setting/plugin-management",name:"system-setting-plugin-management",'
ROUTE='{path:"advanced/miot-panel",name:"miot-panel",component:{render:function(e){return e("iframe",{attrs:{src:"/plugins/app/miot-panel.html",frameborder:"0"},style:{width:"100%",height:"calc(100vh - 183px)",border:"0"}})}},meta:{title:"miot.panel"}},'

LABEL_NEW='miot.miot-panel'
LINK_NEW='miot-panel'
ANCHOR_LABEL='system-setting.plugin-management'

log() { printf '%s [menu] %s\n' "$(date '+%F %T')" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }
JQ="$(command -v jq 2>/dev/null || echo /usr/sbin/jq)"

atomic_write() {
    local src="$1" dst="$2" staged
    staged="$(mktemp "${dst%/*}/.miotp.XXXXXX" 2>/dev/null)" || return 1
    if cat "$src" > "$staged" 2>/dev/null && chmod 644 "$staged" 2>/dev/null && mv -f "$staged" "$dst" 2>/dev/null; then
        return 0
    fi
    rm -f "$staged"
    return 1
}

keep_backup() {
    local src="$1" dst="$2"
    [ -f "$dst" ] && return 0
    mkdir -p "${dst%/*}" 2>/dev/null || return 1
    cp -f "$src" "$dst" 2>/dev/null
}

reload_web() {
    have openresty || { log "未找到 openresty，跳过 reload"; return 0; }
    openresty -s reload >/dev/null 2>&1 && log "已 reload openresty" || log "openresty reload 失败"
    return 0
}

app_js() {
    local ref
    ref="$(grep -o 'app\.[a-f0-9]*\.js' "$IK_WWW/index.html" 2>/dev/null | head -n1)"
    if [ -n "$ref" ] && [ -f "$JS_DIR/${ref}.gz" ]; then
        printf '%s' "$JS_DIR/${ref}.gz"
        return 0
    fi
    ls "$JS_DIR"/app.*.js.gz 2>/dev/null | head -n1
}

route_count() {
    grep -Fo "$ROUTE" "$1" 2>/dev/null | wc -l | tr -d ' '
}

apply_route() {
    local js tmp clean new gz anchor_n
    have gzip && have zcat || { log "缺少 gzip/zcat"; return 1; }
    js="$(app_js)"
    [ -n "$js" ] && [ -f "$js" ] || { log "找不到 app.js.gz"; return 1; }
    tmp="$(mktemp)" || return 1
    clean="$(mktemp)" || { rm -f "$tmp"; return 1; }
    new="$(mktemp)" || { rm -f "$tmp" "$clean"; return 1; }
    gz="$(mktemp)" || { rm -f "$tmp" "$clean" "$new"; return 1; }
    if ! zcat "$js" > "$tmp" 2>/dev/null; then
        log "解压 app.js 失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1
    fi
    if [ "$(route_count "$tmp")" = "1" ]; then
        log "SPA 路由已存在"; rm -f "$tmp" "$clean" "$new" "$gz"; return 0
    fi
    # 先删掉历史插入的副本，再统一插一条，保证幂等
    if ! sed -e "s|$ROUTE||g" "$tmp" > "$clean" 2>/dev/null; then
        log "清理历史路由失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1
    fi
    anchor_n="$(grep -Fo "$ANCHOR" "$clean" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$anchor_n" = "1" ] || { log "找不到路由锚点（plugin-management），跳过"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    sed "s|$ANCHOR|$ROUTE&|" "$clean" > "$new" 2>/dev/null || { log "插入路由失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    [ "$(route_count "$new")" = "1" ] || { log "路由插入校验失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    gzip -9 -c < "$new" > "$gz" 2>/dev/null && gzip -t "$gz" 2>/dev/null || { log "压缩失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    keep_backup "$js" "$BACKUP/app.js.gz" || { log "备份 app.js 失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    atomic_write "$gz" "$js" || { log "写入 app.js 失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    zcat "$js" > "$new" 2>/dev/null
    if [ "$(route_count "$new")" != "1" ]; then
        atomic_write "$BACKUP/app.js.gz" "$js" 2>/dev/null
        log "写回校验失败，已还原"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1
    fi
    log "SPA 路由已插入 miot-panel"
    rm -f "$tmp" "$clean" "$new" "$gz"
    return 0
}

menu_state() {
    "$JQ" -r '[.[] | select(.label=="advanced.advanced") | .children[]? | select(.label=="'"$LABEL_NEW"'") ] | length' "$MENU" 2>/dev/null
}

apply_menu() {
    local tmp n
    [ -f "$MENU" ] || { log "未找到 menu.json，跳过"; return 1; }
    n="$(menu_state)"
    if [ "$n" = "1" ]; then log "菜单项已存在"; return 0; fi
    tmp="$(mktemp)" || return 1
    # 设备上是 jq 1.4：不能用 any(.[]; ...) / reduce，这里用 map+select 的等价写法
    "$JQ" '
        map(if .label == "advanced.advanced" then
              .children |= (
                [ .[] | select(.label != "'"$LABEL_NEW"'") ]
                | [ .[] | ., (if .label == "'"$ANCHOR_LABEL"'"
                              then {"label":"'"$LABEL_NEW"'","linkTo":"'"$LINK_NEW"'"}
                              else empty end) ]
                | if (map(select(.label == "'"$LABEL_NEW"'")) | length) > 0 then .
                  else . + [{"label":"'"$LABEL_NEW"'","linkTo":"'"$LINK_NEW"'"}] end
              )
            else . end)
    ' "$MENU" > "$tmp" 2>/dev/null || { log "菜单 jq 失败"; rm -f "$tmp"; return 1; }
    "$JQ" -e . "$tmp" >/dev/null 2>&1 || { log "菜单输出非法，跳过"; rm -f "$tmp"; return 1; }
    keep_backup "$MENU" "$BACKUP/menu.json" || { log "备份 menu.json 失败"; rm -f "$tmp"; return 1; }
    "$JQ" -e . "$BACKUP/menu.json" >/dev/null 2>&1 || { log "stock 备份不可用，跳过"; rm -f "$tmp"; return 1; }
    atomic_write "$tmp" "$MENU" || { log "写入 menu.json 失败"; rm -f "$tmp"; return 1; }
    if [ "$(menu_state)" != "1" ]; then
        atomic_write "$BACKUP/menu.json" "$MENU" 2>/dev/null
        log "菜单写回校验失败，已还原"; rm -f "$tmp"; return 1
    fi
    log "菜单已插入「米家面板」"
    rm -f "$tmp"
    return 0
}

apply_i18n() {
    local f base label title tmp
    for f in "$I18N_DIR"/zh-CN.json "$I18N_DIR"/zh-TW.json "$I18N_DIR"/en-US.json; do
        [ -f "$f" ] || continue
        base="${f##*/}"
        case "$base" in
            zh-TW.json) label="米家面板"; title="米家面板" ;;
            en-US.json) label="Mi Home Panel"; title="Mi Home Panel" ;;
            *)          label="米家面板"; title="米家面板" ;;
        esac
        if "$JQ" -e --arg l "$label" --arg t "$title" \
            '.["left-menu"]["miot"]["miot-panel"] == $l and .["page-title"]["miot"]["panel"] == $t' \
            "$f" >/dev/null 2>&1; then
            continue
        fi
        tmp="$(mktemp)" || continue
        if ! "$JQ" --arg l "$label" --arg t "$title" \
            '.["left-menu"]["miot"]["miot-panel"] = $l | .["page-title"]["miot"]["panel"] = $t' \
            "$f" > "$tmp" 2>/dev/null; then
            log "i18n 结构不匹配，跳过: $base"; rm -f "$tmp"; continue
        fi
        "$JQ" -e . "$tmp" >/dev/null 2>&1 || { log "i18n 输出非法: $base"; rm -f "$tmp"; continue; }
        keep_backup "$f" "$BACKUP/$base" || { rm -f "$tmp"; continue; }
        atomic_write "$tmp" "$f" && log "已加菜单文案: $base" || log "写入 i18n 失败: $base"
        rm -f "$tmp"
    done
    return 0
}

restore_backups() {
    local js f base ok=0
    [ -d "$BACKUP" ] || { log "没有备份可恢复"; return 1; }
    if [ -f "$BACKUP/app.js.gz" ]; then
        js="$(app_js)"
        [ -n "$js" ] && gzip -t "$BACKUP/app.js.gz" 2>/dev/null && atomic_write "$BACKUP/app.js.gz" "$js" && ok=1
    fi
    if [ -f "$BACKUP/menu.json" ] && "$JQ" -e . "$BACKUP/menu.json" >/dev/null 2>&1; then
        atomic_write "$BACKUP/menu.json" "$MENU" && ok=1
    fi
    for base in zh-CN.json zh-TW.json en-US.json; do
        f="$I18N_DIR/$base"
        [ -f "$BACKUP/$base" ] && "$JQ" -e . "$BACKUP/$base" >/dev/null 2>&1 || continue
        atomic_write "$BACKUP/$base" "$f" && ok=1
    done
    reload_web
    return $((1 - ok))
}

case "$MODE" in
    apply)
        [ -f "$MENU" ] || { log "未找到 menu.json，跳过"; exit 0; }
        have gzip || { log "缺少 gzip，跳过"; exit 0; }
        [ -x "$JQ" ] || { "$JQ" --version >/dev/null 2>&1 || { log "缺少 jq，跳过"; exit 0; } }
        mkdir -p "$BACKUP" 2>/dev/null || { log "无法创建备份目录"; exit 0; }
        if ! apply_route; then
            log "路由补丁未生效，不修改菜单"
            exit 0
        fi
        apply_i18n
        apply_menu
        reload_web
        log "完成；后台已打开时请关闭标签页重开 + Ctrl+F5"
        exit 0
        ;;
    remove)
        restore_backups || log "备份缺失，重启后根分区自动还原"
        exit 0
        ;;
    *)
        echo "用法: $0 apply|remove" >&2
        exit 1
        ;;
esac
