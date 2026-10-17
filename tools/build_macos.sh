#!/bin/bash
# Build dist/HWSTD-macos.zip: "Hot Wheels Stunt Track Driver.app" with a bundled
# x86_64 Wine (Gcenx macOS build; Rosetta 2 on Apple Silicon). No game files.
# macOS only (ditto keeps the bundle's symlinks).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WINE_VER=${MAC_WINE_VER:-11.18}
CACHE="$ROOT/build/macos"
APP="$ROOT/dist/Hot Wheels Stunt Track Driver.app"

mkdir -p "$CACHE"
if [ ! -d "$CACHE/wine-$WINE_VER" ]; then
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/Gcenx/macOS_Wine_builds/releases/download/$WINE_VER/wine-devel-$WINE_VER-osx64.tar.xz" | tar -xJ -C "$tmp"
  mv "$tmp/Wine Devel.app/Contents/Resources/wine" "$CACHE/wine-$WINE_VER" && rm -rf "$tmp"
  curl -fsSL "https://gitlab.winehq.org/wine/wine/-/raw/wine-$WINE_VER/COPYING.LIB" -o "$CACHE/wine-$WINE_VER.COPYING.LIB"
fi

rm -rf "$APP" "$ROOT/dist/HWSTD-macos.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/licenses"
cp "$ROOT/macos/Info.plist" "$APP/Contents/"
cp "$ROOT/macos/launcher.sh" "$APP/Contents/MacOS/launcher"
chmod +x "$APP/Contents/MacOS/launcher"
ditto "$CACHE/wine-$WINE_VER" "$APP/Contents/Resources/wine"
rm -rf "$APP/Contents/Resources/wine/include" "$APP/Contents/Resources/wine/share/man"
find "$APP/Contents/Resources/wine/lib" -name '*.a' -delete
cp "$CACHE/wine-$WINE_VER.COPYING.LIB" "$APP/Contents/Resources/licenses/wine.COPYING.LIB"

(cd "$ROOT/dist" && ditto -c -k --sequesterRsrc --keepParent "Hot Wheels Stunt Track Driver.app" HWSTD-macos.zip)
du -sh "$APP"; ls -lh "$ROOT/dist/HWSTD-macos.zip"
