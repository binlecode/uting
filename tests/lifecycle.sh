#!/usr/bin/env bash
# The detached-player lifecycle: the one surface whose bugs are PROCESSES, not output.
# Everything here starts real players, so it is gated — set YT_TEST_LIFECYCLE=1 to run it.
# Every player is launched with --volume 0, so it is silent, and the run does not pass until
# `pgrep` comes back empty: a leaked mpv is the failure this file exists to catch.
#
# It also carries the one timing claim that needs a player: Starting -> Playing flips on the
# TUI's own 1 s tick with NO keypress. That was the last thing `pty_drive.py` was kept for.
#
# And it carries the one claim that needs a SECOND source: that the player applies the
# http_headers an engine hands it. See the Bilibili section for why only that site can show it.
#
# Portability: bash 3.2. Needs tmux for the tick check, jq for the envelopes.
#
# Usage:  YT_TEST_LIFECYCLE=1 tests/lifecycle.sh
# Exit:   0 = every check held, 1 = at least one failed, 2 = refused to run (not gated in)

set -uo pipefail
REPO=$(cd -P "$(dirname "$0")/.." && pwd -P) || exit 1
cd "$REPO" || exit 1

if [ "${YT_TEST_LIFECYCLE:-0}" != "1" ]; then
    echo "lifecycle.sh: starts real players — re-run with YT_TEST_LIFECYCLE=1" >&2
    exit 2
fi

# Two long, stable tracks. Silent at --volume 0; the point is the process, not the audio.
U1=${YT_TEST_URL1:-https://www.youtube.com/watch?v=n61ULEU7CO0}
U2=${YT_TEST_URL2:-https://www.youtube.com/watch?v=8S0FDjFBj8o}
# The second engine's fixture: an old-format BV with 76M views, picked to outlive the rig.
BV=${YT_TEST_BILI:-BV1fx411N7bU}

pass=0; fail=0; FAILED=""
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); FAILED="${FAILED}    ${1}"$'\n'; printf '  FAIL  %s\n' "$1"; }
report() { if [ "$2" = "$3" ]; then ok "$1 ($3)"; else bad "$1: want $2, got $3"; fi; }

# A detached launch returns the moment the child is forked -- that is the point of it -- so the
# mpv IPC socket does not exist yet. Any check that MUTATES a player has to wait for the socket
# or it asserts on `ipc_failed`/exit 4, which is the CORRECT answer to "talk to a player that is
# not listening". Poll (bounded), never sleep a fixed guess: mpv's start is network-bound here
# and has ranged from under a second to fifteen. Returns 1 on timeout so the caller can say so.
wait_for_sock() {
    local sock=$1 i
    for i in $(seq 1 240); do
        [ -S "$sock" ] && return 0
        sleep 0.25
    done
    return 1
}

# Always stop everything, however this exits — a leaked player outlives the shell.
cleanup() {
    tmux kill-session -t lc-tick 2>/dev/null
    shell/ut-play --stop --all -j >/dev/null 2>&1
    return 0
}
trap cleanup EXIT INT TERM

shell/ut-play --stop --all -j >/dev/null 2>&1        # start from a clean slate

echo "── detach returns BEFORE mpv is up ────────────────────────────────"
# The envelope is the handle; if this waited for the player there would be nothing detached
# about it. A slow return has meant the title updater holding the captured pipe.
t0=$(date +%s)
o1=$(shell/ut-play -d -j --volume 0 -- "$U1" 2>/dev/null)
t1=$(date +%s)
report "detach envelope" 0 \
    "$(printf '%s' "$o1" | jq -e '.id and .pid and .sock' >/dev/null 2>&1; echo $?)"
if [ $((t1 - t0)) -le 3 ]; then ok "detach returned in $((t1 - t0))s (<= 3)"
else bad "detach took $((t1 - t0))s — is something holding the pipe?"; fi

id1=$(printf '%s' "$o1" | jq -r '.id // empty')
o2=$(shell/ut-play -d -j --volume 0 -- "$U2" 2>/dev/null)
id2=$(printf '%s' "$o2" | jq -r '.id // empty')

echo "── two players: the POPULATED envelope, one compact line ──────────"
report "--status one line" 1 "$(shell/ut-play --status -j | wc -l | tr -d ' ')"
report "--status sees 2"   2 "$(shell/ut-play --status -j | jq '.players | length')"

echo "── a selector-less mutation on 2 players is ambiguous -> exit 4 ───"
report "--set-volume no --id" 4 "$(shell/ut-play --set-volume 40 -j >/dev/null 2>&1; echo $?)"
# Ambiguity is decided before any IPC, so the check above needs no player listening. The
# targeted ones below do -- wait for player 1's socket first (see wait_for_sock).
sock1=$(printf '%s' "$o1" | jq -r '.sock // empty')
wait_for_sock "$sock1" || bad "player 1's IPC socket never appeared -- the checks below are moot"
report "--set-volume --id"    0 "$(shell/ut-play --set-volume 40 --id "$id1" -j >/dev/null 2>&1; echo $?)"
# Only the targeted player moved: a mutation that leaks across players is the bug --id exists for.
report "only the target moved" "40" \
    "$(shell/ut-play --status -j | jq -r --arg i "$id1" '.players[]|select(.id==$i)|.volume')"

echo "── Starting -> Playing flips on the tick, with NO keypress ────────"
# The TUI polls the player once a second, so the banner must resolve on its own. Nothing is
# typed after Enter on purpose; a keypress would repaint anyway and prove nothing.
tmux kill-session -t lc-tick 2>/dev/null
tmux new-session -d -s lc-tick -x 100 -y 30 "cd '$REPO' && env YT_SYNC=0 shell/uting 'lofi hip hop'"
i=0
while [ $i -lt 80 ]; do
    tmux capture-pane -t lc-tick -p 2>/dev/null | grep -q 'results=' && break
    sleep 0.3; i=$((i + 1))
done
tmux send-keys -t lc-tick Enter
flip=""
i=0
while [ $i -lt 60 ]; do                              # up to 30s for mpv to produce output
    if tmux capture-pane -t lc-tick -p 2>/dev/null | grep -qE 'Playing:'; then flip=yes; break; fi
    sleep 0.5; i=$((i + 1))
done
tmux kill-session -t lc-tick 2>/dev/null
if [ "$flip" = yes ]; then ok "banner reached Playing unprompted in ~$(echo "$i * 0.5" | bc)s"
else bad "banner never left Starting — the 1s tick is not resolving the state"; fi

echo "── a second engine: the envelope's http_headers reach mpv ─────────"
# The only check in the suite that proves the player APPLIES what an engine hands it.
# contract.sh asserts http_headers is PRESENT in the resolve envelope; nothing asserted that
# ut-play forwards it into mpv. This site is what makes the difference observable: its CDN
# answers 403 to a bare stream URL and 206 to the same URL carrying the envelope's Referer
# (docs/SPEC-system.md §0, measured). So a player that dropped the header block would still
# play YouTube, and every other check in this file would stay green, while bytes never flowed
# from here. Position leaving zero IS the proof that they did.
o3=$(shell/ut-play -d -j --volume 0 --engine bili -- "$BV" 2>/dev/null)
report "bili detach envelope" 0 \
    "$(printf '%s' "$o3" | jq -e '.id and .pid and .sock' >/dev/null 2>&1; echo $?)"
id3=$(printf '%s' "$o3" | jq -r '.id // empty')
sock3=$(printf '%s' "$o3" | jq -r '.sock // empty')
if wait_for_sock "$sock3"; then
    # Poll, never sleep a guess: time-to-first-byte is network-bound, so a fixed wait either
    # flakes or spends the whole budget on a run that was ready in a second (same rule as
    # wait_for_sock). `position` is read live off the socket, not from the record.
    pos=""; i=0
    while [ $i -lt 40 ]; do
        pos=$(shell/ut-play --status -j 2>/dev/null \
              | jq -r --arg i "$id3" '.players[]|select(.id==$i)|.position // empty' 2>/dev/null)
        case "$pos" in "" | null | 0) ;; *) break ;; esac
        sleep 1; i=$((i + 1))
    done
    case "$pos" in
        "" | null | 0) bad "bili position never left 0 — did http_headers reach mpv? (CDN 403s without the Referer)" ;;
        *) ok "bili audio flowed (position ${pos}s) — the envelope's headers reached mpv" ;;
    esac
else
    bad "the bili player's IPC socket never appeared — the header claim is untested"
fi

echo "── stop is targeted, then idempotent, and leaks nothing ───────────"
report "--stop --id"       0 "$(shell/ut-play --stop --id "$id1" -j >/dev/null 2>&1; echo $?)"
report "--stop --all"      0 "$(shell/ut-play --stop --all -j >/dev/null 2>&1; echo $?)"
report "--stop --all again" 0 "$(shell/ut-play --stop --all -j >/dev/null 2>&1; echo $?)"
report "no players left"   0 "$(shell/ut-play --status -j | jq -e '.players==[]' >/dev/null 2>&1; echo $?)"

sleep 1
n=$(pgrep -f 'mpv .*--input-ipc-server' 2>/dev/null | wc -l | tr -d ' ')
report "no orphan mpv" 0 "${n:-0}"

echo
printf '%s: %d ok, %d failed\n' "$(basename "$0")" "$pass" "$fail"
if [ "$fail" -ne 0 ]; then printf 'failures:\n%s' "$FAILED"; exit 1; fi
exit 0
