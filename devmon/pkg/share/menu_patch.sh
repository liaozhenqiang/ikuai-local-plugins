#!/bin/bash
#
# menu_patch.sh —— 把三个云平台监控页合并成一个本地「周边设备监控」入口
#
#   状态监控 -> 摄像头监控   : 删除菜单项（原 system-setting-camera-monitoring）
#   状态监控 -> 交换机监控   : 删除菜单项（原 system-setting-Switch-monitoring）
#   状态监控 -> 周边设备监控 : 指向本地页面（原 tools-instrumented）
#
# 做三件事：
#   1) app.<hash>.js.gz 加一个 iframe 路由 devmon-peripheral（并清掉旧版残留的三条路由）
#   2) menu.json 删掉摄像头/交换机两个叶子，把周边设备监控的 linkTo 指向该路由
#   3) i18n 加页面标题（page-title.devmon.*）
#
# 根分区重启还原，所以 boot.sh 每次重打；备份在插件 data/menu-backup（只写一次，
# 保证里面永远是 stock 版本），卸载时整体恢复。
#
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PLUGIN_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
DATA="${DEVMON_DATA:-$ROOT/data}"
IK_WWW="${IK_WWW:-/usr/ikuai/www}"
MENU="$IK_WWW/json/menu.json"
I18N_DIR="$IK_WWW/static/i18n"
JS_DIR="$IK_WWW/static/js"
BACKUP="$DATA/menu-backup"

MODE="${1:-apply}"

ANCHOR='{path:"system-setting/plugin-management",name:"system-setting-plugin-management",'
# 当前版本只加这一条路由（页面不再按类别过滤，一个入口看全部设备）
ROUTE_PER='{path:"system-setting/devmon-peripheral",name:"devmon-peripheral",component:{render:function(e){return e("iframe",{attrs:{src:"/plugins/app/devmon.html",frameborder:"0"},style:{width:"100%",height:"calc(100vh - 183px)",border:"0"}})}},meta:{title:"devmon.peripheral"}},'
# 旧版本（三个入口）与本版本已插入过的字面量，打补丁前一律先删掉再插入，保证幂等
OLD_CAM='{path:"system-setting/devmon-camera",name:"devmon-camera",component:{render:function(e){return e("iframe",{attrs:{src:"/plugins/app/devmon.html?cat=camera",frameborder:"0"},style:{width:"100%",height:"calc(100vh - 183px)",border:"0"}})}},meta:{title:"devmon.camera"}},'
OLD_SW='{path:"system-setting/devmon-switch",name:"devmon-switch",component:{render:function(e){return e("iframe",{attrs:{src:"/plugins/app/devmon.html?cat=switch",frameborder:"0"},style:{width:"100%",height:"calc(100vh - 183px)",border:"0"}})}},meta:{title:"devmon.switch"}},'
OLD_PER='{path:"system-setting/devmon-peripheral",name:"devmon-peripheral",component:{render:function(e){return e("iframe",{attrs:{src:"/plugins/app/devmon.html?cat=peripheral",frameborder:"0"},style:{width:"100%",height:"calc(100vh - 183px)",border:"0"}})}},meta:{title:"devmon.peripheral"}},'

LABEL_CAM='system-setting.system-status.camera-monitoring'
LABEL_SW='system-setting.system-status.Switch-monitoring'
LABEL_PER='tools.instrumented'
ORIG_PER='tools-instrumented'

log() { printf '%s [menu] %s\n' "$(date '+%F %T')" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

atomic_write() {
    local src="$1" dst="$2" staged
    staged="$(mktemp "${dst%/*}/.devmon.XXXXXX" 2>/dev/null)" || return 1
    if cat "$src" > "$staged" 2>/dev/null && chmod 644 "$staged" 2>/dev/null && mv -f "$staged" "$dst" 2>/dev/null; then
        return 0
    fi
    rm -f "$staged"
    return 1
}

reload_web() {
    if ! have openresty; then
        log "未找到 openresty，跳过 Web reload"
        return 0
    fi
    if openresty -s reload >/dev/null 2>&1; then
        log "已 reload openresty（刷新菜单缓存）"
    else
        log "openresty reload 失败（Web 服务未运行？）"
    fi
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

# 备份只写一次：保证 backup 里永远是未改动的 stock 版本
keep_backup() {
    local src="$1" dst="$2"
    [ -f "$dst" ] && return 0
    mkdir -p "${dst%/*}" 2>/dev/null || return 1
    cp -f "$src" "$dst" 2>/dev/null
}

routes_state() {
    local js="$1" nper ncam nsw nold
    nper="$(grep -Fo "$ROUTE_PER" "$js" 2>/dev/null | wc -l | tr -d ' ')"
    nold="$(grep -Fo "$OLD_PER" "$js" 2>/dev/null | wc -l | tr -d ' ')"
    ncam="$(grep -Fo 'name:"devmon-camera"' "$js" 2>/dev/null | wc -l | tr -d ' ')"
    nsw="$(grep -Fo 'name:"devmon-switch"' "$js" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$nper" = "1" ] && [ "$nold" = "0" ] && [ "$ncam" = "0" ] && [ "$nsw" = "0" ]; then
        echo patched
    else
        echo "todo(per=$nper,old=$nold,cam=$ncam,sw=$nsw)"
    fi
}

apply_route() {
    local js tmp clean new gz st anchor_n
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
    st="$(routes_state "$tmp")"
    if [ "$st" = "patched" ]; then
        log "SPA 路由已是单入口"; rm -f "$tmp" "$clean" "$new" "$gz"; return 0
    fi

    # 先删掉旧版三条路由与本路由的历史写法，再统一插入，重复执行结果一致
    if ! sed -e "s|$OLD_CAM||g" -e "s|$OLD_SW||g" -e "s|$OLD_PER||g" -e "s|$ROUTE_PER||g" \
        "$tmp" > "$clean" 2>/dev/null; then
        log "清理历史路由失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1
    fi
    anchor_n="$(grep -Fo "$ANCHOR" "$clean" 2>/dev/null | wc -l | tr -d ' ')"
    [ "$anchor_n" = "1" ] || { log "找不到路由锚点，跳过"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    sed "s|$ANCHOR|$ROUTE_PER&|" "$clean" > "$new" 2>/dev/null || { log "插入路由失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    [ "$(routes_state "$new")" = "patched" ] || { log "路由插入校验失败: $(routes_state "$new")"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    gzip -9 -c < "$new" > "$gz" 2>/dev/null && gzip -t "$gz" 2>/dev/null || { log "压缩失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    keep_backup "$js" "$BACKUP/app.js.gz" || { log "备份 app.js 失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    atomic_write "$gz" "$js" || { log "写入 app.js 失败"; rm -f "$tmp" "$clean" "$new" "$gz"; return 1; }
    zcat "$js" > "$new" 2>/dev/null
    if [ "$(routes_state "$new")" != "patched" ]; then
        atomic_write "$BACKUP/app.js.gz" "$js" 2>/dev/null
        log "写回校验失败，已还原"
        rm -f "$tmp" "$clean" "$new" "$gz"
        return 1
    fi
    log "SPA 路由已合并为单入口 devmon-peripheral"
    rm -f "$tmp" "$clean" "$new" "$gz"
    return 0
}

menu_state() {
    local ncam nsw per
    ncam="$(jq '[.. | objects | select(.label? == "'"$LABEL_CAM"'")] | length' "$MENU" 2>/dev/null)"
    nsw="$(jq '[.. | objects | select(.label? == "'"$LABEL_SW"'")] | length' "$MENU" 2>/dev/null)"
    per="$(jq -r '[.. | objects | select(.label? == "'"$LABEL_PER"'") | .linkTo] | .[0] // "-"' "$MENU" 2>/dev/null)"
    if [ "$ncam" = "0" ] && [ "$nsw" = "0" ] && [ "$per" = "devmon-peripheral" ]; then
        echo patched
    else
        echo "cam=${ncam:-?},sw=${nsw:-?},per=${per:-?}"
    fi
}

apply_menu() {
    local st tmp
    st="$(menu_state)"
    if [ "$st" = "patched" ]; then log "菜单已是单入口"; return 0; fi
    tmp="$(mktemp)" || return 1
    jq '
        map(if .label == "system-setting.system-status.system-status" then
              .children |= ( map(select(.label != "'"$LABEL_CAM"'" and .label != "'"$LABEL_SW"'"))
                             | map(if .label == "'"$LABEL_PER"'" then .linkTo = "devmon-peripheral" else . end) )
            else . end)
    ' "$MENU" > "$tmp" 2>/dev/null || { log "菜单 jq 失败"; rm -f "$tmp"; return 1; }
    jq -e . "$tmp" >/dev/null 2>&1 || { log "菜单 jq 输出非法，跳过"; rm -f "$tmp"; return 1; }
    keep_backup "$MENU" "$BACKUP/menu.json" || { log "备份 menu.json 失败"; rm -f "$tmp"; return 1; }
    jq -e . "$BACKUP/menu.json" >/dev/null 2>&1 || { log "stock 菜单备份不可用，跳过"; rm -f "$tmp"; return 1; }
    atomic_write "$tmp" "$MENU" || { log "写入 menu.json 失败"; rm -f "$tmp"; return 1; }
    if [ "$(menu_state)" != "patched" ]; then
        atomic_write "$BACKUP/menu.json" "$MENU" 2>/dev/null
        log "菜单写回校验失败，已还原"
        rm -f "$tmp"
        return 1
    fi
    log "菜单已合并：只保留「周边设备监控」指向本地页面"
    rm -f "$tmp"
    return 0
}

apply_i18n() {
    local f base c s p tmp
    for f in "$I18N_DIR"/zh-CN.json "$I18N_DIR"/zh-TW.json "$I18N_DIR"/en-US.json; do
        [ -f "$f" ] || continue
        base="${f##*/}"
        case "$base" in
            zh-TW.json) c="攝像頭監控"; s="交換機監控"; p="周邊設備監控" ;;
            en-US.json) c="Camera Monitoring"; s="Switch Monitoring"; p="Peripheral Monitoring" ;;
            *)          c="摄像头监控"; s="交换机监控"; p="周边设备监控" ;;
        esac
        if jq -e --arg c "$c" --arg s "$s" --arg p "$p" \
            '.["page-title"]["devmon"]["camera"] == $c and .["page-title"]["devmon"]["switch"] == $s and .["page-title"]["devmon"]["peripheral"] == $p' \
            "$f" >/dev/null 2>&1; then
            log "页面标题已存在: $base"
            continue
        fi
        tmp="$(mktemp)" || continue
        if ! jq --arg c "$c" --arg s "$s" --arg p "$p" \
            '.["page-title"]["devmon"]["camera"] = $c | .["page-title"]["devmon"]["switch"] = $s | .["page-title"]["devmon"]["peripheral"] = $p' \
            "$f" > "$tmp" 2>/dev/null; then
            log "i18n 结构不匹配，跳过: $base"
            rm -f "$tmp"
            continue
        fi
        if ! jq -e --arg c "$c" --arg s "$s" --arg p "$p" \
            '.["page-title"]["devmon"]["camera"] == $c and .["page-title"]["devmon"]["switch"] == $s and .["page-title"]["devmon"]["peripheral"] == $p' \
            "$tmp" >/dev/null 2>&1; then
            log "i18n 生成校验失败，跳过: $base"
            rm -f "$tmp"
            continue
        fi
        mkdir -p "$BACKUP" 2>/dev/null || { rm -f "$tmp"; continue; }
        cp -f "$f" "$BACKUP/$base" 2>/dev/null || { rm -f "$tmp"; continue; }
        if atomic_write "$tmp" "$f"; then
            log "已加页面标题: $base"
        else
            log "写入 i18n 失败: $base"
        fi
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
    if [ -f "$BACKUP/menu.json" ] && jq -e . "$BACKUP/menu.json" >/dev/null 2>&1; then
        atomic_write "$BACKUP/menu.json" "$MENU" && ok=1
    fi
    for base in zh-CN.json zh-TW.json en-US.json; do
        f="$I18N_DIR/$base"
        [ -f "$BACKUP/$base" ] && jq -e . "$BACKUP/$base" >/dev/null 2>&1 || continue
        atomic_write "$BACKUP/$base" "$f" && ok=1
    done
    reload_web
    return $((1 - ok))
}

# 备份缺失时的兜底：只能把「周边设备监控」的链接改回云页面；
# 被删掉的摄像头/交换机两个叶子要靠重启（根分区还原）才会回来。
remove_menu_links() {
    local tmp
    tmp="$(mktemp)" || return 1
    jq '
        map(if .label == "system-setting.system-status.system-status" then
              .children |= map(
                if .label == "tools.instrumented" then .linkTo = "tools-instrumented"
                else . end)
            else . end)
    ' "$MENU" > "$tmp" 2>/dev/null && atomic_write "$tmp" "$MENU"
    rm -f "$tmp"
    return 0
}

case "$MODE" in
    apply)
        [ -f "$MENU" ] || { log "未找到 menu.json，跳过"; exit 0; }
        have jq || { log "缺少 jq，跳过"; exit 0; }
        EULA="${PLUGIN_EULA:-/etc/mnt/plugins/.eula}"
        if [ ! -f "$EULA" ] || ! grep -q '^accepted=1' "$EULA" 2>/dev/null; then
            log "使用条款未同意，跳过/恢复菜单入口"
            restore_backups
            exit 0
        fi
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
        restore_backups || {
            log "备份缺失，尝试只恢复菜单链接"
            remove_menu_links
            reload_web
        }
        exit 0
        ;;
    *)
        echo "用法: $0 apply|remove" >&2
        exit 1
        ;;
esac
