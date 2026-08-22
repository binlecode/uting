#!/usr/bin/env bash
# The TUI, asserted against a REAL terminal. tmux is the terminal: it gives a true cell grid
# through `capture-pane` and the raw output stream through `pipe-pane`, so nothing here needs
# a pty harness or a Python screen model.
#
# This replaced two Python rigs that between them hand-rolled a pty and pulled in `pyte` — a
# pip dependency, in a suite whose whole claim is that it depends only on primitives everyone
# already has. Everything they proved is here: layout invariants (through assert_pane.py,
# which stays because measuring a CJK glyph in CELLS is the one thing shell cannot do), the
# in-place repaint, and the redraw-on-resize that neither rig could express at all.
#
# WAIT ON THE READY MARKER, never on a sleep: a captured spinner frame is a picture of the
# loading state, not of the layout, and every blind `sleep` here was once a wrong result.
#
# Portability: bash 3.2. Needs tmux. Starts NO playback, so it is silent and safe to run.
#
# Usage:  tests/tui_pane.sh [query]
# Exit:   0 = every invariant held, 1 = at least one failed

set -uo pipefail
REPO=$(cd -P "$(dirname "$0")/.." && pwd -P) || exit 1
cd "$REPO" || exit 1

QUERY=${1:-lofi hip hop}
OUT=$REPO/tmp/tui_pane
mkdir -p "$OUT"

command -v tmux >/dev/null 2>&1 || { echo "tui_pane: tmux is required" >&2; exit 1; }

pass=0; fail=0; FAILED=""
S=""                                    # the session this script owns right now

cleanup() { [ -n "$S" ] && tmux kill-session -t "$S" 2>/dev/null; return 0; }
trap cleanup EXIT INT TERM

ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad()  { fail=$((fail + 1)); FAILED="${FAILED}    ${1}"$'\n'; printf '  FAIL  %s\n' "$1"; }

# start <name> <cols> <rows> [env...] — launch the TUI and block until the list is drawn.
start() {
    local name=$1 cols=$2 rows=$3; shift 3
    S="tp-$name"
    tmux kill-session -t "$S" 2>/dev/null
    tmux new-session -d -s "$S" -x "$cols" -y "$rows" \
        "cd '$REPO' && env ${*:-} YT_SYNC=0 shell/yt-tui '$QUERY'"
    local i=0
    while [ $i -lt 80 ]; do
        if tmux capture-pane -t "$S" -p 2>/dev/null | grep -q 'results='; then return 0; fi
        sleep 0.3; i=$((i + 1))
    done
    bad "$name: never reached a ready frame (still fetching after 24s?)"
    return 1
}

# grab <file> — the settled pane as the terminal actually drew it.
grab() { tmux capture-pane -t "$S" -p > "$1"; }

# invariants <label> <file> <width> <view>
invariants() {
    if python3 "$REPO/tests/assert_pane.py" "$2" "$3" "$4" >"$OUT/$1.log" 2>&1; then
        ok "$1"
    else
        bad "$1"; sed 's/^/        /' "$OUT/$1.log"
    fi
}

echo "── layout at four geometries (layout is width-conditional) ────────"
# Heredoc, NOT `printf … | while read`: a piped loop body runs in a SUBSHELL, so every
# pass/fail increment inside it is discarded and the run reports 0 failures no matter what.
while read -r w h view; do
    [ -n "$w" ] || continue
    start "$w-$view" "$w" "$h" || continue
    [ "$view" = card ] && { tmux send-keys -t "$S" Tab; sleep 0.6; }
    grab "$OUT/pane-$w-$view.txt"
    invariants "$view ${w}x${h}" "$OUT/pane-$w-$view.txt" "$w" "$view"
    tmux kill-session -t "$S" 2>/dev/null; S=""
done <<'GEOM'
100 30 list
62 20 list
26 24 list
100 30 card
GEOM

echo "── chrome variants (the renderer packs to the width per language) ──"
while read -r knob w h; do
    [ -n "$knob" ] || continue
    start "${knob}-$w" "$w" "$h" "$knob" || continue
    grab "$OUT/pane-$knob-$w.txt"
    invariants "$knob ${w}x${h}" "$OUT/pane-$knob-$w.txt" "$w" list
    tmux kill-session -t "$S" 2>/dev/null; S=""
done <<'KNOBS'
YT_ASCII=1 62 20
YT_LANG=zh 62 20
YT_LANG=zh 26 24
KNOBS

echo "── redraw on resize, with NO keypress ─────────────────────────────"
# The frame is laid out against the size read at the top of its render, so a resize
# invalidates it whole. The proof needs no extra assertion: a stale 100-column frame in a
# 40-column pane is a wrapped one, and assert_pane fails it on width. Nothing is typed here
# on purpose — a keypress would repaint anyway and prove nothing about the WINCH path.
if start resize 100 30; then
    grab "$OUT/resize-before.txt"
    while read -r w h; do
        [ -n "$w" ] || continue
        tmux resize-window -t "$S" -x "$w" -y "$h"
        sleep 1.2
        grab "$OUT/resize-$w.txt"
        invariants "resize -> ${w}x${h} (no key)" "$OUT/resize-$w.txt" "$w" list
    done <<'SIZES'
62 20
40 16
26 24
100 30
SIZES
    tmux kill-session -t "$S" 2>/dev/null; S=""
fi

echo "── in-place repaint: a keypress must emit no screen-clear ─────────"
# ED (ESC[2J / ESC[3J) blanks the screen and the frame is then redrawn into it — two visible
# states per repaint, i.e. a flash. Counted BETWEEN marks, not from session start: tmux emits
# its own clear when the pane opens, and counting that is a false failure.
if start ed 100 30; then
    RAW=$OUT/raw.bin
    : > "$RAW"
    tmux pipe-pane -t "$S" -o "cat >> '$RAW'"
    sleep 0.4
    : > "$RAW"                                  # discard everything up to the mark
    tmux send-keys -t "$S" Down; sleep 0.5
    tmux send-keys -t "$S" Down; sleep 0.5
    tmux pipe-pane -t "$S"                      # stop piping
    # `grep -ao … | wc -l` counts OCCURRENCES; `grep -c` counts matching lines, and a raw
    # terminal stream carries almost no newlines, so several clears on one line read as 1.
    # No `|| echo 0` either: grep already prints 0 and exits 1, so the fallback appended a
    # second 0 and the comparison then failed on "0\n0" rather than on the count.
    n=$(LC_ALL=C grep -ao $'\033\[[23]J' "$RAW" 2>/dev/null | wc -l | tr -d ' ')
    if [ "${n:-0}" -eq 0 ]; then
        ok "two keypresses, 0 screen-clears ($(wc -c < "$RAW" | tr -d ' ') bytes drawn)"
    else
        bad "two keypresses emitted $n screen-clear sequence(s)"
    fi
    tmux kill-session -t "$S" 2>/dev/null; S=""
fi

echo
printf '%s: %d ok, %d failed\n' "$(basename "$0")" "$pass" "$fail"
if [ "$fail" -ne 0 ]; then printf 'failures:\n%s' "$FAILED"; exit 1; fi
exit 0
