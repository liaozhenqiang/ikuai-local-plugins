#!/bin/bash
#
# 组装 pkg/ 并打成 dist/<plugin>-v<version>-plugin.zip —— 纯脚本插件，不需要编译。
#
# 包名必须守 ikupd 的约定（<插件名>-v<版本>-plugin.zip）：它按这个名字解析
# 插件名/版本，并用 release 资源自带的 sha256 与本地归档比对来判断有没有更新。
#
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

NAME="$(sed -n 's/^plugin=//p' pkg/Release | head -n1)"
VER="$(sed -n 's/^version=//p' pkg/Release | head -n1)"
: "${NAME:?pkg/Release 里缺少 plugin=}"
: "${VER:?pkg/Release 里缺少 version=}"
OUT="dist/${NAME}-v${VER}-plugin.zip"

find pkg -type f ! -name '*.png' | while read -r f; do
    sed -i 's/\r$//' "$f"
done
find pkg -type f \( -name '*.sh' -o -path 'pkg/bin/*' -o -path 'pkg/function/*' \) | while read -r f; do
    chmod +x "$f"
done

mkdir -p dist
rm -f "$OUT"

PACKER="$DIR/../tools/pack_plugin.py"
if [ -f "$PACKER" ] && command -v "${PYTHON:-python3}" >/dev/null 2>&1; then
    "${PYTHON:-python3}" "$PACKER" "$DIR/pkg" "$OUT"
elif command -v zip >/dev/null 2>&1; then
    # 没有 python 时退回系统 zip（执行位由 chmod 保证，但无法设置 create_system）
    ( cd pkg && zip -qr "../$OUT" . )
    echo "created: $OUT (zip)"
else
    echo "没有 python3，也找不到 zip；请安装其一，或设置 PYTHON=/path/to/python3" >&2
    exit 1
fi

echo "已生成: $DIR/$OUT"
if command -v unzip >/dev/null 2>&1; then
    unzip -l "$OUT"
fi
