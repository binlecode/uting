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
# Cost, measured 2026-08-29 and broken down because a number at the door is what a reader
# decides on: ~83s in full, of which the live half is ~68s (roughly 21 engine round trips) and
# the tmux section is ~16s of that — it was 4s until the write-back checks landed, and the 12
# is two re-fetches its own keys ask for. `--offline` stops before the first of them: ~15s,
# 168 of the 231 checks, no packet sent. That 15 is dominated by one deliberate 5.5s lock
# spin — a FRESH held lock has to be waited out, that being what the spin is for; the
# stale-lock steal beside it costs 0.1s
# because staleness is tested before the spin, not after (shell/ut-playlist:lock_playlist).
#
# Three of those numbers were wrong here for a while — the file claimed ~80s, "one 5s lock
# spin" where three were paid, and "~25s of tmux" for 4s of it — which is its own lesson: a
# cost comment is a claim, and this file's rule is that a claim gets executed, not read.
# It starts no process it did not have to and talks to no peer — every live claim is
# tests/playback.sh's.
# The TUI section is the near-exception and is held to the same line: the process there is a
# real `uting` on a real tty, it is CHECKED to leave no player behind, and the EXIT trap reaps
# one if it ever does.
#
# Usage:  tests/contract.sh            all checks
#         tests/contract.sh --offline  the hermetic half only — every gate, both stores, the
#                                      lifecycle and the death record, and no packet sent
# Exit:   0 = every check held, 1 = at least one regression

set -uo pipefail
cd "$(cd -P "$(dirname "$0")/.." && pwd -P)" || exit 1

# --offline exists because CLAUDE.md asks for this file on ANY change at all, including a
# comment fix, and a gate that cannot run without YouTube is a gate people learn to skip. It
# is a PREFIX of the same run, never a different one: the hermetic checks are the same
# checks, in the same order, and the flag only stops before the first live call. What it
# gives up is stated where it stops, so nobody mistakes a green --offline for a green suite.
OFFLINE=0
while [ $# -gt 0 ]; do
    case "$1" in
    --offline) OFFLINE=1; shift ;;
    -h | --help) sed -n '/^# Usage:/,/^# Exit:/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "contract.sh: unknown argument '$1' (try --help)" >&2; exit 1 ;;
    esac
done

# ---- the player's state dir, pointed somewhere disposable ---------------------------
# THE ARGUMENT FOR THIS LIVES HERE, and the other two files under tests/ point at it rather
# than restating it (docs/AS-BUILT-verification.md §27 is the doc-level home of the same fact).
#
# `ut-play` derives its state dir from TMPDIR ("${TMPDIR:-/tmp}/uting-$(id -u)", shell/ut-play)
# and takes no override of its own. Left at the user's real TMPDIR, this file --stop --all's a
# player they are listening to, writes its tombstone fixtures into their real players/, and
# rm -rf's their real failure record — three side effects on live user state, in a suite whose
# instruction is "run it before every commit".
#
# Redirecting TMPDIR is what makes that instruction safe. It changes nothing about WHAT is
# invoked or asserted: the player is the real one and its state is really written, just not on
# top of the user's. The playlist store already had this in UT_STATE_DIR; the half that kills
# processes is the half that needed it more.
UT_TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/uting-contract.XXXXXX") || exit 1
export TMPDIR="$UT_TEST_TMP"
STATE_DIR="$TMPDIR/uting-$(id -u)"

# ---- the config file, pointed somewhere disposable ----------------------------------
# The same argument as TMPDIR above, one layer out. Every command in the suite now reads
# ${XDG_CONFIG_HOME:-~/.config}/uting/config, so without this line a developer whose real
# config sets UT_MAX_SEARCH_RESULTS or UT_SORT_FIELD would see this file go red on their
# machine and green on everyone else's — the worst failure a suite can have, because the
# red is not in the subject. It points at a real, EMPTY file rather than a missing path so
# the loader's read path is the one exercised for the rest of the run; the checks that
# prove the loader actually loads something write their own file and set UT_CONFIG
# themselves.
export UT_CONFIG="$UT_TEST_TMP/config"
: > "$UT_CONFIG"

# ---- …and the real one, WATCHED --------------------------------------------------------
# The export above redirects every command this shell runs. It does not reach a tmux pane —
# a new session inherits the tmux SERVER's environment, not this shell's, which is why the
# TUI section passes its own knobs explicitly — and it does not reach whatever a future check
# forks in a way nobody predicted here. That gap used to be harmless because nothing in the
# suite WROTE a config; uting now writes six preference keys back to the user's file, so an
# unisolated caller does not merely read a developer's config, it edits it, and the value it
# leaves is one they never chose.
#
# Two fingerprints around the whole run catch ANY such caller, including one added long after
# this line was written — which is exactly what three call sites each remembering to export
# cannot do. cksum rather than a timestamp: it is POSIX (macOS `stat` and GNU `stat` do not
# share a format string), and the claim is that the file's CONTENT is the one the user left.
REAL_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/uting/config"
cfg_fingerprint() { cksum < "$REAL_CFG" 2>/dev/null || echo absent; }
REAL_CFG_SUM=$(cfg_fingerprint)
# Called before each summary, so both exits make the claim. Absent on both sides is a skip and
# not a green: a machine with no config to damage proves nothing about one that has it. Absent
# then PRESENT is a fail, which is the shape a leaked write takes on that same machine.
report_real_config() {
    if [ "$REAL_CFG_SUM" = absent ] && [ "$(cfg_fingerprint)" = absent ]; then
        echo "  skip  (no config at $REAL_CFG to watch)"
        return 0
    fi
    report "your own config is untouched" "$REAL_CFG_SUM" "$(cfg_fingerprint)"
}

# ---- …and the real STATE DIR, watched the same way ------------------------------------
# The config file got this guard when uting learned to write one. The playlist store and the
# listening log have been writable by every check in this file since long before that, and
# they had no guard at all — the discipline was three sections each remembering to point
# UT_STATE_DIR somewhere disposable, which is exactly the kind of discipline that holds until
# it doesn't. It didn't: a section added after the one that ends with `unset UT_STATE_DIR`
# assigned the variable without exporting it, and every ut-playlist call in it went to the
# user's real store and left a playlist there.
#
# So the same two fingerprints the config gets, around the same run, over the whole state
# tree. `ls -R` piped through cksum rather than the files' contents: what must not change is
# WHICH lists and logs exist, and a real listening session running in another window will
# legitimately grow today's .jsonl while this file runs. A name appearing or vanishing is the
# shape a leak takes, and it is the shape this catches.
REAL_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/uting"
state_fingerprint() { ls -R "$REAL_STATE" 2>/dev/null | cksum || echo absent; }
REAL_STATE_SUM=$(state_fingerprint)
report_real_state() {
    if [ ! -d "$REAL_STATE" ]; then
        echo "  skip  (no state dir at $REAL_STATE to watch)"
        return 0
    fi
    report "your own store is untouched" "$REAL_STATE_SUM" "$(state_fingerprint)"
}

# The reap comes FIRST and the directory second — the order playback.sh's cleanup already
# uses, and for a reason this file learned the hard way. Nothing here presses Enter, but the
# TUI section runs a real `uting`, and on 2026-08-25 a run whose `q` check came back red left
# an `ut-play --engine yt -f audio` child and its mpv behind. With `rm -rf` as the whole of
# the cleanup, the player's RECORD went with the directory: the process was orphaned to PID 1
# and `--stop --all` could no longer reach it — a suite that "does not touch your state" had
# left audio running that nothing but `kill` could stop.
#
# The orphan report is scoped to this run's own socket dir, for the reason playback.sh scopes
# its own: a bare `mpv .*--input-ipc-server` counts the user's players too. It is a report and
# not a check because the CHECK for it is in the TUI section, where it can name the cause.
cleanup() {
    shell/ut-play --stop --all -j >/dev/null 2>&1
    if pgrep -f "mpv .*--input-ipc-server=$STATE_DIR" >/dev/null 2>&1; then
        echo "contract.sh: ORPHAN mpv still running after --stop --all:" >&2
        pgrep -fl "mpv .*--input-ipc-server=$STATE_DIR" >&2
    fi
    rm -rf "$UT_TEST_TMP"
    return 0
}
# INT/TERM exit rather than run the cleanup and carry on: the reap must not happen with the
# rest of the file still to run. Same two lines as drive.sh, and the EXIT trap does the work.
trap cleanup EXIT
trap 'exit 130' INT TERM

pass=0; fail=0
FAILED=""

# report <name> <want> <got>   — the only bookkeeping in this file.
report() {
    if [ "$2" = "$3" ]; then
        pass=$((pass + 1))
        printf '  ok    %-34s %s\n' "$1" "$3"
    else
        fail=$((fail + 1))
        FAILED="${FAILED}    ${1}: want ${2}, got ${3}"$'\n'
        printf '  FAIL  %-34s want %s, got %s\n' "$1" "$2" "$3"
    fi
}

# Four one-liners, and deliberately nothing else. Each runs a real entry point the way a
# caller does and hands back one value for report() to compare.
#
# There is no watchdog: a wedged network call hangs this file until you interrupt it. That is
# the accepted cost of having no orchestration to get wrong — the hand-rolled timeout that
# used to live here inferred "did it fire?" from a background process's liveness and was
# wrong in both directions (a command that succeeded at the boundary aborted the whole run;
# a real timeout was reported as a content mismatch).

# summary                        — the tally, and the exit status the whole file is. A
# function because --offline leaves early and the two exits must be the same words and the
# same status; a second copy of five lines is how the two of them would drift apart.
summary() {
    echo
    printf '%s: %d ok, %d failed\n' "$(basename "$0")" "$pass" "$fail"
    if [ "$fail" -ne 0 ]; then
        printf 'regressions:\n%s' "$FAILED"
        exit 1
    fi
    exit 0
}

# rc <command...>                 — its exit code, output discarded.
rc() { "$@" >/dev/null 2>&1; echo $?; }

# rc_in <payload> <command...>    — the same, for a verb that READS STDIN. `rc` cannot serve
# those: the payload has to arrive on the command's own stdin, and for these verbs an empty
# stdin is a DIFFERENT error with the SAME exit code — a check that would pass for the wrong
# reason. Measured, not reasoned: "idle --enqueue is 4" once came back 1 this way.
rc_in() { local payload=$1; shift; printf '%s' "$payload" | "$@" >/dev/null 2>&1; echo $?; }

# jqv <jq-filter> <json>          — does an envelope already in hand satisfy the filter?
jqv() { printf '%s' "$2" | jq -e "$1" >/dev/null 2>&1; echo $?; }

# jq_ok <jq-filter> <command...>  — run it, then filter what it printed. The output is
# captured FIRST and never piped straight from the command: `set -o pipefail` makes a
# pipeline carry the LEFT side's status, so `yt-resolve … | jq -e …` reports the command's
# own exit as jq's verdict. Both error-path checks below went red against correct behaviour
# that way.
jq_ok() { local f=$1; shift; local o; o=$("$@" 2>/dev/null); jqv "$f" "$o"; }

# jq_in <jq-filter> <payload> <command...>  — jq_ok for a verb that reads STDIN. Same
# capture-first discipline and the same reason, so the reason is stated once, above.
jq_in() { local f=$1 p=$2; shift 2; jqv "$f" "$(printf '%s' "$p" | "$@" 2>/dev/null)"; }

# lines <json>                    — 1 for a single-line envelope.
lines() { printf '%s\n' "$1" | wc -l | tr -d ' '; }

# err_has <pattern> <command...>  — does what it printed on STDERR match? 0 yes, 1 no.
# Captured FIRST, never piped straight from the command, and for a sharper version of
# jq_ok's reason: every command asked this question is a REFUSAL, so it exits non-zero BY
# CONSTRUCTION. Under `set -o pipefail` the pipeline then carries the refusal's status and
# the grep verdict is thrown away — which is not a hypothetical, it is how the two
# capability checks below first read GREEN against an engine that had neither verb.
err_has() {
    local pat=$1
    shift
    local e
    e=$("$@" 2>&1 >/dev/null)
    printf '%s' "$e" | grep -qi -- "$pat" && echo 0 || echo 1
}

# ---- the offline half, FIRST -------------------------------------------------------
# Everything below this line to the live-fixture preamble runs without a network: flag gates,
# the idle lifecycle, the death-record fixtures, the two halves of the user-level store,
# --version, and the host allowlist. It used to sit AFTER ~15 live engine round trips, so the
# most common regression of all — a gate or an envelope broken by the edit you are about to
# commit — cost 80 seconds to see. Measured 2026-08-26: the gates are red at 1s, the idle
# lifecycle at 1s, the death record at 2s, and the whole offline half is done at 14s with no
# network call made. 5.5s of that is the playlist store's deliberate spin against a live
# holder, so a gate regression is still seen in about two seconds.
#
# It is also a HALF you can run on its own, which is the point of --offline: the boundary was
# already load-bearing, and a boundary nobody can stop at is a boundary only the author uses.
#
# THE ORDER IS PART OF THE FILE, not an accident of how it grew:
#   · offline first, so a broken gate is red before anything is fetched;
#   · the death-record fixtures ahead of the TUI section (stated again at that section, where
#     the mechanism is) — the pane's `uting` polls --status once a second and every lifecycle
#     verb reaps, so a fixture created after the pane is up can be deleted before the
#     assertion that reads it;
#   · the TUI section LAST, for the same reason from the other side.
# Moving a section is therefore a deliberate act. Nothing here reads a live fixture — that is
# what made the move a permutation rather than a rewrite, and it is what keeps it one.

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

# ── the queue verbs, idle. They address a player exactly as the socket verbs do (same
# require_live_target, same 4), but they reach its queue FILE rather than mpv — so they are
# checked here rather than folded into the loop above, and they must answer without nc.
Q1='[{"engine":"yt","url":"https://www.youtube.com/watch?v=jNQXAC9IVRw"}]'
report "idle --next is 4"        4 "$(rc shell/ut-play --next -j)"
report "idle --next says why"    0 "$(jq_ok '.status=="not_playing"' shell/ut-play --next -j)"
report "idle --enqueue is 4"     4 "$(rc_in "$Q1" shell/ut-play --enqueue - -j)"
# The one place a repeated envelope assertion is NOT raising a count: --enqueue can exit 4
# for two different reasons (no such player, or a queue it could not write), and only the
# envelope says which. Proved by making it skip require_live_target — the exit code stayed 4
# and this line is what went red.
report "idle --enqueue says why" 0 "$(jq_in '.status=="not_playing"' "$Q1" shell/ut-play --enqueue - -j)"
report "--id on --next parses"   4 "$(rc shell/ut-play --next --id nope -j)"

# The 1-vs-4 split again, on the verbs that take a PAYLOAD: a queue this process could not
# parse never reaches a player, so it is usage (1) — and it is refused in the PARENT, which
# is the whole reason stdin is read here and not in the detached child, where a die would
# only reach a log. Driven through --enqueue rather than --queue on purpose: a --queue that
# got past its gate would LAUNCH A PLAYER, and this file starts none. The pairing with
# "idle --enqueue is 4" above is what gives each of these teeth — 1 where the payload is
# wrong, 4 where only the player is missing.
report "bad JSON is 1"           1 "$(rc_in 'not json' shell/ut-play --enqueue -)"
report "an empty queue is 1"     1 "$(rc_in '[]' shell/ut-play --enqueue -)"
report "a url with a space is 1" 1 "$(rc_in '[{"engine":"yt","url":"a b"}]' shell/ut-play --enqueue -)"
report "an empty url is 1"       1 "$(rc_in '[{"engine":"yt","url":""}]' shell/ut-play --enqueue -)"
report "a bad engine name is 1"  1 "$(rc_in '[{"engine":"../evil","url":"x"}]' shell/ut-play --enqueue -)"
# The three shapes the verb takes, each proved by the SAME rejection: a payload that parses
# reaches the player check (4), one that does not is usage (1). A search envelope is accepted
# because a search result does not carry `engine` — that field is on the envelope, so only
# taking the whole thing can label an item with its source (AS-BUILT-contract.md §3).
report "a --show envelope parses" 4 "$(rc_in '{"status":"playlist","items":[{"engine":"yt","url":"x"}]}' shell/ut-play --enqueue - -j)"
report "a search envelope parses" 4 "$(rc_in '{"status":"ok","engine":"yt","results":[{"url":"x"}]}' shell/ut-play --enqueue - -j)"
report "a shapeless object is 1"  1 "$(rc_in '{"status":"ok"}' shell/ut-play --enqueue -)"
# --queue is a LAUNCH modifier: it needs -d, and it takes its handles from stdin ONLY. Each
# arm names what to do instead rather than saying "invalid combination".
report "--queue needs -d"        1 "$(rc_in "$Q1" shell/ut-play --queue -)"
report "--queue rejects a handle" 1 "$(rc_in "$Q1" shell/ut-play -d --queue - -- URL)"
report "--enqueue rejects a handle" 1 "$(rc_in "$Q1" shell/ut-play --enqueue - -- URL)"
report "--queue rejects an action" 1 "$(rc_in "$Q1" shell/ut-play -d --queue - --status)"

# A detached player that dies on its own is the one lifecycle path the caller does not
# drive, and it used to be silent: --status went empty, which is what a NORMAL finish looks
# like too (docs/AS-BUILT-player.md §9.2). These checks own the boundary that keeps the tombstone
# list an error record rather than the listening history ARCHITECTURE.md §1 rules out — a normal
# finish must leave nothing, a log with no epitaph must not be read as a death, and the list
# must stay bounded. The input is a state file + log written by hand — a FIXTURE, which is
# the only thing this suite is allowed to author: it is data the real reaper really reads, not
# a stand-in that runs in place of a component. Nothing here simulates a player; a record whose
# pid is gone IS a dead player, which is the whole condition under test. The code (reap,
# classify, prune, envelope) is the real one, driven through the real verb. Like --stop --all
# above, this writes in the private TMPDIR this file exports at the top, never in the user's.
#
# ORDER IS LOAD-BEARING: this section must stay AHEAD of the TUI section. The pane's `uting`
# polls --status once a second, every lifecycle verb reaps, and a reaped fixture is a fixture
# deleted before the assertion that reads it — the failure docs/AS-BUILT-verification.md §27 already
# has on record. Today the order holds by accident of layout; this comment is what makes it
# hold on purpose.
echo "── the death record: failures only, bounded, never inferred ───────"
SD="${TMPDIR:-/tmp}/uting-$(id -u)"
dead_record() { # <id> <rc|""> [ended_at]   — a dead player, with or without an epitaph
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
dead_record ctest_ok 0
report "normal finish: no tombstone" 0 "$(jq_ok '.failed==[]' shell/ut-play --status -j)"
dead_record ctest_mute ""
report "no epitaph: no tombstone"  0 "$(jq_ok '.failed==[]' shell/ut-play --status -j)"
dead_record ctest_bad 2
report "death is reported once"    0 "$(jq_ok '[.failed[]|select(.id=="ctest_bad")]|length==1 and (.[0].reason=="unavailable") and (.[0].exit_code==2)' shell/ut-play --status -j)"
report "--status still exits 0"    0 "$(rc shell/ut-play --status -j)"
report "--status still one line"   1 "$(shell/ut-play --status -j | wc -l | tr -d ' ')"
i=0
while [ "$i" -lt 10 ]; do dead_record "ctest_c$i" 2 "2026-01-01T00:00:0${i}Z"; i=$((i + 1)); done
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
report "…and an error envelope under -j" 0 "$(jq_in '.status=="error" and .reason=="invalid_input"' not-json $PL --add mellow -j)"

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
# added.
#
# ONE run, both claims — the exit code and the reason come off the same invocation, the way
# the dead-id pair further down already does it. It used to be two, which meant sitting
# through the 5s spin TWICE to learn two facts about one failure; what the second run added
# was that the code is 4 in prose mode as well as under -j, and the taxonomy section asserts
# that mode-parity on a failure of its own for 40ms.
mkdir -p "$UT_STATE_DIR/playlists/.lock-race"
LOCKED=$(printf '[{"engine":"yt","url":"https://x/z"}]' | $PL --add race -j 2>/dev/null); LOCKED_ST=$?
report "a held lock: 4, not 1"          4 "$LOCKED_ST"
report "…with reason locked"            0 "$(jqv '.reason=="locked"' "$LOCKED")"
# A lock left by a SIGKILLed writer must not wedge a playlist forever — and must not make the
# next caller WAIT for it either: staleness is tested on the first failed mkdir, so this is
# the fast path, not a second 5s spin (shell/ut-playlist:lock_playlist). Measured before the
# reorder: 5.46s. After: 0.10s.
touch -t 202001010000 "$UT_STATE_DIR/playlists/.lock-race"
report "a stale lock is stolen"         0 "$(printf '[{"engine":"yt","url":"https://x/z"}]' | $PL --add race -j >/dev/null 2>&1; echo $?)"
rm -rf "$UT_STATE_DIR"

echo "── the listening log: append-only, one line, bounded ──────────────"
# The eighth entry point, and the second half of the user-level store. Same disposable
# UT_STATE_DIR discipline as the playlist section above, and for a sharper reason: without it
# these checks append to the log of what the user actually listened to, and --clear deletes
# from it.
UT_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/uting-histore.XXXXXX")
HL=shell/ut-history
# A listening is the ITEM record plus the four fields a listening has and a list entry does
# not. `channel` is in here on purpose: it is the field a caller would carry in by accident,
# and the row on disk must not have it.
H_ROW='{"engine":"yt","id":"a1","url":"https://www.youtube.com/watch?v=a1","title":"One","duration":213,"channel":"c","played_at":"2026-06-02T10:00:00Z","ended_at":"2026-06-02T10:01:37Z","seconds":97,"reason":null}'

report "empty log: ok, count 0"        0 "$(jq_ok '.status=="ok" and .count==0 and .items==[]' $HL --ls -j)"
printf '%s' "$H_ROW" | $HL --record - -j >/dev/null 2>&1
report "--record then --ls reads it"   0 "$(jq_ok '.count==1 and .items[0].url=="https://www.youtube.com/watch?v=a1"' $HL --ls -j)"
report "--ls is ONE line"              1 "$($HL --ls -j | wc -l | tr -d ' ')"
# DERIVED on read, never stored — the same rule --show follows for duration_fmt. A stored
# copy would be a second truth about the same number.
report "both _fmt derived on read"     0 "$(jq_ok '.items[0].duration_fmt=="00h:03m:33s" and .items[0].seconds_fmt=="00h:01m:37s"' $HL --ls -j)"
# The row is CONSTRUCTED field by field, so a key the caller happened to carry cannot land on
# disk: `channel` expires into a lie, and this is the check that keeps it out.
report "an unknown key never lands"    0 "$(jq_ok '(.items[0]|has("channel"))==false' $HL --ls -j)"
# Newest first, sorted by played_at rather than trusted in file order — a record can arrive
# back-dated (a track that started last month and ended this one).
printf '%s' "$H_ROW" | jq -c '.played_at="2026-08-02T10:00:00Z" | .id="a2" | .url="https://www.youtube.com/watch?v=a2"' | $HL --record - -j >/dev/null 2>&1
report "--ls is newest first"          0 "$(jq_ok '.items[0].id=="a2" and .items[1].id=="a1"' $HL --ls -j)"
report "-n bounds what is printed"     0 "$(jq_ok '.count==1 and .items[0].id=="a2"' $HL --ls -n 1 -j)"
# THE CLAIM THE ROW SHAPE EXISTS FOR: a listening is a CALL, so --ls drops into --add with no
# field mapping in between. If the two envelopes ever drift, this is what says so.
$HL --ls -j | shell/ut-playlist --add rediscover -j >/dev/null 2>&1
report "--ls feeds ut-playlist --add"  0 "$(jq_ok '.count==2 and ([.items[].engine]|unique==["yt"])' shell/ut-playlist --show rediscover -j)"

# THE 4096-BYTE PREMISE. The lock-free append is only atomic while one line fits under
# PIPE_BUF, so the title is truncated to 200 bytes and the whole row is measured after. A
# check that only ever sees ordinary input is not a check of a premise.
H_BIG=$(printf '%s' "$H_ROW" | jq -c --arg t "$(printf 'x%.0s' $(seq 1 8000))" '.title=$t | .id="big" | .url="https://www.youtube.com/watch?v=big" | .played_at="2026-08-03T10:00:00Z"')
H_OUT=$(printf '%s' "$H_BIG" | $HL --record - -j 2>/dev/null)
report "an 8KB title is recorded"      0 "$(jqv '.status=="ok" and .recorded==1' "$H_OUT")"
report "…and reports truncated"        0 "$(jqv '.truncated==true' "$H_OUT")"
report "…and --ls still parses it"     0 "$(jq_ok '.count==3 and ([.items[]|select(.id=="big")]|length)==1' $HL --ls -j)"
# Bytes, not characters: the budget is PIPE_BUF and awk counts what the kernel writes.
report "…and no line reaches 4096B"    0 "$(LC_ALL=C awk 'length($0) >= 4096 { bad = 1 } END { print bad + 0 }' "$UT_STATE_DIR"/history/*.jsonl)"

# One unreadable line must not hide the rest — the rule --ls already applies to a corrupt
# playlist file, on the format where a hand edit is likeliest.
printf '%s\n' '{ not json' >> "$UT_STATE_DIR/history/2026-08.jsonl"
report "a broken line hides nothing"   0 "$(jq_ok '.status=="ok" and .count==3' $HL --ls -j)"
# `schema` is written by every record; this is what makes writing it worth anything.
printf '%s\n' '{"schema":99,"engine":"yt","url":"https://x/9","played_at":"2026-08-09T10:00:00Z"}' >> "$UT_STATE_DIR/history/2026-08.jsonl"
report "a newer schema is skipped"     0 "$(jq_ok '.count==3' $HL --ls -j)"

# --clear is mostly an `rm`: shards older than the boundary go whole. Everything above lands
# in the 2026-08 shard except the very first record, so a cut at that month must take exactly
# one row and leave the August shard — junk lines and all — untouched.
report "--clear --before cuts by month" 0 "$(jq_ok '.status=="ok" and .removed==1' $HL --clear --before 2026-08 -j)"
report "…and left the rest alone"      0 "$(jq_ok '.count==2 and ([.items[].id]|sort==["a2","big"])' $HL --ls -j)"
report "--clear empties the log"       0 "$(jq_ok '.status=="ok"' $HL --clear -j)"
# Idempotent, like --stop on a player that already exited: the caller asked for an end state.
report "--clear on an empty log: 0"    0 "$(jq_ok '.status=="ok" and .removed==0' $HL --clear -j)"

# The gate. Same shape as ut-playlist's, and every arm names the command that owns the flag
# rather than answering "unknown flag" to a caller who reached for a sibling.
report "two actions at once: 1"        1 "$(rc $HL --ls --clear)"
report "no action at all: 1"           1 "$(rc $HL -n 5)"
report "-n on --clear: 1"              1 "$(rc $HL --clear -n 5)"
report "--before on --ls: 1"           1 "$(rc $HL --ls --before 2026-01)"
report "a playback flag: 1"            1 "$(rc $HL --status)"
report "a playlist verb: 1"            1 "$(rc $HL --add jazz)"
report "a positional argument: 1"      1 "$(rc $HL --ls -- extra)"
report "--record without '-': 1"       1 "$(rc $HL --record /tmp/x)"
report "bad stdin: 1"                  1 "$(rc_in 'not-json' $HL --record -)"
H_OUT=$(printf 'not-json' | $HL --record - -j 2>/dev/null)
report "…and an error envelope under -j" 0 "$(jqv '.status=="error" and .reason=="invalid_input"' "$H_OUT")"
# Every field the row is validated on, one check each: the engine name is a command prefix,
# the url is a handle, played_at names the shard file, and the reason is the PLAYBACK enum.
report "a bad engine name: 1"          1 "$(rc_in "$(printf '%s' "$H_ROW" | jq -c '.engine="yt; rm -rf /"')" $HL --record -)"
report "a url with whitespace: 1"      1 "$(rc_in "$(printf '%s' "$H_ROW" | jq -c '.url="ht tp://x"')" $HL --record -)"
report "a malformed played_at: 1"      1 "$(rc_in "$(printf '%s' "$H_ROW" | jq -c '.played_at="last tuesday"')" $HL --record -)"
report "a reason off the enum: 1"      1 "$(rc_in "$(printf '%s' "$H_ROW" | jq -c '.reason="bored"')" $HL --record -)"

rm -rf "$UT_STATE_DIR"
unset UT_STATE_DIR

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
# No separate count check: an empty ENTRY_POINTS makes the `sort -u | wc -l` below 0, not 1,
# so the vacuous case is already caught by the check that does the work.
report "one version, every entry point" 1 \
    "$(for c in $ENTRY_POINTS; do "$c" --version | awk '{print $NF}'; done | sort -u | wc -l | tr -d ' ')"
# …and that the one version is the FILE's, asserted through a SYMLINK — the documented
# install (ROADMAP D2: users symlink these onto their own PATH) and the configuration this
# breaks in. A script that does not resolve its own symlink chain looks for VERSION next to
# the LINK, finds none, and prints "unknown". Seven entry points all printing "unknown" agree
# with each other perfectly, so the check above stays green while every one of them is wrong;
# pinning the value to the file is what gives it teeth. Real symlinks to real scripts, read by
# the real command — a fixture, not a stand-in.
UT_VER=$(cat VERSION)
LINKDIR="$UT_TEST_TMP/bin"
mkdir -p "$LINKDIR"
for c in $ENTRY_POINTS; do ln -sf "$PWD/$c" "$LINKDIR/$(basename "$c")"; done
report "…and it is VERSION, via a symlink" "$UT_VER" \
    "$(for c in "$LINKDIR"/*; do "$c" --version | awk '{print $NF}'; done | sort -u | tr -d '\n')"
report "uting refuses a non-TTY" 1 "$(shell/uting </dev/null >/dev/null 2>&1; echo $?)"

echo "── gates: verbs, engine names and the host allowlist (no network) ─"
# The last of the hermetic checks, and the ones most likely to be broken by the edit you are
# about to commit: every one of these is a REFUSAL, decided from argv alone, before a
# dependency gate or a transport exists. They used to be scattered through the live half —
# green in 50 seconds, behind fifteen engine round trips they do not need — which is how the
# file's own "offline first" contract had drifted. Nothing about them changed but their
# position, and the position is the point.

# The two handles the whole file resolves, declared here because the gates name them too. A
# short, permanent, caption-bearing public video, and a permanent single-part one on the
# second site. 19 seconds long: nothing here plays it, but a resolve that accidentally starts
# a download costs a second rather than a minute. Single-part matters on the second site — a
# handle that is a 50-track collection resolves to part one, which is correct but makes a
# title assertion depend on which part that is.
MEDIA_ID="jNQXAC9IVRw"
BILI_ID="BV1mL411E7Fb"
# A third handle, and it earns its own line because BILI_ID above is deliberately SINGLE-part
# and --parts has nothing to say about a list of one. A long-lived public 100-part course; the
# checks on it assert `>= 2` and never the count, because the site's own numbers change and a
# regression on 100 would be a regression in Bilibili's catalogue, not in this engine.
BILI_PARTS_ID="BV1vKEn6eE6Q"
# An unreachable proxy is the cheapest deliberate network failure, and it works offline too.
# Declared here because the host-allowlist checks below borrow it; the failure-taxonomy
# section in the live half is where it is asserted ON.
NOPROXY="http://127.0.0.1:1"

# Shape validation lives in the ENGINE now — the player cannot tell a good id from a bad one.
report "resolve rejects a non-id" 1 "$(rc shell/yt-resolve -j -- "not an id")"
report "resolve rejects -d"       1 "$(rc shell/yt-resolve -d -- "$MEDIA_ID")"
report "resolve rejects -n"       1 "$(rc shell/yt-resolve -n 5 -- "$MEDIA_ID")"
# The read-only verb refuses the two flags that would make it write or play. Asserted on the
# plain handle, not on the captioned fixture the envelope checks use: the gate is decided
# before the handle is looked at, and that fixture's reason to exist (it must HAVE captions)
# belongs to the live check that needs it.
report "transcript rejects -f"    1 "$(rc shell/yt-resolve --transcript -f audio -- "$MEDIA_ID")"
report "transcript rejects -d"    1 "$(rc shell/yt-resolve --transcript -d -- "$MEDIA_ID")"
report "bili-resolve rejects a non-id" 1 "$(rc shell/bili-resolve -j -- "not an id")"
# Capability differs per engine and is stated, not faked: this site's videos carry no
# caption track, so the verb is absent rather than always answering "none".
report "bili-resolve has no --transcript" 1 "$(rc shell/bili-resolve --transcript -- "$BILI_ID")"

# --parts is the other half of that same statement-by-capability rule, read from the other
# direction: this site HAS multi-part videos and the sibling site does not, so the verb
# exists on one engine and must never appear on the other.
#
# THE PAIR IS ALSO THE FEASIBILITY PROOF for how `uting` will probe an engine for the verb
# without spending a request (PLAN §5.1): it invokes `--parts` with NO handle. The engine
# that has the verb answers with a usage error about the missing handle; the engine that
# does not falls into the unknown-flag arm every gate in this suite shares
# (AS-BUILT-contract.md §2). BOTH exit 1 — which is exactly why the exit code cannot be the
# probe, and why what these two pin is the stderr WORDING. An engine that grew --parts and
# a `c` key that reads the wrong side of this pair are each caught by one of them alone.
report "bili-resolve has --parts"  1 "$(err_has 'unknown flag' shell/bili-resolve --parts)"
report "bili --parts needs a handle" 1 "$(rc shell/bili-resolve --parts)"
report "yt-resolve has no --parts"  0 "$(err_has 'unknown flag' shell/yt-resolve --parts)"
report "yt --parts is usage"        1 "$(rc shell/yt-resolve --parts)"
# A flag that cannot act is REJECTED, not ignored: -f and -S select a stream format, and
# enumerating parts resolves no stream. Same rule --info is already held to above.
report "bili --parts refuses -f"   1 "$(rc shell/bili-resolve --parts -f audio -- "$BILI_ID")"
report "bili --parts refuses -S"   1 "$(rc shell/bili-resolve --parts -S abr -- "$BILI_ID")"
report "bili --parts takes ONE handle" 1 \
    "$(rc shell/bili-resolve --parts -- "$BILI_ID" "$BILI_ID")"
report "bili-search rejects -d" 1 "$(rc shell/bili-search -d -- 音乐)"
# A mistyped engine must be a USAGE error. If it fell into 2+ an agent would read it as
# "the tool failed, retry later" and retry a name that will never exist.
report "unknown engine is usage"  1 "$(rc shell/ut-play --engine nope -- "$MEDIA_ID")"
report "engine name is validated" 1 "$(rc shell/ut-play --engine ../evil -- "$MEDIA_ID")"

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
# >= 2, not == 2: this section's whole premise is that engine #3 is covered the day its pair
# lands, and a hardcoded count is the one line that would go red on exactly that day. What it
# has to rule out is NENG=0, which would make every `refusals` check below pass vacuously.
report "at least two engine pairs" 1 "$([ "$NENG" -ge 2 ] && echo 1 || echo 0)"

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

# --auth: the cookie DECISION, stated over every discovered engine. It is the one resolve
# verb that takes no handle, makes no request and runs no yt-dlp, so all four of those are
# what these checks pin. All of it is hermetic, which is why it sits above the --offline cut.
#
# The envelope's own rule is pinned too — auth=="cookie" IFF cookie_browser is not "none"
# AND profile_found — because it is the line a third engine is likeliest to get subtly
# wrong: reporting "cookie" from the env var alone, without checking the profile is really
# there, which is exactly the case that silently degrades to anonymous at play time.
#
# What no check here claims, and none can: that the login behind those cookies is valid, or
# that a valid one is worth anything. Measured 2026-08-26 — 3159 cookies extracted from
# chrome, the profile browser-confirmed logged in, and this site still served exactly the
# anonymous audio ladder because the account is not a premium member. The verb reports what
# is SENT; what is ACCEPTED needs an authenticated round trip this suite does not make, and
# what that buys is an account-tier question no envelope here answers.
_auth=0
for n in $ENGINES; do
    [ "$(jq_ok '.status=="ok" and .engine=="'"$n"'"
                and (.auth=="cookie" or .auth=="anonymous")
                and (.cookie_browser|type)=="string"
                and (.profile_found|type)=="boolean"
                and ((.auth=="cookie") == (.cookie_browser!="none" and .profile_found))' \
            "shell/$n-resolve" --auth -j)" = 0 ] && _auth=$((_auth + 1))
done
report "every engine answers --auth -j" "$NENG" "$_auth"

# The set-once knob is <ENGINE>_COOKIE_BROWSER, upper-cased from the engine name — the same
# concatenation-not-a-registry convention the command names follow. Asserting it over every
# discovered engine is what MAKES it a convention rather than two coincidences, and it is on
# the add-an-engine checklist for that reason. Upper-cased with `tr`, never with the
# bash-4 case-conversion expansion: the floor here is 3.2.
_anon=0
for n in $ENGINES; do
    _v="$(echo "$n" | tr '[:lower:]' '[:upper:]')_COOKIE_BROWSER"
    [ "$(jq_ok '.auth=="anonymous" and .cookie_browser=="none" and .profile_found==false' \
            env "$_v=none" "shell/$n-resolve" --auth -j)" = 0 ] && _anon=$((_anon + 1))
done
report "every engine honours _BROWSER=none" "$NENG" "$_anon"

# The DISCRIMINATING input, and the reason this section needs no broken build to trust it: a
# browser name that is not in the case arm at all. cookie_browser is then NOT "none", yet the
# profile cannot exist, so the only correct answer is "anonymous". An engine that derives auth
# from the env var alone — the plausible shortcut, and the one that silently degrades to
# anonymous at play time while reporting "cookie" — answers "cookie" here and goes red. No
# other check in this file separates those two implementations.
_bogus=0
for n in $ENGINES; do
    _v="$(echo "$n" | tr '[:lower:]' '[:upper:]')_COOKIE_BROWSER"
    [ "$(jq_ok '.auth=="anonymous" and .cookie_browser=="definitely-not-a-browser"
                and .profile_found==false' \
            env "$_v=definitely-not-a-browser" "shell/$n-resolve" --auth -j)" = 0 ] &&
        _bogus=$((_bogus + 1))
done
report "an unknown browser is anonymous" "$NENG" "$_bogus"

# A flag that cannot act is REJECTED, not ignored (AS-BUILT-contract.md §2). --auth asks
# about the engine, so a handle is a usage error; -f selects a stream format and --auth
# resolves no stream; -J returns the raw yt-dlp record and --auth runs no yt-dlp.
for _bad in "--auth -- HANDLE" "--auth -f video" "--auth -J"; do
    _r=0
    for n in $ENGINES; do
        # shellcheck disable=SC2086
        [ "$(rc "shell/$n-resolve" $_bad)" = 1 ] && _r=$((_r + 1))
    done
    report "every engine refuses ${_bad}" "$NENG" "$_r"
done

# --auth answers ahead of the dependency gate, the way -V does: it reports how the engine is
# configured, so needing the tool it describes would be backwards. Prose mode is the form
# that proves it — it needs no jq either, so nothing but the script itself is on the path.
# The guard above the loop is what stops the claim passing vacuously on a machine where
# yt-dlp happens to live in /usr/bin.
NODEP_PATH="/usr/bin:/bin"
report "yt-dlp absent from probe PATH" 1 \
    "$(env "PATH=$NODEP_PATH" command -v yt-dlp >/dev/null 2>&1 && echo 0 || echo 1)"
_nod=0
for n in $ENGINES; do
    # `env`, not a `VAR=x rc …` prefix: an assignment in front of a FUNCTION call persists
    # in bash after the call returns, and a leaked PATH would silently reshape every check
    # below this line.
    [ "$(env "PATH=$NODEP_PATH" "shell/$n-resolve" --auth >/dev/null 2>&1; echo $?)" = 0 ] &&
        _nod=$((_nod + 1))
done
report "every engine --auth needs no yt-dlp" "$NENG" "$_nod"

# refusals <url> — how many engines reject it as a USAGE error (1)? A rejected host dies
# before the dependency gate, so a refusal costs ~20ms and no network.
#
# THE PROXY IS WHAT PUTS THIS SECTION OFFLINE. For a real URL one engine does NOT refuse, and
# that engine used to go on and extract it — 2.5s of live yt-dlp per call, for an answer this
# function throws away: it counts REFUSALS. Pointed at an unreachable proxy the claimer fails
# with 2 (network) in ~0.8s instead of succeeding with 0, the refusers still exit 1 before any
# transport exists, and the count — the only thing asserted — is identical. Same dead proxy
# the failure-taxonomy section uses, and it works with the cable out.
refusals() {
    local u=$1 n r=0
    for n in $ENGINES; do
        [ "$(http_proxy=$NOPROXY https_proxy=$NOPROXY rc "shell/$n-resolve" -j -- "$u")" = 1 ] && r=$((r + 1))
    done
    echo $r
}

# A real URL is claimed by EXACTLY ONE engine: the other N-1 refuse it with 1 — usage, not
# extraction failure, because nothing was attempted and nothing is retryable.
report "only 1 engine claims a yt URL"   $((NENG - 1)) "$(refusals "https://www.youtube.com/watch?v=$MEDIA_ID")"
report "only 1 engine claims a bili URL" $((NENG - 1)) "$(refusals 'https://www.bilibili.com/video/BV1mL411E7Fb')"
# The ordering probe: `url_host` strips userinfo BEFORE the port, so `user:pass@host`
# resolves to the host. Swap those two expansions — a plausible tidy-up — and this resolves
# to host `user`, is refused by every engine, and nothing else in this file notices.
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
#
# The claim is the GATE, so the assertion is "not refused" rather than "resolved": under the
# same dead proxy a gate that ACCEPTS this host reaches the transport and fails 2, and a gate
# that dropped it dies at 1 without one. Extraction itself is proved on the canonical URL
# form by the resolve envelope, live, in the half below.
report "yt-resolve still takes youtu.be" 1 \
    "$([ "$(http_proxy=$NOPROXY https_proxy=$NOPROXY rc shell/yt-resolve -j -- https://youtu.be/$MEDIA_ID)" != 1 ] && echo 1 || echo 0)"

echo "── a part list is a playlist nobody saved yet ─────────────────────"
# THE CLAIM --parts EXISTS TO MAKE GOOD ON: every element of a part list IS an item record,
# so the list feeds the durable store and the player's queue with NO field renamed. The
# SUBJECTS here are ut-playlist and ut-play; the part list is their INPUT.
#
# It is a FIXTURE — data a real command really reads — and it is a real capture, not a
# hand-written shape: `bili-resolve --parts -j -- av170001` on 2026-08-29, ten parts, kept
# whole. Hermetic because the pipeline is what is under test and re-fetching the same ten
# rows would only add a way for it to go red for the network's reasons. The one thing a
# frozen fixture cannot prove — that the engine still EMITS this shape — is asserted
# against a LIVE envelope in the half below, which compares its key sets against this very
# string. Neither half covers the other; together they close it.
# EXPORT, not assign. The listening-log section above ends with `unset UT_STATE_DIR`, so by
# the time control reaches here the variable is gone from the environment and a bare
# assignment sets a variable this shell can read and a CHILD cannot — which is not a check
# that fails, it is a check that quietly runs against the user's REAL playlist store. It did:
# this block wrote an 80-row `parts` playlist into ~/.local/state/uting before the line below
# said `export`. The guard that turns a repeat of that into a red is at the top of the file.
export UT_STATE_DIR
UT_STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/uting-parts.XXXXXX")
PARTS_FIXTURE='{"status":"ok","engine":"bili","id":"BV17x411w7KC","url":"https://www.bilibili.com/video/BV17x411w7KC","title":"【MV】保加利亚妖王AZIS视频合辑","count":10,"total_duration":2412,"total_duration_fmt":"00h:40m:12s","parts":[{"n":1,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=1","title":"Хоп","duration":199,"duration_fmt":"00h:03m:19s"},{"n":2,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=2","title":"Imash li surce","duration":205,"duration_fmt":"00h:03m:25s"},{"n":3,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=3","title":"No Kazvam Ti Stiga","duration":308,"duration_fmt":"00h:05m:08s"},{"n":4,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=4","title":"Samo za teb","duration":273,"duration_fmt":"00h:04m:33s"},{"n":5,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=5","title":"Tochno sega","duration":241,"duration_fmt":"00h:04m:01s"},{"n":6,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=6","title":"Kak boli","duration":336,"duration_fmt":"00h:05m:36s"},{"n":7,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=7","title":"Obicham Te","duration":250,"duration_fmt":"00h:04m:10s"},{"n":8,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=8","title":"Mrazish","duration":201,"duration_fmt":"00h:03m:21s"},{"n":9,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=9","title":"Няма накъде","duration":201,"duration_fmt":"00h:03m:21s"},{"n":10,"engine":"bili","url":"https://www.bilibili.com/video/BV17x411w7KC?p=10","title":"Gadna poroda","duration":198,"duration_fmt":"00h:03m:18s"}]}'
PARTS_ITEMS=$(printf '%s' "$PARTS_FIXTURE" | jq -c '{items: .parts}')

report "a part list adds to a playlist" 0 \
    "$(jq_in '.status=="ok" and .added==10 and .count==10' "$PARTS_ITEMS" shell/ut-playlist --add parts -j)"
# Read back FIELD BY FIELD, because "it was accepted" is not the claim — the claim is that
# what came out the other side is still a CALL: an engine to route to and a per-part URL to
# hand it. A part list that stored its rows without the `?p=N` would round-trip clean here
# and play part one ten times.
report "…and every stored row is a call"  0 \
    "$(jq_ok '(.items|length)==10 and all(.items[];
                 .engine=="bili"
                 and (.url|startswith("https://www.bilibili.com/video/BV17x411w7KC?p="))
                 and (.title|type)=="string" and (.title|length)>0
                 and (.duration|type)=="number")' shell/ut-playlist --show parts -j)"

# --enqueue, NOT --queue. `--queue -` without -d is refused on ARGV — the gate never reads
# stdin — so a check on it would be green for any payload at all, including an empty one:
# it cannot fail. `--enqueue` parses the items FIRST and only then discovers there is no
# player to hand them to, which is `not_playing` and exit 4; malformed input is exit 1 on
# that same surface (measured, both). That gap is what makes this able to go red.
report "a part list enqueues"             4 "$(rc_in "$PARTS_ITEMS" shell/ut-play --enqueue - -j)"
report "…parsed, not refused"             0 \
    "$(jq_in '.status=="not_playing"' "$PARTS_ITEMS" shell/ut-play --enqueue - -j)"
# The contrast that gives the two above their meaning: the same surface, a payload whose
# records are NOT calls. 1, not 4 — so the pair really is reading the fixture's shape.
report "…and a record with no url is 1"   1 \
    "$(rc_in '[{"engine":"bili"}]' shell/ut-play --enqueue - -j)"

# --parts runs ONE HTTP request and no yt-dlp — the same backwards gate --auth refuses, one
# verb over. Under the dead proxy this verb reaches its transport and fails with 2; a
# version that had grown a yt-dlp call on this path (to fetch the title, say) would die 1 at
# the dependency gate before any transport existed. The PATH guard further up is what stops
# it passing vacuously on a machine with yt-dlp in /usr/bin.
report "--parts needs no yt-dlp"          2 \
    "$(env "PATH=$NODEP_PATH" "http_proxy=$NOPROXY" "https_proxy=$NOPROXY" \
        shell/bili-resolve --parts -j -- "$BILI_ID" >/dev/null 2>&1; echo $?)"
rm -rf "$UT_STATE_DIR"
unset UT_STATE_DIR

echo "── the config file: precedence, and what it refuses ───────────────"
# WHY THESE CHECKS EXIST AT ALL. The config file is the one input in the suite that a user
# hand-writes and no command validates on their behalf, so its failure modes are not the
# usual ones: a knob that silently does not apply, a precedence order that quietly inverts,
# and — the one that matters — a file that reaches past the suite into the environment. Each
# check below feeds the discriminating input rather than the happy one: the happy path is
# already covered by every other check in this file, all of which now read a config.
CFGD=$(mktemp -d "${TMPDIR:-/tmp}/uting-cfg.XXXXXX")
CFG="$CFGD/config"

# Precedence, proved on ONE observable in three runs. `--engine` names a missing engine, so
# the error text says which value won — a real gate on a real entry point, no parsing of an
# internal. A naive loader that exported over the environment would answer "file" to the
# second, and one that ran before argv parsing would answer "env" to the third.
printf 'UT_DEFAULT_ENGINE=cfgwins\n' > "$CFG"
eng() { UT_CONFIG="$CFG" "$@" 2>&1 | sed -n "s/.*unknown engine '\([^']*\)'.*/\1/p"; }
report "config file sets the default engine" "cfgwins" \
    "$(eng shell/ut-play -- https://x/y)"
report "environment beats the config file" "envwins" \
    "$(UT_DEFAULT_ENGINE=envwins eng shell/ut-play -- https://x/y)"
report "the flag beats both" "flagwins" \
    "$(UT_DEFAULT_ENGINE=envwins eng shell/ut-play --engine flagwins -- https://x/y)"

# THE SECURITY BOUNDARY, and the reason the file is read as data instead of sourced. A config
# that could be sourced would run the command substitution below and set PATH from a file the
# suite never audited; the check is that nine characters arrive as nine characters and that
# the file cannot name anything outside the suite's own namespaces.
printf 'PATH=/nonexistent\nLD_PRELOAD=/evil.so\nlowercase_key=x\nUT_INJECT=$(touch %s/PWNED)\n' \
    "$CFGD" > "$CFG"
report "a config key outside UT_/YT_/BILI_ is inert" "0" \
    "$(UT_CONFIG="$CFG" rc shell/uting --version)"
report "command substitution is never executed" "absent" \
    "$([ -e "$CFGD/PWNED" ] && echo present || echo absent)"

# The player's own four. A file-level YT_IPC_SOCK would aim every player at one socket, so it
# is refused INSIDE an allowed namespace — which is the case a prefix allowlist alone misses.
printf 'YT_IPC_SOCK=%s/hijack.sock\n' "$CFGD" > "$CFG"
report "the player still answers with YT_IPC_SOCK set" "0" \
    "$(UT_CONFIG="$CFG" rc shell/ut-play --stop --all -j)"
report "the file did not create the hijack socket" "absent" \
    "$([ -e "$CFGD/hijack.sock" ] && echo present || echo absent)"

# A TYPO MUST BE LOUD. An emptied cycle would otherwise abort on the first keypress (an empty
# array expansion under set -u aborts on bash 3.2) and an unknown member would put a mode the
# engines reject under the v key — both a long way from the line the user actually wrote.
printf 'UT_THEME_CYCLE=nord,bogus\n' > "$CFG"
report "an unknown cycle member exits 1" "1" "$(UT_CONFIG="$CFG" rc shell/uting q)"
printf 'UT_MAX_SEARCH_RESULTS=-5\n' > "$CFG"
# Over EVERY discovered engine, not just bili: the ceiling is cross-engine, so a check
# driving one of them would be green while the other spent an unbounded fetch.
for n in $ENGINES; do
    report "$n-search rejects a negative ceiling" "1" \
        "$(UT_CONFIG="$CFG" rc "shell/$n-search" -j -- q)"
done

# A restricted cycle must still START. The -f and -s defaults are validated against their
# cycles, so a literal "audio" default would make `UT_MODE_CYCLE=video` a config that cannot
# run — the user narrows the cycle and gets told their flag is wrong. Reaching the TTY refusal
# is the pass: it is the gate immediately after the one under test.
printf 'UT_MODE_CYCLE=video\nUT_SORT_CYCLE=duration\n' > "$CFG"
report "a narrowed cycle reaches the TTY gate" "1" "$(UT_CONFIG="$CFG" rc shell/uting q)"
# Captured and then matched, NOT piped into grep: this file runs under `set -o pipefail`, so
# `shell/uting q | grep -q` reports uting's exit 1 rather than grep's 0 and a matched pattern
# reads as no-match. Every check here asserts on a command that exits non-zero by design.
CFG_OUT=$(UT_CONFIG="$CFG" shell/uting q 2>&1 || true)
case "$CFG_OUT" in
*"requires a terminal"*) CFG_HIT=yes ;;
*) CFG_HIT=no ;;
esac
report "…and it is the TTY gate, not a flag error" "yes" "$CFG_HIT"

# THE BROKEN CHECKOUT. Defaults now live in <checkout>/config and nowhere else, so a copy of
# a script without that file has no values at all. The failure must be this one line and exit
# 2 — not `set -u` reporting an unbound variable from 100 lines further down, which is what
# the first attempt produced when --version and --help were let through. Driven by really
# copying an entry point somewhere that has a VERSION and no config, which is exactly the
# shape of a half-installed checkout.
CFG_BROKE="$CFGD/broke"
mkdir -p "$CFG_BROKE/shell"
cp shell/ut-play "$CFG_BROKE/shell/" && echo 0.0.0 > "$CFG_BROKE/VERSION"
report "no shipped defaults exits 2" "2" "$(rc "$CFG_BROKE/shell/ut-play" --version)"
CFG_OUT=$("$CFG_BROKE/shell/ut-play" --version 2>&1 || true)
case "$CFG_OUT" in
*"cannot read the shipped defaults"*) CFG_HIT=yes ;;
*) CFG_HIT=no ;;
esac
report "…naming the file, not an unbound variable" "yes" "$CFG_HIT"
cp config "$CFG_BROKE/config"
report "restoring the file restores --version" "0" "$(rc "$CFG_BROKE/shell/ut-play" --version)"
rm -rf "$CFGD"

if [ "$OFFLINE" = 1 ]; then
    echo
    echo "── the live half: SKIPPED (--offline) ─────────────────────────────"
    # Named, not counted: what is missing is the only thing that makes a green here smaller
    # than a green run, and a reader who cannot see the list will assume it is nothing.
    echo "  not run: both engines' live envelopes and their parity, --transcript, the dead"
    echo "  id, the network taxonomy, and the TUI under tmux. Run without --offline to push."
    report_real_config
    report_real_state
    summary
fi

# ---- fetch once, assert many --------------------------------------------------------
# A live engine call costs a yt-dlp start (~2s) whether one question is asked of its answer
# or four, and nearly every assertion below is about an envelope's SHAPE. Two identical
# queries cannot answer a shape question differently, so each fixture is one plain command
# substitution, interrogated as many times as it has claims. The command is still the real
# entry point and the answer is still its real stdout.
#
# A call keeps its own invocation when its ARGV differs (-j and -J are two envelopes, not two
# questions about one), when its ENVIRONMENT differs (the proxy checks), or when its INPUT
# differs (a second query, chosen for content the first one does not have).

echo "── the config file, on a real fetch ───────────────────────────────"
# THE TWO CLAIMS THAT ONLY A REAL FETCH CAN SETTLE. Everything about the config file in the
# offline half is about parsing and refusal; these two are about the values actually reaching
# the code that spends requests, and the observable is the row count in a real envelope.
#
# Both are stated over EVERY discovered engine, because the whole point of these two keys is
# that they are cross-engine: a check driving one of them would be green while the other
# ignored the ceiling entirely. Two round trips per engine, which is why they live here.
CFGL=$(mktemp -d "${TMPDIR:-/tmp}/uting-cfglive.XXXXXX")

# The ceiling. -n asks for 20 and the file caps at 3, so an engine that honours it returns at
# most 3 — and one that does not returns up to 20. That gap IS the check: before this key,
# bili-search capped at ten pages and yt-search was bounded only by what the site stopped
# sending, so "unclamped" is a real implementation, not a strawman.
printf 'UT_MAX_SEARCH_RESULTS=3\n' > "$CFGL/config"
for n in $ENGINES; do
    report "$n-search honours the row ceiling" "true" \
        "$(UT_CONFIG="$CFGL/config" shell/"$n"-search -j -n 20 -- lofi 2>/dev/null \
           | jq -r '(.results | length) <= 3' 2>/dev/null)"
done

# The shared default really is shared. No -n at all, so the count comes from
# UT_SEARCH_RESULTS in the config — and this is the check that would have caught the drift
# the centralisation was for: an engine still carrying its own inlined 25 answers with more
# than 4 here.
printf 'UT_SEARCH_RESULTS=4\n' > "$CFGL/config"
for n in $ENGINES; do
    report "$n-search takes -n from the config" "true" \
        "$(UT_CONFIG="$CFGL/config" shell/"$n"-search -j -- lofi 2>/dev/null \
           | jq -r '(.results | length) <= 4' 2>/dev/null)"
done
rm -rf "$CFGL"

echo "── search envelope ────────────────────────────────────────────────"
# One live search, four claims — and the parity check further down reuses this same
# envelope rather than fetching a fifth.
YT_S=$(shell/yt-search -j -n 3 -- lofi 2>/dev/null)
YT_SJ=$(shell/yt-search -J -n 2 -- lofi 2>/dev/null)
report "search -j envelope" 0 \
    "$(jqv '.query and .count and (.results|length==3)' "$YT_S")"
# The engine names itself in its own envelope. This is what lets a caller route a chosen
# result back to the matching <engine>-resolve without pattern-matching its URL, so a new
# engine that forgets the field breaks routing rather than merely looking different.
report "search -j names its engine" 0 \
    "$(jqv '.status=="ok" and .engine=="yt"' "$YT_S")"
report "search -J has raw id" 0 \
    "$(jqv '.results[0]|has("id")' "$YT_SJ")"
# Was an open R8 drift (26 lines for -n 3); fixed, so it is a hard check now — a "known"
# label on a passing behaviour is how a real regression gets waved through later.
report "search -j is one line" 1 "$(lines "$YT_S")"

echo "── resolve envelope: the half that turns a handle into bytes ──────"
YT_R=$(shell/yt-resolve -j -- "$MEDIA_ID" 2>/dev/null)
# Every key the PLAYER reads. A new engine that renames one, or omits http_headers, breaks
# playback in a way no other check here would notice: the search half would still look fine.
# http_headers is asserted PRESENT rather than non-empty — {} is a legal answer, absent is not.
report "resolve -j envelope" 0 \
    "$(jqv '.status=="ok" and .engine=="yt" and (.stream_urls|length)>0
              and has("http_headers") and (.http_headers|type)=="object"
              and has("title") and has("format") and has("retried")' "$YT_R")"
report "resolve -j is one line" 1 "$(lines "$YT_R")"
echo "── the player's engine seam ───────────────────────────────────────"
# A well-formed id that resolves to nothing is a PROPAGATED tool failure (2+), not usage,
# and it must still say why — the semantics the shape check sitting in the engine buys.
# One resolve attempt answers both: the exit code and the envelope come off the same run,
# which is also the only way they are guaranteed to be describing the same failure.
DEAD=$(shell/ut-play -j -- AAAAAAAAAAA 2>/dev/null); DEAD_ST=$?
report "dead id is 2+, not 1"     2 "$DEAD_ST"
report "dead id keeps its reason" 0 \
    "$(jqv '.status=="error" and .exit_code>=2 and (.reason|type)=="string"' "$DEAD")"

echo "── argv order: a flag-shaped query after -- is SEARCHED ───────────"
# Not a player list: --status after -- is eight characters of query text. The check lives on
# yt-search because that is where searching lives now; the player has no search branch left
# to confuse a flag-shaped token with (AS-BUILT-contract.md §2).
# Asserted POSITIVELY, on the query the engine echoes back. The old form folded stderr into
# the pipe and asked only "is line one not JSON?", so `Error: search failed (network)` — a
# yt-search that did not run at all — satisfied it. It was also the one live call in this file
report "yt-search -- --status searches" 0 \
    "$(jq_ok '.status=="ok" and .query=="--status"' shell/yt-search -j -n 1 -- --status)"

echo "── --transcript: the read-only verb, both envelopes (gate above) ──"
# The ok-path fixture must be a video that HAS captions and the error-path one must not:
# pointing the ok-path at a long music stream is how this check first went red against
# working code.
CAPTIONED="https://www.youtube.com/watch?v=8S0FDjFBj8o"
BARE="https://www.youtube.com/watch?v=n61ULEU7CO0"
report "transcript envelope"      0 \
    "$(jq_ok '.status=="ok" and .id and .lang and .chars>0 and (.is_auto|type=="boolean") and (.text|length>0)' \
        shell/yt-resolve --transcript -j -- "$CAPTIONED")"
report "transcript -J has segments" 0 \
    "$(jq_ok '.segments[0]|has("start") and has("text")' shell/yt-resolve --transcript -J -- "$CAPTIONED")"
NOCAP=$(shell/yt-resolve --transcript -j -- "$BARE" 2>/dev/null); NOCAP_ST=$?
report "no captions -> error"     0 \
    "$(jqv '.status=="error" and .reason=="no_subtitles_available"' "$NOCAP")"
report "no captions exit"         1 "$NOCAP_ST"

echo "── the second engine: the same envelope, or the split is a fiction ─"
# The second engine's three envelopes, one call each. `-n 5` because the duration check
# below needs a page rather than a pair, and a key set does not care how long the list is.
BILI_S=$(shell/bili-search  -j -n 5 -- 音乐 2>/dev/null)
BILI_R=$(shell/bili-resolve -j -- "$BILI_ID" 2>/dev/null)
YT_I=$(shell/yt-resolve   --info -j -- "$MEDIA_ID" 2>/dev/null)
BILI_I=$(shell/bili-resolve --info -j -- "$BILI_ID" 2>/dev/null)

# THE check the engine split exists for. Two engines are only interchangeable if a caller
# cannot tell which one answered, so the assertion is on the KEY SETS THEMSELVES rather
# than on a list of names written out twice: a field renamed, added or dropped in EITHER
# engine fails here, including one added to yt-search years from now and forgotten on the
# other side. Nothing else in this file would notice — each engine's own checks would still
# pass, and playback would break only for the engine nobody happened to run.
report "search envelopes agree" \
    "$(printf '%s' "$YT_S" | jq -Sc 'keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_S" | jq -Sc 'keys' 2>/dev/null)"
report "search result keys agree" \
    "$(printf '%s' "$YT_S" | jq -Sc '.results[0]|keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_S" | jq -Sc '.results[0]|keys' 2>/dev/null)"

# The row's own premise, over every DISCOVERED engine and BOTH envelope shapes — two places
# a real implementation has already been wrong, and neither is caught by the parity check
# above (two engines agree on a key set they are both missing, and it only ever reads -j).
#
#   · `kind`/`access` are the ENGINE'S JUDGEMENT about a row (AS-BUILT-contract.md §3), which
#     is why they are injected before the lean projection rather than inside it: an engine
#     that adds them to the projection alone hands the caller who asked for MORE data (-J) an
#     envelope missing two required fields, and every -j check in this file stays green.
#   · A row whose `url` is null is not a row: `ut-play` has nothing to call. bili-search
#     shipped exactly that — search_type=video mixes in `ketang` (paid-course) records that
#     carry no `bvid`, 3 of 20 on "钢琴", and an EMPTY bvid is TRUTHY in jq, so the `.id !=
#     null` gate passed them through with `id: ""` and `url: null`.
#
# Asserted against the CLOSED ENUM, never against `has("kind")`: an engine writing
# kind:"video" — the site's own word, the likeliest wrong answer — satisfies presence and
# fails here. The non-empty result requirement is what stops the whole thing passing
# vacuously on an engine that returned nothing.
ROW_IS_A_CALL='(.results|length)>0 and all(.results[];
      (.url|type=="string") and (.url|length)>0
      and (.id|type=="string") and (.id|length)>0
      and (.kind|IN("track","collection","multipart"))
      and (.access|IN("full","preview","paywalled")))'
for n in $ENGINES; do
    report "$n-search -j rows are calls" 0 \
        "$(jq_ok "$ROW_IS_A_CALL" shell/"$n"-search -j -n 5 -- lofi)"
    report "$n-search -J rows are calls" 0 \
        "$(jq_ok "$ROW_IS_A_CALL" shell/"$n"-search -J -n 5 -- lofi)"
done
report "resolve envelopes agree" \
    "$(printf '%s' "$YT_R" | jq -Sc 'keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_R" | jq -Sc 'keys' 2>/dev/null)"
# --info gets the same parity treatment: it is the third envelope both engines publish
# (AS-BUILT-contract.md §3), and nothing else here would notice a field renamed on one
# side. The ok/engine assertion is what keeps the key comparison from passing vacuously —
# two ERROR envelopes agree on their keys too.
report "info -j is ok and named" 0 \
    "$(jqv '.status=="ok" and .engine=="yt"' "$YT_I")"
report "info envelopes agree" \
    "$(printf '%s' "$YT_I" | jq -Sc 'keys' 2>/dev/null)" \
    "$(printf '%s' "$BILI_I" | jq -Sc 'keys' 2>/dev/null)"
report "--info -j is one line" 1 "$(lines "$YT_I")"

report "bili-search names its engine" 0 \
    "$(jqv '.status=="ok" and .engine=="bili"' "$BILI_S")"
report "bili-search -j is one line" 1 "$(lines "$BILI_S")"
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
    "$(jqv '[.results[].duration]
               | length>0
               and all(type=="number" or type=="null")
               and any(type=="number")' "$BILI_S")"
# The site filters duration itself, in four coarse buckets, and a -m/-M window that fits
# inside ONE of them is pushed down — the only lever there is on a 20-per-page endpoint with
# no page-size knob. `-M 600` fits bucket 1 exactly and `-M 601` fits nothing, which makes
# this the discriminating input rather than a restatement of the bounds: measured 2026-08-26
# on one request each, the pushed-down form returned 20 usable rows and the local-only form
# returned 1. An engine that stops sending `duration` — a renamed parameter, a bucket
# mis-mapped, the plan computed after the first page — passes every other check in this file
# and quietly hands back a handful of rows where -n asked for twenty. The bound itself is
# asserted with it, because the buckets are COARSE and pushing one down must never widen the
# answer: 600 is the ceiling the caller named, not the ten minutes the site understood.
report "bili pushes -M to the site" 0 \
    "$(jq_ok '.count >= 15 and ([.results[].duration] | all(. == null or . < 600))' \
        shell/bili-search -j -n 20 -M 600 -- 周杰伦)"
# Titles arrive as search-result HTML (<em class="keyword">) and entity-escaped. Markup that
# survives into a title is counted by the width layer, which reflows every row wrongly.
report "bili titles carry no markup" 0 \
    "$(jq_ok '[.results[].title]|all((test("<") or test("&[a-z#]+;"))|not)' shell/bili-search -j -n 10 -- 周杰伦)"

# This site's CDN checks Referer: the bare stream URL answers 403 and the same URL with
# these headers answers 206 (measured). An empty http_headers here is a silently unplayable
# engine, which is exactly the contract hole the key was added to close.
report "bili resolve sends a Referer" 0 \
    "$(jqv '.http_headers|has("Referer")' "$BILI_R")"
# --parts, live: the two claims the hermetic half above structurally cannot make. One, that
# the engine still EMITS the shape that fixture froze — asserted as a key-set comparison
# against the fixture ITSELF, so a field renamed or added on either side is red here and the
# fixture can never quietly rot into a description of an older engine. Two, that it is still
# ONE request: this verb talks HTTP rather than going through yt-dlp precisely because one
# GET answers the whole question (0.5s measured), and a version that started paying a second
# round trip — or an extractor start — would still be CORRECT and would have given away the
# only reason the transport is here. 5s against a measured 0.5 is ten-fold headroom, so what
# trips it is a new round trip, not a slow afternoon.
_pt0=$(date +%s)
BILI_P=$(shell/bili-resolve --parts -j -- "$BILI_PARTS_ID" 2>/dev/null)
_pt1=$(date +%s)
report "bili --parts is one request" 1 "$([ $((_pt1 - _pt0)) -lt 5 ] && echo 1 || echo 0)"
report "bili --parts is one line"    1 "$(lines "$BILI_P")"
# Every part is asserted, not just the first: `?p=N` is built per element, and an off-by-one
# or a base URL that kept the caller's own query string shows up on element two onwards. The
# base is taken from the envelope's OWN top-level url, so the claim is internal consistency
# — the thing a caller relies on when it pipes .parts straight into the player.
report "bili --parts envelope"       0 \
    "$(jqv '.status=="ok" and .engine=="bili" and (.id|startswith("BV"))
              and (.title|type)=="string" and (.title|length)>0
              and (.count|type)=="number" and .count>=2 and .count==(.parts|length)
              and (.total_duration|type)=="number"
              and (.total_duration_fmt|type)=="string"
              and (.url as $b | all(.parts[];
                    (.n|type)=="number" and .engine=="bili"
                    and (.title|type)=="string" and (.title|length)>0
                    and (.duration|type)=="number"
                    and (.duration_fmt|type)=="string"
                    and .url == ($b + "?p=" + (.n|tostring))))' "$BILI_P")"
report "the offline fixture still fits" \
    "$(printf '%s' "$PARTS_FIXTURE" | jq -Sc '[keys, (.parts[0]|keys)]' 2>/dev/null)" \
    "$(printf '%s' "$BILI_P" | jq -Sc '[keys, (.parts[0]|keys)]' 2>/dev/null)"
# A single-part video is a list of ONE and is NOT an error — the contract says so, and the
# plausible wrong implementation (treat "no parts to choose between" as a failure) would pass
# every other --parts check in this file. BILI_ID is that handle, which is why it is separate
# from BILI_PARTS_ID above.
report "one part is still a list"    0 \
    "$(jq_ok '.status=="ok" and .count==1 and (.parts|length)==1
                and .parts[0].url==(.url + "?p=1")' shell/bili-resolve --parts -j -- "$BILI_ID")"

# The player routes by NAME, and the name is the command prefix — the whole reason the
# lookup is a string concatenation instead of a registry.
report "ut-play routes to the bili engine" 0 \
    "$(jq_ok '.status=="error" and .exit_code>=2 and (.reason|type)=="string"' \
        shell/ut-play --engine bili -j -- BV1111111111)"

echo "── failure taxonomy: 2 is a tool failure, never 1 ─────────────────"
report "network envelope" 0 \
    "$(http_proxy=$NOPROXY https_proxy=$NOPROXY jq_ok '.status=="error" and .reason=="network"' \
        shell/yt-search -j -n 2 -- lofi)"
report "network exit is 2" 2 \
    "$(http_proxy=$NOPROXY https_proxy=$NOPROXY rc shell/yt-search -j -n 2 -- lofi)"
report "network exit is 2 (text)" 2 \
    "$(http_proxy=$NOPROXY https_proxy=$NOPROXY rc shell/yt-search -n 2 -- lofi)"

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
    # TMPDIR is passed explicitly: a tmux SERVER that was already running carries the
    # environment of whoever started it, so the export at the top of this file does not reach
    # the pane, and uting's --status polls would create a players/ dir in the user's real
    # state dir. Nothing destructive happens there — every --stop and every fixture below runs
    # in this shell, where TMPDIR is redirected — but "this file does not touch your state"
    # should be true without a footnote.
    # A state dir of the pane's own, seeded with ONE listening. Two reasons, and the second
    # is the check below: the pane stops reading the user's real store (the footnote the
    # TMPDIR comment above wishes it did not need), and `h` has something deterministic to
    # open — against a real user's log the row-source check would pass on an empty history
    # without ever leaving the search, which is a check that cannot fail.
    TUI_STATE=$(mktemp -d "${TMPDIR:-/tmp}/uting-tuistore.XXXXXX")
    printf '%s' '{"engine":"yt","id":"t1","url":"https://www.youtube.com/watch?v=t1","title":"Seeded","duration":213,"played_at":"2026-06-02T10:00:00Z","ended_at":"2026-06-02T10:01:37Z","seconds":97,"reason":null}' |
        UT_STATE_DIR="$TUI_STATE" shell/ut-history --record - -j >/dev/null 2>&1
    # The fixture answers for itself. Without this, a seed that did not land reads as "h did
    # nothing" — blaming the key for the state it was given, which is the one way this check
    # could point at the wrong thing.
    report "the log fixture really seeded" 1 \
        "$(UT_STATE_DIR="$TUI_STATE" shell/ut-history --ls -j 2>/dev/null | jq -r '.count // 0')"
    # The other store, seeded the same way and for the `b` check below: a search envelope on
    # stdin is exactly what `a` hands the store, so this is a fixture (data a real command
    # really reads), not a stand-in for one.
    printf '%s' '{"status":"ok","engine":"yt","count":1,"results":[{"id":"t2","url":"https://www.youtube.com/watch?v=t2","title":"Stored","duration":97}]}' |
        UT_STATE_DIR="$TUI_STATE" shell/ut-playlist --add seeded-list -j >/dev/null 2>&1
    report "the playlist fixture really seeded" 1 \
        "$(UT_STATE_DIR="$TUI_STATE" shell/ut-playlist --ls -j 2>/dev/null | jq -r '.count // 0')"
    # A config file of the pane's own, and the fixture for every write-back check below. Its
    # SHAPE is the discriminator: UT_PLAY_MODE is present, so `v` has to edit that line in
    # place and leave the comment on it alone — a naive `printf '%s=%s\n'` rewrite passes the
    # value check and fails the comment beside it. UT_START_RESULTS is absent, so the count
    # keys have to APPEND. UT_SORT_FIELD is absent too, and pinned in the pane's environment
    # below: "the file never grew that key" is how a refused write is asserted without
    # needing to know when the write would have happened.
    # It is also a SYMLINK to the real file — the shape a config kept in a dotfiles repo
    # has, and a second discriminator for free: a write that renamed onto the link would
    # leave a regular file here, orphan the real dotfile, and still pass the value check
    # below (the new regular file carries the new value). Only `-L` afterwards separates them.
    TUI_CFG="$UT_TEST_TMP/tui-config"
    TUI_CFG_REAL="$UT_TEST_TMP/tui-config.real"
    printf '%s\n' '# a config a human wrote' 'UT_PLAY_MODE=audio    # keep me' >"$TUI_CFG_REAL"
    ln -s "$TUI_CFG_REAL" "$TUI_CFG"
    # UT_SORT_FIELD in the pane's ENVIRONMENT is the discriminating input for the refusal:
    # the environment beats the file at every startup, so a uting that wrote this key would
    # record view_count and then discard it on the next run. The value it would write
    # (view_count) differs from the pinned one (relevance), so the check cannot pass by
    # accident — which is exactly what a fixture that agreed with the environment would do.
    TUI_CMD="cd '$PWD' && env YT_SYNC=0 TMPDIR='$TMPDIR' UT_STATE_DIR='$TUI_STATE' UT_CONFIG='$TUI_CFG' UT_SORT_FIELD=relevance shell/uting 'lofi hip hop'"
    TUI_CMD="$TUI_CMD"'; printf "RC=%s\n" $?'
    TUI_CMD="$TUI_CMD"'; stty -a </dev/tty | tr " " "\n" | grep -E "^-?(echo|icanon)$" | tr "\n" " " | sed "s/^/FLAGS= /"; echo; sleep 20'
    tmux new-session -d -s "$TS" -x 100 -y 30 "$TUI_CMD"
    TUI_TTY=$(tmux display-message -p -t "$TS" '#{pane_tty}' 2>/dev/null)
    # `-echo` with ICANON still SET is the termios signature of getpass(), and terminals poll
    # the pty for exactly that pair: Ghostty flips macOS Secure Input on it, iTerm2 draws a
    # padlock at the cursor — which the fetch spinner parks on its own glyph. Two greps, not a
    # case glob: `-echo` is a prefix of `-echoe`/`-echok`.
    #
    # This is a SAMPLE, and the name says so. The state it looks for is transient, so the
    # sampling rate is what the check is worth: at the capture-pane cadence (0.3s) it could
    # miss a flip that lasted a frame and report a pass it had not earned. termios is read
    # every 0.05s and the pane only every sixth pass — same wall clock, 6x the chance of
    # catching it. Waiting for the first frame is the right window: it is the one stretch of
    # the session where no `read` is running and the tty carries whatever the app left on it.
    booted=0; i=0; getpass=0
    while [ $i -lt 480 ]; do
        if [ -n "$TUI_TTY" ]; then
            flags=$(stty -f "$TUI_TTY" -a 2>/dev/null | tr ' ' '\n')
            [ "$(printf '%s\n' "$flags" | grep -c '^-echo$')" = 1 ] &&
                [ "$(printf '%s\n' "$flags" | grep -c '^icanon$')" = 1 ] && getpass=1
        fi
        if [ $((i % 6)) = 5 ]; then
            tmux capture-pane -t "$TS" -p 2>/dev/null | grep -q 'results=' && { booted=1; break; }
        fi
        sleep 0.05; i=$((i + 1))
    done
    report "TUI boots and paints a list" 1 "$booted"
    report "no password prompt sampled" 0 "$getpass"

    # Reflow is width-conditional, so the two geometries that change layout are the ones
    # worth walking. The assertion is survival, not shape: still up, still showing a list.
    alive=1
    for geom in "62x20" "26x24"; do
        gw=${geom%x*}; gh=${geom#*x}
        tmux resize-window -t "$TS" -x "$gw" -y "$gh" 2>/dev/null
        j=0; seen=0
        while [ $j -lt 20 ]; do
            tmux capture-pane -t "$TS" -p 2>/dev/null | grep -q 'results=' && { seen=1; break; }
            sleep 0.25; j=$((j + 1))
        done
        [ "$seen" = 1 ] || alive=0
    done
    report "survives 62x20 and 26x24" 1 "$alive"

    # A store is a room with a door, not a one-way trip — and the door is the key that opened
    # it (AS-BUILT-tui.md §11). `h` REPLACES the rows with the log (`items=` in the header,
    # where a search says `results=`) and `h` again puts the search back; until it did, the
    # only exits from that room were retyping a query and quitting. Both halves are asserted:
    # an `h` that quietly did nothing would leave the search on screen and make the return
    # leg pass for free.
    tmux resize-window -t "$TS" -x 100 -y 30 2>/dev/null

    # ---- the preference write-back and the two count edges ----------------------------
    # All of it on the pane that is ALREADY up: no second cold start, no second cold search.
    # The rows on screen are the fixture these keys need, and the keys are the only way to
    # reach the write path — there is no verb for it, deliberately (the agent surface for a
    # preference IS the config file, ROADMAP.md D8).
    #
    # The write is DEFERRED — a cycle sets a dirty bit and the flush happens on the reader's
    # idle tick — so every assertion below POLLS the file instead of reading it once. That is
    # not a workaround for a race; it is the claim: a preference must reach the disk without
    # anyone quitting the app.
    pane_results() {
        tmux capture-pane -t "$TS" -p -J 2>/dev/null |
            grep -o 'results=[0-9][0-9]*' | head -1 | cut -d= -f2
    }
    tmux send-keys -t "$TS" v
    wrote=0; i=0
    while [ $i -lt 40 ]; do
        grep -q '^UT_PLAY_MODE=video' "$TUI_CFG" && { wrote=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "v writes the mode to your config" 1 "$wrote"
    report "the comment on that line survived" 1 "$(grep -c '# keep me' "$TUI_CFG")"
    report "your config is still the symlink" 1 "$(test -L "$TUI_CFG" && echo 1 || echo 0)"
    report "and the real file behind it moved" 1 \
        "$(grep -c '^UT_PLAY_MODE=video' "$TUI_CFG_REAL")"

    # → past the last page fetches one more batch. Two presses is the geometry this pane has
    # (10 rows a page, 20 rows on screen), and the round repeats rather than assuming it: a
    # reflow that made the pages shorter would just take another lap. The assertion is
    # RELATIONAL — it grew — so a lap that overshoots to three batches still proves the edge.
    grew=0; i=0
    while [ $i -lt 3 ]; do
        tmux send-keys -t "$TS" Right; sleep 0.4
        tmux send-keys -t "$TS" Right
        j=0
        while [ $j -lt 48 ]; do
            n=$(pane_results)
            [ -n "$n" ] && [ "$n" -gt 20 ] && { grew=1; break; }
            sleep 0.25; j=$((j + 1))
        done
        [ "$grew" = 1 ] && break
        i=$((i + 1))
    done
    report "the right edge grows the count" 1 "$grew"

    # ← on page 1 is the mirror, and the reason it can live on a bare arrow: it truncates
    # what is already in hand, so it costs nothing and cannot fail. Twelve presses is a walk
    # back to page 1 from wherever the growth left the cursor plus the steps down; the ones
    # that land at the floor are the next check's, and they must do nothing at all.
    i=0
    while [ $i -lt 12 ]; do tmux send-keys -t "$TS" Left; sleep 0.12; i=$((i + 1)); done
    shrank=0; i=0
    while [ $i -lt 40 ]; do
        [ "$(pane_results)" = 20 ] && { shrank=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "the left edge drops it again" 1 "$shrank"
    # The floor. An implementation without one walks 20 → 0 and renders an empty list, which
    # is the shape this catches: the count must sit still, not fall.
    i=0
    while [ $i -lt 6 ]; do tmux send-keys -t "$TS" Left; sleep 0.12; i=$((i + 1)); done
    sleep 1
    report "and stops at a screenful" 20 "$(pane_results)"
    # The append path, and the key that must NOT be written: UT_FETCH_BATCH is the STEP each
    # edge moves by, so storing a total in it would make the next → add 20 rows at a time
    # more than the last. The count lives in its own key or nowhere.
    appended=0; i=0
    while [ $i -lt 24 ]; do
        grep -q '^UT_START_RESULTS=20$' "$TUI_CFG" && { appended=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "the count lands in its own key" 1 "$appended"
    report "and not in the step key" 0 "$(grep -c '^UT_FETCH_BATCH' "$TUI_CFG")"

    # A filter is a page of MATCHES, so running off its end is not a request for more rows.
    # This went red before the guard landed (measured 2026-08-29): `/` then `zzz` then `→`
    # against 20 rows fetched 20 more and dropped the filter — filter_live drives the same
    # move_selection, so more_results' "no filter can be open here" was an assertion, not a
    # fact. `zzz` matches nothing, which is what makes the check discriminating: the filtered
    # count is 0, and an unguarded edge replaces it with a whole re-fetched row set.
    tmux send-keys -t "$TS" / z z z
    narrowed=0; i=0
    while [ $i -lt 40 ]; do
        [ "$(pane_results)" = 0 ] && { narrowed=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "a filter narrows to nothing" 1 "$narrowed"
    # Esc right behind the arrow, so the wait has a MARKER instead of a guessed duration:
    # leaving the filter restores the rows, and the count that comes back is the answer —
    # 20 if the arrow did nothing, 40 if it re-fetched (Esc is read after the blocking fetch
    # returns, so the number is settled by the time it is non-zero again).
    tmux send-keys -t "$TS" Right
    tmux send-keys -t "$TS" Escape
    n=""; i=0
    while [ $i -lt 60 ]; do
        n=$(pane_results)
        [ -n "$n" ] && [ "$n" != 0 ] && break
        sleep 0.25; i=$((i + 1))
    done
    report "the edge does not fire under it" 20 "$n"

    # The refusal. `o` re-fetches and rotates the sort on screen either way — what must not
    # happen is the WRITE, because the environment pins this key and the next startup would
    # read the file's value and throw it away. The notice names the key, which is what makes
    # this greppable in either chrome language.
    tmux send-keys -t "$TS" o
    said=0; i=0
    while [ $i -lt 60 ]; do
        tmux capture-pane -t "$TS" -p -J 2>/dev/null | grep -q 'UT_SORT_FIELD' && { said=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "a pinned key is refused out loud" 1 "$said"
    report "and never reaches the file" 0 "$(grep -c '^UT_SORT_FIELD' "$TUI_CFG")"
    # The notice holds the frame on a press-any-key; Space is inert here (there is no player
    # to pause), so it dismisses the notice without doing anything if the notice never came.
    tmux send-keys -t "$TS" Space
    sleep 0.5

    tmux send-keys -t "$TS" h
    opened=0; i=0
    while [ $i -lt 40 ]; do
        tmux capture-pane -t "$TS" -p 2>/dev/null | grep -q 'items=' && { opened=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "h opens the log as the rows" 1 "$opened"
    # Same witness the `q` check keeps, and for the same reason: the pane is the only place a
    # key that went somewhere else is legible. A reader that is not the menu loop
    # (press_any_key behind a notice, the `n` prompt) shows up here and nowhere else.
    if [ "$opened" != 1 ]; then
        echo "  ---- pane at the moment h did not open the log ----" >&2
        tmux capture-pane -t "$TS" -p -J >&2 2>/dev/null
        echo "  ---- end of pane ----" >&2
    fi
    # The toggle. A plain byte, so unlike the Esc this shipped as it needs no disambiguation
    # window — but the poll stays: a redraw is not instant either.
    tmux send-keys -t "$TS" h
    backed=0; i=0
    while [ $i -lt 40 ]; do
        pane=$(tmux capture-pane -t "$TS" -p 2>/dev/null)
        case "$pane" in
        *"items="*) ;;
        *"results="*) backed=1; break ;;
        esac
        sleep 0.25; i=$((i + 1))
    done
    report "h again leaves it for search" 1 "$backed"

    # `b` is the same door as `h`, but it has to ASK which room — and asking used to mean one
    # line of the store's own prose above a caret identical to the search prompt, with the
    # name typed from memory. It now prints the store NUMBERED, and the number is resolved in
    # the TUI so the store still only ever hears a name. Three claims, one sequence: the
    # picker lists what is stored, a digit opens THAT list (the header names it, so an
    # off-by-one is legible), and `b` again is still the way out.
    tmux send-keys -t "$TS" b
    picked=0; i=0
    while [ $i -lt 40 ]; do
        tmux capture-pane -t "$TS" -p -J 2>/dev/null | grep -q '1\. seeded-list' && { picked=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "b lists the stored playlists" 1 "$picked"
    if [ "$picked" != 1 ]; then
        echo "  ---- pane at the moment b did not list the store ----" >&2
        tmux capture-pane -t "$TS" -p -J >&2 2>/dev/null
        echo "  ---- end of pane ----" >&2
    fi
    # The digit, then Enter: prompt_name's reader ends on Enter like every other prompt here.
    tmux send-keys -t "$TS" 1
    tmux send-keys -t "$TS" Enter
    byname=0; i=0
    while [ $i -lt 40 ]; do
        tmux capture-pane -t "$TS" -p -J 2>/dev/null | grep -q "playlist='seeded-list'" && { byname=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "1 opens that playlist by number" 1 "$byname"
    tmux send-keys -t "$TS" b
    backed=0; i=0
    while [ $i -lt 40 ]; do
        pane=$(tmux capture-pane -t "$TS" -p 2>/dev/null)
        case "$pane" in
        *"items="*) ;;
        *"results="*) backed=1; break ;;
        esac
        sleep 0.25; i=$((i + 1))
    done
    report "b again leaves it for search" 1 "$backed"

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
    # A red here is TWO reds: the FLAGS line the next check reads is printed by the same
    # command line, after uting returns, so a TUI that did not leave takes the tty check down
    # with it. And the pane is the only witness there will ever be. `q` cannot be SLOW —
    # shell/uting:3485 prints and exits, and with no player the nav read blocks with no
    # timeout — so the byte was eaten by a reader that is not the menu loop (press_any_key,
    # the `n` prompt, the loading spinner's own `read -t 1`), and which one it was is legible
    # in the frame and nowhere else. Measured once, 2026-08-25, and unreproducible since.
    if [ "$left" != 1 ]; then
        echo "  ---- pane at the moment q was not honoured ----" >&2
        # `>&2` BEFORE `2>/dev/null`: the other order points stdout at stderr's CURRENT
        # target, which by then is /dev/null, and the dump silently prints nothing.
        tmux capture-pane -t "$TS" -p -J >&2 2>/dev/null
        echo "  ---- end of pane ----" >&2
    fi
    restored=0
    tui_flags=" $(tmux capture-pane -t "$TS" -p -J 2>/dev/null | grep -o 'FLAGS=.*' | head -1) "
    case "$tui_flags" in *" echo "*) case "$tui_flags" in *" icanon "*) restored=1 ;; esac ;; esac
    report "hands the tty back on exit" 1 "$restored"
    # The one place in this file where a PROCESS can outlive the run. Nothing above presses
    # Enter, so zero is the honest expectation — and on 2026-08-25 it was not what a machine
    # running this file got: a real player was up behind a red `q`, started from a URL off the
    # result list. The trap reaps it now whatever happens, which is why this is a check rather
    # than a silent stop: the reap makes the leak harmless, and only this line makes it VISIBLE.
    report "the TUI left no player behind" 0 \
        "$(shell/ut-play --status -j 2>/dev/null | jq '.players | length')"
    tmux kill-session -t "$TS" 2>/dev/null
    rm -rf "$TUI_STATE"
fi

report_real_config
report_real_state
summary
