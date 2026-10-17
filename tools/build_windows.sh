#!/bin/bash
# Build dist/HWSTD-windows.zip: installer scripts + cnc-ddraw. No game files.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE="$ROOT/dist/windows-stage/HWSTD"

"$ROOT/tools/fetch_cnc.sh"

rm -rf "$ROOT/dist/windows-stage" "$ROOT/dist/HWSTD-windows.zip"
mkdir -p "$STAGE/cnc-ddraw"
cp "$ROOT"/windows/{Install.cmd,Play.cmd,install.ps1,README.txt} "$STAGE/"
cp "$ROOT/windows/ddraw.ini" "$STAGE/cnc-ddraw/"
cp "$ROOT/build/cnc-ddraw/ddraw.dll" "$ROOT/build/cnc-ddraw/LICENSE" "$STAGE/cnc-ddraw/"

# Windows line endings for everything a user might open in Notepad.
for f in "$STAGE"/*.cmd "$STAGE"/*.ps1 "$STAGE"/*.txt "$STAGE"/cnc-ddraw/ddraw.ini; do
  sed -i.bak 's/\r*$/\r/' "$f" && rm "$f.bak"
done

(cd "$ROOT/dist/windows-stage" && zip -qr -X "$ROOT/dist/HWSTD-windows.zip" HWSTD)
rm -rf "$ROOT/dist/windows-stage"
ls -lh "$ROOT/dist/HWSTD-windows.zip"
