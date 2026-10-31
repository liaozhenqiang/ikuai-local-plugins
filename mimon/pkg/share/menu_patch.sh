#!/bin/bash
#
# menu_patch.sh —— 把「小米设备」挂到 iKuai「状态监控」菜单下（可选的前端集成）
#
# 改三处（都是 iKuai 自己的前端资源，根分区重启会还原）：
#   1) /usr/ikuai/www/json/menu.json
#        在 system-status 组追加叶子：状态监控 -> 小米设备
#   2) /usr/ikuai/www/static/i18n/{zh-CN,zh-TW,en-US}.json
#        菜单文案 left-menu.system-setting.system-status.mimon
#        页面标题 page-title.system-setting.mimon
#   3) /usr/ikuai/www/static/js/app.<hash>.js.gz
#        加一个 iframe 路由 system-setting-mimon -> /plugins/app/mimon.html
#
# 设计原则：只在锚点/结构匹配时写；先写临时文件并校验，再原子替换；
# 任何一步失败都不碰原文件（fail-safe）。boot.sh 每次开机重打，幂等。
#
# 用法: menu_patch.sh apply|remove
#
set -u

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${PLUGIN_DIR:-$(cd "$SELF_DIR/.." && pwd)}"
DATA="${MIMON_DATA:-$ROOT/data}"
IK_WWW="${IK_WWW:-/usr/ikuai/www}"
MENU="$IK_WWW/json/menu.json"
I18N_DIR="$IK_WWW/static/i18n"
JS_DIR="$IK_WWW/static/js"
BACKUP="$DATA/menu-backup"

MODE="${1:-apply}"
ROUTE_NAME="system-setting-mimon"
ROUTE_PATH="system-setting/mimon"
LINK="system-setting-mimon"
MENU_LABEL_KEY="system-setting.system-status.mimon"

# 锚点：3.7.16 里唯一；插在这个路由对象之前
ANCHOR='{path:"system-setting/plugin-management",name:"system-setting-plugin-management",'
ROUTE='{path:"system-setting/mimon",name:"system-setting-mimon",component:{render:function(e){return e("iframe",{attrs:{src:"/plugins/app/mimon.html",frameborder:"0"},style:{width:"100%",height:"calc(100vh - 183px)",border:"0"}})}},meta:{title:"system-setting.mimon"}},'

log() { printf '%s [menu] %s\n' "$(date '+%F %T')" "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

# iKuai 的 /json/menu.json 由 funcore.lua 在 openresty 启动时生成并缓存；
# funcore.sh 自己改权限后也是 `openresty -s reload`。只刷新 Web，不动网络。
reload_web() {
    if ! have openresty; then
        log "未找到 openresty，跳过 Web reload"
        return 0
    fi
    if openresty -s reload >/dev/null 2>&1; then
        log "已 reload openresty（刷新 Web 菜单缓存）"
    else
        log "openresty reload 失败（Web 服务未运行？菜单会在 Web 启动时重新生成）"
    fi
    return 0
}

atomic_write() {
    local src="$1" dst="$2" staged
    staged="$(mktemp "${dst%/*}/.mimon.XXXXXX" 2>/dev/null)" || return 1
    if cat "$src" > "$staged" 2>/dev/null && chmod 644 "$staged" 2>/dev/null && mv -f "$staged" "$dst" 2>/dev/null; then
        return 0
    fi
    rm -f "$staged"
    return 1
}

apply_route() {
    local ref js tmp new gz n
    have gzip || { log "缺少 gzip，跳过路由补丁"; return 1; }
    have zcat || { log "缺少 zcat，跳过路由补丁"; return 1; }

    ref="$(grep -o 'app\.[a-f0-9]*\.js' "$IK_WWW/index.html" 2>/dev/null | head -n1)"
    if [ -n "$ref" ] && [ -f "$JS_DIR/${ref}.gz" ]; then
        js="$JS_DIR/${ref}.gz"
    else
        js="$(ls "$JS_DIR"/app.*.js.gz 2>/dev/null | head -n1)"
    fi
    [ -n "$js" ] && [ -f "$js" ] || { log "找不到 app.*.js.gz，跳过路由补丁"; return 1; }

    tmp="$(mktemp)" || return 1
    new="$(mktemp)" || { rm -f "$tmp"; return 1; }
    gz="$(mktemp)" || { rm -f "$tmp" "$new"; return 1; }

    if ! zcat "$js" > "$tmp" 2>/dev/null; then
        log "解压失败: $js"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi

    n="$(grep -Fo "name:\"$ROUTE_NAME\"" "$tmp" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n:-0}" -gt 0 ]; then
        log "SPA 路由已存在，跳过"
        rm -f "$tmp" "$new" "$gz"
        return 0
    fi

    n="$(grep -Fo "$ANCHOR" "$tmp" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n:-0}" != "1" ]; then
        log "找不到路由锚点（前端版本变化？），不写前端、不添加菜单项"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi

    if ! sed "s|$ANCHOR|$ROUTE&|" "$tmp" > "$new" 2>/dev/null; then
        log "插入路由失败"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi

    n="$(grep -Fo "name:\"$ROUTE_NAME\"" "$new" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${n:-0}" != "1" ]; then
        log "路由插入校验失败"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi

    if ! gzip -9 -c < "$new" > "$gz" 2>/dev/null || ! gzip -t "$gz" 2>/dev/null; then
        log "重新压缩失败"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi
    if ! zcat "$gz" 2>/dev/null | grep -Fq "name:\"$ROUTE_NAME\""; then
        log "压缩后校验失败"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi

    mkdir -p "$BACKUP" 2>/dev/null || { log "无法创建备份目录"; rm -f "$tmp" "$new" "$gz"; return 1; }
    if ! cp -f "$js" "$BACKUP/app.js.gz" 2>/dev/null; then
        log "备份 app 分包失败，不写"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi

    if ! atomic_write "$gz" "$js"; then
        log "写入 app 分包失败"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi
    if ! zcat "$js" 2>/dev/null | grep -Fq "name:\"$ROUTE_NAME\""; then
        atomic_write "$BACKUP/app.js.gz" "$js" 2>/dev/null
        log "写回校验失败，已还原 app 分包"
        rm -f "$tmp" "$new" "$gz"
        return 1
    fi

    log "已加 SPA 路由: $ROUTE_PATH -> /plugins/app/mimon.html"
    rm -f "$tmp" "$new" "$gz"
    return 0
}

apply_i18n() {
    local f base label title tmp staged
    for f in "$I18N_DIR"/zh-CN.json "$I18N_DIR"/zh-TW.json "$I18N_DIR"/en-US.json; do
        [ -f "$f" ] || continue
        base="${f##*/}"
        case "$base" in
            zh-TW.json) label="小米設備"; title="小米設備" ;;
            en-US.json) label="Xiaomi Devices"; title="Xiaomi Devices" ;;
            *)          label="小米设备"; title="小米设备" ;;
        esac

        if jq -e --arg l "$label" --arg t "$title" \
            '.["left-menu"]["system-setting"]["system-status"]["mimon"] == $l and .["page-title"]["system-setting"]["mimon"] == $t' \
            "$f" >/dev/null 2>&1; then
            log "i18n 已是目标状态: $base"
            continue
        fi

        tmp="$(mktemp)" || continue
        if ! jq --arg l "$label" --arg t "$title" \
            '.["left-menu"]["system-setting"]["system-status"]["mimon"] = $l |
             .["page-title"]["system-setting"]["mimon"] = $t' \
            "$f" > "$tmp" 2>/dev/null; then
            log "i18n 结构不匹配，跳过: $base"
            rm -f "$tmp"
            continue
        fi

        if ! jq -e --arg l "$label" --arg t "$title" \
            '.["left-menu"]["system-setting"]["system-status"]["mimon"] == $l and .["page-title"]["system-setting"]["mimon"] == $t' \
            "$tmp" >/dev/null 2>&1; then
            log "i18n 生成校验失败，跳过: $base"
            rm -f "$tmp"
            continue
        fi

        if cmp -s "$f" "$tmp"; then
            log "i18n 无变化: $base"
            rm -f "$tmp"
            continue
        fi

        mkdir -p "$BACKUP" 2>/dev/null || { log "无法创建备份目录"; rm -f "$tmp"; continue; }
        if ! cp -f "$f" "$BACKUP/$base" 2>/dev/null; then
            log "备份 i18n 失败，跳过: $base"
            rm -f "$tmp"
            continue
        fi
        if ! atomic_write "$tmp" "$f"; then
            log "写入 i18n 失败: $base"
            rm -f "$tmp"
            continue
        fi
        if ! jq -e --arg l "$label" --arg t "$title" \
            '.["left-menu"]["system-setting"]["system-status"]["mimon"] == $l and .["page-title"]["system-setting"]["mimon"] == $t' \
            "$f" >/dev/null 2>&1; then
            atomic_write "$BACKUP/$base" "$f" 2>/dev/null
            log "i18n 写回校验失败，已还原: $base"
        else
            log "已加菜单文案: $base"
        fi
        rm -f "$tmp"
    done
    return 0
}

apply_menu_i18n() {
    local f="$IK_WWW/json/menu-i18n.json" tmp
    [ -f "$f" ] || { log "未找到 menu-i18n.json，跳过"; return 0; }
    if jq -e --arg l "小米设备" --arg e "Xiaomi Devices" --arg t "小米設備" \
        '.["mimon"] == [$l, $e, $t]' "$f" >/dev/null 2>&1; then
        log "menu-i18n 已是目标状态"
        return 0
    fi
    tmp="$(mktemp)" || return 1
    if ! jq --arg l "小米设备" --arg e "Xiaomi Devices" --arg t "小米設備" \
        '.["mimon"] = [$l, $e, $t]' "$f" > "$tmp" 2>/dev/null; then
        log "menu-i18n 写入生成失败，跳过"
        rm -f "$tmp"
        return 1
    fi
    if ! jq -e --arg l "小米设备" --arg e "Xiaomi Devices" --arg t "小米設備" \
        '.["mimon"] == [$l, $e, $t]' "$tmp" >/dev/null 2>&1; then
        log "menu-i18n 生成校验失败，跳过"
        rm -f "$tmp"
        return 1
    fi
    mkdir -p "$BACKUP" 2>/dev/null || { log "无法创建备份目录"; rm -f "$tmp"; return 1; }
    cp -f "$f" "$BACKUP/menu-i18n.json" 2>/dev/null || { log "备份 menu-i18n 失败"; rm -f "$tmp"; return 1; }
    if ! atomic_write "$tmp" "$f"; then
        log "写入 menu-i18n 失败"
        rm -f "$tmp"
        return 1
    fi
    if ! jq -e --arg l "小米设备" --arg e "Xiaomi Devices" --arg t "小米設備" \
        '.["mimon"] == [$l, $e, $t]' "$f" >/dev/null 2>&1; then
        atomic_write "$BACKUP/menu-i18n.json" "$f" 2>/dev/null
        log "menu-i18n 写回校验失败，已还原"
    else
        log "已加权限页菜单文案: menu-i18n.json"
    fi
    rm -f "$tmp"
    return 0
}

apply_menu() {
    local tmp
    if jq -e '[.. | objects | select(.linkTo? == "system-setting-mimon")] | length > 0' "$MENU" >/dev/null 2>&1; then
        log "菜单项已存在，跳过"
        return 0
    fi

    tmp="$(mktemp)" || return 1
    if ! jq '
        map(if .label == "system-setting.system-status.system-status" and ((.children // []) | type) == "array"
            then .children += [{"label":"'"$MENU_LABEL_KEY"'","func_name":"mimon","linkTo":"'"$LINK"'"}]
            else . end)
    ' "$MENU" > "$tmp" 2>/dev/null; then
        log "菜单结构不匹配，跳过"
        rm -f "$tmp"
        return 1
    fi

    if ! jq -e '[.. | objects | select(.linkTo? == "system-setting-mimon")] | length > 0' "$tmp" >/dev/null 2>&1; then
        log "没找到 system-status 菜单组，跳过"
        rm -f "$tmp"
        return 1
    fi

    mkdir -p "$BACKUP" 2>/dev/null || { log "无法创建备份目录"; rm -f "$tmp"; return 1; }
    if ! cp -f "$MENU" "$BACKUP/menu.json" 2>/dev/null; then
        log "备份 menu.json 失败，跳过"
        rm -f "$tmp"
        return 1
    fi
    if ! atomic_write "$tmp" "$MENU"; then
        log "写入 menu.json 失败"
        rm -f "$tmp"
        return 1
    fi
    if ! jq -e '[.. | objects | select(.linkTo? == "system-setting-mimon")] | length > 0' "$MENU" >/dev/null 2>&1; then
        atomic_write "$BACKUP/menu.json" "$MENU" 2>/dev/null
        log "菜单写回校验失败，已还原"
        rm -f "$tmp"
        return 1
    fi
    log "已加菜单项: 状态监控 -> 小米设备"
    rm -f "$tmp"
    return 0
}

remove_menu_item() {
    local tmp
    if ! jq -e '[.. | objects | select(.linkTo? == "system-setting-mimon")] | length > 0' "$MENU" >/dev/null 2>&1; then
        log "菜单项不存在，无需移除"
        return 0
    fi
    tmp="$(mktemp)" || return 1
    if ! jq '
        map(if .label == "system-setting.system-status.system-status" and ((.children // []) | type) == "array"
            then .children |= map(select(.linkTo != "system-setting-mimon"))
            else . end)
    ' "$MENU" > "$tmp" 2>/dev/null; then
        log "移除菜单项失败（结构不匹配）"
        rm -f "$tmp"
        return 1
    fi
    if ! jq -e '[.. | objects | select(.linkTo? == "system-setting-mimon")] | length == 0' "$tmp" >/dev/null 2>&1; then
        log "移除校验失败，跳过"
        rm -f "$tmp"
        return 1
    fi
    mkdir -p "$BACKUP" 2>/dev/null || { log "无法创建备份目录"; rm -f "$tmp"; return 1; }
    cp -f "$MENU" "$BACKUP/menu.json.before-remove" 2>/dev/null
    if atomic_write "$tmp" "$MENU"; then
        log "已移除菜单项: 状态监控 -> 小米设备"
    else
        log "移除菜单项写回失败"
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
    return 0
}

case "$MODE" in
    apply)
        [ -f "$MENU" ] || { log "未找到 $MENU，跳过"; exit 0; }
        have jq || { log "缺少 jq，跳过菜单集成"; exit 0; }
        mkdir -p "$BACKUP" 2>/dev/null || { log "无法创建备份目录，跳过"; exit 0; }

        EULA="${PLUGIN_EULA:-/etc/mnt/plugins/.eula}"
        if [ ! -f "$EULA" ] || ! grep -q '^accepted=1' "$EULA" 2>/dev/null; then
            log "使用条款未同意（$EULA），跳过菜单集成并清理旧菜单项"
            remove_menu_item
            exit 0
        fi

        if ! apply_route; then
            log "路由补丁未生效；移除可能残留的菜单项，插件卡片仍可用"
            remove_menu_item
            exit 0
        fi
        apply_i18n
        apply_menu_i18n
        apply_menu
        reload_web
        log "完成；若后台已打开，请关闭标签页重开（菜单会缓存在 sessionStorage.allFirstMenu）"
        exit 0
        ;;
    remove)
        [ -f "$MENU" ] || { log "未找到 $MENU，跳过"; exit 0; }
        have jq || { log "缺少 jq，跳过"; exit 0; }
        remove_menu_item
        reload_web
        log "菜单项已移除；SPA 路由与语言键会在重启后随根分区还原"
        exit 0
        ;;
    *)
        echo "用法: $0 apply|remove" >&2
        exit 1
        ;;
esac
