#!/bin/bash

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

GAMEDIR="/$directory/ports/hwstd"
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Bundled x86 layer: box64 (aarch64) + Wine amd64 WoW64 build (runs the 32-bit exe).
BOX64="$GAMEDIR/box64/box64"
WINE="$GAMEDIR/wine/bin/wine"
export WINEPREFIX="$GAMEDIR/prefix"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="  # no Mono/Gecko install prompt
export BOX64_LOG=0 BOX64_NOBANNER=1

# First run: the user drops their own CD image (*.iso) in this folder.
# The game runs straight from the CD's setup/hot98 folder, no installer needed.
install_game() {
  local iso
  iso=$(ls "$GAMEDIR"/*.iso "$GAMEDIR"/*.ISO 2>/dev/null | head -n 1)
  if [ -z "$iso" ]; then
    pm_message "Copy your Hot Wheels Stunt Track Driver CD image (.iso) to ports/hwstd/ and launch again."
    sleep 5
    return 1
  fi
  pm_message "Extracting game files from $(basename "$iso")..."
  rm -rf "$GAMEDIR/gamedata"
  python3 "$GAMEDIR/tools/isoextract.py" "$iso" setup/hot98 "$GAMEDIR/gamedata" || return 1
  [ -f "$GAMEDIR/gamedata/stunt.exe" ] || return 1
}

setup_prefix() {
  pm_message "Preparing Wine (first run, takes a few minutes)..."
  "$BOX64" "$WINE" wineboot -i || return 1
  # The game draws in software through DirectDraw: Wine's GDI path needs no GPU.
  "$BOX64" "$WINE" reg add 'HKCU\Software\Wine\Direct3D' /v renderer /d gdi /f || return 1
  "$BOX64" "$WINE" reg add 'HKLM\Software\Mattel\Stunt Track Driver\1.0' /f || return 1
  "$BOX64" "$GAMEDIR/wine/bin/wineserver" -w
  touch "$WINEPREFIX/.installed"
}

[ -f "$GAMEDIR/gamedata/stunt.exe" ] || install_game || exit 1
[ -f "$WINEPREFIX/.installed" ] || setup_prefix || exit 1

# Wine needs an X11 server: Westonpack provides one.
weston_dir=/tmp/weston
weston_runtime="weston_pkg_0.2"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
$ESUDO mkdir -p "${weston_dir}"
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"

# Menus are mouse driven (relative DirectInput mouse), races use the arrow keys.
$GPTOKEYB "stunt.exe" -c "$GAMEDIR/hwstd.gptk" &
pm_platform_helper "$BOX64"

cd "$GAMEDIR/gamedata"
$ESUDO env $weston_dir/westonwrap.sh drm gl kiosk system \
  WINEPREFIX="$WINEPREFIX" WINEDEBUG="$WINEDEBUG" WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  BOX64_LOG=0 BOX64_NOBANNER=1 \
  "$BOX64" "$WINE" stunt.exe

"$BOX64" "$GAMEDIR/wine/bin/wineserver" -k 2>/dev/null
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
pm_finish
