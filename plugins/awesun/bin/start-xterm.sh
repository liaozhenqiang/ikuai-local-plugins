#!/bin/sh
# 在已有的 X 上起/重启终端窗口（远端的操作界面）。
#
# 单独成文件有两个原因：
#   1. 带续行的超长命令在 SSH 里容易被吞掉；
#   2. kill 时要用精确路径匹配 —— 用 '[x]term' 会匹配到本脚本自己的进程名
#      （start-xterm.sh 里就含 xterm），脚本会把自己 kill 掉。
#
# 几何尺寸按**实测字符单元**算，不写死行列数：
# WenQuanYi Micro Hei Mono @13pt 实测 12.03 x 22.10 px。
# 之前写死 158x40，实际需要 1900x888 像素，而屏幕只有 1280x720，
# 结果右侧和底部都被裁掉（`ls` 一下后半截就看不见了）。

RT=${RT:-/etc/log/awesun}
RT_BIN="$RT/bin"
DPY=${DPY:-:99}
X=$RT/x11

# 这一屏跑什么：
#   PROG 留空（默认）= 交互 shell
#   PROG=top 之类    = 先跑那个程序，退出后再落到交互 shell（屏不会变死）
# XTERM_TAG：多屏时用来区分窗口与日志，也用来**只杀本屏的 xterm**
PROG=${PROG:-}
XTERM_TAG=${XTERM_TAG:-xterm}

# 字体配置：**优先用插件自己那份**（awesunctl 的 install_fonts 写的）——
# 它带渲染参数（antialias/hinting/embeddedbitmap）、字体族别名，还挂上了我们自带的
# 中文字体。这里**千万不要再自己写一份最小配置**：原来这段用一个 184 字节的
# fonts.conf 把 fontconfig 的默认规则整个顶掉了，字渲得又细又飘、小字号中文
# 看着像"显示了一半"，而且每次开屏都会把插件那份覆盖回去（踩过）。
mkdir -p "$RT/fontcache"
FONTCONF="$RT/etc/fonts/fonts.conf"
if [ ! -f "$FONTCONF" ]; then
    # 兜底：插件那份还没铺好时给个能跑的最小配置（至少别让 fontconfig 报错）
    mkdir -p "$X/etc/fonts"
    FONTCONF="$X/etc/fonts/fonts.conf"
    cat > "$FONTCONF" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>$X/share/fonts</dir>
  <cachedir>$RT/fontcache</cachedir>
</fontconfig>
EOF
fi
export FONTCONFIG_FILE="$FONTCONF"

# ---- 屏幕尺寸（问 X 要，不猜）----
DIM=$(DISPLAY=$DPY "$X/bin/xdpyinfo" 2>/dev/null | awk '/dimensions:/{print $2; exit}')
SW=${DIM%x*}
SH=${DIM#*x}
case "$SW" in ''|*[!0-9]*) SW=1280; SH=720 ;; esac
case "$SH" in ''|*[!0-9]*) SW=1280; SH=720 ;; esac

# ---- 字符单元与边框（实测值，换字体/字号要重新量）----
CELL_W=12
CELL_H=22
BORDER=2
SBAR=13          # 右侧滚动条占的宽度

COLS=$(( (SW - SBAR - BORDER * 2) / CELL_W ))
ROWS=$(( (SH - BORDER * 2) / CELL_H ))
[ "$COLS" -lt 20 ] && COLS=80
[ "$ROWS" -lt 5 ] && ROWS=24

# ---- xterm 资源：剪贴板与滚动 ----
#
# selectToClipboard 是关键：xterm 默认只把选中内容放进 PRIMARY，
# 而向日葵同步的是 CLIPBOARD —— 不开这个，"选中复制"在手机端拿不到。
#
# **不要在这里覆盖 translations**：`#override` 会把 xterm 默认的鼠标绑定
# （select-start / select-extend / select-end）整表替掉，选中直接失效。
# 粘贴用 xterm 内置的 Shift+Insert / Ctrl+Insert 就够了。
RES=$RT/xterm.Xresources
cat > "$RES" <<EOF
XTerm*selectToClipboard: true
XTerm*rightScrollBar: true
XTerm*scrollBar: true
XTerm*saveLines: 4096
! 用 #augment 往默认绑定上"追加"，而不是 #override 整表替换。
! #override 会把 select-start/select-extend/select-end 一起干掉，鼠标选中就废了。
XTerm*VT100.translations: #augment \n\
        Ctrl Shift <Key>C: copy-selection(CLIPBOARD) \n\
        Ctrl Shift <Key>V: insert-selection(CLIPBOARD)
EOF

# 先停掉旧的。**只杀本屏的**：多屏时所有 xterm 都是同一个二进制路径，
# 按路径杀会把别的屏一起干掉（踩过），所以再用窗口标题里的 tag 区分开。
for p in $(ps | grep "$X/bin/xterm" | grep "$XTERM_TAG" | grep -v grep | awk '{print $1}'); do
    kill -9 "$p" 2>/dev/null
done
sleep 1

# ---- 交互 shell ----
#
# 设备上 /bin/sh 是 busybox（vi 风格行编辑、没有花括号展开/数组/[[ ]]），
# 但固件里本来就带了一个**完整的 GNU bash 4.4**（/bin/bash），
# 所以不用额外打包任何东西，直接用它当交互 shell 就够了。
# /usr/bin 下的 vi/less/top/find/du 也都是真的，只有 bin/{ls,cat,grep,sed}
# 是 busybox 软链（bashrc 里的别名对它们做了兼容回退）。
SHELL_DIR="$RT/shell"
mkdir -p "$SHELL_DIR"
RC="$SHELL_DIR/bashrc"
# 从 runtime 目录或插件目录取一份现成的 rc（内容见 pkg/bin/bashrc）
# 注意两处 locale 的分工，缺一个就出问题：
#   xterm 需要 C.UTF-8 —— 否则它不按 UTF-8 解码，中文全变乱码（踩过）；
#   bash  需要 C       —— 设备上的 bash 是 uClibc 版、没有 C.UTF-8 数据，
#                          给它 C.UTF-8 会在启动时（rc 之前）刷 setlocale 告警。
# 所以用 `env` 只给 bash 单独降级，不影响 xterm。
if [ -f "${RT_BIN:-$RT/bin}/bashrc" ]; then
    cp -f "${RT_BIN:-$RT/bin}/bashrc" "$RC"
elif [ -f "$RT_BIN/bashrc" ]; then
    cp -f "$RT_BIN/bashrc" "$RC"
elif [ -f "$RES.rc" ]; then
    cp -f "$RES.rc" "$RC"
fi

# ---- 选交互 shell ----
#
# 优先用我们自己打包的 **glibc 版** bash + 新版 GNU 工具（$RT/tools/）：
# 设备自带的 bash 是 uClibc 版，uClibc 没有 C.UTF-8 的 locale 数据，
# setlocale 失败后它不把中文当多字节字符 —— 输入的中文会显示成
# \344\270\255 这种八进制转义，退格也会错位。
# glibc 版能直接用 x11 payload 里的 C.utf8，中文显示/编辑都正常。
TOOLS="$RT/tools"
if [ -x "$TOOLS/usr/bin/bash" ]; then
    # 注意：**不要用 LD_LIBRARY_PATH**。
    # 它会污染 PATH 里那些 uClibc 的 busybox 软链（/bin/ls、/bin/clear…），
    # uClibc 的加载器读到 glibc 的 .so 直接报 "can't handle reloc type 0x25"。
    # 工具库由 awesunctl 的 link_rootfs 软链进 /lib/x86_64-linux-gnu，
    # 走标准搜索路径就够了。
    SHELL_CMD="env LOCPATH=$X/lib/locale XLOCALEDIR=$X/share/X11/locale \
        LANG=C.UTF-8 LC_ALL=C.UTF-8 \
        PATH=$TOOLS/usr/bin:$TOOLS/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        $TOOLS/usr/bin/bash --rcfile $RC -i"
    echo "交互 shell: $TOOLS/usr/bin/bash（glibc 版，UTF-8 正常）"
else
    # 退回固件自带的 bash。它是 uClibc 版，给它 C.UTF-8 会在启动时刷
    # setlocale 告警（rc 里再改已经晚了，bash 是启动那一刻就 setlocale）。
    SHELL_CMD="env LC_ALL=C LANG=C /bin/bash --rcfile $RC -i"
    echo "交互 shell: /bin/bash（固件自带，UuClibc 版，中文行编辑会退化）"
fi

# 有 PROG 就先跑它（比如 top），退出后自动落到交互 shell
if [ -n "$PROG" ]; then
    RUN_CMD="$PROG; echo; echo '[程序已退出，转到交互 shell]'; exec $SHELL_CMD"
    echo "本屏程序: $PROG（退出后落到交互 shell）"
else
    RUN_CMD="$SHELL_CMD"
fi

# ===== 环境变量块：**每行都必须以 \ 收尾，中间绝不能插注释** =====
# 踩过（用户的"shell 屏一片空白"就是这个）：在这段续行中间加了两行注释，
# 把 `LANG=C.UTF-8 LC_ALL=C.UTF-8 \` 后面的续行接断 —— 前半段变成一条
# "只赋值、没有命令"的独立语句，赋值不会导出；xterm 那行单独执行时
# DISPLAY 没了，日志里就是：
#     xterm: Xt error: Can't open display: %s
#     xterm: DISPLAY is not set
# 屏幕全黑。以后这个块只许改值，不许插注释/空行。
#
# 只重定向**缓存**（根分区只有 113MB 且长期占满是老问题）。
# HOME/TMPDIR **不动**：系统 /tmp 是 tmpfs，本来就该用它；覆盖 HOME 会让
# 终端里的程序行为异常（踩过）。
DISPLAY=$DPY \
LOCPATH="$X/lib/locale" \
XLOCALEDIR="$X/share/X11/locale" \
LANG=C.UTF-8 LC_ALL=C.UTF-8 \
XDG_CACHE_HOME="$RT/cache" \
FONTCONFIG_FILE="$FONTCONF" \
XENVIRONMENT="$RES" \
"$X/bin/xterm" -u8 -ut \
    -fa 'WenQuanYi Micro Hei Mono' -fs "${FONTSIZE:-13}" \
    -bg '#0f1720' -fg '#d8e3ee' -bd '#2c3d50' -b "$BORDER" \
    -cr '#7fd1ff' -geometry "${COLS}x${ROWS}+0+0" \
    -title "iKuai:$XTERM_TAG" \
    -e sh -c "$RUN_CMD" \
    >> "$RT/log/xterm.log" 2>&1 &

sleep 3
echo "[$XTERM_TAG] 屏幕 ${SW}x${SH} -> 终端 ${COLS}x${ROWS}（单元 ${CELL_W}x${CELL_H}）"
