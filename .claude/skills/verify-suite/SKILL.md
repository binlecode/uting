---
name: verify-suite
description: Run uting's regression sweep — the checks that stand in for a CI pipeline this repo deliberately does not have. Four phases, cheapest first: syntax under the bash 3.2 floor plus the shellcheck baseline, the CLI contract via tests/contract.sh, the TUI via tests/tui_pane.sh, and the detached-player lifecycle (audible, the one phase with no rig yet). Use before a push, before a YT_VERSION bump, and after any change to the core, a wrapper, or the renderer.
argument-hint: "[phase: syntax | contract | tui | lifecycle | all (default)]"
---

# verify-suite

There is no CI behind a push here, on purpose. This skill is what stands in its place.

**Two of the four phases are executable rigs, and this skill does not restate their commands.**
That is deliberate and it is the lesson `tests/contract.sh` records in its own header: this
skill used to carry the contract checks as prose for an agent to copy out by hand, and that
version rotted silently — it listed a resident socket server as a check (it hangs and asserts
nothing), asserted the same exit code twice, described a network path with no command behind
it, and had no `--transcript` coverage at all. **A check-list that cannot be executed reports
green by default.** So: new contract check goes *in the rig*, never in here as prose.

Phases are independent — `/verify-suite contract` runs one. Report per phase what ran, the
observed numbers, and PASS/FAIL. Never report a skipped phase as passed; say it was skipped.

## Phase 1 — Syntax on the floor, and the shellcheck baseline (seconds, no side effects)

```bash
/bin/bash -n shell/ut-play shell/yt-search shell/yt-play shell/yt-tui && echo "syntax OK"
```

`/bin/bash` explicitly, not `bash`: the floor is macOS's system 3.2 (`SPEC-system.md` §28) and
a Homebrew bash 5 on PATH parses things 3.2 rejects. Then the class `bash -n` cannot see —
runtime 3.2 behaviours — by driving the empty-argument paths, which `tests/contract.sh` also
covers in phase 2 (`yt no args`, `yt-search no args`).

The shellcheck baseline is a **tracked count, not a clean bill** (`ROADMAP.md` §6.1): 15
warnings — SC2128×5, SC2178×4, SC2034×3, SC2054×2, SC2174×1.

```bash
shellcheck --severity=warning --format=gcc shell/ut-play shell/yt-search shell/yt-play shell/yt-tui | wc -l
```

Count in `gcc` format; the human format repeats each code in a footer and inflates a naive
`grep -c` to 18. Above 15 means a new warning landed — fix it, or move the baseline
deliberately. The SC2128/SC2178 nine are **false positives** (a `local query=""` shadowing a
same-named global argv array; shellcheck does not track scope) and the stated remedy is a
rename to de-noise, never a logic change. The three SC2034s (`SCRIPT_DIR`, `C_YELLOW`,
`CURRENT_PLAY_URL`) are genuine one-sided-variable candidates — R1 in **audit-conformance**.

## Phase 2 — The CLI contract (network, no playback, no audio)

```bash
tests/contract.sh        # or: tests/contract.sh -q   (failures + summary only)
```

30 checks, exit 0 when every one holds: the search envelope's shape, **every documented
rejection in both spellings** (bare and after `--`), the argv-ordering rule, `--transcript`
both ways plus its no-captions error, the failure taxonomy (2 is a tool failure, never 1), the
idle lifecycle, one version across four entry points, and the non-TTY refusal.

It also asserts the **one-line rule** (`SPEC-system.md` §14): every `-j`/`-J` payload on stdout
is a single line. That class was broken in five places until 2026-08-22 — search `-j`/`-J`,
`--info -j`/`-J`, `--get-url -j`, and `--status`, the last compact only while the player list
was *empty*, i.e. pretty exactly when something is polling it. If you add an envelope, add its
`wc -l` check to the rig.

The summary line ends with a **known drift** count. A known drift is a check whose expected
value records what the code does today while a decision is pending; it does not fail the run.
Read it, don't ignore it — and when a drift is resolved, the fix is to change the rig's
expectation, not to leave a permanent exemption.

## Phase 3 — The TUI against a real terminal (silent — starts no playback)

```bash
tests/tui_pane.sh        # tmux is the terminal; needs tmux, starts no player
```

12 checks: layout at four geometries (layout is width-conditional, so one geometry proves
almost nothing), the `YT_ASCII=1` and `YT_LANG=zh` chrome variants, redraw-on-resize **with no
keypress**, and the in-place repaint (a keypress must emit zero screen-clears).

`tests/assert_pane.py` stays and is called by that rig: measuring a CJK glyph in **cells** is
the one thing shell cannot do. To capture a frame for a doc rather than a check, use the
**capture-pane** skill.

The two pty rigs this phase used to list (`tui_screen.py`, `pty_drive.py`) are **deleted**, not
demoted. `tui_pane.sh` covers what they proved and reaches what they could not: `tmux
capture-pane` is a real terminal's cell grid and `tmux pipe-pane` is its byte stream, so the
screen claims, the screen-clear count and the spinner's four turning quadrants are all here —
and the hand-rolled pty plus a `pyte` install are gone from a suite whose whole claim is that
it depends only on primitives everyone already has. The one thing they carried that needed a
player (`Starting` → `Playing` flipping on the tick) moved to phase 4's rig.

`mpv_ipc_mock.py` is a fixture, not a step: a resident peer that never closes its side, so
running it standalone hangs and asserts nothing. Point a change at it when you touch the IPC
reader, and say so when you didn't.

## Phase 4 — Detached-player lifecycle (STARTS REAL PLAYBACK — the one phase with no rig)

This is the coverage gap: phases 2 and 3 are executable, this one is still commands. Say what
it will do before running it, use `--volume 0` so it is silent, and do not call it passed until
`pgrep` is empty.

```bash
U1='https://www.youtube.com/watch?v=<id1>'; U2='https://www.youtube.com/watch?v=<id2>'
o1=$(shell/yt-play -d -j --volume 0 -- "$U1")     # must return in ~0.03s, not after mpv starts
echo "$o1" | jq -e '.id and .pid and .sock' >/dev/null; echo "detach envelope exit=$?"
o2=$(shell/yt-play -d -j --volume 0 -- "$U2")
id1=$(echo "$o1" | jq -r .id)

shell/yt-play --status -j | wc -l                  # 1 — the POPULATED envelope, only measurable here
shell/yt-play --status -j | jq '.players | length' # 2
shell/yt-play --set-volume 40 -j; echo "ambiguous exit=$? (want 4)"
shell/yt-play --set-volume 40 --id "$id1" -j; echo "targeted exit=$? (want 0, see below)"
shell/yt-play --stop --id "$id1" -j; echo "stop one exit=$? (want 0)"
shell/yt-play --stop --all -j;       echo "stop all exit=$? (want 0)"
pgrep -fl 'mpv .*--input-ipc-server' || echo "no orphan mpv — PASS"
```

**Do not write a property inside the start-up window.** `--set-volume --id` on a just-launched
player answers `{"status":"error","reason":"ipc_failed"}` with exit 4 until mpv is actually
listening — measured at t=3 s, then exit 0 from t=6 s on a cold URL. That is the taxonomy
working (4 = did not take effect), so a check that writes too early collects a false red. Poll
until exit 0 rather than sleeping a guess.

Two properties worth measuring while a player runs, both of which have regressed before:

- **Detach latency.** `time out=$(shell/yt-play -d -j -- URL)` returns in ~0.03 s. Slower means
  the title updater is holding the captured pipe.
- **Log growth.** the detached `mpv-<id>.log` stays ~59 bytes with **zero** growth while
  playing, and still records a real `ytdl_hook` ERROR when one occurs.

For anything timing-sensitive prefer a **local synthetic source** (`av://lavfi:sine`) over
YouTube — network throttling has corrupted a timing measurement here before (§25.1).

## Reporting

```
## verify-suite — <date>

Phase 1 syntax      PASS (4 scripts under /bin/bash; shellcheck 15 = baseline)
Phase 2 contract    PASS (tests/contract.sh: 30 ok, 0 failed, 0 known drift)
Phase 3 tui         PASS (tests/tui_pane.sh: 12 ok, 0 failed)
Phase 4 lifecycle   SKIPPED (starts playback — not run)

Findings for audit-conformance: none
```

A FAIL is a finding, not a reason to adjust the check. If a documented behaviour and the code
disagree, report both values and say which one you believe is wrong — that call belongs to
whoever owns the contract.
