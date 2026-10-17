#!/bin/bash
# Hot Wheels Stunt Track Driver for macOS: bundled Wine (x86_64, runs under Rosetta 2
# on Apple Silicon) runs the original Windows game from the user's own CD image.
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
DATA="$HOME/Library/Application Support/HWSTD"
GAME="$DATA/game"
WINE="$RES/wine/bin/wine"
WINESERVER="$RES/wine/bin/wineserver"
export WINEPREFIX="$DATA/prefix"
export WINEDEBUG=${WINEDEBUG:--all}  # e.g. WINEDEBUG=trace+msgbox to debug
# No Mono/Gecko install prompt; native ddraw = bundled cnc-ddraw (macOS refuses the
# game's 640x480x8 mode switch, so plain Wine fails with "Can't Init Graphic Card").
export WINEDLLOVERRIDES="mscoree,mshtml=;ddraw=n,b"
mkdir -p "$DATA"
exec > "$DATA/log.txt" 2>&1

alert() { osascript -e "display alert \"Hot Wheels Stunt Track Driver\" message \"$1\"" >/dev/null; }

if [ "$(uname -m)" = "arm64" ] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
  alert "This needs Rosetta 2. Install it with: softwareupdate --install-rosetta"
  exit 1
fi

install_game() {
  local iso mnt
  iso=$(osascript -e 'POSIX path of (choose file with prompt "Select your Hot Wheels Stunt Track Driver CD image (.iso)" of type {"iso", "public.iso-image"})') || return 1
  mnt=$(mktemp -d)
  hdiutil attach -readonly -nobrowse -noverify -mountpoint "$mnt" "$iso" >/dev/null || return 1
  local src
  src=$(find "$mnt" -maxdepth 2 -iname hot98 -type d | head -n 1)
  if [ -z "$src" ] || [ ! -f "$src/stunt.exe" ]; then
    hdiutil detach "$mnt" >/dev/null; alert "setup/hot98/stunt.exe not found in that image."; return 1
  fi
  rm -rf "$GAME" && ditto "$src" "$GAME"
  hdiutil detach "$mnt" >/dev/null
  chmod -R u+w "$GAME"  # CD files are read-only; the game saves next to the exe
}

setup_prefix() {
  "$WINE" wineboot -i
  # The game draws in software through DirectDraw: Wine's GDI path needs no GPU setup.
  "$WINE" reg add 'HKCU\Software\Wine\Direct3D' /v renderer /d gdi /f
  # Joysticks crash the game's DirectInput setup on some pads; it is played with keyboard + mouse.
  for v in DisableHidraw DisableInput; do
    "$WINE" reg add 'HKLM\System\CurrentControlSet\Services\WineBus' /v $v /t REG_DWORD /d 1 /f
  done
  "$WINE" reg add 'HKLM\System\CurrentControlSet\Services\WineBus' /v 'Enable SDL' /t REG_DWORD /d 0 /f
  "$WINESERVER" -w
  grep -q '"renderer"="gdi"' "$WINEPREFIX/user.reg" && touch "$WINEPREFIX/.installed"
}

[ -f "$GAME/stunt.exe" ] || install_game || exit 1
if [ ! -f "$WINEPREFIX/.installed" ]; then
  osascript -e 'display notification "Preparing Wine (first launch only)..." with title "Hot Wheels Stunt Track Driver"'
  setup_prefix || { alert "Could not prepare Wine. See $DATA/log.txt"; exit 1; }
fi

# Refresh cnc-ddraw unless the user edited their own ddraw.ini.
cp "$RES/cnc-ddraw/ddraw.dll" "$GAME/"
[ -f "$GAME/ddraw.ini" ] || cp "$RES/cnc-ddraw/ddraw.ini" "$GAME/"

cd "$GAME"
"$WINE" stunt.exe
"$WINESERVER" -k
