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
# Portability: bash 3.2 (macOS system bash). No bash-4 idioms; see docs/ARCHITECTURE.md §28.
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
    # FAIL FAST on a hang, and ONLY on a hang. An ordinary mismatch keeps going — the point
    # of a suite is the whole list. But a check that hit the ceiling means the environment is
    # wedged (throttled, offline, a dead socket), and every live call after it will spend the
    # same five seconds proving the same thing.
    if [ "$3" = 124 ] && [ "$2" != 124 ]; then
        printf '  HUNG  %-34s exceeded %ss\n' "$1" "$UT_CHECK_TIMEOUT"
        printf '\ncontract.sh: aborted — a check wedged. %d checks ran before it.\n' "$((pass + fail))"
        exit 1
    fi
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

# ---- the upper bound on any ONE check -----------------------------------------------
# About twenty-five of the checks below make a LIVE call to YouTube or Bilibili (yt-dlp,
# curl), and a throttled or wedged one of those blocks FOREVER: nothing else in this file is
# a clock. macOS ships no `timeout` and the Homebrew coreutils one is not a dependency this
# suite may grow (CLAUDE.md), so the watchdog is written here out of builtins.
#
# It changes nothing about WHAT is invoked or asserted — every check still runs its own real
# command and reads its own real answer. It only refuses to wait forever for one.
#
# 5s: measured, yt-search 2.74s / yt-resolve 2.45s / bili-search 0.71s, so ~2x headroom.
# Anything past it is WEDGED, not slow, and a generous ceiling just turns a hung run into a
# long one — the exact failure this exists to prevent.
#
# The command runs in its OWN process group (set -m, the idiom ut-play's detach_play uses)
# and the GROUP is what gets killed: a check that shelled out to yt-dlp leaves that child
# holding the network otherwise, and the child is the part that hangs. The budget lives in
# its own process and the check BLOCKS in `wait` — polling instead cost 213ms on every check
# that finished in 2ms, because the first sleep is paid before the first liveness test can
# succeed.
UT_CHECK_TIMEOUT=${UT_CHECK_TIMEOUT:-5}
bounded() {
    local pid wd st
    set -m
    "$@" &
    pid=$!
    set +m
    # BOTH fds redirected, and it matters: a caller reads this function through
    # `out=$(bounded ...)`, and the watchdog would otherwise inherit that command
    # substitution's stdout PIPE. Killing the subshell does not kill the `sleep` under it, so
    # the orphan kept the pipe open and every captured check paid the full budget — 5s each,
    # turning a 114s suite into one that could not finish.
    { sleep "$UT_CHECK_TIMEOUT"; kill -TERM "-$pid" 2>/dev/null; } >/dev/null 2>&1 &
    wd=$!
    wait "$pid"
    st=$?
    # The watchdog exits the moment it fires, so finding it ALIVE is what proves it did not.
    if kill -0 "$wd" 2>/dev/null; then
        { kill "$wd"; wait "$wd"; } 2>/dev/null
    else
        { wait "$wd"; } 2>/dev/null
        st=124
    fi
    return $st
}

# Exit code of a command whose output we do not want.
rc() { bounded "$@" >/dev/null 2>&1; echo $?; }

# jq_ok <jq-filter> <command...> — does the command's stdout satisfy the filter?
# The output is captured FIRST and the filter applied to the variable, never piped straight
# from the command: `set -o pipefail` makes a pipeline carry the LEFT side's status, so
# `yt-resolve --transcript -j <no-captions> | jq -e …` reported jq's success as the command's
# exit 1. Both error-path checks below went red against correct behaviour that way.
jq_ok() {
    local filter=$1; shift
    local out st
    out=$(bounded "$@" 2>/dev/null)
    st=$?
    # A timeout must stay 124 all the way to report(). Letting jq answer for it turns a
    # wedged network call into an ordinary content mismatch — the one diagnosis that sends
    # the reader looking at the engine instead of at the link.
    [ "$st" = 124 ] && { echo 124; return; }
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
# to confuse a flag-shaped token with (AS-BUILT-contract.md §2).
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
# --info gets the same parity treatment: it is the third envelope both engines publish
# (AS-BUILT-contract.md §3), and nothing else here would notice a field renamed on one
# side. The ok/engine assertion is what keeps the key comparison from passing vacuously —
# two ERROR envelopes agree on their keys too.
YT_I=$(shell/yt-resolve --info -j -- "$MEDIA_ID" 2>/dev/null)
BILI_I=$(shell/bili-resolve --info -j -- "$BILI_ID" 2>/dev/null)
report "info -j is ok and named" 0 \
    "$(printf '%s' "$YT_I" | jq -e '.status=="ok" and .engine=="yt"' >/dev/null 2>&1; echo $?)"
report "info envelopes agree" \
    "$(printf '%s' "$YT_I" | jq -Sc 'keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_I" | jq -Sc 'keys' 2>/dev/null)"
report "--info -j is one line" 1 \
    "$(shell/yt-resolve --info -j -- "$MEDIA_ID" | wc -l | tr -d ' ')"

report "bili-search names its engine" 0 \
    "$(jq_ok '.status=="ok" and .engine=="bili"' shell/bili-search -j -n 2 -- 音乐)"
report "bili-search -j is one line" 1 \
    "$(shell/bili-search -j -n 2 -- 音乐 | wc -l | tr -d ' ')"
# The site sends duration as "MM:SS" with unbounded minutes ("222:28"), which every surface
# above would silently mis-sort and mis-render as a string. It is parsed in the engine, so
# the assertion is that what leaves the engine is a NUMBER — never the raw string.
#
# `null` is ALLOWED and is not a miss: §7/AS-BUILT-contract.md §3 make duration/duration_fmt null together when the
# row has no duration, and this endpoint does return such rows intermittently (observed: one
# null among five, on a result set the site swapped in between two identical requests). An
# earlier `all(type=="number")` here failed on exactly those runs and read as flaky — it was
# asserting against the contract rather than for it. What must hold: nothing is a string, and
# the page is not ALL nulls (which would mean the parser stopped working).
report "bili duration is seconds" 0 \
    "$(jq_ok '[.results[].duration]
               | length>0
               and all(type=="number" or type=="null")
               and any(type=="number")' shell/bili-search -j -n 5 -- 音乐)"
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
report "bili-search rejects -d" 1 "$(rc shell/bili-search -d -- 音乐)"
# One engine, one site. `yt-resolve` used to accept ANY http(s) URL and hand it to yt-dlp,
# which supports 1700+ sites — so a Bilibili URL resolved fine and came back labelled
# `engine:"yt"`. It WORKED, which is why it went unnoticed, and it made the one field whose
# job is routing a result back to its resolver into a field that lies.
#
# Engine-DISCOVERED, not hardcoded: the pair convention (`<name>-search` + `<name>-resolve`)
# is the one `uting` already builds its registry from, so a third engine is covered the day
# its pair lands rather than when someone remembers to add it here. And the claim is stated
# as an invariant over ALL engines, needing no table of who owns what — which is why it
# cannot drift from the engines themselves. Every host-gate function is duplicated per
# engine (`url_host` is byte-identical across the pair today), so a check that drove only
# one engine would be green while the other copy, and engine #3, said nothing.
ENGINES=""
for f in shell/*-resolve; do
    n=$(basename "$f"); n=${n%-resolve}
    [ -x "shell/$n-search" ] && ENGINES="$ENGINES $n"
done
NENG=$(echo "$ENGINES" | wc -w | tr -d ' ')
report "engine pairs discovered" 2 "$NENG"

# A search half resolves no format, so -S (a stream-format sort) is a value it cannot act
# on. Stated over EVERY discovered engine, not just the one that got it right: yt-search
# took the flag and forwarded it into a --flat-playlist dump where it changed nothing, so
# the two halves disagreed about what a search IS and the add-an-engine checklist copied
# the wrong one. Engine #3 is covered the day it lands.
_sdash=0
for n in $ENGINES; do
    [ "$(rc "shell/$n-search" -S abr -- q)" = 1 ] && _sdash=$((_sdash + 1))
done
report "every search half refuses -S" "$NENG" "$_sdash"

# refusals <url> — how many engines reject it as a USAGE error (1)? A rejected host dies
# before the dependency gate, so each of these costs ~20ms and no network.
refusals() {
    local u=$1 n r=0
    for n in $ENGINES; do
        [ "$(rc "shell/$n-resolve" -j -- "$u")" = 1 ] && r=$((r + 1))
    done
    echo $r
}

# A real URL is claimed by EXACTLY ONE engine: the other N-1 refuse it with 1 — usage, not
# extraction failure, because nothing was attempted and nothing is retryable.
report "only 1 engine claims a yt URL"   $((NENG - 1)) "$(refusals "https://www.youtube.com/watch?v=$MEDIA_ID")"
report "only 1 engine claims a bili URL" $((NENG - 1)) "$(refusals 'https://www.bilibili.com/video/BV1mL411E7Fb')"
# The ordering probe, and the one here that costs a network call: `url_host` strips userinfo
# BEFORE the port, so `user:pass@host` resolves to the host. Swap those two expansions — a
# plausible tidy-up — and this resolves to host `user`, is refused by every engine, and
# nothing else in this file notices.
report "userinfo stripped before port"   $((NENG - 1)) "$(refusals "https://user:pass@www.youtube.com/watch?v=$MEDIA_ID")"

# A confusable is refused by EVERY engine. These are the shapes `url_host`'s expansion ORDER
# decides, and the two plain URLs above exercise three of its eight lines:
#   evil<host>.com    an explicit host list, never a substring test
#   <host>@evil.com   the LAST `@` is the separator, the way browsers read it
#   https:///         an empty host must match nothing
#   <host>.           trailing dot refused — the safe direction, pinned so a change is deliberate
for u in 'https://evilyoutube.com/watch?v=x' 'https://evilbilibili.com/x' \
         'https://youtube.com@evil.com/' 'https://bilibili.com@evil.com/' \
         'https:///watch?v=x' 'https://youtube.com./watch?v=x'; do
    report "all refuse ${u#https://}" "$NENG" "$(refusals "$u")"
done
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
# --stop treats an empty set as idempotent success; --set-volume must NOT — there is no
# volume it could have set, so this is the did-not-take-effect class (4), and the envelope
# names the why so a caller can tell it from ambiguity (AS-BUILT-contract.md §3/§4).
report "idle --set-volume is 4"   4 "$(rc shell/ut-play --set-volume 50 -j)"
report "idle --set-volume says why" 0 "$(jq_ok '.status=="not_playing"' shell/ut-play --set-volume 50 -j)"
# Every socket verb answers the empty set the way --set-volume does — ONE taxonomy, not one
# per verb. Stated as a loop over the verbs so a sixth one is covered the day it lands
# instead of needing its own copied pair of lines.
for v in --pause --resume "--seek +30" "--seek-to 0"; do
    # shellcheck disable=SC2086  # $v carries a flag AND its value on purpose
    report "idle $v is 4"        4 "$(rc shell/ut-play $v -j)"
done
# The envelope text comes from ONE helper (require_live_target), so asserting it once per
# verb is raising a count, not covering a case — the exit codes above are what catch a verb
# wired to the wrong helper.
report "idle --pause says why"   0 "$(jq_ok '.status=="not_playing"' shell/ut-play --pause -j)"
# The 1-vs-4 split on the one verb that can fail both ways. A malformed value never reaches a
# player, so it is usage (1); a well-formed call with no player to receive it is 4. Getting
# these the same way round is what makes an agent retry a call it should have fixed instead.
report "--seek unsigned is 1"     1 "$(rc shell/ut-play --seek 30 -j)"
report "--seek non-numeric is 1"  1 "$(rc shell/ut-play --seek abc -j)"
report "--seek-to negative is 1"  1 "$(rc shell/ut-play --seek-to -5 -j)"
# --seek -15 is a VALUE, not an unknown flag: the parser must take $2 verbatim.
report "--seek accepts -15"       4 "$(rc shell/ut-play --seek -15 -j)"
# --id now names the playback verbs too, so it has to be ACCEPTED by one of them; the arms
# that reject it elsewhere are already covered by "ut-play selector alone" and
# "ut-play -d + action" above, which exercise the same case statement.
report "--id on --pause parses"   4 "$(rc shell/ut-play --pause --id nope -j)"


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
# like too (docs/ARCHITECTURE.md §9.2). These checks own the boundary that keeps the tombstone
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

echo "── the playlist store: durable state, one file, one lock ──────────"
# UT_STATE_DIR is exported, and that is the whole reason the knob exists: without it every
# check below would write into the user's real playlists. It points somewhere disposable
# for the rest of this file.
export UT_STATE_DIR
UT_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/uting-plstore.XXXXXX")
PL=shell/ut-playlist
ENV_JSON='{"status":"ok","engine":"yt","query":"q","count":2,"results":[{"id":"a1","title":"One","url":"https://www.youtube.com/watch?v=a1","channel":"c","duration":213,"duration_fmt":"00h:03m:33s","view_count":5,"live_status":"not_live"},{"id":"a2","title":"Two","url":"https://www.youtube.com/watch?v=a2","channel":"c","duration":null,"duration_fmt":null,"view_count":null,"live_status":"is_live"}]}'

report "empty store: ok, exit 0"      0 "$(jq_ok '.status=="ok" and .count==0 and .playlists==[]' $PL --ls -j)"
printf '%s' "$ENV_JSON" | $PL --add chill -j >/dev/null 2>&1
report "a search envelope tags engine" 0 "$(jq_ok '.count==2 and ([.items[].engine]|unique==["yt"])' $PL --show chill -j)"
# An ITEM carries no engine — the envelope does. An engine tag that survived the store is
# the only thing that makes a stored record a callable `ut-play --engine E -- URL`.
echo '[{"engine":"bili","id":"BV1","url":"https://www.bilibili.com/video/BV1","title":"三","duration":90}]' | $PL --add chill -j >/dev/null 2>&1
report "an array keeps its own engine"  0 "$(jq_ok '[.items[].engine]|unique==["bili","yt"]' $PL --show chill -j)"
report "--show is ONE line"             1 "$($PL --show chill -j | wc -l | tr -d ' ')"
report "duration_fmt derived on read"   0 "$(jq_ok '.items[0].duration_fmt=="00h:03m:33s" and (.items[1].duration_fmt==null)' $PL --show chill -j)"
# 4, not 1: the argv was well formed and the store had nothing to answer with — the same
# split ut-play makes when --set-volume finds no player. 1 stays for a malformed call.
report "--show missing: 4, not_found"   4 "$(rc $PL --show nope)"
report "…and says so in the envelope"   0 "$(jq_ok '.status=="error" and .reason=="not_found"' $PL --show nope -j)"
report "--rm out of range: 1"           1 "$(rc $PL --rm chill --index 9)"
report "--rm removes exactly one"       0 "$(jq_ok '.count==2' $PL --rm chill --index 1 -j)"
# Idempotent, like --stop on a player that already exited: the caller asked for an end state
# and the end state holds. `deleted` is the field that says which of the two happened.
report "--del missing: 0, deleted=false" 0 "$(jq_ok '.status=="ok" and .deleted==false' $PL --del ghost -j)"
$PL --rename chill mellow -j >/dev/null 2>&1
report "--rename moves the file"        0 "$(jq_ok '.playlists[0].name=="mellow" and .count==1' $PL --ls -j)"
printf '%s' "$ENV_JSON" | $PL --add other -j >/dev/null 2>&1
report "--rename onto a name: 4"        4 "$(rc $PL --rename other mellow)"
report "…with reason exists"            0 "$(jq_ok '.reason=="exists"' $PL --rename other mellow -j)"
# The store round trip: its own --show output is accepted by --add, which is what copying
# one list into another is.
$PL --show mellow -j | $PL --add copy -j >/dev/null 2>&1
report "a playlist envelope re-adds"    0 "$(jq_ok '.count==2' $PL --show copy -j)"
# An unreadable file on disk. Before this, jq's parse error escaped as exit 5 with no
# envelope at all under -j — the failure yt-search was fixed for, reintroduced in a second
# command. --show fails (the question was about that list); --ls still answers (the question
# was about the store, and one bad file must not hide the rest).
printf '%s' '{ not json' > "$UT_STATE_DIR/playlists/wrecked.json"
report "--show on a corrupt file: 4"    4 "$(rc $PL --show wrecked)"
report "…with reason corrupt"           0 "$(jq_ok '.status=="error" and .reason=="corrupt"' $PL --show wrecked -j)"
report "--ls survives a corrupt file"   0 "$(jq_ok '.status=="ok" and (.playlists|length)>0' $PL --ls -j)"
# `schema` is WRITTEN by every add; this is the check that makes writing it worth anything.
printf '%s' '{"schema":99,"name":"future","created_at":"x","updated_at":"x","count":0,"items":[]}' \
    > "$UT_STATE_DIR/playlists/future.json"
report "a newer schema is refused: 4"   4 "$(rc $PL --show future)"
rm -f "$UT_STATE_DIR/playlists/wrecked.json" "$UT_STATE_DIR/playlists/future.json"
report "a name with / is refused"       1 "$(rc $PL --del "a/b")"
report "…with reason invalid_name"      0 "$(jq_ok '.reason=="invalid_name"' $PL --del "a/b" -j)"
report "a selector with no verb: 1"     1 "$(rc $PL --show mellow --index 2)"
# …including on the one verb that takes no name: the check used to live inside the branch
# that does, so `--ls --index 3` exited 0 having silently ignored it.
report "…--ls too, not just the named" 1 "$(rc $PL --ls --index 3)"
report "two actions at once: 1"         1 "$(rc $PL --ls --show mellow)"
report "a playback flag: 1"             1 "$(rc $PL --status)"
report "a handle after --: 1"           1 "$(rc $PL -- "https://youtu.be/x")"
report "bad stdin: 1"                   1 "$(echo not-json | $PL --add mellow >/dev/null 2>&1; echo $?)"
# Captured first, never piped straight into jq: `set -o pipefail` makes a pipeline carry the
# LEFT side's status, so `$PL … -j | jq -e` reports the command's own exit 1 as jq's verdict
# and the check goes red against correct behaviour. Same lesson as jq_ok, which cannot be
# used here because these commands read stdin.
PL_OUT=$(echo not-json | $PL --add mellow -j 2>/dev/null)
report "…and an error envelope under -j" 0 "$(printf '%s' "$PL_OUT" | jq -e '.status=="error" and .reason=="invalid_input"' >/dev/null 2>&1; echo $?)"

# THE LOCK, driven rather than asserted from prose. Without it these eight writers are eight
# read-modify-write races on one file and the list ends up with ONE item — measured, by
# stubbing lock_playlist out and re-running this exact loop.
i=0
while [ "$i" -lt 8 ]; do
    printf '[{"engine":"yt","url":"https://x/%s"}]' "$i" | $PL --add race -j >/dev/null 2>&1 &
    i=$((i + 1))
done
wait
report "8 concurrent adds keep all 8"   0 "$(jq_ok '.count==8' $PL --show race -j)"
# A held lock is did-not-take-effect (4), never a usage error and never a silent unlocked
# write: this store is durable, so proceeding without the lock could drop what the user just
# added. Costs the 5s spin once.
mkdir -p "$UT_STATE_DIR/playlists/.lock-race"
report "a held lock: 4, not 1"          4 "$(printf '[{"engine":"yt","url":"https://x/z"}]' | $PL --add race >/dev/null 2>&1; echo $?)"
PL_OUT=$(printf '[{"engine":"yt","url":"https://x/z"}]' | $PL --add race -j 2>/dev/null)
report "…with reason locked"            0 "$(printf '%s' "$PL_OUT" | jq -e '.reason=="locked"' >/dev/null 2>&1; echo $?)"
# A lock left by a SIGKILLed writer must not wedge a playlist forever.
touch -t 202001010000 "$UT_STATE_DIR/playlists/.lock-race"
report "a stale lock is stolen"         0 "$(printf '[{"engine":"yt","url":"https://x/z"}]' | $PL --add race -j >/dev/null 2>&1; echo $?)"
rm -rf "$UT_STATE_DIR"
unset UT_STATE_DIR

echo "── the TUI boots, paints, survives a resize, and leaves on q ──────"
# NOT a renderer assertion: no cell arithmetic, no width table, no captured frame compared
# against an expected picture. The claim is only that the interactive surface starts on a
# real tty, paints a list, stays up across two resizes, and exits 0 on `q`.
#
# It earns its place because every other check in this file is BLIND to the TUI: they all
# reach it through a non-tty, where it correctly refuses to run. A `uting` that aborts on
# boot or wedges on exit would leave this whole suite green.
#
# tmux is the tty. Wait on the ready marker, never on a sleep — a captured spinner frame is
# a picture of the loading state, and a blind sleep here has produced a wrong result before.
if ! command -v tmux >/dev/null 2>&1; then
    echo "  skip  (needs tmux for a real tty)"
else
    TS="ctest-tui-$$"
    tmux kill-session -t "$TS" 2>/dev/null
    # The session outlives the TUI on purpose: what the tty looks like AFTER `q` is a claim
    # of its own, and the pane is the only place to read it from once uting has gone.
    TUI_CMD="cd '$PWD' && env YT_SYNC=0 shell/uting 'lofi hip hop'"
    TUI_CMD="$TUI_CMD"'; printf "RC=%s\n" $?'
    TUI_CMD="$TUI_CMD"'; stty -a </dev/tty | tr " " "\n" | grep -E "^-?(echo|icanon)$" | tr "\n" " " | sed "s/^/FLAGS= /"; echo; sleep 20'
    tmux new-session -d -s "$TS" -x 100 -y 30 "$TUI_CMD"
    TUI_TTY=$(tmux display-message -p -t "$TS" '#{pane_tty}' 2>/dev/null)
    booted=0; i=0; getpass=0
    while [ $i -lt 80 ]; do
        # Sampled from inside this loop rather than in a phase of its own: waiting for the
        # first frame IS the fetch, the one stretch of the session where no `read` is running
        # and the tty carries whatever the app left on it.
        #
        # `-echo` with ICANON still SET is the termios signature of getpass(), and terminals
        # poll the pty for exactly that pair: Ghostty flips macOS Secure Input on it,
        # iTerm2 draws a padlock at the cursor — which the fetch spinner parks on its own
        # glyph. Two greps, not a case glob: `-echo` is a prefix of `-echoe`/`-echok`.
        if [ -n "$TUI_TTY" ]; then
            flags=$(stty -f "$TUI_TTY" -a 2>/dev/null | tr ' ' '\n')
            [ "$(printf '%s\n' "$flags" | grep -c '^-echo$')" = 1 ] &&
                [ "$(printf '%s\n' "$flags" | grep -c '^icanon$')" = 1 ] && getpass=1
        fi
        tmux capture-pane -t "$TS" -p 2>/dev/null | grep -q 'results=' && { booted=1; break; }
        sleep 0.3; i=$((i + 1))
    done
    report "TUI boots and paints a list" 1 "$booted"
    report "never signals a password prompt" 0 "$getpass"

    # Reflow is width-conditional, so the two geometries that change layout are the ones
    # worth walking. The assertion is survival, not shape: still up, still showing a list.
    alive=1
    for geom in "62 20" "26 24"; do
        set -- $geom
        tmux resize-window -t "$TS" -x "$1" -y "$2" 2>/dev/null
        j=0; seen=0
        while [ $j -lt 20 ]; do
            tmux capture-pane -t "$TS" -p 2>/dev/null | grep -q 'results=' && { seen=1; break; }
            sleep 0.25; j=$((j + 1))
        done
        [ "$seen" = 1 ] || alive=0
    done
    report "survives 62x20 and 26x24" 1 "$alive"

    # `q` used to be asserted by waiting for tmux to tear the session down, which proves the
    # pty is not wedged but says nothing about the status or about what was handed back. The
    # pane now outlives the TUI, so both come out of the same exit.
    tmux send-keys -t "$TS" q
    left=0; i=0
    while [ $i -lt 40 ]; do
        tmux capture-pane -t "$TS" -p -J 2>/dev/null | grep -q 'RC=0' && { left=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "quits on q with 0" 1 "$left"
    restored=0
    tui_flags=" $(tmux capture-pane -t "$TS" -p -J 2>/dev/null | grep -o 'FLAGS=.*' | head -1) "
    case "$tui_flags" in *" echo "*) case "$tui_flags" in *" icanon "*) restored=1 ;; esac ;; esac
    report "hands the tty back on exit" 1 "$restored"
    tmux kill-session -t "$TS" 2>/dev/null
fi

echo "── version and the non-TTY refusal ────────────────────────────────"
# Stated over every entry point the checkout HAS, not over a list of six names: a hardcoded
# list is a check that silently stops covering the thing it was written for the moment a
# seventh command lands. Anything in shell/ with a shebang is an entry point.
ENTRY_POINTS=""
for f in shell/*; do
    [ -f "$f" ] || continue
    head -n 1 "$f" | grep -q '^#!' || continue      # VERSION is data, not a command
    ENTRY_POINTS="$ENTRY_POINTS $f"
done
report "at least seven entry points" 1 \
    "$(set -- $ENTRY_POINTS; [ $# -ge 7 ] && echo 1 || echo 0)"
report "one version, every entry point" 1 \
    "$(for c in $ENTRY_POINTS; do "$c" --version | awk '{print $NF}'; done | sort -u | wc -l | tr -d ' ')"
report "uting refuses a non-TTY" 1 "$(shell/uting </dev/null >/dev/null 2>&1; echo $?)"

echo
printf '%s: %d ok, %d failed, %d known drift\n' "$(basename "$0")" "$pass" "$fail" "$known"
if [ "$fail" -ne 0 ]; then
    printf 'regressions:\n%s' "$FAILED"
    exit 1
fi
exit 0
