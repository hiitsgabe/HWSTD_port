#!/bin/bash
# Fetch/build the x86 layer into ports/hwstd/hwstd/ (gitignored):
#   box64/box64  - aarch64 box64, built on Debian bookworm (glibc 2.36) so it runs on older CFWs
#   wine.squashfs - Kron4ek Wine amd64 WoW64 build (runs the 32-bit stunt.exe under box64).
#                   Squashfs because device SD cards are often exFAT (no symlinks); the
#                   launcher mounts it read-only like a PortMaster runtime.
# Needs docker with linux/arm64 (OrbStack on Apple Silicon works natively).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/ports/hwstd/hwstd"
WORK="$ROOT/build"  # unpacked wine kept here for VM testing
WINE_VER=${WINE_VER:-10.0}  # 11.x aborts in anon_mmap_alloc under box64 on the H700 4.9 kernel
BOX64_REF=${BOX64_REF:-main}  # Tracks main; pin a commit once a device-tested build exists

mkdir -p "$DEST/licenses"

if [ ! -x "$DEST/box64/box64" ] || [ ! -d "$DEST/box64/x64lib" ]; then
  docker run --rm --platform linux/arm64 -v "$DEST:/out" debian:bookworm bash -ec "
    apt-get update -qq && apt-get install -y -qq git cmake build-essential python3 >/dev/null
    git clone -q --depth 1 -b $BOX64_REF https://github.com/ptitSeb/box64 /src
    cmake -S /src -B /build -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
    make -C /build -j\$(nproc) >/dev/null
    mkdir -p /out/box64 && strip -o /out/box64/box64 /build/box64
    cp -r /src/x64lib /out/box64/x64lib  # x86_64 libgcc_s/libstdc++ needed by Wine
    cp /src/LICENSE /out/licenses/box64.LICENSE"
fi

if [ ! -x "$WORK/wine/bin/wine" ]; then
  mkdir -p "$WORK" && tmp=$(mktemp -d)
  curl -fsSL "https://github.com/Kron4ek/Wine-Builds/releases/download/$WINE_VER/wine-$WINE_VER-amd64-wow64.tar.xz" | tar -xJ -C "$tmp"
  rm -rf "$WORK/wine" && mv "$tmp/wine-$WINE_VER-amd64-wow64" "$WORK/wine" && rmdir "$tmp"
  # Not needed at runtime: headers, static import libs, man pages, desktop files.
  rm -rf "$WORK/wine/include" "$WORK/wine/share/man" "$WORK/wine/share/applications"
  find "$WORK/wine/lib" -name '*.a' -delete
  curl -fsSL "https://gitlab.winehq.org/wine/wine/-/raw/wine-$WINE_VER/COPYING.LIB" -o "$DEST/licenses/wine.COPYING.LIB"
  rm -f "$DEST/wine.squashfs"
fi

if [ ! -f "$DEST/wine.squashfs" ]; then
  docker run --rm --platform linux/arm64 -v "$WORK:/in:ro" -v "$DEST:/out" debian:bookworm bash -ec "
    apt-get update -qq && apt-get install -y -qq squashfs-tools >/dev/null
    mksquashfs /in/wine /out/wine.squashfs -comp xz -all-root -no-xattrs -noappend -quiet"
fi

du -sh "$DEST/box64" "$DEST/wine.squashfs"
