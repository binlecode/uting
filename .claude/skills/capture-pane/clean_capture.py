#!/usr/bin/env python3
"""Clean a raw `tmux capture-pane -p` frame of uting into a block ready to paste
VERBATIM into a Markdown fence.

Usage:
    tmux capture-pane -t SESSION -p > tmp/raw.txt
    python3 clean_capture.py tmp/raw.txt > tmp/list.txt

What it does:
  - right-trims every line (tmux pads each row out to the pane width),
  - drops trailing blank rows (the unused bottom of the pane),
  - drops a leading fetch line (`searching "…"…`) and its spinner glyph,
  - refuses (exit 2) a capture that still looks mid-fetch, because a spinner frame
    pasted into a doc is a diagram of the loading state, not of the layout.

What it deliberately does NOT do: measure widths. Cell measurement lives in
this skill's assert_pane.py and must not exist twice — run that on the cleaned file before
splicing it into a doc. It also never removes an interior row: every row of a list
frame is load-bearing (the index column, the right-flush duration rail and the
details block are all mutually aligned), so a "compressed" frame is a torn frame.
"""

import argparse
import re
import sys

SPINNER = "▖▘▝▗|/-\\"
FETCH = re.compile(r'^\s*(searching|搜索中)\b.*$')


def clean(lines):
    out = [ln.rstrip() for ln in lines]
    out = [ln for ln in out if not FETCH.match(ln)]
    while out and out[-1].strip() == "":
        out.pop()
    while out and out[0].strip() == "":
        out.pop(0)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("path", nargs="?", help="raw capture file (default: stdin)")
    ap.add_argument(
        "--allow-fetch",
        action="store_true",
        help="keep going even if the frame looks mid-fetch (only when the loading state IS the subject)",
    )
    args = ap.parse_args()

    raw = (open(args.path) if args.path else sys.stdin).read()

    # Staleness is judged on the RAW frame, before the fetch line is dropped — a pure
    # spinner frame cleans down to nothing, and "empty pane" would be the wrong diagnosis.
    stale = ("results=" not in raw) and (
        FETCH.search(raw) is not None or any(g in raw for g in SPINNER)
    )
    if stale and not args.allow_fetch:
        sys.exit(
            "clean_capture: this frame looks mid-fetch (spinner present, no `results=` header).\n"
            "  Wait for the ready marker before capturing:\n"
            "    until tmux capture-pane -t $S -p | grep -q 'results='; do sleep 0.5; done\n"
            "  Pass --allow-fetch if the loading state is what you mean to document."
        )

    lines = clean(raw.split("\n"))
    if not lines:
        sys.exit("clean_capture: nothing left after cleaning — captured an empty pane?")

    sys.stdout.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
