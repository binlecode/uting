---
name: verify-suite
description: Run uting's hand-driven regression sweep — the checks that stand in for a CI pipeline this repo deliberately does not have. Four phases, cheapest first: syntax under the bash 3.2 floor, the headless contract (envelope shape, gating rejections, exit codes), the pty/pane rigs, and the detached-player lifecycle (audible, run deliberately). Use before a push, before a YT_VERSION bump, and after any change to the core, a wrapper, or the renderer.
argument-hint: "[phase: syntax | contract | rigs | lifecycle | all (default)]"
---

# verify-suite

There is no CI behind a push here, on purpose. This skill is what stands in its place: the
sweep in `CLAUDE.md`'s "minimum checks", made executable, in cheapest-first order so a failure
surfaces before an expensive phase runs.

Phases are independent — `/verify-suite contract` runs one. Default is all four, but **phase 4
starts real, audible playback**, so read its preamble before running it on someone's machine.

Report per phase: what ran, what the observed value was, and PASS/FAIL. Never report a phase as
passed because it was skipped — say it was skipped.

## Phase 1 — Syntax, on the floor (seconds, no side effects)

```bash
/bin/bash -n shell/yt shell/yt-search shell/yt-play shell/yt-tui && echo "syntax OK"
```

`/bin/bash` explicitly, not `bash`: the floor is macOS's system 3.2 (`docs/DESIGN.md` §28), and
a Homebrew bash 5 on PATH will happily parse things 3.2 rejects. Then the class `bash -n`
cannot see — runtime 3.2 behaviors — by exercising the empty-argument and empty-array paths:

```bash
/bin/bash shell/yt >/dev/null 2>&1;            echo "no-args exit=$? (want 1)"
/bin/bash shell/yt-search >/dev/null 2>&1;     echo "no-args exit=$? (want 1)"
/bin/bash shell/yt-play --status -j >/dev/null; echo "status exit=$? (want 0)"
```

The pre-commit hook gates bash-4 idioms on added lines; this phase catches what a
`--no-verify` or a pre-hook commit let through.

## Phase 2 — The headless contract (network, no playback, no audio)

Every row below is the actual observed behavior of the suite. Run the command, compare, and
report the mismatch rather than the intent.

```bash
shell/yt-search -j -n 3 -- lofi | jq -e '.query and .count and (.results|length==3)' >/dev/null
echo "search envelope exit=$? (want 0)"
shell/yt-search -j -n 2 -- lofi | wc -l        # README claims ONE line — see note below
shell/yt-search -J -n 2 -- lofi | jq -e '.results[0]|has("id")' >/dev/null; echo "full exit=$?"

# gating (each must be exit 1, with a message naming the other verb)
shell/yt-search --detach -- x  >/dev/null 2>&1; echo "yts --detach exit=$? (want 1)"
shell/yt-search -f audio -- x  >/dev/null 2>&1; echo "yts -f exit=$? (want 1)"
shell/yt-play "a query"        >/dev/null 2>&1; echo "ytp bare query exit=$? (want 1)"
shell/yt-play -- "a query"     >/dev/null 2>&1; echo "ytp -- query exit=$? (want 1)"
shell/yt-play -n 5 -- URL      >/dev/null 2>&1; echo "ytp -n exit=$? (want 1)"

# argv ordering: a flag-shaped query after -- is SEARCHED, never interpreted
shell/yt -l -- --status | head -2                # must be search output, not a player list

# conflicting actions and misplaced selectors (all exit 1)
shell/yt-play --status --stop      >/dev/null 2>&1; echo "conflict exit=$? (want 1)"
shell/yt-play --status --id X      >/dev/null 2>&1; echo "selector exit=$? (want 1)"
shell/yt-play -d --stop            >/dev/null 2>&1; echo "-d+action exit=$? (want 1)"

# idle lifecycle: both exit 0, both emit ONE compact line
shell/yt-play --status -j; echo "exit=$? (want 0)"        # {"status":"players","players":[]}
shell/yt-play --stop --all -j; echo "exit=$? (want 0)"    # idempotent

# version, before any dependency gate
for c in yt yt-search yt-play yt-tui; do shell/$c --version; done   # all one number

# non-TTY refusal
shell/yt-tui </dev/null >/dev/null 2>&1; echo "non-tty exit=$? (want 1)"
```

**Known drift as of the last sweep — verify, don't assume it is fixed:** `shell/yt-search -j`
pretty-prints (26 lines for `-n 3`) while `--status`/`--stop`/`--set-volume` emit one compact
line, and `shell/yt-play -- "<query>"` reaches the core and *searches* instead of being
rejected as a non-URL the way `shell/yt-play "<query>"` correctly is. Both are contract
findings (R8 in **audit-conformance**), not phase failures to paper over — report the observed
numbers.

A search failure must surface as `{"status":"error",…,"reason":"network"}` with exit 2 under
`-j`, and as stderr prose with a die under the default output — exit 2, never 1, so a tool
failure is never confused with a usage error.

## Phase 3 — The pty and pane rigs (needs a TTY-capable environment + pyte)

```bash
python3 tests/tui_screen.py     # screen-model claims: one-row repaint, zero ED sequences
python3 tests/pty_drive.py      # stream + timing: spinner frames, Starting→Playing, the 1 s tick
python3 tests/mpv_ipc_mock.py --reverse   # out-of-order replies (drive the reader against it)
```

Then the pane invariants, at more than one width — layout here is width-conditional, so a
single geometry proves almost nothing. Capture through the **capture-pane** skill (it blocks a
mid-fetch frame), then:

```bash
python3 tests/assert_pane.py tmp/pane-100.txt 100 list
python3 tests/assert_pane.py tmp/pane-62.txt   62 list    # the reflow floor: details block DROPS
python3 tests/assert_pane.py tmp/card-100.txt 100 card
```

Add the chrome variants when the renderer changed: `YT_ASCII=1` (a rendered pane holds no
non-ASCII beyond the title text), `YT_LANG=zh` (no English literal leaks), and a theme under
`COLORTERM=truecolor`.

## Phase 4 — Detached-player lifecycle (STARTS REAL AUDIBLE PLAYBACK)

Say what this phase will do before running it, and run it deliberately. Every player it starts
must be stopped by the end, and the phase does not pass until `pgrep` is empty.

```bash
URL1="https://www.youtube.com/watch?v=<id1>"; URL2="https://www.youtube.com/watch?v=<id2>"

out1=$(shell/yt-play -d -j --volume 0 -- "$URL1")   # must return in ~0.03s, not after mpv starts
echo "$out1" | jq -e '.id and .pid and .sock' >/dev/null; echo "detach envelope exit=$?"
out2=$(shell/yt-play -d -j --volume 0 -- "$URL2")

shell/yt-play --status -j | jq '.players | length'          # want 2
id1=$(echo "$out1" | jq -r .id)

shell/yt-play --set-volume 40 -j                            # ambiguous, no --id → exit 4
echo "ambiguous exit=$? (want 4)"
shell/yt-play --set-volume 40 --id "$id1" -j; echo "targeted exit=$? (want 0)"
shell/yt-play --status -j | jq -r '.players[] | "\(.id) \(.volume)"'   # only id1 moved

shell/yt-play --stop --id "$id1" -j; echo "stop one exit=$? (want 0)"
shell/yt-play --stop --all -j;       echo "stop all exit=$? (want 0)"
shell/yt-play --status -j                                   # players: []

# the gate this phase exists for
pgrep -fl 'mpv .*--input-ipc-server' || echo "no orphan mpv — PASS"
ls "${XDG_STATE_HOME:-$HOME/.local/state}"/yt/players/ 2>/dev/null   # only <id>.json, no bare token
```

Two properties worth measuring while a player runs, both of which have regressed before:

- **Detach latency.** `time out=$(shell/yt-play -d -j -- URL)` returns in ~0.03 s. A slow return
  means the title updater is holding the captured pipe.
- **Log growth.** the detached `mpv-<id>.log` stays ~59 bytes with **zero** growth while
  playing, and still records a real `ytdl_hook` ERROR when one occurs.

For anything timing-sensitive, drive a **local synthetic source** (`av://lavfi:sine`) rather
than YouTube — network throttling has corrupted a timing measurement here before
(`docs/DESIGN.md` §25.1).

## Reporting

```
## verify-suite — <date>

Phase 1 syntax      PASS (4 scripts, /bin/bash 3.2)
Phase 2 contract    FAIL — search -j emitted 26 lines (want 1); ytp -- "<query>" exit 0 (want 1)
Phase 3 rigs        PASS (tui_screen, pty_drive; assert_pane at 100/62 list + 100 card)
Phase 4 lifecycle   SKIPPED (audible playback — not run)

Findings for audit-conformance: R8 ×2 (both above)
```

A FAIL is a finding, not a reason to adjust the check. If a documented behavior and the code
disagree, report both values and say which one you believe is wrong — that decision belongs to
whoever owns the contract.
