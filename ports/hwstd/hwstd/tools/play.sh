#!/bin/bash
# Run by westonwrap with BOX64 and WINE set: start the B-button helper next to the
# game (it needs the X display westonwrap provides), then the game in a 640x480 Wine
# desktop. The game command lives here, not in westonwrap's arguments, because
# gptokeyb quits with `pkill -f stunt.exe`. The helper must not outlive the game:
# an X client left behind keeps Xwayland and Weston up.
python3 "$(dirname "$0")/bkey.py" &
helper=$!
trap 'kill $helper 2>/dev/null' EXIT
trap 'exit 143' INT TERM
# In the background + wait, so a TERM runs the traps at once instead of after the game.
"$BOX64" "$WINE" explorer /desktop=hwstd,640x480 stunt.exe &
wait $!
