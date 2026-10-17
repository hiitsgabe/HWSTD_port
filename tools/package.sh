#!/bin/bash
# Build dist/hwstd.zip: unzip it into the device's ports/ folder.
#   Hot Wheels Stunt Track Driver.sh
#   hwstd/  (box64, wine.squashfs, gptk, tools, licenses, port metadata)
# Run tools/fetch_deps.sh first.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/ports/hwstd"
OUT="$ROOT/dist"
STAGE="$OUT/stage"

for f in "Hot Wheels Stunt Track Driver.sh" port.json README.md gameinfo.xml screenshot.png \
         hwstd/hwstd.gptk hwstd/tools/isoextract.py hwstd/box64/box64 hwstd/box64/x64lib/libgcc_s.so.1 \
         hwstd/wine.squashfs hwstd/licenses/box64.LICENSE hwstd/licenses/wine.COPYING.LIB; do
  [ -e "$SRC/$f" ] || { echo "missing: $f (run tools/fetch_deps.sh?)" >&2; exit 1; }
done

rm -rf "$STAGE" "$OUT/hwstd.zip" && mkdir -p "$STAGE/hwstd"
cp "$SRC/Hot Wheels Stunt Track Driver.sh" "$STAGE/"
cp -R "$SRC/hwstd/hwstd.gptk" "$SRC/hwstd/tools" "$SRC/hwstd/box64" "$SRC/hwstd/licenses" "$SRC/hwstd/wine.squashfs" "$STAGE/hwstd/"
cp "$SRC/port.json" "$SRC/README.md" "$SRC/gameinfo.xml" "$SRC/screenshot.png" "$STAGE/hwstd/"
mkdir -p "$STAGE/hwstd/gamedata"
echo "Copy the CD's setup/hot98 folder contents here (stunt.exe, data, menudata, saves)." > "$STAGE/hwstd/gamedata/PUT_GAME_FILES_HERE.txt"
chmod +x "$STAGE/Hot Wheels Stunt Track Driver.sh" "$STAGE/hwstd/box64/box64"

(cd "$STAGE" && zip -qr -X "$OUT/hwstd.zip" .)
rm -rf "$STAGE"
ls -lh "$OUT/hwstd.zip"
