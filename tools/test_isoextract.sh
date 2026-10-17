#!/bin/bash
# Check isoextract.py against the OS's own ISO mount (macOS hdiutil).
# usage: tools/test_isoextract.sh "/path/to/Hot Wheels - Stunt Track Driver.iso"
set -e
ISO=${1:?iso path}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$(mktemp -d)
MNT=$(hdiutil attach -readonly -nobrowse -noverify "$ISO" | awk -F'\t' '/\/Volumes\//{print $NF}')
trap 'hdiutil detach "$MNT" >/dev/null; rm -rf "$OUT"' EXIT

python3 -I "$ROOT/ports/hwstd/hwstd/tools/isoextract.py" "$ISO" setup/hot98 "$OUT/hot98"
diff -r "$MNT/setup/hot98" "$OUT/hot98" && echo "PASS: extracted tree matches mounted ISO"
