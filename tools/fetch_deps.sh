#!/bin/bash
# Fetch/build the x86 layer into ports/hwstd/hwstd/ (gitignored):
#   box64/box64  - aarch64 box64, built on Debian bookworm (glibc 2.36) so it runs on older CFWs
#   wine/        - Kron4ek Wine amd64 WoW64 build (runs the 32-bit stunt.exe under box64)
# Needs docker with linux/arm64 (OrbStack on Apple Silicon works natively).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/ports/hwstd/hwstd"
WINE_VER=${WINE_VER:-11.19}
BOX64_REF=${BOX64_REF:-main}  # Tracks main; pin a commit once a device-tested build exists

mkdir -p "$DEST/licenses"

if [ ! -x "$DEST/box64/box64" ]; then
  docker run --rm --platform linux/arm64 -v "$DEST:/out" debian:bookworm bash -ec "
    apt-get update -qq && apt-get install -y -qq git cmake build-essential python3 >/dev/null
    git clone -q --depth 1 -b $BOX64_REF https://github.com/ptitSeb/box64 /src
    cmake -S /src -B /build -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
    make -C /build -j\$(nproc) >/dev/null
    mkdir -p /out/box64 && strip -o /out/box64/box64 /build/box64
    cp /src/LICENSE /out/licenses/box64.LICENSE"
fi

if [ ! -x "$DEST/wine/bin/wine" ]; then
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/Kron4ek/Wine-Builds/releases/download/$WINE_VER/wine-$WINE_VER-amd64-wow64.tar.xz" | tar -xJ -C "$tmp"
  rm -rf "$DEST/wine" && mv "$tmp/wine-$WINE_VER-amd64-wow64" "$DEST/wine" && rmdir "$tmp"
  # Not needed at runtime: headers, static import libs, man pages, desktop files.
  rm -rf "$DEST/wine/include" "$DEST/wine/share/man" "$DEST/wine/share/applications"
  find "$DEST/wine/lib" -name '*.a' -delete
  curl -fsSL "https://gitlab.winehq.org/wine/wine/-/raw/wine-$WINE_VER/COPYING.LIB" -o "$DEST/licenses/wine.COPYING.LIB"
fi

du -sh "$DEST/box64" "$DEST/wine"
