#!/usr/bin/env python3
"""把插件目录打成 ikupd 认得的包：<plugin>-v<version>-plugin.zip

ikupd 只扫描 release 里的 .zip 资源，按「<插件名>-v<版本>-plugin.zip」解析
插件名和版本，再用资源自带的 sha256 与本地归档比对，所以包名必须守这个约定。

用法:
    pack_plugin.py <插件目录> [输出文件]
    （输出文件名默认是 dist/<plugin>-v<version>-plugin.zip）

执行位：install.sh / boot.sh / uninstall.sh / *.sh / bin/* / function/* 一律 0755。
不打包 data/、dist/、__pycache__、*.pyc、*.log。
"""
import os
import re
import stat
import sys
import time
import zipfile

EXEC_NAMES = {"install.sh", "boot.sh", "uninstall.sh"}
SKIP_DIRS = {"data", "dist", "__pycache__", ".git", ".idea"}
SKIP_SUFFIX = (".pyc", ".log", ".b64", ".tmp")


def release_field(text: str, key: str) -> str:
    m = re.search(r"(?m)^%s=(.*)$" % re.escape(key), text)
    return m.group(1).strip() if m else ""


def is_exec(rel: str) -> bool:
    if (
        rel in EXEC_NAMES
        or rel.endswith(".sh")
        or rel.startswith("bin/")
        or rel.startswith("function/")
    ):
        return True
    if rel.startswith("runtime/python/bin/") or rel == "runtime/lib/ld-linux-x86-64.so.2":
        return True
    if rel.startswith("payload/panel/music-stack/"):
        return rel.rsplit("/", 1)[-1] in {"songloft", "music-dl", "ffmpeg", "ffprobe"}
    return False


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    src = sys.argv[1].rstrip("/\\")
    rel_file = os.path.join(src, "Release")
    if not os.path.isfile(rel_file):
        print("缺少 %s（插件包里必须先有 Release）" % rel_file, file=sys.stderr)
        return 2
    with open(rel_file, encoding="utf-8", errors="replace") as fh:
        rel = fh.read()
    name = release_field(rel, "plugin") or os.path.basename(os.path.abspath(src))
    ver = release_field(rel, "version") or "0"
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(
        "dist", "%s-v%s-plugin.zip" % (name, ver)
    )
    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)

    # 所有条目用 Release 的 mtime 当固定时间戳：同一份源码在哪台机器上打，
    # zip 的字节都一样（sha256 稳定），否则重新 clone 后 mtime 变了，
    # ikupd 会把「同版本重新打包」误判成有更新。
    stamp = time.localtime(os.path.getmtime(rel_file))[:6]

    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for base, dirs, files in os.walk(src):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
            for fn in sorted(files):
                if fn.endswith(SKIP_SUFFIX):
                    continue
                full = os.path.join(base, fn)
                arc = os.path.relpath(full, src).replace(os.sep, "/")
                # 关键：标成 Unix 创建的 zip，否则 busybox unzip 会忽略执行位
                info = zipfile.ZipInfo(arc)
                info.create_system = 3
                info.date_time = stamp
                info.compress_type = zipfile.ZIP_DEFLATED
                mode = 0o755 if is_exec(arc) else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                with open(full, "rb") as fh:
                    zf.writestr(info, fh.read())
                n += 1

    size = os.path.getsize(out)
    print("created: %s  (%d files, %d bytes)  plugin=%s version=%s" % (out, n, size, name, ver))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
