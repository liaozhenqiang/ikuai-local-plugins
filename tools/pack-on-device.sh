#!/bin/bash
#
# 在 iKuai 本机上把「已安装」的插件打回成可以发布的安装包（含第三方二进制），
# 文件名遵守 ikupd 约定：<插件名>-v<版本>-plugin.zip
#
# 用法（在路由器上执行）:
#   bash pack-on-device.sh <插件名> [输出目录]     # 默认 /tmp
#
# 打包时会排除 data/（运行时数据，里面可能有证书/token/清单）和日志。
# 打完把 zip 拿到电脑上，作为 release 资源上传：
#   gh release upload <tag> <插件名>-v<版本>-plugin.zip
# ikupd 会用资源自带的 sha256 和本地归档比对，所以**发布哪个包就装哪个包**。
#
set -u
P="${1:-}"
[ -n "$P" ] || { echo "用法: $0 <插件名> [输出目录]" >&2; exit 2; }

SRC="/etc/mnt/plugins/$P"
[ -f "$SRC/Release" ] || { echo "找不到 $SRC/Release（插件没装？）" >&2; exit 1; }
command -v zip >/dev/null 2>&1 || { echo "设备上没有 zip，无法打包" >&2; exit 1; }

VER="$(sed -n 's/^version=//p' "$SRC/Release" | head -n1)"
VER="${VER:-0}"
OUTDIR="${2:-/tmp}"
OUT="$OUTDIR/$P-v$VER-plugin.zip"

rm -f "$OUT"
( cd "$SRC" && zip -qr "$OUT" . -x "data/*" "*.log" "*.tmp" ".*" ) || {
    echo "压缩失败" >&2; exit 1
}

SIZE="$(wc -c < "$OUT" | tr -d ' ')"
HASH="$(sha256sum "$OUT" | cut -d' ' -f1)"
printf '包: %s\n大小: %s 字节\nsha256: %s\n' "$OUT" "$SIZE" "$HASH"
printf '\n检查包内 Release:\n'
unzip -p "$OUT" Release 2>/dev/null | sed -n '1,4p'
printf '\n上传: gh release upload <tag> %s\n' "$(basename "$OUT")"
