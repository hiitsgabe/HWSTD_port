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
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

GAMEDIR="/$directory/ports/hwstd"
cd "$GAMEDIR"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Bundled x86 layer: box64 (aarch64) + Wine amd64 WoW64 build (runs the 32-bit exe).
# SD cards are often exFAT (no symlinks), so Wine ships as a squashfs and the Wine
# prefix lives in an ext4 image; both are mounted under /tmp only while the game runs.
BOX64="$GAMEDIR/box64/box64"
MNT=/tmp/hwstd
WINE="$MNT/wine/bin/wine"
WINESERVER="$MNT/wine/bin/wineserver"
export WINEPREFIX="$MNT/prefix/pfx"
export WINEDEBUG=-all
export WINEDLLOVERRIDES="mscoree,mshtml="  # no Mono/Gecko install prompt
export BOX64_LOG=0 BOX64_NOBANNER=1
export BOX64_LD_LIBRARY_PATH="$GAMEDIR/box64/x64lib"  # x86_64 libgcc_s/libstdc++ that Wine links against

# First run: the user drops their own CD image (*.iso) in this folder.
# The game runs straight from the CD's setup/hot98 folder, no installer needed.
install_game() {
  local iso
  iso=$(ls "$GAMEDIR"/*.iso "$GAMEDIR"/*.ISO 2>/dev/null | head -n 1)
  if [ -z "$iso" ]; then
    pm_message "Copy the CD folder setup/hot98 into ports/hwstd/gamedata/ (or the CD .iso into ports/hwstd/) and launch again."
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
  # Under box64 on the H700, Wine processes end with SIGKILL even on success,
  # so check what they wrote instead of their exit codes.
  "$BOX64" "$WINE" wineboot -i
  # The game draws in software through DirectDraw: Wine's GDI path needs no GPU.
  "$BOX64" "$WINE" reg add 'HKCU\Software\Wine\Direct3D' /v renderer /d gdi /f
  "$BOX64" "$WINE" reg add 'HKLM\Software\Mattel\Stunt Track Driver\1.0' /f
  # Hide joysticks from Wine: the game crashes (null read at 004290b2) initialising the
  # handheld's pad through DirectInput. gptokeyb feeds it keyboard + mouse instead.
  for v in DisableHidraw DisableInput; do
    "$BOX64" "$WINE" reg add 'HKLM\System\CurrentControlSet\Services\WineBus' /v $v /t REG_DWORD /d 1 /f
  done
  "$BOX64" "$WINE" reg add 'HKLM\System\CurrentControlSet\Services\WineBus' /v 'Enable SDL' /t REG_DWORD /d 0 /f
  "$BOX64" "$WINESERVER" -w
  grep -q '"renderer"="gdi"' "$WINEPREFIX/user.reg" || return 1
  grep -qi 'Mattel\\\\Stunt Track Driver' "$WINEPREFIX/system.reg" || return 1
  grep -q '"DisableInput"=dword:00000001' "$WINEPREFIX/system.reg" || return 1
  touch "$WINEPREFIX/.installed"
}

unmount_all() {
  $ESUDO umount "$MNT/prefix" 2>/dev/null
  $ESUDO umount "$MNT/wine" 2>/dev/null
}

mount_all() {
  $ESUDO mkdir -p "$MNT/wine" "$MNT/prefix"
  unmount_all
  if [ ! -f "$GAMEDIR/prefix.img" ]; then
    pm_message "Creating Wine prefix image (first run, about a minute)..."
    truncate -s 1G "$GAMEDIR/prefix.img" && mkfs.ext4 -q -F "$GAMEDIR/prefix.img" || { rm -f "$GAMEDIR/prefix.img"; return 1; }
  fi
  $ESUDO mount -o ro "$GAMEDIR/wine.squashfs" "$MNT/wine" || return 1
  $ESUDO mount -o loop "$GAMEDIR/prefix.img" "$MNT/prefix" || return 1
  $ESUDO mkdir -p "$WINEPREFIX"
}

[ -f "$GAMEDIR/gamedata/stunt.exe" ] || install_game || exit 1
mount_all || { pm_message "Could not mount Wine files."; sleep 5; unmount_all; exit 1; }
[ -f "$WINEPREFIX/.installed" ] || setup_prefix || { unmount_all; exit 1; }

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

# Races always run at 640x480: lines 3-4 of saves/config.dat hold the race
# resolution (F1 used to cycle it) and the low modes draw 320x200 in a corner.
cfg="$GAMEDIR/gamedata/saves/config.dat"
[ -f "$cfg" ] && sed -i '3s/^[0-9]*/0/;4s/^[0-9]*/0/' "$cfg"

# A 640x480 Wine desktop that Weston's kiosk shell doesn't resize gets centred on
# wider screens (720x480 on the RG34XX-SP). Esc quits the game from its menus (and
# inside the desktop, sometimes from the intro), so B goes through tools/bkey.py
# (gptokeyb sends F12): Esc during a race, Space everywhere else.
# gptokeyb's quit combo runs `pkill -f stunt.exe`, so "stunt.exe" must not appear
# in westonwrap's command line (it would die before stopping Weston: black screen);
# tools/play.sh builds the game command from BOX64 and WINE instead.
cd "$GAMEDIR/gamedata"
$ESUDO env WESTON_KIOSK_NO_RESIZE=1 $weston_dir/westonwrap.sh drm gl kiosk system \
  WINEPREFIX="$WINEPREFIX" WINEDEBUG="$WINEDEBUG" WINEDLLOVERRIDES="$WINEDLLOVERRIDES" \
  BOX64_LOG=0 BOX64_NOBANNER=1 BOX64_LD_LIBRARY_PATH="$BOX64_LD_LIBRARY_PATH" \
  BOX64="$BOX64" WINE="$WINE" "$GAMEDIR/tools/play.sh"

"$BOX64" "$WINESERVER" -k 2>/dev/null
unmount_all
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
fi
pm_finish
