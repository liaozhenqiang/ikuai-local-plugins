#!/bin/bash
#
# 组装 pkg/ 并打成 dist/<name>.zip —— 纯 shell/脚本插件，不需要编译。
#
# 关键点: zip 会保存 unix 权限位，设备端框架会 `test -x install.sh`，
#         所以打 zip 之前必须保证 pkg/ 下的脚本是可执行的。

set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

NAME="$(sed -n 's/^plugin=//p' pkg/Release | head -n1)"
: "${NAME:?pkg/Release 里缺少 plugin=}"

# 统一 LF + 执行位（含 Lua/HTML/JSON，避免 Windows 上写出的 CRLF 传到设备）
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
