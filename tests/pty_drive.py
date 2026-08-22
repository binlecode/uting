#!/usr/bin/env python3
"""Drive yt-tui in a pty and assert on the STREAM and its TIMING.

The sibling rig (tui_screen.py) answers "what does the terminal end up showing". This one
answers "what came out, and when" — which is the only way to check things that are about
motion rather than about a final frame:

  - does the fetch spinner actually animate (frames arriving ~8/s), or is the line static?
  - does the banner flip Starting -> Playing on its OWN, with no keypress, and how long did
    mpv's start-up window really last?
  - does the 1 s tick STOP when the state resolves, or does the list keep redrawing forever?
  - what exit code does a cancel path produce?

Timing assertions need the raw stream because a screen model collapses "drawn twice" into
one cell state. Conversely, this rig cannot tell you what the screen shows — an in-place
frame's bytes are not its picture. Use the right one.

Usage:
    ./pty_drive.py 'lofi hip hop' --at 9.0 '\\r' --at 26 q --secs 30
    ./pty_drive.py --keys '\\x1b'                 # Esc at the startup prompt -> exit 0

Options:
    --at SEC KEYS   send KEYS at SEC seconds after start (repeatable, time-ordered)
    --keys KEYS     shorthand for --at 1.0 KEYS
    --secs N        run for N seconds (default: last --at + 8)
    --ascii         run with YT_ASCII=1
    --grep PATTERN  print each match with the second it arrived (default: play states)

KEYS goes through unicode_escape, so '\\r', '\\x1b', '\\x7f', '\\t' all work.
"""
import os
import pty
import re
import select
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YT_TUI = os.path.join(REPO, "shell", "yt-tui")

# Default: the three play states and the two waiting lines, with whatever glyph precedes them.
DEFAULT_GREP = r"[▘▝▗▖▶●❚|/\\-]{1,2} ?(?:Starting|Playing|Paused)|searching|re-fetching"


def parse_argv(argv):
    query, script, secs, ascii_mode, pattern = None, [], None, False, DEFAULT_GREP
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--at":
            script.append((float(argv[i + 1]),
                           argv[i + 2].encode().decode("unicode_escape").encode("latin-1")))
            i += 3
        elif a == "--keys":
            script.append((1.0, argv[i + 1].encode().decode("unicode_escape").encode("latin-1")))
            i += 2
        elif a == "--secs":
            secs = float(argv[i + 1]); i += 2
        elif a == "--ascii":
            ascii_mode = True; i += 1
        elif a == "--grep":
            pattern = argv[i + 1]; i += 2
        else:
            query = a; i += 1
    if secs is None:
        secs = (script[-1][0] + 8) if script else 12.0
    return query, script, secs, ascii_mode, pattern


def drive(query, script, secs, ascii_mode=False, pattern=DEFAULT_GREP, cols=100, rows=30):
    """Returns (exit_code_or_None, raw_text, [(seconds, matched_text), ...])."""
    import fcntl
    import struct
    import termios

    pid, fd = pty.fork()
    if pid == 0:
        os.environ.update({"LINES": str(rows), "COLUMNS": str(cols)})
        if ascii_mode:
            os.environ["YT_ASCII"] = "1"
        args = [query] if query else []
        os.execv("/bin/bash", ["bash", YT_TUI] + args)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    rx = re.compile(pattern)
    out = b""
    hits = []
    status = None
    sent = 0
    t0 = time.time()
    while time.time() - t0 < secs:
        r, _, _ = select.select([fd], [], [], 0.1)
        if r:
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            out += data
            now = round(time.time() - t0, 1)
            for m in rx.finditer(data.decode(errors="replace")):
                hits.append((now, m.group(0).strip()))
        while sent < len(script) and time.time() - t0 > script[sent][0]:
            os.write(fd, script[sent][1])
            sent += 1
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = os.waitstatus_to_exitcode(st)
            pid = 0
            break
    if pid:
        try:
            os.kill(pid, 9)
            os.waitpid(pid, 0)
        except Exception:
            pass
    return status, out.decode(errors="replace"), hits


if __name__ == "__main__":
    query, script, secs, ascii_mode, pattern = parse_argv(sys.argv[1:])
    status, text, hits = drive(query, script, secs, ascii_mode, pattern)
    print("exit=%s   bytes=%d   matches=%d" % (status, len(text), len(hits)))
    for sec, hit in hits:
        print("  %6.1fs  %s" % (sec, hit))
