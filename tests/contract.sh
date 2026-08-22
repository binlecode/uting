#!/usr/bin/env bash
# The CLI contract, asserted by RUNNING it. No rig: a command-line tool is tested by
# invoking it and reading its exit code and its stdout, which is all this file does.
#
# What it covers: the search envelope's shape, every documented rejection (a flag on the
# wrong verb, a bare query where a URL belongs, two actions at once, a selector with no
# action), the read-only --transcript verb both ways, the idle lifecycle, --version, the
# non-TTY refusal, and the failure taxonomy — 1 is usage, 2 is a tool that failed.
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
