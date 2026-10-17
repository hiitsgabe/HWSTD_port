#!/bin/bash
# Fetch cnc-ddraw (DirectDraw wrapper for the Windows and macOS packages) into
# build/cnc-ddraw/{ddraw.dll,LICENSE}.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CNC_VER=${CNC_VER:-v7.1.0.0}
OUT="$ROOT/build/cnc-ddraw"
[ -f "$OUT/$CNC_VER.stamp" ] && exit 0
rm -rf "$OUT" && mkdir -p "$OUT"
curl -fsSL -o "$OUT/cnc-ddraw.zip" "https://github.com/FunkyFr3sh/cnc-ddraw/releases/download/$CNC_VER/cnc-ddraw.zip"
unzip -q -j -o "$OUT/cnc-ddraw.zip" ddraw.dll -d "$OUT" && rm "$OUT/cnc-ddraw.zip"
curl -fsSL -o "$OUT/LICENSE" "https://raw.githubusercontent.com/FunkyFr3sh/cnc-ddraw/$CNC_VER/LICENSE"
touch "$OUT/$CNC_VER.stamp"
