#!/usr/bin/env python3
"""B button helper for Hot Wheels Stunt Track Driver.

Esc quits the game from its menus (and, inside a Wine desktop, sometimes from the
intro); the menus have on-screen back arrows instead. gptokeyb maps B to F12;
this grabs F12 on the X display and sends:
  - Esc during a race (recognised by the Hot Wheels logo on the race HUD)
  - Space everywhere else (skips the intro, harmless on the menus)

Run inside westonwrap (needs DISPLAY plus libX11/libXtst on LD_LIBRARY_PATH).
`bkey.py --check FILE.ppm` tests the detector on a 640x480 binary PPM.
"""
import ctypes
import os
import signal
import sys
import time

DEBUG = bool(os.environ.get('BKEY_DEBUG'))

# (x, y, (r, g, b)) in game coordinates (640x480): the HUD logo, bottom left.
# Identical on every race shot, far from every intro/menu shot.
RACE_PIXELS = [
    (142, 440, (252, 252, 252)),
    (96, 436, (252, 252, 0)),
    (148, 442, (244, 244, 244)),
    (88, 448, (252, 252, 0)),
    (102, 440, (252, 252, 124)),
    (84, 448, (252, 252, 124)),
]
TOLERANCE = 24      # per channel
NEEDED = 5          # matches out of len(RACE_PIXELS)
HOLD = 0.2          # seconds a sent key stays down (well below the 400 ms key repeat delay)


def is_race(get_pixel):
    hits = 0
    for x, y, ref in RACE_PIXELS:
        rgb = get_pixel(x, y)
        if rgb and all(abs(a - b) <= TOLERANCE for a, b in zip(rgb, ref)):
            hits += 1
    return hits >= NEEDED


def check_ppm(path):
    data = open(path, 'rb').read()
    # binary PPM with a plain "P6\n640 480\n255\n" header
    parts = data.split(b'\n', 3)
    w, h = map(int, parts[1].split())
    pix = parts[3]
    print(is_race(lambda x, y: tuple(pix[(y * w + x) * 3:(y * w + x) * 3 + 3])))


class WindowAttributes(ctypes.Structure):
    _fields_ = [('x', ctypes.c_int), ('y', ctypes.c_int), ('width', ctypes.c_int), ('height', ctypes.c_int),
                ('border_width', ctypes.c_int), ('depth', ctypes.c_int), ('visual', ctypes.c_void_p),
                ('root', ctypes.c_ulong), ('class_', ctypes.c_int), ('bit_gravity', ctypes.c_int),
                ('win_gravity', ctypes.c_int), ('backing_store', ctypes.c_int),
                ('backing_planes', ctypes.c_ulong), ('backing_pixel', ctypes.c_ulong),
                ('save_under', ctypes.c_int), ('colormap', ctypes.c_ulong), ('map_installed', ctypes.c_int),
                ('map_state', ctypes.c_int), ('all_event_masks', ctypes.c_long),
                ('your_event_mask', ctypes.c_long), ('do_not_propagate_mask', ctypes.c_long),
                ('override_redirect', ctypes.c_int), ('screen', ctypes.c_void_p)]


class KeyEvent(ctypes.Structure):  # XKeyEvent
    _fields_ = [('type', ctypes.c_int), ('serial', ctypes.c_ulong), ('send_event', ctypes.c_int),
                ('display', ctypes.c_void_p), ('window', ctypes.c_ulong), ('root', ctypes.c_ulong),
                ('subwindow', ctypes.c_ulong), ('time', ctypes.c_ulong), ('x', ctypes.c_int), ('y', ctypes.c_int),
                ('x_root', ctypes.c_int), ('y_root', ctypes.c_int), ('state', ctypes.c_uint),
                ('keycode', ctypes.c_uint), ('same_screen', ctypes.c_int)]


class KeyboardControl(ctypes.Structure):  # XKeyboardControl
    _fields_ = [(name, ctypes.c_int) for name in ('key_click_percent', 'bell_percent', 'bell_pitch',
                                                    'bell_duration', 'led', 'led_mode', 'key', 'auto_repeat_mode')]


class X:
    def __init__(self):
        self.x = ctypes.CDLL('libX11.so.6')
        self.t = ctypes.CDLL('libXtst.so.6')
        x = self.x
        x.XOpenDisplay.restype = ctypes.c_void_p
        x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x.XDefaultRootWindow.restype = ctypes.c_ulong
        x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        x.XKeysymToKeycode.restype = ctypes.c_ubyte
        x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x.XGrabKey.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_uint, ctypes.c_ulong,
                               ctypes.c_int, ctypes.c_int, ctypes.c_int]
        x.XConnectionNumber.argtypes = [ctypes.c_void_p]
        x.XPending.argtypes = [ctypes.c_void_p]
        x.XNextEvent.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
        x.XUngrabKeyboard.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x.XChangeKeyboardControl.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(KeyboardControl)]
        x.XFlush.argtypes = [ctypes.c_void_p]
        x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                                 ctypes.POINTER(ctypes.c_ulong),
                                 ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                                 ctypes.POINTER(ctypes.c_uint)]
        x.XFree.argtypes = [ctypes.c_void_p]
        x.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(WindowAttributes)]
        x.XGetImage.restype = ctypes.c_void_p
        x.XGetImage.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_int,
                                ctypes.c_uint, ctypes.c_uint, ctypes.c_ulong, ctypes.c_int]
        x.XGetPixel.restype = ctypes.c_ulong
        x.XGetPixel.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
        x.XDestroyImage.argtypes = [ctypes.c_void_p]
        self.t.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]

        # Windows come and go (Wine recreates them): ignore X errors instead of exiting.
        self._handler = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)(lambda d, e: 0)
        x.XSetErrorHandler(self._handler)

        for _ in range(50):  # Xwayland may still be starting
            self.d = x.XOpenDisplay(None)
            if self.d:
                break
            time.sleep(0.2)
        else:
            sys.exit('bkey: cannot open display')
        self.root = x.XDefaultRootWindow(self.d)
        self.kc = {name: x.XKeysymToKeycode(self.d, sym)
                   for name, sym in (('f12', 0xffc9), ('space', 0x20), ('esc', 0xff1b))}

    def grab_f12(self):
        # Keyboard grab in sync mode: while it is active the server queues every other key
        # instead of sending it here, and XUngrabKeyboard hands the queue to the game.
        GrabModeSync, GrabModeAsync, AnyModifier = 0, 1, 1 << 15
        self.x.XGrabKey(self.d, self.kc['f12'], AnyModifier, self.root, 0, GrabModeAsync, GrabModeSync)
        # No key repeat on F12: every KeyPress is a real B press, even when B is held or mashed.
        ctl = KeyboardControl(key=self.kc['f12'], auto_repeat_mode=0)  # AutoRepeatModeOff
        self.x.XChangeKeyboardControl(self.d, (1 << 6) | (1 << 7), ctypes.byref(ctl))  # KBKey | KBAutoRepeatMode
        self.x.XFlush(self.d)

    def game_window(self):
        """Largest viewable window at least 640x480 (the game, or the Wine desktop)."""
        best, best_area = None, 0
        stack = [self.root]
        attrs = WindowAttributes()
        while stack:
            w = stack.pop()
            root, parent, kids, n = ctypes.c_ulong(), ctypes.c_ulong(), ctypes.POINTER(ctypes.c_ulong)(), ctypes.c_uint()
            if self.x.XQueryTree(self.d, w, ctypes.byref(root), ctypes.byref(parent), ctypes.byref(kids), ctypes.byref(n)):
                stack.extend(kids[i] for i in range(n.value))
                if kids:
                    self.x.XFree(kids)
            if w == self.root or not self.x.XGetWindowAttributes(self.d, w, ctypes.byref(attrs)):
                continue
            area = attrs.width * attrs.height
            if (attrs.class_ == 1 and attrs.map_state == 2  # InputOutput, IsViewable
                    and attrs.width >= 640 and attrs.height >= 480 and area > best_area):
                best, best_area = w, area
        return best

    def pixel(self, win, x, y):
        img = self.x.XGetImage(self.d, win, x, y, 1, 1, 0xffffffff, 2)  # ZPixmap
        if not img:
            return None
        p = self.x.XGetPixel(img, 0, 0)
        self.x.XDestroyImage(img)
        return ((p >> 16) & 255, (p >> 8) & 255, p & 255)

    def send(self, key, down):
        self.x.XUngrabKeyboard(self.d, 0)  # a new B press may have grabbed the keyboard again
        self.t.XTestFakeKeyEvent(self.d, self.kc[key], 1 if down else 0, 0)
        self.x.XFlush(self.d)


def main():
    # Die with play.sh even if it is killed outright (gptokeyb's quit combo): a stray
    # X client keeps Xwayland and Weston alive and the screen stays black.
    ctypes.CDLL(None).prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    if os.getppid() == 1:
        sys.exit(0)
    x = X()
    x.grab_f12()
    event = ctypes.create_string_buffer(192)  # XEvent
    key = ctypes.cast(event, ctypes.POINTER(KeyEvent)).contents
    while True:
        x.x.XNextEvent(x.d, event)  # blocks: nothing runs between B presses
        if key.type != 2 or key.keycode != x.kc['f12']:  # only KeyPress of F12 (B)
            continue
        # The passive grab now holds the whole keyboard until F12 is released: give it
        # straight back so the queued keys (the d-pad) reach the game.
        x.x.XUngrabKeyboard(x.d, 0)
        x.x.XFlush(x.d)
        win = x.game_window()
        in_race = bool(win) and is_race(lambda px, py: x.pixel(win, px, py))
        sent = 'esc' if in_race else 'space'
        if DEBUG:
            print(f'B: window={win} in_race={in_race} -> {sent}', flush=True)
        x.send(sent, True)
        time.sleep(HOLD)  # the game polls the keyboard once per frame; a zero-length tap is missed
        x.send(sent, False)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--check':
        check_ppm(sys.argv[2])
    else:
        main()
