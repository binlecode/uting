#!/usr/bin/env python3
"""Assert yt-tui's layout invariants against a captured pane.

Three rigs merged into one, because they all read the same capture and all failed the same
way when kept apart — you fix a renderer, remember to re-run two of the three, and the third
goes stale. The checks:

  pane width   No drawn line exceeds the pane. This is the one that catches the width layer
               getting something wrong, and it is measured in CELLS (east_asian_width), not
               characters, because a CJK title is two cells and a naive len() would pass a
               line that visibly wraps.

  index column Every result row's title starts on the SAME cell, whether the row is selected
               ("> ") or not, 1-digit index or 2-digit. The prefixes used to be per-row
               literals, so a page that reached two digits started every 1-digit title one
               cell to the left — ragged in the one column the eye scans down.

  rail column  Every result row's duration rail is right-flush at exactly the pane width.
               A capture is the terminal's own cell grid, so this measures where the rail was
               actually DRAWN — which is the whole point: char_w over-counts on purpose, so a
               rail placed by computed padding lands early on rows the terminal drew narrower
               than we measured. Placing it with CHA is what makes this pass.

  card rails   In the card view, every divider rail and the progress bar are the same width.

Captures come from `tmux capture-pane -p` or from tui_screen.py's screen model (write the
lines to a file). Ambiguous-width characters count as ONE cell, matching the suite's default
(YT_AMBIG_WIDE unset); pass --ambig-wide to match the other setting.

usage: assert_pane.py <capture.txt> <pane_width> [list|card] [--rows N] [--ambig-wide]
exit:  0 = every applicable invariant held, 1 = at least one failed
"""
import re
import sys
import unicodedata

ZERO_WIDTH = "‍︎️"


def cells(s, ambig_wide=False):
    n = 0
    for ch in s:
        if unicodedata.combining(ch) or ch in ZERO_WIDTH:
            continue
        ea = unicodedata.east_asian_width(ch)
        if ea in ("W", "F"):
            n += 2
        elif ea == "A":
            n += 2 if ambig_wide else 1
        else:
            n += 1
    return n


ROW = re.compile(r"^(> |  )( *)(\d+\.) (?=\S)")
RAIL = re.compile(r"(LIVE|--:--|\d+:\d\d(?::\d\d)?)$")


def main(argv):
    ambig_wide = "--ambig-wide" in argv
    argv = [a for a in argv if a != "--ambig-wide"]
    expect_rows = None
    if "--rows" in argv:
        i = argv.index("--rows")
        expect_rows = int(argv[i + 1])
        del argv[i:i + 2]
    path, width = argv[0], int(argv[1])
    view = argv[2] if len(argv) > 2 else "list"

    lines = open(path, encoding="utf-8").read().split("\n")
    while lines and lines[-1].strip() == "":   # captures keep trailing blanks
        lines.pop()

    def w(s):
        return cells(s, ambig_wide)

    fails, notes = [], []

    for i, line in enumerate(lines):
        if w(line) > width:
            fails.append("line %d is %d cells > pane %d: %r" % (i + 1, w(line), width, line[:70]))

    body = "\n".join(lines)

    if view == "list":
        if not lines or "yt-tui" not in lines[0]:
            fails.append("header not on line 1 (scrolled off?): %r" % (lines[0][:60] if lines else ""))
        # Detect the hint block by its LAST item (q quit), not by a label: the block carried a
        # "Navigation:" prefix once and no longer does, and a rig that keys off chrome wording
        # fails the day the wording is tuned. The last item is structural — the block is packed
        # in order and q is always last.
        if not re.search(r"\bq\s+(quit|退出)", body):
            # Dropped on purpose when the pane cannot pay for it (nav_ok). This was a flat
            # "len(lines) >= 12", which only held at >= 40 columns — the chrome packs to the
            # width, so at 30 columns the same hints cost three more lines and the gate
            # fires in a 14-row pane. Ask instead whether the drop bought anything: a frame
            # with rows to spare at the bottom dropped the block for nothing.
            spare = len(lines) - 1 - max([i for i, l in enumerate(lines) if l.strip()] or [-1])
            if spare > 1:
                fails.append("navigation hint block missing, %d rows spare" % spare)
            else:
                notes.append("hint block dropped (short terminal) — expected")

        rows = [l for l in lines if ROW.match(l)]
        notes.append("result rows: %d" % len(rows))
        if expect_rows is not None and len(rows) != expect_rows:
            fails.append("expected %d result rows, found %d" % (expect_rows, len(rows)))

        # index column: one start cell for every row, and the marker must appear somewhere
        starts, seen = {}, []
        for l in rows:
            m = ROW.match(l)
            seen.append(">" if m.group(1) == "> " else m.group(3))
            starts.setdefault(m.end(), []).append(m.group(1) + m.group(3))
        if rows and len(starts) > 1:
            fails.append("titles start in %d different columns: %r" % (len(starts), starts))
        if rows and ">" not in seen:
            fails.append("no selected row in this capture (marker never rendered)")
        if rows:
            digits = sorted(set(len(s) - 1 for s in seen if s != ">"))
            notes.append("index: title col=%s digits=%s" % (sorted(starts), digits or "-"))

        # rail column: right-flush at exactly the pane width, same column on every row
        ends = {}
        for l in rows:
            m = RAIL.search(l)
            if not m:
                fails.append("row has no duration rail: %r" % l[-30:])
                continue
            ends.setdefault(w(l), []).append(m.group(1))
        if len(ends) > 1:
            fails.append("rails end in %d different columns: %r" % (len(ends), dict(ends)))
        elif ends and list(ends)[0] != width:
            fails.append("rail column is %d, expected the pane width %d" % (list(ends)[0], width))
        if ends:
            notes.append("rail: end col=%s" % sorted(ends))

        # The boundary under the hint block is a static divider when nothing plays and the live
        # progress rail when something does (same width, by construction — that is the claim).
        rail_line = [l for l in lines if re.match(r"^[─━●]{10,}$", l.strip())
                     or re.match(r"^●[─━]{9,}", l.strip())]
        if rail_line:
            rw = sorted(set(w(l.strip()) for l in rail_line))
            if rw != [width]:
                fails.append("boundary rail is %s cells, expected exactly the pane width %d" % (rw, width))
            notes.append("boundary rail: %s cells" % rw)

    elif view == "card":
        # The view name is ELIDED at narrow widths (it is chrome like any other row), so the
        # old literal match failed on a correct 28-column frame. The header's LAYOUT is what
        # this rig is about: brand on line 1, blank line under it. A header too long for the
        # pane wraps into that blank line, which is the defect the literal match was really
        # catching.
        head = lines[0] if lines else ""
        if "yt-tui" not in head or (len(lines) > 1 and lines[1].strip()):
            fails.append("card header missing or wrapped: %r" % head[:60])
        rails = [l for l in lines if re.match(r"^[─━-]{10,}$", l.strip())]
        widths = sorted(set(w(r.strip()) for r in rails))
        if len(widths) > 1:
            fails.append("divider rails disagree in width: %r" % widths)
        notes.append("rails: %d @ %s cells" % (len(rails), widths))

    print("%-26s %-5s pane=%-4d lines=%-3d max_cell=%-4d %s"
          % (path.split("/")[-1], view, width, len(lines),
             max([w(l) for l in lines] or [0]), "PASS" if not fails else "FAIL"))
    for n in notes:
        print("      . " + n)
    for f in fails:
        print("      ! " + f)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
