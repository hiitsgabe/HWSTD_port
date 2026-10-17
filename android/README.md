# Hot Wheels: Stunt Track Driver on Android

`build_apk.sh` builds an arm64 APK that boots straight into the game, without going through the Winlator interface.
The APK contains no game files: on first launch it asks for your own ISO.

## Approach

A small fork of [Winlator](https://github.com/brunodev85/winlator-app) (Wine + Box64 + its own X server, LGPL-2.1).
The script fetches Winlator at a pinned commit, applies `winlator.patch`, copies `overlay/` on top and builds it.

Alternatives considered:

- **A new app bundling Box64 + Wine + Termux-X11**: it would mean rebuilding glibc, Wine and Box64 for Android and writing the app, months of work to reach what Winlator already does.
- **Bigger forks (Winlator Ludashi/cmod, GameNative)**: 550 to 700 MB APKs against about 160 MB for upstream, and nothing this game needs (it uses software DirectDraw, no accelerated 3D).

What changes compared to Winlator (about 25 lines of patch and four new files):

| File | What it does |
|---|---|
| `overlay/.../StuntLauncher.java` | On app start: creates the "Stunt Track Driver" container once, asks for the ISO, copies `SETUP/HOT98` to `C:\hot98` and launches `stunt.exe`. Also holds the Game Settings dialog |
| `overlay/.../IsoExtractor.java` | Minimal ISO 9660 reader, no dependencies |
| `overlay/.../controls-5.icp` | Controls profile: on-screen buttons and a mapping for any gamepad |
| `rename_package.py` | Moves the paths baked into Winlator's assets to the app's package id (see below) |
| `winlator.patch` | Sets the package id to `com.hwstd.td`; calls StuntLauncher after the system files are installed; closes the app when the game exits; adds Game Settings to the in-game menu; accepts the `*` controller id (any gamepad); lets stick motion reach the profile before the XInput bridge; hidden controls no longer catch touches; the X server refuses pointer grabs on disabled windows (see below); renames the app |

The app has its own package id, `com.hwstd.td`, and installs next to Winlator.
Winlator's prebuilt binaries (rootfs, Box64, drivers) have `/data/data/com.winlator` baked into about 460 places: RPATH, ELF interpreter, glibc paths.
`com.hwstd.td` has the same length as `com.winlator`, so `rename_package.py` replaces that path byte for byte inside the `.tzst` archives and rewrites the tar headers (symlinks and checksums).
The patch does the same in the C headers, `AppUtils.java` and the FileProvider authority.
To change the id, keep it at 12 characters, and update `PACKAGE_ID` in `build_apk.sh` and the `com.hwstd.td` occurrences in `winlator.patch`.

## Building the APK

Requirements: git, python3, zstd, JDK 17 to 21 and the Android SDK with `sdkmanager`.
The script installs NDK 24, CMake 3.22.1 and platform 35 by itself.
On macOS, `brew install openjdk@21 android-commandlinetools` covers it.

```bash
android/build_apk.sh
```

The APK lands in `android/out/StuntTrackDriver-winlator-<commit>.apk` (about 160 MB).
The first build downloads about 330 MB of Winlator source and assets into `android/.cache/`.
The assets include the rootfs with Wine 10.10 and Box64 0.4.4, prebuilt by the Winlator author: the script does not rebuild them.

## Usage

1. Install the APK (`adb install -r android/out/*.apk`) and open **Stunt Track Driver**.
2. Allow storage access and wait for the system files to install (first launch only).
3. Pick the game's ISO in the file picker. The `SETUP/HOT98` folder (about 470 MB) is copied into the app, so the ISO can be deleted afterwards.
4. The game starts. Quitting the game closes the app; opening it again goes straight to the game.

If you cancel the picker, the regular Winlator interface shows up; close and reopen the app to try again.

## Controls

**Touch**: the middle of the screen works as a touchpad for the menus (drag to move the mouse, tap to click).
◀ ▶ are at the bottom left; accelerate (▲) and brake (▼) are on the right; ESC and ENTER are at the top.

**Xbox-style gamepad** (any controller Android recognizes; the profile uses the `*` id):

| Control | Key or mouse |
|---|---|
| Left stick, D-pad | Arrow keys |
| RT / LT | ↑ accelerate / ↓ brake |
| Right stick | Moves the mouse |
| A | Left click |
| B, Back | ESC |
| X, Start | ENTER |
| Y | Space |

To change the bindings: in-game side menu (Back button) → Input Controls → "Stunt Track Driver" profile.

## Game Settings

In the game, Android's Back button opens the side menu; the first item is **Game Settings**.
Changes apply immediately and are kept for the next launches:

| Option | Default | Effect |
|---|---|---|
| Show touch controls | on | Off: the overlay disappears and the hidden buttons don't catch touches (the whole screen becomes a touchpad). The gamepad keeps working |
| Stretch to fill screen | off | On: stretches 640x480 to the whole screen. Off: keeps 4:3 with side bars |
| Gamepad support | on | Off: the gamepad is no longer mapped to keyboard and mouse |

## Menu mouse input: Winlator fix

The game reads the mouse through exclusive DirectInput with `SetEventNotification`, so it only looks at the mouse when DirectInput signals an event.
On unpatched Winlator the mouse did nothing in the menus.
The cause: Wine calls `XGrabPointer` on its clip window, which belongs to `explorer.exe`. Winlator's desktop workaround disables that window, and a grab on a disabled window swallows every pointer event.
The patch makes the X server refuse grabs on disabled windows (`GrabRequests.java`). Wine carries on without the grab and the events get through.

## Wine configuration

StuntLauncher applies the same configuration that works on Linux (Box64 + Wine 11):

| Setting | How |
|---|---|
| Builtin ddraw on the GDI renderer, no GPU | Container with the `wined3d` DX wrapper and `renderer=gdi`. Winlator turns this into `WINE_D3D_CONFIG`, which takes precedence over `HKCU\Software\Wine\Direct3D\renderer`, so the value is not written to the registry |
| `HKLM\Software\Mattel\Stunt Track Driver\1.0` key | Written empty to `system.reg`, also under `Wow6432Node` (32-bit view) |
| Winlator's native DLLs (wincomponents) | All off: Wine builtins only |
| Resolution | 640x480 X screen (the game runs at 640x480; F1 switches to 320x240) |
| Audio | Winlator's ALSA, output to Android. Without audio the game stops at "Sound card not found" |

Winlator's prefix comes ready, so there is no Wine Mono prompt.

## License

The patch and the overlay derive from Winlator and are under LGPL-2.1.
The built APK redistributes Winlator, Wine, Box64 and Mesa under their own licenses. Do not publish APKs that include game files.
