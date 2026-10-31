#!/bin/bash
# 存放/查看向日葵身份凭证，并检查钩子是否命中。
# 凭证放 /etc/log/awesun/identity（/etc/log 是 15.5G 持久分区，重启不丢）
ID=/etc/log/awesun/identity
RT=/etc/log/awesun

save() {
    mkdir -p "$ID"
    for f in /etc/orayentconfig.conf /etc/sys_ent_config.conf; do
        [ -f "$f" ] && cp -p "$f" "$ID/"
    done
    {
        echo "saved_at=$(date '+%F %T')"
        echo "macaddress=$(grep -m1 '^macaddress=' /etc/orayentconfig.conf | cut -d= -f2-)"
        echo "fastcode=$(grep -m1 '^fastcode=' /etc/sys_ent_config.conf | cut -d= -f2-)"
        echo "license=$(grep -m1 '^license=' /etc/sys_ent_config.conf | cut -d= -f2-)"
        echo "account=$(grep -m1 '^account=' /etc/orayentconfig.conf | cut -d= -f2-)"
        echo "userid=$(grep -m1 '^userid=' /etc/orayentconfig.conf | cut -d= -f2-)"
        echo "hostname=$(grep -m1 '^hostname=' /etc/orayentconfig.conf | cut -d= -f2-)"
    } > "$ID/meta"
    echo "[identity] 已保存到 $ID:"
    sed 's/^/    /' "$ID/meta"
    ls -la "$ID/"
}

show() {
    echo "--- 凭证备份 ---"
    if [ -f "$ID/meta" ]; then sed 's/^/  /' "$ID/meta"; else echo "  （无）"; fi
    echo "--- 设备当前 ---"
    echo "  mac   = $(grep -m1 '^macaddress=' /etc/orayentconfig.conf | cut -d= -f2-)"
    echo "  fastcode = $(grep -m1 '^fastcode=' /etc/sys_ent_config.conf | cut -d= -f2-)"
    echo "  account  = $(grep -m1 '^account=' /etc/orayentconfig.conf | cut -d= -f2-)"
    echo "  userid   = $(grep -m1 '^userid=' /etc/orayentconfig.conf | cut -d= -f2-)"
    echo "  license  = $(grep -m1 '^license=' /etc/sys_ent_config.conf | cut -d= -f2-)"
    echo "  hostname = $(grep -m1 '^hostname=' /etc/orayentconfig.conf | cut -d= -f2-)"
}

hooks() {
    echo "--- 钩子日志 ---"
    tail -20 "$RT/hook.log" 2>&1
    echo "--- 桌面插件是否已加载 ---"
    for p in $(ps | grep -E '[a]wesuncli' | awk '{print $1}'); do
        echo "  pid $p: $(cat /proc/$p/cmdline 2>/dev/null | tr '\0' ' ')"
        echo "     sl-client-desktop 段数: $(grep -c sl-client-desktop /proc/$p/maps 2>/dev/null)"
        echo "     打开 fb0: $(ls -l /proc/$p/fd 2>/dev/null | grep -c fb0)"
    done
    echo "--- 向日葵日志里的采集/登录 ---"
    grep -rhiE 'OpenFb|fb screen capture|drm screen|Do login|status: on|EncodeStream|CreateNewCapturer|remote-id' \
        "$RT/app/var-log/"*.log 2>/dev/null | tail -18
}

case "${1:-show}" in
save) save ;;
show) show ;;
hooks) hooks ;;
all)  save; echo; show; echo; hooks ;;
*)    echo "用法: $0 save|show|hooks|all" ;;
esac
