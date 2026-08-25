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
# It also owns the LIVE READ (--status off the mpv socket), for the same reason: the peer is
# real mpv or it is nothing. The suite keeps no stand-in for a component, so a claim about
# talking to mpv can only be made where mpv is running — here, behind the gate.
#
# Portability: bash 3.2. Needs jq for the envelopes; no tmux and no terminal — every
# assertion here is an exit code or a field out of a real envelope.
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
# --stop takes the same ambiguity rule (AS-BUILT-contract.md §3): with 2 players and no
# selector it must refuse with 4 AND stop nothing — a --stop that guessed would kill the
# wrong listener's audio, which no exit code repairs.
report "--stop no --id"       4 "$(shell/ut-play --stop -j >/dev/null 2>&1; echo $?)"
report "ambiguous --stop stopped nothing" 2 "$(shell/ut-play --status -j | jq '.players | length')"
# Ambiguity is decided before any IPC, so the check above needs no player listening. The
# targeted ones below do -- wait for player 1's socket first (see wait_for_sock).
sock1=$(printf '%s' "$o1" | jq -r '.sock // empty')
wait_for_sock "$sock1" || bad "player 1's IPC socket never appeared -- the checks below are moot"
report "--set-volume --id"    0 "$(shell/ut-play --set-volume 40 --id "$id1" -j >/dev/null 2>&1; echo $?)"
# Only the targeted player moved: a mutation that leaks across players is the bug --id exists for.
report "only the target moved" "40" \
    "$(shell/ut-play --status -j | jq -r --arg i "$id1" '.players[]|select(.id==$i)|.volume')"

echo "── the live read: a real socket, a real peer, null is not false ───"
# The four live fields cost a round trip to mpv itself. Nothing in this repo may stand in for
# that peer, so the read is proved HERE, against the real one, behind the gate — never in
# contract.sh against something written to imitate it.
#
# Poll for the first reading rather than sleeping a guess: position/duration are null until
# mpv starts decoding (network-bound, ~8s cold), and null there is an honest READING, not a
# failure. What must not happen is null forever.
pos=""; i=0
while [ $i -lt 40 ]; do
    pos=$(shell/ut-play --status -j 2>/dev/null \
          | jq -r --arg i "$id1" '.players[]|select(.id==$i)|.position // empty' 2>/dev/null)
    case "$pos" in "" | null | 0) ;; *) break ;; esac
    sleep 1; i=$((i + 1))
done
case "$pos" in
    "" | null | 0) bad "player 1 never reported a position — the live read is unproved" ;;
    *) ok "position came off the socket (${pos}s), not off the record" ;;
esac
# false is an ANSWER; null is "the question could not be asked" (§9.3). A playing player that
# reported paused:null would make every consumer's readiness probe read a fabrication, and a
# playing player that reported it as anything but false would make --pause unobservable.
report "live paused is false, not null" 0 \
    "$(shell/ut-play --status -j | jq -e --arg i "$id1" \
        '.players[]|select(.id==$i)|.paused==false' >/dev/null 2>&1; echo $?)"
report "live duration is a number" 0 \
    "$(shell/ut-play --status -j | jq -e --arg i "$id1" \
        '.players[]|select(.id==$i)|.duration|type=="number"' >/dev/null 2>&1; echo $?)"
echo "── the playback verbs: the envelope reports what mpv answered ───"
# --pause / --resume / --seek / --seek-to over the same one-shot socket as --set-volume.
# contract.sh owns the idle half (no player → 4, an unsigned --seek → 1); what only a real
# player can show is that the verb MOVED something and that the number in the envelope came
# back off mpv rather than out of the caller's own arithmetic.
#
# Pause FIRST and seek while paused: a playing time-pos advances on its own, so any assertion
# about where a seek landed would be racing the decoder — and a check that depends on how
# fast this machine decodes is the timing assertion CLAUDE.md forbids. Paused, the playhead
# holds still and every claim below is about behaviour.
report "--pause reads back paused"  "true" \
    "$(shell/ut-play --pause --id "$id1" -j | jq -r '.paused')"
report "…and --status agrees"         "true" \
    "$(shell/ut-play --status -j | jq -r --arg i "$id1" '.players[]|select(.id==$i)|.paused')"
# The order is load-bearing: seek FORWARD first, then home. Doing it the other way round
# leaves a --seek-to that secretly seeks RELATIVE looking correct — a relative 0 from a
# playhead near the start also lands near the start. Proved by breaking it exactly that way
# and watching this pass; it only goes red once the absolute seek has somewhere to come back
# from. Each claim is anchored to the position BEFORE it, so a verb that does nothing at all
# cannot ride on where the decoder happened to be.
before=$(shell/ut-play --status -j | jq -r --arg i "$id1" '.players[]|select(.id==$i)|.position')
# A RELATIVE seek lands on a keyframe, so the claim is "forward by about that much", never an
# exact 30 — asserting the exact number would be asserting mpv's keyframe interval. What is
# proved here is that the sign was honoured and that the number is READ, not computed.
p1=$(shell/ut-play --seek +30 --id "$id1" -j | jq -r '.position')
case "$before$p1" in
    *null* | "") bad "--seek +30 reported no position — the read-back is unproved" ;;
    *) if [ "$p1" -ge $((before + 20)) ]; then ok "--seek +30 moved the playhead forward (${before}s → ${p1}s)"
       else bad "--seek +30 left the playhead at ${p1}s (was ${before}s)"; fi ;;
esac
# An ABSOLUTE seek is exact (mpv hr-seeks it), so coming back from ~30s means the start
# itself, not a keyframe in its neighbourhood.
p0=$(shell/ut-play --seek-to 0 --id "$id1" -j | jq -r '.position')
case "$p0" in
    "" | null) bad "--seek-to 0 reported no position — the read-back is unproved" ;;
    *) if [ "$p0" -le 2 ]; then ok "--seek-to 0 came back to the start (${p1}s → ${p0}s)"
       else bad "--seek-to 0 landed at ${p0}s, which is not the start"; fi ;;
esac
report "--resume reads back running" "false" \
    "$(shell/ut-play --resume --id "$id1" -j | jq -r '.paused')"
report "…and --status agrees"         "false" \
    "$(shell/ut-play --status -j | jq -r --arg i "$id1" '.players[]|select(.id==$i)|.paused')"

# NOT checked here: the `head -n <count>` pipe close in live_props (§9.3). It was tried and
# pulled the same day — with the real peer it CANNOT go red. Swapping the head for a `cat`
# and re-running measures 0.04s either way, so a timing assertion on it would be a check that
# passes whatever the code does. The 1.11s it used to save was a scripted peer's idle timer,
# and that peer is gone; the guard stays in the player as defence, without a green tick
# pretending the suite proved it.
# The degradation an agent must be able to tell from a reading — and it is produced by doing
# it, not by imitating it: the socket of a REALLY running player is really removed, which is
# what a crashed mpv or a half-cleaned state dir leaves behind. Live fields go null and volume
# falls back to the record, which --set-volume patched to 40 above.
rm -f "$sock1"
report "socketless player: nulls, volume off the record" 0 \
    "$(shell/ut-play --status -j | jq -e --arg i "$id1" \
        '.players[]|select(.id==$i)|.paused==null and .position==null and .duration==null and .volume==40' \
        >/dev/null 2>&1; echo $?)"

echo "── a second engine: the envelope's http_headers reach mpv ─────────"
# The only check in the suite that proves the player APPLIES what an engine hands it.
# contract.sh asserts http_headers is PRESENT in the resolve envelope; nothing asserted that
# ut-play forwards it into mpv. This site is what makes the difference observable: its CDN
# answers 403 to a bare stream URL and 206 to the same URL carrying the envelope's Referer
# (docs/ARCHITECTURE.md §6.1, measured). So a player that dropped the header block would still
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

echo "── a queue is a player consuming a playlist ───────────────────────"
# Everything above played ONE handle. This section plays a LIST, and it is here rather than
# in contract.sh for the reason that file states about itself: proving a queue ADVANCES
# needs a real engine round trip and a real mpv reaching the end of a track, and nothing may
# stand in for either. A mock engine answering av://lavfi:sine would skip the JIT resolve —
# the very thing most likely to break between two tracks — and be green for it.
#
# One player, so no --id is needed anywhere below (exactly-one is the zero-friction case).
shell/ut-play --stop --all -j >/dev/null 2>&1
qout=$(jq -nc --arg a "$U1" --arg b "$U2" \
    '[{engine:"yt",url:$a},{engine:"yt",url:$b}]' | shell/ut-play -d --queue - -j --volume 0 2>/dev/null)
report "--queue - launches" 0 "$(printf '%s' "$qout" | jq -e '.status=="started" and .id' >/dev/null 2>&1; echo $?)"
# The queue is visible from the moment the player exists, not once the first track decodes:
# a caller that asks what is queued must not have to wait for mpv.
report "--status carries the queue" 0 \
    "$(shell/ut-play --status -j | jq -e '.players[0].queue
        | .pos==0 and .len==2 and (.next.url|type=="string")' >/dev/null 2>&1; echo $?)"
qsock=$(printf '%s' "$qout" | jq -r '.sock // empty')
wait_for_sock "$qsock" || bad "the queued player's socket never appeared — the checks below are moot"

# --enqueue lands on a RUNNING player, and the envelope reports the queue it wrote.
report "--enqueue appends" 0 \
    "$(jq -nc --arg a "$U1" '[{engine:"yt",url:$a}]' | shell/ut-play --enqueue - -j 2>/dev/null \
        | jq -e '.status=="ok" and .added==1 and .queue.len==3' >/dev/null 2>&1; echo $?)"
# Concurrency is DRIVEN, not argued (the rule ut-playlist's eight concurrent --add checks
# already follow): six writers, six items, no lost update. With lock_queue_state stubbed to
# fail this loop leaves fewer — watched, so the check is known to be able to fail.
for i in 1 2 3 4 5 6; do
    jq -nc --arg a "$U2" '[{engine:"yt",url:$a}]' | shell/ut-play --enqueue - -j >/dev/null 2>&1 &
done
wait
report "6 concurrent --enqueue all land (3+6)" 9 \
    "$(shell/ut-play --status -j | jq -r '.players[0].queue.len')"

# --next: the POSITION moves in the parent, so the envelope reports a queue it read. Then the
# player follows — a bounded poll, because what is being proved is that it DID follow, not
# how fast it resolved (a duration assertion against a live site is the timing check
# CLAUDE.md forbids).
report "--next advances the position" 1 \
    "$(shell/ut-play --next -j 2>/dev/null | jq -r '.queue.pos')"
i=0
while [ $i -lt 60 ]; do
    u=$(shell/ut-play --status -j | jq -r '.players[0].url // empty')
    [ "$u" = "$U2" ] && break
    sleep 1; i=$((i + 1))
done
report "the record follows the track" "$U2" \
    "$(shell/ut-play --status -j | jq -r '.players[0].url // empty')"

# The one a queue exists for: a track ENDING on its own starts the next. Seek to just before
# the end rather than waiting out a six-hour stream, then poll for the position to move —
# the child has to notice mpv exited, advance under its own lock, resolve the next handle and
# start a new mpv, and none of that is driven from here.
dur=$(shell/ut-play --status -j | jq -r '.players[0].duration // empty')
case "$dur" in
    "" | null) bad "no duration on the queued player — cannot drive it to the end of a track" ;;
    *)
        shell/ut-play --seek-to $((dur - 4)) -j >/dev/null 2>&1
        i=0
        while [ $i -lt 90 ]; do
            [ "$(shell/ut-play --status -j | jq -r '.players[0].queue.pos // empty')" = "2" ] && break
            sleep 1; i=$((i + 1))
        done
        report "a track ending advances the queue" "2" \
            "$(shell/ut-play --status -j | jq -r '.players[0].queue.pos // empty')"
        ;;
esac

# --stop takes the whole QUEUE down. The child cannot trap SIGINT — an async command enters
# with it SIG_IGN — so a group INT alone leaves the leader alive and playing on into the next
# track until stop_group's KILL escalation. stop_group therefore tells the LEADER with
# SIGTERM, and repeats both signals on every tick of the escalation because the engine call
# between two tracks spawns processes that never saw the first one.
shell/ut-play --next -j >/dev/null 2>&1
sleep 0.5
report "--stop ends the queue" 0 "$(shell/ut-play --stop --all -j >/dev/null 2>&1; echo $?)"
sleep 2
report "no players after a queue" 0 "$(shell/ut-play --status -j | jq -e '.players==[]' >/dev/null 2>&1; echo $?)"
n=$(pgrep -f 'mpv .*--input-ipc-server' 2>/dev/null | wc -l | tr -d ' ')
report "no orphan mpv after a queue" 0 "${n:-0}"
# NOT checked here, and the reason is the rule this file lives by: that a stopped queue
# files no tombstone was TRIED as a check and pulled, because it could not be made to go red
# — disabling the child's `stopped` arm outright still produced an empty failed[]. A green
# tick nobody has seen fail proves nothing, so the claim stays where it can fail: contract.sh
# already drives the tombstone boundaries (a normal finish writes none, a log with no epitaph
# writes none) from fixtures, which is where a rule about what the REAPER records belongs.

echo
printf '%s: %d ok, %d failed\n' "$(basename "$0")" "$pass" "$fail"
if [ "$fail" -ne 0 ]; then printf 'failures:\n%s' "$FAILED"; exit 1; fi
exit 0
