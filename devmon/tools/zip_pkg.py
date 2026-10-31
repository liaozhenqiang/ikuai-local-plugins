#!/usr/bin/env python3
"""Fallback packer for hosts without `zip`. Preserves the exec bits the iKuai
plugin framework checks (install.sh, bin/*, function/*)."""
import os
import stat
import sys
import time
import zipfile


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: zip_pkg.py <plugin-dir> <name>", file=sys.stderr)
        return 2
    root, name = sys.argv[1], sys.argv[2]
    pkg = os.path.join(root, "pkg")
    out = os.path.join(root, "dist", name + ".zip")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    exec_names = {"install.sh", "boot.sh", "uninstall.sh"}

    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        for base, _dirs, files in os.walk(pkg):
            for fn in sorted(files):
                full = os.path.join(base, fn)
                rel = os.path.relpath(full, pkg).replace(os.sep, "/")
                info = zipfile.ZipInfo(rel)
                # 关键：标成 Unix 创建的 zip，否则 busybox unzip 会忽略 external_attr 里的执行位
                info.create_system = 3
                info.date_time = time.localtime(os.path.getmtime(full))[:6]
                info.compress_type = zipfile.ZIP_DEFLATED
                mode = 0o755 if (
                    rel in exec_names
                    or rel.endswith(".sh")
                    or rel.startswith("bin/")
                    or rel.startswith("function/")
                ) else 0o644
                info.external_attr = (stat.S_IFREG | mode) << 16
                with open(full, "rb") as fh:
                    zf.writestr(info, fh.read())

    print("created:", out)
    with zipfile.ZipFile(out) as zf:
        for info in zf.infolist():
            mode = (info.external_attr >> 16) & 0o777
            print(f"{mode:04o}  {info.file_size:>8}  {info.filename}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
