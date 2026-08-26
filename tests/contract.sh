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
# Cost: ~80s and the network (seven runs on 2026-08-25: 77/80/81/82/82/94/109s). CLAUDE.md asks for this
# file before every commit, so the number belongs at the door: roughly 15 live engine round
# trips, one 5s lock spin the stale-lock check has to sit through, and ~25s of tmux bringing
# the TUI up. The OFFLINE half runs first, so a broken gate is red in about two seconds and
# the network is not touched for 22 — see the section-order contract below. It starts no
# process it did not have to and talks to no peer — every live claim is tests/playback.sh's.
# The TUI section is the near-exception and is held to the same line: the process there is a
# real `uting` on a real tty, it is CHECKED to leave no player behind, and the EXIT trap reaps
# one if it ever does.
#
# Usage:  tests/contract.sh            all checks
# Exit:   0 = every check held, 1 = at least one regression

set -uo pipefail
cd "$(cd -P "$(dirname "$0")/.." && pwd -P)" || exit 1

# ---- the player's state dir, pointed somewhere disposable ---------------------------
# THE ARGUMENT FOR THIS LIVES HERE, and the other two files under tests/ point at it rather
# than restating it (docs/ARCHITECTURE.md §27 is the doc-level home of the same fact).
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

# ---- the offline half, FIRST -------------------------------------------------------
# Everything below this line to the live-fixture preamble runs without a network: flag gates,
# the idle lifecycle, the death-record fixtures, the two halves of the user-level store, and
# --version. It used to sit AFTER ~15 live engine round trips, so the most common regression of
# all — a gate or an envelope broken by the edit you are about to commit — cost 80 seconds to
# see. Measured after the move (2026-08-25): the gates are red at 1s, the idle lifecycle at 1s,
# the death record at 2s, and the whole offline half is done at 22s, the first network call not
# starting until then. The 19s inside it are the playlist store's — a deliberate 5s lock spin
# plus eight concurrent writers — so a gate regression is still seen in about two seconds.
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
# like too (docs/ARCHITECTURE.md §9.2). These checks own the boundary that keeps the tombstone
# list an error record rather than the listening history ROADMAP.md §0 rules out — a normal
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
# deleted before the assertion that reads it — the failure docs/ARCHITECTURE.md §27 already
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
# added. Costs the 5s spin once.
mkdir -p "$UT_STATE_DIR/playlists/.lock-race"
report "a held lock: 4, not 1"          4 "$(printf '[{"engine":"yt","url":"https://x/z"}]' | $PL --add race >/dev/null 2>&1; echo $?)"
report "…with reason locked"            0 "$(jq_in '.reason=="locked"' '[{"engine":"yt","url":"https://x/z"}]' $PL --add race -j)"
# A lock left by a SIGKILLed writer must not wedge a playlist forever.
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
# install (ROADMAP D1/D2: users symlink these onto their own PATH) and the configuration this
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

# A short, permanent, caption-bearing public video: the one handle every engine-contract
# check below resolves. Chosen for being 19 seconds long — nothing here plays it, but a
# resolve that accidentally starts a download costs a second rather than a minute.
MEDIA_ID="jNQXAC9IVRw"

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
NOCAP=$(shell/yt-resolve --transcript -j -- "$BARE" 2>/dev/null); NOCAP_ST=$?
report "no captions -> error"     0 \
    "$(jqv '.status=="error" and .reason=="no_subtitles_available"' "$NOCAP")"
report "no captions exit"         1 "$NOCAP_ST"

echo "── the second engine: the same envelope, or the split is a fiction ─"
# A permanent, single-part music video on the second site. Single-part matters: a handle
# that is a 50-track collection resolves to part one, which is correct but makes a title
# assertion depend on which part that is.
BILI_ID="BV1mL411E7Fb"

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
# Titles arrive as search-result HTML (<em class="keyword">) and entity-escaped. Markup that
# survives into a title is counted by the width layer, which reflows every row wrongly.
report "bili titles carry no markup" 0 \
    "$(jq_ok '[.results[].title]|all((test("<") or test("&[a-z#]+;"))|not)' shell/bili-search -j -n 10 -- 周杰伦)"

report "bili-resolve rejects a non-id" 1 "$(rc shell/bili-resolve -j -- "not an id")"
# This site's CDN checks Referer: the bare stream URL answers 403 and the same URL with
# these headers answers 206 (measured). An empty http_headers here is a silently unplayable
# engine, which is exactly the contract hole the key was added to close.
report "bili resolve sends a Referer" 0 \
    "$(jqv '.http_headers|has("Referer")' "$BILI_R")"
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
    TUI_CMD="cd '$PWD' && env YT_SYNC=0 TMPDIR='$TMPDIR' UT_STATE_DIR='$TUI_STATE' shell/uting 'lofi hip hop'"
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

    # A store is a room with a door, not a one-way trip. `h` REPLACES the rows with the log
    # (`items=` in the header, where a search says `results=`) and `Esc` puts the search back
    # — and until it did, the only exits from that room were retyping a query and quitting.
    # Both halves are asserted: an `h` that quietly did nothing would leave the search on
    # screen and make the return leg pass for free.
    tmux resize-window -t "$TS" -x 100 -y 30 2>/dev/null
    tmux send-keys -t "$TS" h
    opened=0; i=0
    while [ $i -lt 40 ]; do
        tmux capture-pane -t "$TS" -p 2>/dev/null | grep -q 'items=' && { opened=1; break; }
        sleep 0.25; i=$((i + 1))
    done
    report "h opens the log as the rows" 1 "$opened"
    # Esc is read on a 1s timeout (it is also the lead byte of every arrow key), so this waits
    # rather than photographs.
    tmux send-keys -t "$TS" Escape
    backed=0; i=0
    while [ $i -lt 40 ]; do
        pane=$(tmux capture-pane -t "$TS" -p 2>/dev/null)
        case "$pane" in
        *"items="*) ;;
        *"results="*) backed=1; break ;;
        esac
        sleep 0.25; i=$((i + 1))
    done
    report "Esc leaves it for the search" 1 "$backed"

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

echo
printf '%s: %d ok, %d failed\n' "$(basename "$0")" "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
    printf 'regressions:\n%s' "$FAILED"
    exit 1
fi
exit 0
