#!/usr/bin/env python3
"""Moves Winlator's prebuilt assets from /data/data/com.winlator to another package.

The rootfs, Box64 and graphics drivers ship as .tzst archives whose binaries have
/data/data/com.winlator baked in (RPATH, ELF interpreter, glibc paths). The new
package id has the same length, so the path is replaced byte for byte and every
ELF stays valid. Tar headers are rewritten by tarfile, so symlink targets and
checksums stay consistent.

Usage: rename_package.py <assets dir> <new package id>
"""
import io
import os
import subprocess
import sys
import tarfile

OLD = b"/data/data/com.winlator"


def rewrite_tzst(path, new):
    """Rewrites one .tzst in place. Returns the number of replacements."""
    count = 0
    unzstd = subprocess.Popen(["zstd", "-dcq", path], stdout=subprocess.PIPE)
    out_path = path + ".tmp"
    with open(out_path, "wb") as out_file:
        rezstd = subprocess.Popen(["zstd", "-19", "-T0", "-q", "-c"], stdin=subprocess.PIPE, stdout=out_file)
        with tarfile.open(fileobj=unzstd.stdout, mode="r|") as src, \
             tarfile.open(fileobj=rezstd.stdin, mode="w|", format=tarfile.PAX_FORMAT) as dst:
            for member in src:
                for attr in ("name", "linkname"):
                    value = getattr(member, attr).encode("utf-8", "surrogateescape")
                    if OLD in value:
                        count += value.count(OLD)
                        setattr(member, attr, value.replace(OLD, new).decode("utf-8", "surrogateescape"))
                # tarfile regenerates these from the fields above
                member.pax_headers = {k: v for k, v in member.pax_headers.items() if k not in ("path", "linkpath", "size")}
                data = None
                if member.isreg():
                    data = src.extractfile(member).read()
                    if OLD in data:
                        count += data.count(OLD)
                        data = data.replace(OLD, new)
                    member.size = len(data)
                dst.addfile(member, io.BytesIO(data) if data is not None else None)
        rezstd.stdin.close()
        if rezstd.wait() != 0 or unzstd.wait() != 0:
            raise SystemExit("zstd failed on " + path)
    os.replace(out_path, path)
    return count


def main():
    assets, package = sys.argv[1], sys.argv[2]
    new = ("/data/data/" + package).encode()
    if len(new) != len(OLD):
        raise SystemExit(f"package id must have {len(OLD) - len('/data/data/')} characters, like com.winlator")
    total = 0
    for root, _, files in os.walk(assets):
        for name in sorted(files):
            path = os.path.join(root, name)
            if name.endswith(".tzst"):
                # cheap pre-check: skip archives without the path
                listing = subprocess.run(["zstd", "-dcq", path], stdout=subprocess.PIPE, check=True).stdout
                if OLD not in listing:
                    continue
                n = rewrite_tzst(path, new)
            else:
                with open(path, "rb") as f:
                    data = f.read()
                n = data.count(OLD)
                if n:
                    with open(path, "wb") as f:
                        f.write(data.replace(OLD, new))
            if n:
                print(f"  {os.path.relpath(path, assets)}: {n}")
                total += n
    print(f"{total} paths moved to /data/data/{package}")
    if total == 0:
        raise SystemExit("no /data/data/com.winlator path found: did the Winlator assets change?")


if __name__ == "__main__":
    main()
