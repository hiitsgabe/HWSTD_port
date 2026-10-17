#!/usr/bin/env python3
"""Extract one directory tree from an ISO9660 image. Stdlib only.

usage: isoextract.py IMAGE.iso SRC/DIR DEST
Prefers Joliet names (real case), falls back to ISO9660 primary names.
"""
import os
import struct
import sys

SECTOR = 2048


def volume_root(f):
    """Return (root_lba, root_size, joliet) from the best volume descriptor."""
    primary = None
    for n in range(16, 64):
        f.seek(n * SECTOR)
        vd = f.read(SECTOR)
        kind = vd[0]
        if kind == 255:
            break
        root = vd[156:156 + 34]
        lba, size = struct.unpack_from('<I', root, 2)[0], struct.unpack_from('<I', root, 10)[0]
        if kind == 2 and vd[88:91] in (b'%/@', b'%/C', b'%/E'):
            return lba, size, True
        if kind == 1:
            primary = (lba, size, False)
    if not primary:
        sys.exit('not an ISO9660 image')
    return primary


def entries(f, lba, size, joliet):
    """Yield (name, lba, size, is_dir) for a directory extent."""
    f.seek(lba * SECTOR)
    data = f.read(size)
    pos = 0
    while pos < len(data):
        rlen = data[pos]
        if rlen == 0:  # records never cross sectors; skip padding
            pos = (pos // SECTOR + 1) * SECTOR
            continue
        rec = data[pos:pos + rlen]
        pos += rlen
        nlen = rec[32]
        raw = rec[33:33 + nlen]
        if raw in (b'\0', b'\1'):
            continue
        name = raw.decode('utf-16-be') if joliet else raw.decode('latin1')
        name = name.split(';')[0]
        if not joliet and name.endswith('.'):
            name = name[:-1]
        yield name, struct.unpack_from('<I', rec, 2)[0], struct.unpack_from('<I', rec, 10)[0], bool(rec[25] & 2)


def find(f, lba, size, joliet, path):
    for part in [p for p in path.split('/') if p]:
        for name, l, s, d in entries(f, lba, size, joliet):
            if d and name.lower() == part.lower():
                lba, size = l, s
                break
        else:
            sys.exit(f'{path}: not found in image')
    return lba, size


def extract(f, lba, size, joliet, dest):
    os.makedirs(dest, exist_ok=True)
    count = 0
    for name, l, s, d in entries(f, lba, size, joliet):
        out = os.path.join(dest, name)
        if d:
            count += extract(f, l, s, joliet, out)
            continue
        f.seek(l * SECTOR)
        with open(out, 'wb') as o:
            left = s
            while left:
                chunk = f.read(min(left, 1 << 20))
                o.write(chunk)
                left -= len(chunk)
        count += 1
    return count


def main(image, src, dest):
    with open(image, 'rb') as f:
        lba, size, joliet = volume_root(f)
        lba, size = find(f, lba, size, joliet, src)
        n = extract(f, lba, size, joliet, dest)
    print(f'extracted {n} files from {src} to {dest}')


if __name__ == '__main__':
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
