## Notes

Thanks to Semi Logic Entertainments and Mattel Media for the original game, to ptitSeb for [box64](https://github.com/ptitSeb/box64), to the Wine project and Kron4ek for the [Wine builds](https://github.com/Kron4ek/Wine-Builds), and to binarycounter for [Westonpack](https://github.com/binarycounter/Westonpack).

This port runs the original Windows release. You need your own copy of the game CD. Either:

- copy everything inside the CD's `setup/hot98/` folder (`stunt.exe`, `data`, `menudata`, `saves`) into `ports/hwstd/gamedata/`, or
- copy the CD image (`.iso`) into `ports/hwstd/` and the port extracts that folder itself.

The first launch prepares Wine, which takes a few minutes.

The game renders entirely in software, so it does not need a GPU or OpenGL.

## Controls

| Button | Action |
|--|--|
| Left stick | Move mouse cursor (menus) |
| A | Mouse click |
| L1 (hold) | Slow cursor |
| D-pad | Arrow keys (race) |
| B | Skip the intro; leave a race (Esc). On the menus it does nothing: use the on-screen arrows |
| X | Space (skip the intro) |
| Select | Esc (quits the game from the menus) |
| Start | Enter |
| Select + Start | Quit |
