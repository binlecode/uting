#!/usr/bin/env bash
# Drive the TUI in a real terminal, then ALWAYS clean up after it.
#
# This is a DRIVER, not a test: it asserts nothing about layout and reports no checks. It
# exists because four mechanical facts have to be got right every single time, and prose
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
#   4. That trap's reach is the state dir, so the state dir has to be this run's own — see
#      the isolation block below. Reaping unconditionally is only safe once nothing else
#      lives there.
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

# ---- a state dir of this run's own --------------------------------------------------
# `ut-play` derives its state dir from TMPDIR and takes no override (shell/ut-play, STATE_DIR),
# so at the user's real TMPDIR the cleanup below reaches the player they are listening to and
# the orphan check counts THEIR mpv. Both suites in tests/ already redirect for this reason;
# this is the same derivation and the last entry point that had not. Isolation changes nothing
# about what runs — the pane holds a real `uting` driving a real `ut-play` and a real mpv —
# only whose state it is written on top of. Their playlists and their history still render,
# because those live in UT_STATE_DIR, which is deliberately NOT redirected: a frame captured
# from this driver should show the store a human sees. What the driver does suppress is the
# WRITE side of that store (UT_HISTORY=0 in the pane): a track this script starts and reaps a
# second later is not a listening, and a log is not something --stop takes back.
UT_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/uting-drive.XXXXXX") || exit 1
export TMPDIR="$UT_TEST_TMP"
STATE_DIR="$TMPDIR/uting-$(id -u)"

S="drive-$$"

# The point of this script. A leaked player outlives the shell, the session, and the terminal,
# so the trap runs on EVERY exit path — including the ready-frame timeout below.
cleanup() {
    local rc=0
    tmux kill-session -t "$S" 2>/dev/null
    # Unconditional. It used to run only when the keys contained Enter, because --stop --all
    # reached the user's players and reaping without cause was the worse bug — which meant `-i`,
    # the one mode where a HUMAN presses Enter, never reaped at all. The state dir above is what
    # retires that trade: there is nothing here but this run's own players.
    shell/ut-play --stop --all -j >/dev/null 2>&1
    # Report rather than assume: --stop is idempotent, but an mpv that escaped its record would
    # not be reaped by it, and that is exactly the failure worth seeing. Scoped to this run's
    # socket dir, as playback.sh scopes its own: a bare `mpv .*--input-ipc-server` counts the
    # user's players too, so on any machine where uting is actually used it was a coin toss.
    if pgrep -f "mpv .*--input-ipc-server=$STATE_DIR" >/dev/null 2>&1; then
        echo "drive.sh: ORPHAN mpv still running after --stop --all:" >&2
        pgrep -fl "mpv .*--input-ipc-server=$STATE_DIR" >&2
        rc=1
    else
        echo "drive.sh: this run's players stopped, no orphan mpv"
    fi
    rm -rf "$UT_TEST_TMP"
    return $rc
}
trap 'cleanup || exit 1' EXIT
trap 'exit 130' INT TERM

# The suite's own knobs are forwarded EXPLICITLY, not inherited. A new tmux session does not
# get this shell's environment: it gets the tmux SERVER's, and the server is whichever one is
# already running — often started hours ago from another window. `YT_ASCII=1 tests/drive.sh`
# looked like it worked only when no server was up yet; with one up it silently drove the
# default. Verified by driving UT_STATE_DIR: the pane reported an empty store while the same
# variable listed four playlists outside tmux.
#
# YT_SYNC=0 (tmux and DCS frame sync do not mix) and TMPDIR are placed AFTER the forwarded
# block so the driver's own choice wins over an inherited one — TMPDIR because the isolation
# above is not negotiable, and it is not a YT_*/UT_* name so it is never forwarded anyway.
# UT_HISTORY=0 goes BEFORE it: suppressing the log write is a default, not a rule, so
# `UT_HISTORY=1 tests/drive.sh -k Enter` still drives the writing path.
env_prefix=""
while IFS= read -r line; do
    case "$line" in
    YT_*=* | UT_*=*)
        _n=${line%%=*}
        _v=${line#*=}
        _v=$(printf '%s' "$_v" | sed "s/'/'\\\\''/g")
        env_prefix="$env_prefix $_n='$_v'"
        ;;
    esac
done < <(env)

tmux new-session -d -s "$S" -x "$COLS" -y "$ROWS" \
    "cd '$PWD' && UT_HISTORY=0$env_prefix TMPDIR='$TMPDIR' YT_SYNC=0 shell/uting '$QUERY'"

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
    tmux attach -t "$S"
    exit 0
fi

echo "── ${COLS}x${ROWS}  query=$QUERY${KEYS:+  keys=$KEYS} ──"
tmux capture-pane -t "$S" -p
tmux send-keys -t "$S" 'q' 2>/dev/null   # let it reap its own player before the trap fires
sleep 1
exit 0
