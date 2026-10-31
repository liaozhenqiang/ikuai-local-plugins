#!/bin/bash
#
# install.sh —— 框架安装/升级时执行，必须幂等。
#
# 做的事：
#   1. 准备 Python 3.11 运行时（python-build-standalone，解压到 runtime/）
#   2. 准备 glibc 兼容库（爱快系统是 uClibc；从系统里能找到的 glibc 复制进 runtime/lib）
#   3. 离线安装面板依赖（payload/wheels）
#   4. 把 payload/panel 同步到 app/
#   5. 初始化 data/ 并拉起面板
#
# 数据（PIN、登录态、设备设置）在 data/，框架升级时会保留。
#
set -u

ROOT="${PLUGIN_DIR:-/etc/mnt/plugins/miot-panel}"
DATA="$ROOT/data"
APP="$ROOT/app"
RT="$ROOT/runtime"
PY="$RT/python/bin/python3"
SITE="$ROOT/site"
LOGDIR=/etc/log/miot-panel
LOG="$LOGDIR/install.log"
PY_VER="3.11.18"
PY_TAG="20261026"
PY_NAME="cpython-${PY_VER}%2B${PY_TAG}-x86_64-unknown-linux-gnu-install_only.tar.gz"
PY_URLS="
https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/${PY_NAME}
https://gh-proxy.com/https://github.com/astral-sh/python-build-standalone/releases/download/${PY_TAG}/${PY_NAME}
"

mkdir -p "$DATA" "$LOGDIR" "$RT" "$SITE" 2>/dev/null
echo "$(date '+%F %T') [install] version=${PLUGIN_VERSION:-?} action=${PLUGIN_ACTION:-?} root=$ROOT" >> "$LOG"

# ---------------------------------------------------------------- Python 运行时
if [ ! -x "$PY" ]; then
    echo "$(date '+%F %T') [install] 准备 Python ${PY_VER} 运行时" >> "$LOG"
    TARBALL=""
    if [ -s /tmp/py311.tar.gz ]; then
        TARBALL=/tmp/py311.tar.gz
        echo "$(date '+%F %T') [install] 复用 /tmp/py311.tar.gz" >> "$LOG"
    else
        for u in $PY_URLS; do
            [ -n "$u" ] || continue
            echo "$(date '+%F %T') [install] 下载 $u" >> "$LOG"
            if curl -sL --retry 2 -m 600 -o /tmp/py311.tar.gz "$u"; then
                TARBALL=/tmp/py311.tar.gz
                break
            fi
        done
    fi
    if [ -z "$TARBALL" ]; then
        echo "$(date '+%F %T') [install] 下载 Python 失败" >> "$LOG"
        echo "下载 Python 运行时失败，请检查网络后重新安装"
        exit 1
    fi
    rm -rf "$RT/python"
    tar -xzf "$TARBALL" -C "$RT" >> "$LOG" 2>&1
    # 精简：面板不需要 pip/setuptools、tk、测试套件和头文件
    rm -rf "$RT/python/lib/python3.11/test" "$RT/python/lib/python3.11/config-3.11"* \
           "$RT/python/lib/python3.11/idlelib" "$RT/python/lib/python3.11/tkinter" \
           "$RT/python/lib/python3.11/turtledemo" "$RT/python/lib/python3.11/ensurepip" \
           "$RT/python/lib/python3.11/site-packages" \
           "$RT/python/include" "$RT/python/share" "$RT/python/lib/pkgconfig" \
           "$RT/python/bin/2to3"* "$RT/python/bin/idle3"* "$RT/python/bin/pydoc3"* 2>/dev/null
    if [ ! -x "$PY" ]; then
        echo "$(date '+%F %T') [install] 解压后找不到 $PY" >> "$LOG"
        echo "Python 运行时解压失败"
        exit 1
    fi
fi

# ---------------------------------------------------------------- glibc 兼容库
# 爱快自带的是 uClibc；机器上通常已经有一份 glibc（例如向日葵客户端）。
# 这里把它复制进插件自己的 runtime/lib，之后即使那个软件被卸载也不影响面板。
if [ ! -f "$RT/lib/libc.so.6" ]; then
    SRC_LIB=""
    for d in /etc/log/awesun/app/lib /usr/lib/x86_64-linux-gnu /lib/x86_64-linux-gnu /usr/lib64 /lib64; do
        if [ -f "$d/libc.so.6" ]; then SRC_LIB="$d"; break; fi
    done
    if [ -n "$SRC_LIB" ]; then
        mkdir -p "$RT/lib"
        cp -a "$SRC_LIB"/*.so* "$RT/lib/" 2>/dev/null
        rm -f "$RT/lib/libawesun_hook.so" 2>/dev/null
        echo "$(date '+%F %T') [install] 复制 glibc: $SRC_LIB" >> "$LOG"
    else
        echo "$(date '+%F %T') [install] 找不到 glibc" >> "$LOG"
    fi
fi
# glibc 2.34+ 把 libutil 合并进了 libc，但 Python 仍声明依赖 libutil.so.1
if [ -f "$RT/lib/libc.so.6" ] && [ ! -e "$RT/lib/libutil.so.1" ]; then
    ln -sf libc.so.6 "$RT/lib/libutil.so.1" 2>/dev/null
fi

run_py() { "$RT/lib/ld-linux-x86-64.so.2" --library-path "$RT/lib" "$PY" "$@"; }

if ! run_py -c 'import ssl' >/dev/null 2>&1; then
    echo "$(date '+%F %T') [install] Python 无法启动（缺 glibc）" >> "$LOG"
    echo "Python 运行时无法启动：系统缺少 glibc 兼容库"
    exit 1
fi

# ---------------------------------------------------------------- 面板依赖
# 直接把 wheel 解压到 site/：设备上的 pip 会去调 uname 等 uClibc 程序，
# 在 glibc 解释器下容易失败；wheel 本身就是 zip，解压更稳。
if [ ! -d "$SITE/micloud" ]; then
    echo "$(date '+%F %T') [install] 解包面板依赖" >> "$LOG"
    for whl in "$ROOT"/payload/wheels/*.whl; do
        [ -f "$whl" ] || continue
        unzip -o -q "$whl" -d "$SITE" >> "$LOG" 2>&1
    done
fi
if ! PYTHONPATH="$SITE" run_py -c 'import micloud, segno, requests' >/dev/null 2>&1; then
    echo "$(date '+%F %T') [install] 依赖导入失败" >> "$LOG"
    echo "面板依赖安装失败，日志：$LOG"
    exit 1
fi

# ---------------------------------------------------------------- 面板文件
mkdir -p "$APP"
cp -a "$ROOT/payload/panel/." "$APP/" 2>/dev/null
echo "$(date '+%F %T') [install] app 已同步: $(ls "$APP" | wc -l) 项" >> "$LOG"

# ---------------------------------------------------------------- 初始化
chmod +x "$ROOT/bin/miot-panel" "$ROOT/share/menu_patch.sh" 2>/dev/null

# 左侧菜单补丁默认不启用：爱快 3.7.16 实测前端不随 /json/menu.json 刷新，
# 打上去也不会显示。脚本留在 share/ 下，需要时用 `miot-panel menu on` 手动试。
chmod +x "$ROOT/share/menu_patch.sh" 2>/dev/null
"$ROOT/bin/miot-panel" init >> "$LOG" 2>&1
"$ROOT/bin/miot-panel" restart >> "$LOG" 2>&1
echo "$(date '+%F %T') [install] 完成: $("$ROOT/bin/miot-panel" status 2>/dev/null)" >> "$LOG"
exit 0
