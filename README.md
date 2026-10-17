# Hot Wheels Stunt Track Driver port

Runs the 1998 Windows game *Hot Wheels Stunt Track Driver* on ARM Linux handhelds (Anbernic H700 family: RG35XXSP, RG34XXSP, …) as a [PortMaster](https://portmaster.games) package, using box64 + Wine. Game files are never included: the user supplies their own CD image.

## Why it works

`setup/hot98/stunt.exe` on the CD imports only `DDRAW` (`DirectDrawCreate`, `IDirectDraw2`), `DINPUT` and `DSOUND`. There is no Direct3D or Glide: the 3D is rendered in software into an 8-bit 640x480 surface (F1 in-race switches to 320x240 / 320x200). So Wine can present it through its GDI DirectDraw path (`HKCU\Software\Wine\Direct3D\renderer=gdi`) with no GPU at all, which sidesteps the Mali-G31 (GLES only, no Vulkan).

Verified in an Ubuntu 24.04 arm64 VM (OrbStack, Apple M1) with box64 (git main) and Wine 11.19 amd64-wow64: intro videos, menus and a 3D race all run. Findings:

- No installer and no CD check: copying `setup/hot98` is enough. The game reads the (empty) key `HKLM\Software\Mattel\Stunt Track Driver\1.0`.
- Without an audio device it stops at "Sound card not found, or fail in sound init." Any working ALSA/PulseAudio output fixes it.
- Menus read a relative DirectInput mouse; races use the arrow keys.
- `WINEDLLOVERRIDES="mscoree,mshtml="` avoids Wine's Mono/Gecko install prompt on first boot.
- About 245 MB RAM for the game process.

## Layout

```
ports/hwstd/                      PortMaster package (zip root)
  Hot Wheels Stunt Track Driver.sh  launcher
  port.json, README.md, gameinfo.xml, screenshot.png
  hwstd/
    hwstd.gptk                    controls
    tools/isoextract.py           stdlib-only ISO9660 extractor (first run)
    licenses/
    box64/, wine/                 fetched by tools/fetch_deps.sh (gitignored)
tools/
  fetch_deps.sh                   build box64 (Debian bookworm container) + fetch pruned Wine
  test_isoextract.sh              extractor check against a real mount (macOS)
```

## Build

```bash
tools/fetch_deps.sh
```

Then copy `ports/hwstd/*` into the device's `ports/` folder, and put your `.iso` in `ports/hwstd/`.

## Status

- [x] Runs under box64 + Wine on arm64 (VM)
- [x] Package skeleton, ISO extraction
- [ ] On-device test (Knulli, RG35XXSP): Westonpack display, audio, FPS
- [ ] Controls for devices without analog sticks
