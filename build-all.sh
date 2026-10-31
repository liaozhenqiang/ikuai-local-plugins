#!/bin/bash
#
# 打包入口：
#   bash build-all.sh           只打 devmon（源码完整，可直接安装）
#   bash build-all.sh --all     连 plugins/ 下的也一起打（只有集成层，见下方提示）
#
# 输出统一按 ikupd 的约定命名：dist/<插件名>-v<版本>-plugin.zip
# 只有这种名字的 .zip 资源会被「插件在线升级」识别，并用它自带的 sha256 判断更新。
#
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
mkdir -p dist
PY="${PYTHON:-python3}"
if ! command -v "$PY" >/dev/null 2>&1; then
    echo "找不到 python3；请设置 PYTHON=/path/to/python3" >&2
    exit 1
fi

pack() {   # <包根目录> -> dist/<plugin>-v<version>-plugin.zip
    local src="$1" name ver out
    [ -f "$src/Release" ] || { echo "跳过 $src（没有 Release）" >&2; return 0; }
    name="$(sed -n 's/^plugin=//p' "$src/Release" | head -n1)"
    ver="$(sed -n 's/^version=//p' "$src/Release" | head -n1)"
    out="dist/${name}-v${ver:-0}-plugin.zip"
    "$PY" tools/pack_plugin.py "$src" "$out"
}

pack devmon/pkg

if [ "${1:-}" = "--all" ]; then
    for d in plugins/*/; do
        pack "${d%/}"
    done
    cat <<'EOF'

注意：plugins/ 下的包只含 iKuai 集成层，第三方二进制（mihomo / AdGuardHome / ttyd / frp …）
不在仓库里，直接装会缺程序本体。要能装的完整包请在路由器上打：

    bash tools/pack-on-device.sh <插件名>

然后把这个 zip 作为 release 资源上传（文件名不要改）。
EOF
fi

ls -l dist/*.zip
