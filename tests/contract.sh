#!/usr/bin/env bash
# The CLI contract, asserted by RUNNING it. No rig: a command-line tool is tested by
# invoking it and reading its exit code and its stdout, which is all this file does.
#
# What it covers: the search envelope's shape, every documented rejection (a flag on the
# wrong verb, a bare query where a URL belongs, two actions at once, a selector with no
# action), the read-only --transcript verb both ways, the idle lifecycle, the tombstone
# record for a player that died unasked, --version, the non-TTY refusal, and the failure
# taxonomy — 1 is usage, 2 is a tool that failed.
#
# This replaced a skill that carried the same commands as prose for an agent to copy out by
# hand. That version rotted silently: it listed a resident socket server as a check (it hangs
# and asserts nothing), asserted the same exit code in two phases, described the network path
# in a sentence with no command behind it, referenced capture files that were never made, and
# had no coverage at all for --transcript. A test suite that cannot be executed reports green
# by default, which is worse than having none.
#
# Portability: bash 3.2 (macOS system bash). No bash-4 idioms; see docs/SPEC-system.md §28.
#
# Usage:  tests/contract.sh            all checks
#         tests/contract.sh -q         failures and the summary only
# Exit:   0 = every check held (known drifts excluded), 1 = at least one regression

set -uo pipefail
cd "$(cd -P "$(dirname "$0")/.." && pwd -P)" || exit 1

QUIET=0
[ "${1:-}" = "-q" ] && QUIET=1

pass=0; fail=0; known=0
FAILED=""

# report <name> <want> <got>          — a regression if they differ
report() {
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
        ((QUIET)) || printf '  ok    %-34s %s\n' "$1" "$3"
    else
        fail=$((fail + 1))
        FAILED="${FAILED}    ${1}: want ${2}, got ${3}"$'\n'
        printf '  FAIL  %-34s want %s, got %s\n' "$1" "$2" "$3"
    fi
}

# drift <name> <want> <got> <note>    — an OPEN finding, recorded and not counted as a
# regression. The point is that a new break still stands out against a red line that is
# already understood; papering over is reporting the wrong number, not labelling a known one.
drift() {
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
        printf '  FIXED %-34s now %s (was a known drift: %s)\n' "$1" "$3" "$4"
    else
        known=$((known + 1))
        printf '  drift %-34s want %s, got %s — %s\n' "$1" "$2" "$3" "$4"
    fi
}

# Exit code of a command whose output we do not want.
rc() { "$@" >/dev/null 2>&1; echo $?; }

# jq_ok <jq-filter> <command...> — does the command's stdout satisfy the filter?
# The output is captured FIRST and the filter applied to the variable, never piped straight
# from the command: `set -o pipefail` makes a pipeline carry the LEFT side's status, so
# `yt-play --transcript -j <no-captions> | jq -e …` reported jq's success as the command's
# exit 1. Both error-path checks below went red against correct behaviour that way.
jq_ok() {
    local filter=$1; shift
    local out
    out=$("$@" 2>/dev/null)
    printf '%s' "$out" | jq -e "$filter" >/dev/null 2>&1
    echo $?
}

echo "── search envelope ────────────────────────────────────────────────"
report "search -j envelope" 0 \
    "$(jq_ok '.query and .count and (.results|length==3)' shell/yt-search -j -n 3 -- lofi)"
report "search -J has raw id" 0 \
    "$(jq_ok '.results[0]|has("id")' shell/yt-search -J -n 2 -- lofi)"
# Was an open R8 drift (26 lines for -n 3); fixed, so it is a hard check now — a "known"
# label on a passing behaviour is how a real regression gets waved through later.
report "search -j is one line" 1 \
    "$(shell/yt-search -j -n 2 -- lofi | wc -l | tr -d ' ')"

echo "── rejections (1 = usage error) ───────────────────────────────────"
report "yt no args"               1 "$(rc /bin/bash shell/yt)"
report "yt-search no args"        1 "$(rc /bin/bash shell/yt-search)"
report "yt-search --detach"       1 "$(rc shell/yt-search --detach -- x)"
report "yt-search -f audio"       1 "$(rc shell/yt-search -f audio -- x)"
report "yt-play bare query"       1 "$(rc shell/yt-play "a query")"
report "yt-play -n"               1 "$(rc shell/yt-play -n 5 -- URL)"
report "yt-play two actions"      1 "$(rc shell/yt-play --status --stop)"
report "yt-play selector alone"   1 "$(rc shell/yt-play --status --id X)"
report "yt-play -d + action"      1 "$(rc shell/yt-play -d --stop)"
report "yt-play -- <query>"      1 "$(rc shell/yt-play -- "a query")"

echo "── argv order: a flag-shaped query after -- is SEARCHED ───────────"
# Not a player list: --status after -- is four characters of query text.
report "yt -l -- --status searches" 0 \
    "$(shell/yt -l -- --status 2>&1 | head -1 | grep -qv '^{' && echo 0 || echo 1)"

echo "── --transcript: read-only, so the gate and both envelopes are all ─"
# The ok-path fixture must be a video that HAS captions and the error-path one must not:
# pointing the ok-path at a long music stream is how this check first went red against
# working code.
CAPTIONED="https://www.youtube.com/watch?v=8S0FDjFBj8o"
BARE="https://www.youtube.com/watch?v=n61ULEU7CO0"
report "transcript rejects -f"    1 "$(rc shell/yt-play --transcript -f audio -- "$CAPTIONED")"
report "transcript rejects -d"    1 "$(rc shell/yt-play --transcript -d -- "$CAPTIONED")"
report "transcript envelope"      0 \
    "$(jq_ok '.status=="ok" and .id and .lang and .chars>0 and (.is_auto|type=="boolean") and (.text|length>0)' \
        shell/yt-play --transcript -j -- "$CAPTIONED")"
report "transcript -J has segments" 0 \
    "$(jq_ok '.segments[0]|has("start") and has("text")' shell/yt-play --transcript -J -- "$CAPTIONED")"
report "no captions -> error"     0 \
    "$(jq_ok '.status=="error" and .reason=="no_subtitles_available"' shell/yt-play --transcript -j -- "$BARE")"
report "no captions exit"         1 "$(rc shell/yt-play --transcript -j -- "$BARE")"

echo "── failure taxonomy: 2 is a tool failure, never 1 ─────────────────"
# An unreachable proxy is the cheapest deliberate network failure, and it works offline too.
NOPROXY="http://127.0.0.1:1"
report "network envelope" 0 \
    "$(http_proxy=$NOPROXY https_proxy=$NOPROXY jq_ok '.status=="error" and .reason=="network"' \
        shell/yt-search -j -n 2 -- lofi)"
report "network exit is 2" 2 \
    "$(http_proxy=$NOPROXY https_proxy=$NOPROXY rc shell/yt-search -j -n 2 -- lofi)"
report "network exit is 2 (text)" 2 \
    "$(http_proxy=$NOPROXY https_proxy=$NOPROXY rc shell/yt-search -n 2 -- lofi)"

echo "── idle lifecycle: exit 0, ONE compact line, idempotent ───────────"
report "--status exit"      0 "$(rc shell/yt-play --status -j)"
report "--status one line"  1 "$(shell/yt-play --status -j | wc -l | tr -d ' ')"
report "--status is empty"  0 "$(jq_ok '.players==[]' shell/yt-play --status -j)"
report "--stop --all exit"  0 "$(rc shell/yt-play --stop --all -j)"
report "--stop --all line"  1 "$(shell/yt-play --stop --all -j | wc -l | tr -d ' ')"

# The four live fields are read off a real unix socket, so the peer is the one thing that
# cannot be faked away — and mpv will not answer out of order, report a property null, or
# refuse to close its side on cue. tests/mpv_ipc_mock.py does exactly that (the same fixture
# the TUI readers are checked against), behind a real socket, with the real verb in front.
# The timing check is the guard on `head -n <count>`: without it the read waits out `nc -w1`
# per player, which is a 30x slowdown no output assertion would notice. python3-gated: the
# rest of this file is dependency-free on purpose.
echo "── live read: four properties, one round trip, null != false ──────"
SD="${TMPDIR:-/tmp}/yt-cli-$(id -u)"
if ! command -v python3 >/dev/null 2>&1; then
    echo "  skip  (needs python3 for tests/mpv_ipc_mock.py)"
else
    # A player record is only LIVE while pgrep -g finds its stored pid, so the stand-in has
    # to be a process-group leader — `set -m` makes a background job one, exactly as
    # detach_play does. --no-peer leaves the socket absent, which is the degradation case.
    mkplayer() { # <id> [--no-peer] [mock-flags...]
        local id=$1 peer=1; shift
        [ "${1:-}" = "--no-peer" ] && { peer=0; shift; }
        mkdir -p "$SD/players"
        set -m; sleep 60 & LIVE_PID=$!; set +m
        disown "$LIVE_PID" 2>/dev/null
        MOCK_PID=""
        if [ "$peer" = 1 ]; then
            python3 tests/mpv_ipc_mock.py "$SD/mpv-$id.sock" "$@" & MOCK_PID=$!
            disown "$MOCK_PID" 2>/dev/null
            local i=0
            while [ ! -S "$SD/mpv-$id.sock" ] && [ "$i" -lt 40 ]; do sleep 0.1; i=$((i + 1)); done
        fi
        printf '{"id":"%s","pid":%s,"url":"https://youtu.be/%s","mode":"audio","format":"ba","started_at":"2026-01-01T00:00:00Z","log":"%s/mpv-%s.log","sock":"%s/mpv-%s.sock","title":null,"volume":7}\n' \
            "$id" "$LIVE_PID" "$id" "$SD" "$id" "$SD" "$id" >"$SD/players/$id.json"
    }
    rmplayer() {
        kill "$LIVE_PID" 2>/dev/null
        [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null
        rm -f "$SD/players/$1.json" "$SD/mpv-$1.sock"
        return 0
    }

    mkplayer ctest_live --paused
    report "paused is read live"    0 "$(jq_ok '[.players[]|select(.id=="ctest_live")][0].paused==true' shell/yt-play --status -j)"
    report "position/duration live" 0 "$(jq_ok '[.players[]|select(.id=="ctest_live")][0]|.position==61 and .duration==245' shell/yt-play --status -j)"
    report "volume beats the record" 0 "$(jq_ok '[.players[]|select(.id=="ctest_live")][0].volume==55' shell/yt-play --status -j)"
    # A peer that never closes: three --status calls must not cost three nc timeouts.
    start=$SECONDS
    shell/yt-play --status -j >/dev/null 2>&1
    shell/yt-play --status -j >/dev/null 2>&1
    shell/yt-play --status -j >/dev/null 2>&1
    report "3 reads under 2s (pipe closes)" 1 "$([ $((SECONDS - start)) -lt 2 ] && echo 1 || echo 0)"
    rmplayer ctest_live

    mkplayer ctest_null --null pause
    report "unanswered pause is null"  0 "$(jq_ok '[.players[]|select(.id=="ctest_null")][0].paused==null' shell/yt-play --status -j)"
    rmplayer ctest_null

    mkplayer ctest_rev --reverse --noisy
    report "out-of-order lands right" 0 "$(jq_ok '[.players[]|select(.id=="ctest_rev")][0]|.position==61 and .duration==245 and .volume==55' shell/yt-play --status -j)"
    rmplayer ctest_rev

    # No peer at all: the socket is absent, so every live field is null and volume falls back
    # to the record — the degradation an agent must be able to tell from a real reading.
    mkplayer ctest_nosock --no-peer
    report "dead socket: nulls, not false" 0 \
        "$(jq_ok '[.players[]|select(.id=="ctest_nosock")][0]|.paused==null and .position==null and .duration==null and .volume==7' shell/yt-play --status -j)"
    rmplayer ctest_nosock
fi

# A detached player that dies on its own is the one lifecycle path the caller does not
# drive, and it used to be silent: --status went empty, which is what a NORMAL finish looks
# like too (docs/SPEC-system.md §9.2). These checks own the boundary that keeps the tombstone
# list an error record rather than the listening history ROADMAP.md §0 rules out — a normal
# finish must leave nothing, a log with no epitaph must not be read as a death, and the list
# must stay bounded. The input is a fabricated state file + log, which is exactly what the
# reaper reads; the code under test (reap, classify, prune, envelope) is the real one, driven
# through the real verb. Like --stop --all above, this writes in the live state dir.
echo "── the death record: failures only, bounded, never inferred ───────"
SD="${TMPDIR:-/tmp}/yt-cli-$(id -u)"
mkfake() { # <id> <rc|""> [ended_at]   — a dead player, with or without an epitaph
    mkdir -p "$SD/players"
    printf '{"id":"%s","pid":999999,"url":"https://youtu.be/%s","mode":"audio","format":"ba","started_at":"2026-01-01T00:00:00Z","log":"%s/mpv-%s.log","sock":"%s/mpv-%s.sock","title":null,"volume":50}\n' \
        "$1" "$1" "$SD" "$1" "$SD" "$1" >"$SD/players/$1.json"
    printf 'mpv chatter\n' >"$SD/mpv-$1.log"
    [ -n "$2" ] && printf '{"yt_event":"exit","rc":%s,"reason":"unavailable","ended_at":"%s"}\n' \
        "$2" "${3:-2026-01-01T00:00:01Z}" >>"$SD/mpv-$1.log"
    return 0
}
rm -rf "$SD/players/dead"
report "failed[] always present"   0 "$(jq_ok '.failed|type=="array"' shell/yt-play --status -j)"
mkfake ctest_ok 0
report "normal finish: no tombstone" 0 "$(jq_ok '.failed==[]' shell/yt-play --status -j)"
mkfake ctest_mute ""
report "no epitaph: no tombstone"  0 "$(jq_ok '.failed==[]' shell/yt-play --status -j)"
mkfake ctest_bad 2
report "death is reported once"    0 "$(jq_ok '[.failed[]|select(.id=="ctest_bad")]|length==1 and (.[0].reason=="unavailable") and (.[0].exit_code==2)' shell/yt-play --status -j)"
report "--status still exits 0"    0 "$(rc shell/yt-play --status -j)"
report "--status still one line"   1 "$(shell/yt-play --status -j | wc -l | tr -d ' ')"
i=0
while [ "$i" -lt 10 ]; do mkfake "ctest_c$i" 2 "2026-01-01T00:00:0${i}Z"; i=$((i + 1)); done
shell/yt-play --status -j >/dev/null 2>&1
report "capped at 8 in the envelope" 8 "$(shell/yt-play --status -j | jq '.failed|length')"
report "capped at 8 on disk"         8 "$(ls "$SD/players/dead" 2>/dev/null | wc -l | tr -d ' ')"
report "newest kept"                 0 "$(jq_ok '.failed[0].id=="ctest_c9"' shell/yt-play --status -j)"
rm -f "$SD/players"/ctest_*.json "$SD"/mpv-ctest_*.log
rm -rf "$SD/players/dead"

echo "── version and the non-TTY refusal ────────────────────────────────"
report "one version, four entry points" 1 \
    "$(for c in yt yt-search yt-play yt-tui; do shell/$c --version | awk '{print $NF}'; done | sort -u | wc -l | tr -d ' ')"
report "yt-tui refuses a non-TTY" 1 "$(shell/yt-tui </dev/null >/dev/null 2>&1; echo $?)"

echo
printf '%s: %d ok, %d failed, %d known drift\n' "$(basename "$0")" "$pass" "$fail" "$known"
if [ "$fail" -ne 0 ]; then
    printf 'regressions:\n%s' "$FAILED"
    exit 1
fi
exit 0
