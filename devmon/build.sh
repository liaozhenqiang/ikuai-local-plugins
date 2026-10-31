#!/bin/bash
#
# 组装 pkg/ 并打成 dist/<name>.zip —— 纯脚本插件，不需要编译。
#
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

NAME="$(sed -n 's/^plugin=//p' pkg/Release | head -n1)"
: "${NAME:?pkg/Release 里缺少 plugin=}"

find pkg -type f ! -name '*.png' | while read -r f; do
    sed -i 's/\r$//' "$f"
done
find pkg -type f \( -name '*.sh' -o -path 'pkg/bin/*' -o -path 'pkg/function/*' \) | while read -r f; do
    chmod +x "$f"
done

mkdir -p dist
rm -f "dist/$NAME.zip"
if command -v zip >/dev/null 2>&1; then
    ( cd pkg && zip -qr "../dist/$NAME.zip" . )
else
    PY="${PYTHON:-python}"
    if ! command -v "$PY" >/dev/null 2>&1; then
        echo "没有 zip，也找不到 python；请安装 zip 或设置 PYTHON=/path/to/python3" >&2
        exit 1
    fi
    "$PY" "$DIR/tools/zip_pkg.py" "$DIR" "$NAME"
fi

echo "已生成: $DIR/dist/$NAME.zip"
if command -v unzip >/dev/null 2>&1; then
    unzip -l "dist/$NAME.zip"
fi
