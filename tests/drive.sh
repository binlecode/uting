#!/usr/bin/env bash
# Drive the TUI in a real terminal, then ALWAYS clean up after it.
#
# This is a DRIVER, not a test: it asserts nothing about layout and reports no checks. It
# exists because three mechanical facts have to be got right every single time, and prose
# telling a human or an agent to get them right is a runner nobody executes reliably:
#
#   1. `uting` refuses a non-TTY (exit 1), so it cannot be run from a pipe or a Bash tool
#      call. tmux is the terminal.
#   2. The pane size must be set AT SESSION CREATION (-x/-y). LINES/COLUMNS do nothing — the
#      TUI reads the real ioctl via `stty size </dev/tty` (shell/uting:648), so a harness
#      that skips TIOCSWINSZ gets a 0x0 terminal and a one-row list whose frames still look
#      plausible enough to trust.
#   3. `Enter` starts mpv DETACHED, in its own process group. Killing the tmux session does
#      not stop it; the audio keeps playing after everything else is gone. This script's
#      EXIT trap is the whole reason it exists.
#
# The keymap it can send lives in README.md (§Keys) and the YT_* knobs in
# AS-BUILT-contract.md §5 — this file restates neither.
#
# Portability: bash 3.2 (macOS system bash). Needs tmux; jq only for the cleanup report.
#
# Usage:
#   tests/drive.sh                                  100x30, default query, dump the frame
#   tests/drive.sh -x 62 -y 20                      a narrower geometry
#   tests/drive.sh -q '周杰伦'                       another query (exercises CJK widths)
#   tests/drive.sh -k 'Tab'                         send keys after the list is ready
#   tests/drive.sh -k 'Enter' -w Playing            send Enter, wait for the banner
#   tests/drive.sh -i                               leave it up and ATTACH (interactive)
#   YT_ASCII=1 tests/drive.sh                       any YT_* var is passed through
# Exit: 0 = reached a ready frame and cleaned up; 1 = never got a frame, or orphans remained.
set -uo pipefail
cd "$(cd -P "$(dirname "$0")/.." && pwd -P)" || exit 1

COLS=100; ROWS=30; QUERY="lofi hip hop"; KEYS=""; WAIT_FOR=""; ATTACH=0
while [ $# -gt 0 ]; do
    case "$1" in
    -x) COLS=$2; shift 2 ;;
    -y) ROWS=$2; shift 2 ;;
    -q) QUERY=$2; shift 2 ;;
    -k) KEYS=$2; shift 2 ;;
    -w) WAIT_FOR=$2; shift 2 ;;
    -i) ATTACH=1; shift ;;
    -h | --help) sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "drive.sh: unknown argument '$1' (try --help)" >&2; exit 1 ;;
    esac
done

command -v tmux >/dev/null 2>&1 || { echo "drive.sh: tmux is required (uting needs a real tty)" >&2; exit 1; }

S="drive-$$"
PRESSED_ENTER=0
case "$KEYS" in *Enter*) PRESSED_ENTER=1 ;; esac

# The point of this script. A leaked player outlives the shell, the session, and the terminal,
# so the trap runs on EVERY exit path — including the ready-frame timeout below.
cleanup() {
    tmux kill-session -t "$S" 2>/dev/null
    if ((PRESSED_ENTER)); then
        shell/ut-play --stop --all -j >/dev/null 2>&1
        # Report rather than assume: --stop is idempotent, but an mpv that escaped its record
        # would not be reaped by it, and that is exactly the failure worth seeing.
        if pgrep -f 'mpv .*--input-ipc-server' >/dev/null 2>&1; then
            echo "drive.sh: ORPHAN mpv still running after --stop --all:" >&2
            pgrep -fl 'mpv .*--input-ipc-server' >&2
            return 1
        fi
        echo "drive.sh: players stopped, no orphan mpv"
    fi
    return 0
}
trap 'cleanup || exit 1' EXIT
trap 'exit 130' INT TERM

# YT_SYNC=0 because tmux and DCS frame sync do not mix. Everything else in the environment
# is passed through untouched, so `YT_ASCII=1 tests/drive.sh` works with no flag here.
tmux new-session -d -s "$S" -x "$COLS" -y "$ROWS" \
    "cd '$PWD' && YT_SYNC=0 shell/uting '$QUERY'"

# Wait on the ready MARKER, never on a sleep: a captured spinner frame is a picture of the
# loading state, not of the layout. A cold yt-dlp search takes ~10s.
i=0
while [ $i -lt 100 ]; do
    tmux capture-pane -t "$S" -p 2>/dev/null | grep -q 'results=' && break
    sleep 0.3; i=$((i + 1))
done
if [ $i -ge 100 ]; then
    echo "drive.sh: never reached a ready frame in 30s — still fetching, or it died:" >&2
    tmux capture-pane -t "$S" -p 2>/dev/null >&2
    exit 1
fi

if [ -n "$KEYS" ]; then
    # -l (literal) is deliberately NOT used: these are key names (Tab, Enter, Down), which is
    # what a driver sends. Literal filter text is an interactive job — use -i for that.
    # shellcheck disable=SC2086
    tmux send-keys -t "$S" $KEYS
    if [ -n "$WAIT_FOR" ]; then
        j=0
        while [ $j -lt 100 ]; do
            tmux capture-pane -t "$S" -p 2>/dev/null | grep -q "$WAIT_FOR" && break
            sleep 0.3; j=$((j + 1))
        done
        [ $j -ge 100 ] && echo "drive.sh: '$WAIT_FOR' never appeared" >&2
    else
        sleep 0.6                       # let the frame settle before we photograph it
    fi
fi

if ((ATTACH)); then
    echo "drive.sh: attaching — press q inside the TUI to quit; cleanup runs on detach."
    trap - INT TERM                     # let tmux own the keyboard while attached
    trap 'cleanup || exit 1' EXIT
    tmux attach -t "$S"
    exit 0
fi

echo "── ${COLS}x${ROWS}  query=$QUERY${KEYS:+  keys=$KEYS} ──"
tmux capture-pane -t "$S" -p
tmux send-keys -t "$S" 'q' 2>/dev/null   # let it reap its own player before the trap fires
sleep 1
exit 0
