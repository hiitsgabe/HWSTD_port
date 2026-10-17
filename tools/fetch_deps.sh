#!/bin/bash
# Fetch/build the x86 layer into ports/hwstd/hwstd/ (gitignored):
#   box64/box64   - aarch64 box64 + its x86_64 libs, built on Ubuntu 22.04 (glibc 2.35)
#                   so it runs on older CFWs
#   wine.squashfs - Kron4ek Wine amd64 WoW64 build (runs the 32-bit stunt.exe under box64).
#                   Squashfs because device SD cards are often exFAT (no symlinks); the
#                   launcher mounts it read-only like a PortMaster runtime.
# On an arm64 Linux host (CI) the arm64 steps run natively and need
# git cmake build-essential python3 squashfs-tools; elsewhere they run in docker
# (linux/arm64, e.g. OrbStack on Apple Silicon).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/ports/hwstd/hwstd"
WORK="$ROOT/build"  # unpacked wine kept here for VM testing
WINE_VER=${WINE_VER:-10.0}  # 11.x aborts in anon_mmap_alloc under box64 on the H700 4.9 kernel
BOX64_REF=${BOX64_REF:-main}  # Tracks main; pin a commit once a device-tested build exists

arm64() {
  if [ "$(uname -sm)" = "Linux aarch64" ]; then
    bash -ec "$1"
  else
    docker run --rm --platform linux/arm64 -v "$ROOT:$ROOT" ubuntu:22.04 bash -ec "
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq && apt-get install -y -qq git cmake build-essential python3 squashfs-tools >/dev/null
      $1"
  fi
}

mkdir -p "$DEST/licenses" "$WORK"

if [ ! -x "$DEST/box64/box64" ] || [ ! -d "$DEST/box64/x64lib" ]; then
  arm64 "
    rm -rf '$WORK/box64-src' '$WORK/box64-build'
    git clone -q --depth 1 -b $BOX64_REF https://github.com/ptitSeb/box64 '$WORK/box64-src'
    cmake -S '$WORK/box64-src' -B '$WORK/box64-build' -DARM_DYNAREC=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo >/dev/null
    make -C '$WORK/box64-build' -j\$(nproc) >/dev/null
    rm -rf '$DEST/box64' && mkdir -p '$DEST/box64'
    strip -o '$DEST/box64/box64' '$WORK/box64-build/box64'
    cp -r '$WORK/box64-src/x64lib' '$DEST/box64/x64lib'  # x86_64 libgcc_s/libstdc++ needed by Wine
    cp '$WORK/box64-src/LICENSE' '$DEST/licenses/box64.LICENSE'"
fi

if [ ! -x "$WORK/wine/bin/wine" ]; then
  tmp=$(mktemp -d)
  curl -fsSL "https://github.com/Kron4ek/Wine-Builds/releases/download/$WINE_VER/wine-$WINE_VER-amd64-wow64.tar.xz" | tar -xJ -C "$tmp"
  rm -rf "$WORK/wine" && mv "$tmp/wine-$WINE_VER-amd64-wow64" "$WORK/wine" && rmdir "$tmp"
  # Not needed at runtime: headers, static import libs, man pages, desktop files.
  rm -rf "$WORK/wine/include" "$WORK/wine/share/man" "$WORK/wine/share/applications"
  find "$WORK/wine/lib" -name '*.a' -delete
  curl -fsSL "https://gitlab.winehq.org/wine/wine/-/raw/wine-$WINE_VER/COPYING.LIB" -o "$DEST/licenses/wine.COPYING.LIB"
  rm -f "$DEST/wine.squashfs"
fi

if [ ! -f "$DEST/wine.squashfs" ]; then
  arm64 "mksquashfs '$WORK/wine' '$DEST/wine.squashfs' -comp xz -all-root -no-xattrs -noappend -quiet"
fi

du -sh "$DEST/box64" "$DEST/wine.squashfs"
