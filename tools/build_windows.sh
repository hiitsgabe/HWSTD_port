#!/bin/bash
# Build dist/HWSTD-windows.zip: installer scripts + cnc-ddraw. No game files.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CNC_VER=${CNC_VER:-v7.1.0.0}
STAGE="$ROOT/dist/windows-stage/HWSTD"
CACHE="$ROOT/build/windows"

mkdir -p "$CACHE"
if [ ! -f "$CACHE/cnc-ddraw-$CNC_VER.zip" ]; then
  curl -fsSL -o "$CACHE/cnc-ddraw-$CNC_VER.zip" "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/$CNC_VER/cnc-ddraw.zip"
  curl -fsSL -o "$CACHE/cnc-ddraw-$CNC_VER.LICENSE" "https://raw.githubusercontent.com/FunkyFr3sh/cnc-ddraw/$CNC_VER/LICENSE"
fi

rm -rf "$ROOT/dist/windows-stage" "$ROOT/dist/HWSTD-windows.zip"
mkdir -p "$STAGE/cnc-ddraw"
cp "$ROOT"/windows/{Install.cmd,Play.cmd,install.ps1,README.txt} "$STAGE/"
cp "$ROOT/windows/ddraw.ini" "$STAGE/cnc-ddraw/"
cp "$CACHE/cnc-ddraw-$CNC_VER.LICENSE" "$STAGE/cnc-ddraw/LICENSE"
unzip -q -j -o "$CACHE/cnc-ddraw-$CNC_VER.zip" ddraw.dll -d "$STAGE/cnc-ddraw"

# Windows line endings for everything a user might open in Notepad.
for f in "$STAGE"/*.cmd "$STAGE"/*.ps1 "$STAGE"/*.txt "$STAGE"/cnc-ddraw/ddraw.ini; do
  sed -i.bak 's/\r*$/\r/' "$f" && rm "$f.bak"
done

(cd "$ROOT/dist/windows-stage" && zip -qr -X "$ROOT/dist/HWSTD-windows.zip" HWSTD)
rm -rf "$ROOT/dist/windows-stage"
ls -lh "$ROOT/dist/HWSTD-windows.zip"
