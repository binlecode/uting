#!/usr/bin/env bash
# The CLI contract, asserted by RUNNING it. No rig: a command-line tool is tested by
# invoking it and reading its exit code and its stdout, which is all this file does.
#
# What it covers: the search envelope's shape, every documented rejection (a flag on the
# wrong verb, a bare query where a URL belongs, two actions at once, a selector with no
# action), the read-only --transcript verb both ways, the idle lifecycle, the tombstone
# record for a player that died unasked, --version, the non-TTY refusal, and the failure
# taxonomy — 1 is usage, 2 is a tool that failed, and the two engines' envelopes agreeing
# key for key.
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
# `yt-resolve --transcript -j <no-captions> | jq -e …` reported jq's success as the command's
# exit 1. Both error-path checks below went red against correct behaviour that way.
jq_ok() {
    local filter=$1; shift
    local out
    out=$("$@" 2>/dev/null)
    printf '%s' "$out" | jq -e "$filter" >/dev/null 2>&1
    echo $?
}

# A short, permanent, caption-bearing public video: the one handle every engine-contract
# check below resolves. Chosen for being 19 seconds long — nothing here plays it, but a
# resolve that accidentally starts a download costs a second rather than a minute.
MEDIA_ID="jNQXAC9IVRw"

echo "── search envelope ────────────────────────────────────────────────"
report "search -j envelope" 0 \
    "$(jq_ok '.query and .count and (.results|length==3)' shell/yt-search -j -n 3 -- lofi)"
# The engine names itself in its own envelope. This is what lets a caller route a chosen
# result back to the matching <engine>-resolve without pattern-matching its URL, so a new
# engine that forgets the field breaks routing rather than merely looking different.
report "search -j names its engine" 0 \
    "$(jq_ok '.status=="ok" and .engine=="yt"' shell/yt-search -j -n 2 -- lofi)"
report "search -J has raw id" 0 \
    "$(jq_ok '.results[0]|has("id")' shell/yt-search -J -n 2 -- lofi)"
# Was an open R8 drift (26 lines for -n 3); fixed, so it is a hard check now — a "known"
# label on a passing behaviour is how a real regression gets waved through later.
report "search -j is one line" 1 \
    "$(shell/yt-search -j -n 2 -- lofi | wc -l | tr -d ' ')"

echo "── resolve envelope: the half that turns a handle into bytes ──────"
# Every key the PLAYER reads. A new engine that renames one, or omits http_headers, breaks
# playback in a way no other check here would notice: the search half would still look fine.
# http_headers is asserted PRESENT rather than non-empty — {} is a legal answer, absent is not.
report "resolve -j envelope" 0 \
    "$(jq_ok '.status=="ok" and .engine=="yt" and (.stream_urls|length)>0
              and has("http_headers") and (.http_headers|type)=="object"
              and has("title") and has("format") and has("retried")' \
        shell/yt-resolve -j -- "$MEDIA_ID")"
report "resolve -j is one line" 1 \
    "$(shell/yt-resolve -j -- "$MEDIA_ID" | wc -l | tr -d ' ')"
# The id is what search hands over; accepting it is what makes the two halves a pair.
report "resolve takes a bare id"  0 "$(rc shell/yt-resolve -j -- "$MEDIA_ID")"
# Shape validation lives in the ENGINE now — the player cannot tell a good id from a bad one.
report "resolve rejects a non-id" 1 "$(rc shell/yt-resolve -j -- "not an id")"
report "resolve rejects -d"       1 "$(rc shell/yt-resolve -d -- "$MEDIA_ID")"
report "resolve rejects -n"       1 "$(rc shell/yt-resolve -n 5 -- "$MEDIA_ID")"

echo "── the player's engine seam ───────────────────────────────────────"
# A mistyped engine must be a USAGE error. If it fell into 2+ an agent would read it as
# "the tool failed, retry later" and retry a name that will never exist.
report "unknown engine is usage"  1 "$(rc shell/ut-play --engine nope -- "$MEDIA_ID")"
report "engine name is validated" 1 "$(rc shell/ut-play --engine ../evil -- "$MEDIA_ID")"
# A well-formed id that resolves to nothing is a PROPAGATED tool failure (2+), not usage,
# and it must still say why. This is the semantic B-2 bought by moving the shape check down.
report "dead id is 2+, not 1"     2 "$(rc shell/ut-play -j -- AAAAAAAAAAA)"
report "dead id keeps its reason" 0 \
    "$(jq_ok '.status=="error" and .exit_code>=2 and (.reason|type)=="string"' \
        shell/ut-play -j -- AAAAAAAAAAA)"

echo "── rejections (1 = usage error) ───────────────────────────────────"
report "core no args"             1 "$(rc /bin/bash shell/ut-play)"
report "yt-search no args"        1 "$(rc /bin/bash shell/yt-search)"
report "yt-search --detach"       1 "$(rc shell/yt-search --detach -- x)"
report "yt-search -f audio"       1 "$(rc shell/yt-search -f audio -- x)"
report "ut-play bare query"       1 "$(rc shell/ut-play "a query")"
report "ut-play -n"               1 "$(rc shell/ut-play -n 5 -- URL)"
report "ut-play two actions"      1 "$(rc shell/ut-play --status --stop)"
report "ut-play selector alone"   1 "$(rc shell/ut-play --status --id X)"
report "ut-play -d + action"      1 "$(rc shell/ut-play -d --stop)"
report "ut-play -- <query>"       1 "$(rc shell/ut-play -- "a query")"
# The gating wrapper is gone, so these three are the checks that it took its gate with it
# rather than dropping it: an unknown long flag must not reach getopts as a bare `-`, and
# the two verbs that moved to the engine must name the engine instead of half-working.
report "ut-play unknown long flag" 1 "$(rc shell/ut-play --json-full -- URL)"
report "--get-url is retired"     1 "$(rc shell/ut-play --get-url -- URL)"
report "--info is the engine's"   1 "$(rc shell/ut-play --info -- URL)"

echo "── argv order: a flag-shaped query after -- is SEARCHED ───────────"
# Not a player list: --status after -- is eight characters of query text. The check lives on
# yt-search because that is where searching lives now; the player has no search branch left
# to confuse a flag-shaped token with (PLAN-ut-restructure step B-1).
report "yt-search -- --status searches" 0 \
    "$(shell/yt-search -l -- --status 2>&1 | head -1 | grep -qv '^{' && echo 0 || echo 1)"
# The other half of that split: a non-URL positional is no longer a search, it is a usage
# error naming the right tool. Exit 1, not a silent fall-through to playback.
report "core: non-URL is a usage error" 1 "$(rc /bin/bash shell/ut-play -- "a query")"

echo "── --transcript: read-only, so the gate and both envelopes are all ─"
# The ok-path fixture must be a video that HAS captions and the error-path one must not:
# pointing the ok-path at a long music stream is how this check first went red against
# working code.
CAPTIONED="https://www.youtube.com/watch?v=8S0FDjFBj8o"
BARE="https://www.youtube.com/watch?v=n61ULEU7CO0"
report "transcript rejects -f"    1 "$(rc shell/yt-resolve --transcript -f audio -- "$CAPTIONED")"
report "transcript rejects -d"    1 "$(rc shell/yt-resolve --transcript -d -- "$CAPTIONED")"
report "transcript envelope"      0 \
    "$(jq_ok '.status=="ok" and .id and .lang and .chars>0 and (.is_auto|type=="boolean") and (.text|length>0)' \
        shell/yt-resolve --transcript -j -- "$CAPTIONED")"
report "transcript -J has segments" 0 \
    "$(jq_ok '.segments[0]|has("start") and has("text")' shell/yt-resolve --transcript -J -- "$CAPTIONED")"
report "no captions -> error"     0 \
    "$(jq_ok '.status=="error" and .reason=="no_subtitles_available"' shell/yt-resolve --transcript -j -- "$BARE")"
report "no captions exit"         1 "$(rc shell/yt-resolve --transcript -j -- "$BARE")"

echo "── the second engine: the same envelope, or the split is a fiction ─"
# A permanent, single-part music video on the second site. Single-part matters: a handle
# that is a 50-track collection resolves to part one, which is correct but makes a title
# assertion depend on which part that is.
BILI_ID="BV1mL411E7Fb"

# THE check the engine split exists for. Two engines are only interchangeable if a caller
# cannot tell which one answered, so the assertion is on the KEY SETS THEMSELVES rather
# than on a list of names written out twice: a field renamed, added or dropped in EITHER
# engine fails here, including one added to yt-search years from now and forgotten on the
# other side. Nothing else in this file would notice — each engine's own checks would still
# pass, and playback would break only for the engine nobody happened to run.
YT_S=$(shell/yt-search -j -n 2 -- lofi 2>/dev/null)
BILI_S=$(shell/bili-search -j -n 2 -- 音乐 2>/dev/null)
report "search envelopes agree" \
    "$(printf '%s' "$YT_S" | jq -Sc 'keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_S" | jq -Sc 'keys' 2>/dev/null)"
report "search result keys agree" \
    "$(printf '%s' "$YT_S" | jq -Sc '.results[0]|keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_S" | jq -Sc '.results[0]|keys' 2>/dev/null)"
YT_R=$(shell/yt-resolve -j -- "$MEDIA_ID" 2>/dev/null)
BILI_R=$(shell/bili-resolve -j -- "$BILI_ID" 2>/dev/null)
report "resolve envelopes agree" \
    "$(printf '%s' "$YT_R" | jq -Sc 'keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_R" | jq -Sc 'keys' 2>/dev/null)"

report "bili-search names its engine" 0 \
    "$(jq_ok '.status=="ok" and .engine=="bili"' shell/bili-search -j -n 2 -- 音乐)"
report "bili-search -j is one line" 1 \
    "$(shell/bili-search -j -n 2 -- 音乐 | wc -l | tr -d ' ')"
# The site sends duration as "MM:SS" with unbounded minutes ("222:28"), which every surface
# above would silently mis-sort and mis-render as a string. It is parsed in the engine, so
# the assertion is that what leaves the engine is a NUMBER.
report "bili duration is seconds" 0 \
    "$(jq_ok '[.results[].duration]|length>0 and all(type=="number")' shell/bili-search -j -n 5 -- 音乐)"
# Titles arrive as search-result HTML (<em class="keyword">) and entity-escaped. Markup that
# survives into a title is counted by the width layer, which reflows every row wrongly.
report "bili titles carry no markup" 0 \
    "$(jq_ok '[.results[].title]|all((test("<") or test("&[a-z#]+;"))|not)' shell/bili-search -j -n 10 -- 周杰伦)"

report "bili-resolve takes a BV id" 0 "$(rc shell/bili-resolve -j -- "$BILI_ID")"
report "bili-resolve rejects a non-id" 1 "$(rc shell/bili-resolve -j -- "not an id")"
# This site's CDN checks Referer: the bare stream URL answers 403 and the same URL with
# these headers answers 206 (measured). An empty http_headers here is a silently unplayable
# engine, which is exactly the contract hole the key was added to close.
report "bili resolve sends a Referer" 0 \
    "$(jq_ok '.http_headers|has("Referer")' shell/bili-resolve -j -- "$BILI_ID")"
# Capability differs per engine and is stated, not faked: this site's videos carry no
# caption track, so the verb is absent rather than always answering "none".
report "bili-resolve has no --transcript" 1 "$(rc shell/bili-resolve --transcript -- "$BILI_ID")"
# -S on a search that resolves no format takes a value it cannot act on.
report "bili-search rejects -S" 1 "$(rc shell/bili-search -S abr -- 音乐)"
report "bili-search rejects -d" 1 "$(rc shell/bili-search -d -- 音乐)"
# One engine, one site. `yt-resolve` used to accept ANY http(s) URL and hand it to yt-dlp,
# which supports 1700+ sites — so a Bilibili URL resolved fine and came back labelled
# `engine:"yt"`. It WORKED, which is why it went unnoticed, and it made the one field whose
# job is routing a result back to its resolver into a field that lies. These two checks are
# each other's mirror, because a rule only one engine follows is not a rule.
report "yt-resolve refuses a bili URL" 1 \
    "$(rc shell/yt-resolve -j -- https://www.bilibili.com/video/BV1mL411E7Fb)"
report "bili-resolve refuses a yt URL" 1 \
    "$(rc shell/bili-resolve -j -- "https://www.youtube.com/watch?v=$MEDIA_ID")"
# The opposite failure is just as real: a host list tightened too far silently drops a
# spelling users actually type. youtu.be is the one every share button produces.
report "yt-resolve still takes youtu.be" 0 "$(rc shell/yt-resolve -j -- https://youtu.be/$MEDIA_ID)"
# The player routes by NAME, and the name is the command prefix — the whole reason the
# lookup is a string concatenation instead of a registry.
report "ut-play routes to the bili engine" 0 \
    "$(jq_ok '.status=="error" and .exit_code>=2 and (.reason|type)=="string"' \
        shell/ut-play --engine bili -j -- BV1111111111)"

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
report "--status exit"      0 "$(rc shell/ut-play --status -j)"
report "--status one line"  1 "$(shell/ut-play --status -j | wc -l | tr -d ' ')"
report "--status is empty"  0 "$(jq_ok '.players==[]' shell/ut-play --status -j)"
report "--stop --all exit"  0 "$(rc shell/ut-play --stop --all -j)"
report "--stop --all line"  1 "$(shell/ut-play --stop --all -j | wc -l | tr -d ' ')"

# The four live fields are read off a real unix socket, so the peer is the one thing that
# cannot be faked away — and mpv will not answer out of order, report a property null, or
# refuse to close its side on cue. tests/mpv_ipc_mock.py does exactly that (the same fixture
# the TUI readers are checked against), behind a real socket, with the real verb in front.
# The timing check is the guard on `head -n <count>`: without it the read waits out `nc -w1`
# per player, which is a 30x slowdown no output assertion would notice. python3-gated: the
# rest of this file is dependency-free on purpose.
echo "── live read: four properties, one round trip, null != false ──────"
SD="${TMPDIR:-/tmp}/uting-$(id -u)"
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
    report "paused is read live"    0 "$(jq_ok '[.players[]|select(.id=="ctest_live")][0].paused==true' shell/ut-play --status -j)"
    report "position/duration live" 0 "$(jq_ok '[.players[]|select(.id=="ctest_live")][0]|.position==61 and .duration==245' shell/ut-play --status -j)"
    report "volume beats the record" 0 "$(jq_ok '[.players[]|select(.id=="ctest_live")][0].volume==55' shell/ut-play --status -j)"
    # A peer that never closes: three --status calls must not cost three nc timeouts.
    start=$SECONDS
    shell/ut-play --status -j >/dev/null 2>&1
    shell/ut-play --status -j >/dev/null 2>&1
    shell/ut-play --status -j >/dev/null 2>&1
    report "3 reads under 2s (pipe closes)" 1 "$([ $((SECONDS - start)) -lt 2 ] && echo 1 || echo 0)"
    rmplayer ctest_live

    mkplayer ctest_null --null pause
    report "unanswered pause is null"  0 "$(jq_ok '[.players[]|select(.id=="ctest_null")][0].paused==null' shell/ut-play --status -j)"
    rmplayer ctest_null

    mkplayer ctest_rev --reverse --noisy
    report "out-of-order lands right" 0 "$(jq_ok '[.players[]|select(.id=="ctest_rev")][0]|.position==61 and .duration==245 and .volume==55' shell/ut-play --status -j)"
    rmplayer ctest_rev

    # No peer at all: the socket is absent, so every live field is null and volume falls back
    # to the record — the degradation an agent must be able to tell from a real reading.
    mkplayer ctest_nosock --no-peer
    report "dead socket: nulls, not false" 0 \
        "$(jq_ok '[.players[]|select(.id=="ctest_nosock")][0]|.paused==null and .position==null and .duration==null and .volume==7' shell/ut-play --status -j)"
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
SD="${TMPDIR:-/tmp}/uting-$(id -u)"
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
report "failed[] always present"   0 "$(jq_ok '.failed|type=="array"' shell/ut-play --status -j)"
mkfake ctest_ok 0
report "normal finish: no tombstone" 0 "$(jq_ok '.failed==[]' shell/ut-play --status -j)"
mkfake ctest_mute ""
report "no epitaph: no tombstone"  0 "$(jq_ok '.failed==[]' shell/ut-play --status -j)"
mkfake ctest_bad 2
report "death is reported once"    0 "$(jq_ok '[.failed[]|select(.id=="ctest_bad")]|length==1 and (.[0].reason=="unavailable") and (.[0].exit_code==2)' shell/ut-play --status -j)"
report "--status still exits 0"    0 "$(rc shell/ut-play --status -j)"
report "--status still one line"   1 "$(shell/ut-play --status -j | wc -l | tr -d ' ')"
i=0
while [ "$i" -lt 10 ]; do mkfake "ctest_c$i" 2 "2026-01-01T00:00:0${i}Z"; i=$((i + 1)); done
shell/ut-play --status -j >/dev/null 2>&1
report "capped at 8 in the envelope" 8 "$(shell/ut-play --status -j | jq '.failed|length')"
report "capped at 8 on disk"         8 "$(ls "$SD/players/dead" 2>/dev/null | wc -l | tr -d ' ')"
report "newest kept"                 0 "$(jq_ok '.failed[0].id=="ctest_c9"' shell/ut-play --status -j)"
rm -f "$SD/players"/ctest_*.json "$SD"/mpv-ctest_*.log
rm -rf "$SD/players/dead"

echo "── version and the non-TTY refusal ────────────────────────────────"
report "one version, six entry points" 1 \
    "$(for c in ut-play yt-search yt-resolve bili-search bili-resolve uting; do shell/$c --version | awk '{print $NF}'; done | sort -u | wc -l | tr -d ' ')"
report "uting refuses a non-TTY" 1 "$(shell/uting </dev/null >/dev/null 2>&1; echo $?)"

echo
printf '%s: %d ok, %d failed, %d known drift\n' "$(basename "$0")" "$pass" "$fail" "$known"
if [ "$fail" -ne 0 ]; then
    printf 'regressions:\n%s' "$FAILED"
    exit 1
fi
exit 0
