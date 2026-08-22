#!/usr/bin/env python3
"""Drive yt-tui in a real pty and assert on the SCREEN, not on the byte stream.

What it is for: claims like "pause repaints exactly one row" or "no frame blanks the screen"
are statements about cells after \033[K / \033[J / CHA have been applied. Grepping emitted
bytes cannot make them — the byte stream of a correct in-place frame looks nothing like the
screen it produces. So the raw output is fed to a pyte Screen and the assertions read the
resulting cell grid.

Two things this rig learned the hard way, both worth keeping:

  1. A bare pty starts at 0x0, and LINES/COLUMNS in the environment do NOT fix it — the TUI
     reads `stty size` through /dev/tty on purpose. Without TIOCSWINSZ the reflow has no rows
     to spend and draws a ONE-ROW list whose frames look plausible enough to trust. Every
     assertion made on that screen is worthless. Hence the ioctl before the first read.

  2. YT_SYNC=0. pyte does not consume the DCS frame-hold sequences (\033P=1q / =2q) and
     leaks their payload into the display as literal "=2q" text. Turning sync off is a
     property of the RIG, not of the program under test.

Usage as a library:

    from tui_screen import drive
    marks = drive(["lofi hip hop"], [(8.0, b"\\r", "played"), (12.0, b"q", "quit")])
    for label, screen, raw_since_prev in marks:
        ...

Each mark is captured just BEFORE the next key is sent, so `screen` is the settled frame that
key acted on, and `raw_since_prev` is every byte emitted since the previous mark — which is
what "how many ED sequences did that keypress cost?" is counted from.

Standalone smoke run:  ./tui_screen.py "lofi hip hop"

Requires: pyte (pip install pyte). Not a runtime dependency of the suite.
"""
import fcntl
import os
import pty
import select
import struct
import sys
import termios
import time

import pyte

COLS, ROWS = 100, 30

# Where the suite lives, relative to this file: tests/ -> repo root -> shell/
REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YT_TUI = os.path.join(REPO, "shell", "yt-tui")


def drive(argv, script, cols=COLS, rows=ROWS, env=None):
    """Run yt-tui with `argv`, sending scripted keys, and return screen snapshots.

    script: [(seconds_since_start, keys_bytes, label), ...] — must be time-ordered.
    returns: [(label, [screen lines], raw_bytes_since_previous_mark), ...] plus a
             trailing ("final", ...) mark.
    """
    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update({"LINES": str(rows), "COLUMNS": str(cols), "YT_SYNC": "0"})
        if env:
            os.environ.update(env)
        os.execv("/bin/bash", ["bash", YT_TUI] + list(argv))

    # The TUI trusts `stty size`, so the pty needs a real window size. See docstring note 1.
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    screen = pyte.Screen(cols, rows)
    stream = pyte.Stream(screen)
    marks = []
    raw = b""
    sent = 0
    t0 = time.time()
    end = script[-1][0] + 3 if script else 5

    while time.time() - t0 < end:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            raw += data
            stream.feed(data.decode(errors="replace"))
        while sent < len(script) and time.time() - t0 > script[sent][0]:
            # Snapshot BEFORE sending: this is the frame the key is about to act on.
            marks.append((script[sent][2], [l.rstrip() for l in screen.display], raw))
            raw = b""
            os.write(fd, script[sent][1])
            sent += 1

    marks.append(("final", [l.rstrip() for l in screen.display], raw))
    try:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    except Exception:
        pass
    return marks


def changed_rows(before, after):
    """Row indices whose cells differ — the unit "pause changed exactly one row" is counted in."""
    return [i for i, (a, b) in enumerate(zip(before, after)) if a != b]


def ed_count(raw):
    """ED (erase-in-display) sequences in a byte run. A correct in-place frame emits ZERO:
    a `clear` blanks the screen and then redraws it, which is two visible states per frame."""
    return raw.count(b"[2J") + raw.count(b"[3J")


if __name__ == "__main__":
    query = sys.argv[1] if len(sys.argv) > 1 else "lofi hip hop"
    marks = drive([query], [(9.0, b"\r", "list"), (22.0, b" ", "playing"),
                            (25.0, b" ", "paused"), (27.0, b"q", "resumed")])
    prev = None
    for label, screen, raw in marks:
        line = "%-10s ED=%d" % (label, ed_count(raw))
        if prev is not None:
            line += "  changed_rows=%s" % changed_rows(prev, screen)
        print(line)
        prev = screen
    print("\n--- final screen ---")
    for i, l in enumerate(marks[-1][1]):
        if l:
            print("%3d %s" % (i, l))
