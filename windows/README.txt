Hot Wheels Stunt Track Driver for Windows 10/11
https://github.com/hiitsgabe/HWSTD_port

You need your own copy of the game CD.

1. Put your CD image (.iso) in this folder, or keep it anywhere and pick it
   when asked.
2. Double-click Install.cmd. It copies the game into the "game" folder.
3. Double-click Play.cmd to play.

Already have the files? Copy everything inside the CD's setup\hot98 folder
into "game", plus cnc-ddraw\ddraw.dll and cnc-ddraw\ddraw.ini.

cnc-ddraw (MIT license, see cnc-ddraw\LICENSE) replaces the game's DirectDraw
so its 256-color graphics display correctly on modern Windows. Edit
game\ddraw.ini to change its settings (e.g. fullscreen=false for a window).
