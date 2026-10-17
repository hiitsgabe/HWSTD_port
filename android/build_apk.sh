#!/usr/bin/env bash
# Builds an Android (arm64) APK that runs Hot Wheels: Stunt Track Driver on Winlator.
# Usage: android/build_apk.sh            -> android/out/StuntTrackDriver-winlator-<rev>.apk
# Needs: git, JDK 17-21, Android SDK (ANDROID_HOME or ANDROID_SDK_ROOT) with sdkmanager.
# No game files are involved: the APK asks for the user's own ISO on first launch.
set -euo pipefail

WINLATOR_REPO=https://github.com/brunodev85/winlator-app
WINLATOR_COMMIT=8077f374ef2d54127b088de9e8cd7b4af14d9c8b   # Winlator 11.2 + fixes (2026-10-16)
NDK_VERSION=24.0.8215888                                     # pinned by winlator-app/app/build.gradle

HERE=$(cd "$(dirname "$0")" && pwd)
CACHE=$HERE/.cache
SRC=$CACHE/winlator-app
OUT=$HERE/out

die() { echo "error: $*" >&2; exit 1; }

# --- JDK: Gradle 8.14 runs on 17..24; prefer an explicit 21 or 17 over a too-new default.
java_major() { "$1/bin/java" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1; }
if [ -z "${JAVA_HOME:-}" ] || ! [ "$(java_major "$JAVA_HOME")" -ge 17 -a "$(java_major "$JAVA_HOME")" -le 24 ] 2>/dev/null; then
  JAVA_HOME=
  for candidate in \
      "$(/usr/libexec/java_home -v 21 2>/dev/null || true)" "$(/usr/libexec/java_home -v 17 2>/dev/null || true)" \
      /opt/homebrew/opt/openjdk@21 /opt/homebrew/opt/openjdk@17 /usr/local/opt/openjdk@21 /usr/local/opt/openjdk@17 \
      /usr/lib/jvm/java-21-openjdk* /usr/lib/jvm/java-17-openjdk*; do
    [ -n "$candidate" ] && [ -x "$candidate/bin/java" ] && { JAVA_HOME=$candidate; break; }
  done
  [ -n "$JAVA_HOME" ] || die "JDK 17-21 not found (macOS: brew install openjdk@21; Debian/Ubuntu: apt install openjdk-21-jdk-headless)"
fi
export JAVA_HOME
echo "JDK: $JAVA_HOME"

# --- Android SDK + the exact NDK/CMake Winlator's native code is built with.
SDK=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
if [ -z "$SDK" ]; then
  for candidate in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" /opt/homebrew/share/android-commandlinetools; do
    [ -d "$candidate" ] && { SDK=$candidate; break; }
  done
fi
[ -n "$SDK" ] || die "Android SDK not found; set ANDROID_HOME"
SDKMANAGER=$(command -v sdkmanager || ls "$SDK"/cmdline-tools/*/bin/sdkmanager 2>/dev/null | head -1 || true)
[ -n "$SDKMANAGER" ] || die "sdkmanager not found (install Android command-line tools)"
if [ ! -d "$SDK/ndk/$NDK_VERSION" ] || [ ! -d "$SDK/cmake/3.22.1" ] || [ ! -d "$SDK/platforms/android-35" ]; then
  yes | "$SDKMANAGER" --sdk_root="$SDK" --install "ndk;$NDK_VERSION" "cmake;3.22.1" "platforms;android-35" "build-tools;34.0.0" >/dev/null
fi

# --- Winlator source at a pinned commit (prebuilt rootfs/Wine/Box64 are committed upstream as assets).
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$WINLATOR_REPO"
fi
if [ "$(git -C "$SRC" rev-parse -q --verify HEAD 2>/dev/null)" != "$WINLATOR_COMMIT" ]; then
  git -C "$SRC" fetch -q --depth 1 origin "$WINLATOR_COMMIT"
  git -C "$SRC" checkout -q -f FETCH_HEAD
fi
# Back to pristine upstream (build outputs kept for faster rebuilds), then our changes on top.
git -C "$SRC" reset -q --hard
git -C "$SRC" clean -fdq -e build -e .cxx -e .gradle -e local.properties
git -C "$SRC" apply "$HERE/winlator.patch"
cp -R "$HERE/overlay/." "$SRC/"
echo "sdk.dir=$SDK" > "$SRC/local.properties"

# --- Build. Upstream only configures the (minified, debug-signed) debug variant.
(cd "$SRC" && sh ./gradlew --no-daemon -q assembleDebug)

mkdir -p "$OUT"
APK=$OUT/StuntTrackDriver-winlator-${WINLATOR_COMMIT:0:7}.apk
cp "$SRC/app/build/outputs/apk/debug/app-debug.apk" "$APK"
echo "APK: $APK ($(du -h "$APK" | cut -f1))"
