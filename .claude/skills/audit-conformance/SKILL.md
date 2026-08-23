---
name: audit-conformance
description: Periodic whole-suite audit of uting against the coding rules baked into this skill — surface layering (no YouTube logic in the TUI), DRY across the four scripts, bash 3.2 portability, dead functions and one-sided variables, swallowed errors, contract drift in the JSON envelope / exit codes, and doc drift against docs/SPEC-system.md. Inventories every violation with file:line + rule citation, then writes a scoped cleanup report. The whole-tree counterpart to reviewing a single diff. Never proposes structural or guard tests.
argument-hint: "[file-or-surface scope, default all of shell/]"
---

# audit-conformance

**Invocation:** `/audit-conformance [scope]` (default scope: all four scripts in `shell/`)

**Mission:** reviewing a diff catches what a *change* introduces; it is structurally blind to
slow accretion. This skill is the other scope: judgment-scan the whole suite against the rules
**defined in this file**, inventory every violation with `file:line` + the rule cited, and
write a scoped cleanup report.

**Why this exists here specifically.** uting has no linter, no type checker, no CI, and a
1.7k-line core plus a 2.8k-line TUI written to a frozen bash 3.2 floor. Nothing but judgment
defends its invariants, and three of them erode silently: logic creeping *up* into the TUI, a
bash-4 idiom slipping in (it runs fine on the author's shell and aborts under `/bin/bash`), and
`docs/SPEC-system.md` drifting away from the code it claims to describe. Those are the accretion
classes this skill owns.

**This skill is self-contained.** Every rule is defined below. It cross-references `CLAUDE.md`
for two project facts it must honor — the bash 3.2 floor and the rigs-only testing mandate —
and both are restated inline where they matter.

**Hard doctrine — read before producing output:**
- **Never propose a guard test, fitness function, or "conformance test."** `CLAUDE.md` mandates
  rigs that drive a *real* surface (a pty, a socket, a real envelope). A structural test that
  greps the source for a forbidden idiom passes against a gutted script and is itself a
  violation. Eliminating a class structurally — move the shared helper down into the core so
  the duplicate cannot exist — beats detecting it. The pre-commit hook already gates the two
  classes that *are* mechanically decidable (secrets, bash-4 idioms); do not propose a second
  detector for them.
- **Ground every finding in a read.** Each row cites `file:line` and the exact rule (Rn). A
  grep hit is a candidate, never a finding. No "looks like" rows.
- **Verify contract claims by running the command**, not by reading the emitter. R8 findings in
  particular (single-line JSON, exit codes) are cheap to execute and easy to mis-read.
- **This skill does not edit code.** It produces an inventory + a cleanup report.

**Produces:** `docs/PLAN-conformance-YYYY-MM-DD.md` + a terminal summary. Scratch scripts go in
`tmp/` (create it if absent) — never the repo root, never `tests/`.

---

## The rule set (complete, self-contained)

| # | Rule | What it means | Primary detector |
|---|------|---------------|------------------|
| R1 | **One-sided variable / flag** | A variable, flag, or env knob with only a write site or only a read site. A parsed flag that nothing consumes, an exported `YT_*` nothing reads, a state var set and never tested. | grep the bare name **and** the `${…}` form **and** `"$name"`; one side missing = candidate. Beware indirection: a var read only inside a `jq --arg`, a heredoc, or an `eval`-shaped string won't show in a bare-word grep — that is this rule's #1 false positive. |
| R2 | **Redundant same-lifecycle state** | Two variables always assigned together and cleared together (e.g. a `CURRENT_PLAY_*` pair, a "have we drawn" flag beside the value it guards) — one concept wearing two names. | read the mutation sites; look for co-set / co-cleared pairs. |
| R3 | **Logic in the wrong surface (layer back-edge)** | Two hard layering rules now. (a) **`yt-tui` contains ZERO site logic and ZERO playback logic** — it shapes argv for `yt-search` / `ut-play` and delegates; a `yt-dlp` or `mpv` invocation or an IPC command construction there is a back-edge (reading the mpv socket through the *documented* envelope field is not). (b) **player and engine do not trade knowledge**: a `yt-dlp` call, a cookie decision, a format string, or a URL pattern in `shell/ut-play` is a back-edge, and so is an `mpv` call or any player-state / `players/` write in `yt-search` / `yt-resolve`. | `grep -n 'yt-dlp\|cookies-from-browser' shell/ut-play shell/yt-tui` and `grep -n 'mpv \|--input-ipc-server\|players/' shell/yt-search shell/yt-resolve` must both be empty apart from dependency-check strings and comments — read each hit. |
| R4 | **Duplication (DRY)** | Three carve-outs first, all deliberate: (a) each script must run standalone, so `die` / `print_usage` / `require_cmd` living in more than one file is **not** a finding; (b) the engine pair each holding its own cookie block and jq prelude is **not** a finding either — they are separate executables and the alternative is a shared library the split exists to avoid (a duplicate spanning *player* and *engine*, however, IS a finding: that is a boundary leak); (c) the player's IPC property reader and `yt-tui`'s are intentionally separate and must not call each other — the TUI's is fire-and-forget, the core's confirms delivery and exits 4 (`PLAN-envelope-observability.md` §3). Otherwise: the same logic in ≥2 homes: a second duration formatter beside the core's `JQ_PRELUDE` `fmt_dur`, a re-implemented width/cell measurement, a copied jq filter, the same validation in a wrapper and the core. The governing principle is that correctness is added *down* in the core so every surface inherits it. | the function graph (Pass 0) for same-named or near-identical bodies across files; grep for duplicated jq programs and `printf` format strings. |
| R5 | **bash 3.2 violation** | `declare -A`, `mapfile`/`readarray`, `${var,,}`/`${var^^}`, `${arr[-1]}`, `&>>`, `\|&`, `${!prefix@}`; an unguarded `"${arr[@]}"` on a possibly-empty array under `set -u`; a bare `((n += w))` **as a statement** under `set -e`; treating `read -rsn1` as one character rather than one byte; `LC_ALL=C [[ … ]]` (not valid bash at all). | the forbidden-idiom greps below, then **read** each array expansion and each `((…))` to classify statement vs test. The pre-commit hook blocks these on *added* lines; this rule sweeps what predates the hook. |
| R6 | **Swallowed error** | `\|\| true`, `2>/dev/null`, or an empty branch on a path where the user must see the failure — a real fault rendered as an empty list, a `0`, or a blank field. A *deliberate* best-effort degrade is fine **if** it degrades visibly (`--:--`, `n/a`, `LIVE`) and never as a fake value. | `grep -n '|| true\|2>/dev/null' shell/*` then read every hit and ask what the user sees when it fires. |
| R7 | **Optimistic state** | State written before the operation it asserts has committed: a player record or a "playing" flag persisted before mpv is confirmed launched, a lock recorded before it is held, `TTY_ECHO_OFF=1` set before `stty` succeeded. A failure mid-op then leaves a lying record. | read the order of the write vs the op, in `detach_play`, the lock helpers, and the echo/cursor traps. |
| R8 | **Contract drift** | The frozen surface (`CLAUDE.md`): `-j` emits **one line**; the envelope's field names; the exit-code taxonomy (0 ok · 1 usage/validation · 2+ propagated tool failure · 4 didn't take effect); lifecycle semantics (idempotent stop, ambiguity → 4). Any deviation, in either direction — code that violates the doc, or a doc that overstates the code. | **run the command.** `shell/yt-search -j -n 2 -- lofi \| wc -l` must be 1. Check each documented rejection actually rejects, including via `--`. Compare against `docs/SPEC-system.md` §14/§15. |
| R9 | **Naming drift** | Env knobs missing the `YT_` prefix; a unit-less numeric where the codebase suffixes (`_s`, `_ms`, `_pct`); a deprecated short alias (`yts`/`ytp`) used anywhere at all, or `ytt` used where the canonical `yt-tui` belongs (one name per command — `CLAUDE.md`); a new envelope field whose name doesn't match its siblings' style. | grep the env-read sites against §16's documented list; scan user-visible strings for the wrong name form. |
| R10 | **Dead code** | A function with zero call sites (across all four scripts and the rigs); a `case` arm for a flag no usage text mentions and nothing emits; an env knob read nowhere; a code path reachable only through a removed flag. | the function graph (Pass 0): defs minus call sites. Confirm by reading — a function called only from a heredoc or a `trap` string looks dead to a grep. |
| R11 | **Doc drift** | `docs/SPEC-system.md` is the single home of each fact and it is the *spec*: §15 exit codes, §16 config surface, §17 function map, §14 data contracts, §27 verification matrix. A function map missing a function, a config table missing a knob, a §27 entry citing a **scratch** rig by path (a `tmp/` path is a promise the checkout can't keep; the four committed `tests/` rigs are the stated exception and SHOULD be named), or a fact restated in the README *and* the design doc so the two can disagree. | diff the function graph against §17; diff the `YT_*` read sites against §16; diff observed exit codes against §15; grep §27 for `tmp/` paths (a `tests/` path there is correct, not a finding). |
| R12 | **Terminal-ownership violation (yt-tui only)** | The TUI owns the whole screen: every drawn line goes through the measured-width layer (`char_w`/`wrap_print` and friends) so a CJK or math-bold glyph is counted in cells; echo and the cursor are owned for the session and restored from the **same** trap; a redraw is a whole frame, never a partial that leaves a stale row. A raw `printf`/`echo` of variable-width content, or a `stty` restore that isn't in the trap, is a violation. | grep `printf\|echo` in `shell/yt-tui` for lines carrying interpolated title/channel text; read the trap. |

### The suite's layer order (for R3 / R4)

```
  primitives     yt-dlp · curl (engines only)   ·   mpv · nc (player only)   ·   jq (all)
        ↑                                            ↑
  engine pair    shell/yt-search · shell/yt-resolve   shell/ut-play        (player)
                 (every site-specific fact)           (playback + lifecycle; asks an
        ↑                                              engine BY NAME, never a site)
        └───────────────┬──────────────────────────────────┘
                        ↑
  human surface  shell/yt-tui                    (orchestration only; calls the verbs)
```

Every arrow points **up**. A violation is any downward reach that skips a layer: the TUI
touching a primitive, a wrapper implementing a decision, the core knowing anything about the
TUI. The core may not read a `YT_TUI_*`-shaped knob; the TUI may not construct yt-dlp argv.

---

## Pass 0 — Scope, function graph, cheap sweeps

1. **Resolve scope** from `$ARGUMENTS` (default all of `shell/`). State it in the summary. For
   a narrow scope (say `shell/yt-tui`) still build the whole graph, so cross-file edges into
   the scope stay visible.

2. **Pick up any open report:** `ls docs/PLAN-conformance-*.md`. If a recent one is
   unaddressed, read it and fold new findings in — do not re-list tracked violations as new.

3. **Build the function graph.** `fn_graph.py` (next to this file) lists every function
   with its definition site(s) and its call sites across all four scripts:

   ```bash
   mkdir -p tmp
   python3 .claude/skills/audit-conformance/fn_graph.py > tmp/fns.txt
   awk -F'\t' '$4 ~ /DEAD/' tmp/fns.txt      # R10 candidates
   awk -F'\t' '$4 ~ /DUP/'  tmp/fns.txt      # R4 candidates — same name in two files
   ```

   Both columns are **candidates**. A function invoked from a `trap` string, a heredoc, or a
   name assembled at runtime reads as DEAD; confirm every one by reading before proposing a
   delete. The script is a manual aid and must never become a gate or a `tests/` member —
   it over-flags by construction, which is precisely what a structural test must not do.

4. **Cheap sweeps** — each one seeds candidates that Pass 1 confirms by reading:

   ```bash
   # R3 back-edges: these MUST be empty apart from dep-check strings and comments
   grep -n 'yt-dlp\|mpv \|--input-ipc-server' shell/yt-tui
   grep -n 'yt-dlp\|cookies-from-browser' shell/ut-play
   grep -n 'mpv \|--input-ipc-server\|players/' shell/yt-search shell/yt-resolve

   # R5 bash-4 leaks (the hook gates added lines; this catches what predates it)
   grep -nE 'declare -A|mapfile|readarray|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)|&>>|\|&|\[-1\]' shell/*
   grep -nE '^\s*\(\([^)]*[-+*/]?=' shell/*        # (( )) as a STATEMENT under set -e — read each
   grep -n '"\${[A-Za-z_][A-Za-z0-9_]*\[@\]}"' shell/*   # unguarded empty-array expansion

   # R6 swallowed errors
   grep -n '|| true\|2>/dev/null' shell/*

   # R9/R11 config surface: every YT_* read site, to diff against SPEC-system.md §16
   grep -ohE 'YT_[A-Z_]+' shell/* | sort -u

   # R11 §27 must cite no rig by path
   sed -n '/## 27. Verification matrix/,/## 28/p' docs/SPEC-system.md | grep -n 'tmp/\|tests/'
   ```

5. **Run the contract, don't read it** (R8). These are seconds each and settle the class:

   ```bash
   shell/yt-search -j -n 2 -- lofi | wc -l          # the -j single-line guarantee: must be 1
   shell/ut-play --status -j; echo "exit=$?"        # 0 + {"status":"players",...}
   shell/ut-play --stop --all -j; echo "exit=$?"    # 0, idempotent
   shell/yt-search --detach -- x; echo "exit=$?"    # 1 (gating)
   shell/ut-play "a query"; echo "exit=$?"          # 1 (a query is not a handle)
   shell/ut-play -- "a query"; echo "exit=$?"       # ALSO must be 1 — check the -- path too
   shell/ut-play --info -- ID; echo "exit=$?"       # 1 (an engine verb, named as such)
   shell/ut-play >/dev/null; echo "exit=$?"              # 1 (no handle, no action)
   shell/yt-tui </dev/null >/dev/null; echo "exit=$?"  # 1 (non-TTY refusal)
   ```

   Do not start a detached player as part of an audit — that is audible playback on someone's
   machine. Lifecycle claims belong to the **verify-suite** skill, run deliberately.

---

## Pass 1 — Rule-class audit

Read-only. The suite is four files; a single careful sweep by the orchestrator is usually
right. For a full periodic audit, fan out to read-only subagents (`Read, Grep, Bash`; no
Edit/Write) grouped by rule cluster so each holds one mental model:

- **A — layering & surfaces:** R3, R4, R12.
- **B — subtraction:** R1, R2, R10.
- **C — portability & failure:** R5, R6, R7.
- **D — contract & docs:** R8, R9, R11.

Each pass returns **only** a table — no narrative, no fixes:

| rule | file:line | what (the offending symbol / line) | evidence (a read or a command's output) | proposed source fix |
|------|-----------|-------------------------------------|------------------------------------------|---------------------|

R1/R10 systematically **over-flag** (indirect reads, heredocs, trap strings). R2/R4/R12 **under-flag**
(judgment-heavy). R8 is the one class where the evidence must be a command's actual output.
Treat every DELETE proposal as a candidate to re-confirm.

---

## Pass 2 — Dedup, prioritize, write the report

The orchestrator does this, so source-verification stays in one place.

1. **Merge + dedup.** One physical violation = one row, even when it trips two rules (note
   both). **Dead (R10) dominates:** before proposing a lifecycle fix for an R6/R7 row, count
   the callers — zero reclassifies it to R10 and deletion supersedes the remedy.

2. **Re-verify every row against source, and blind-re-read every DELETE.** Re-read the cited
   symbol with the verdict set aside, hunting for any caller, trap, heredoc, or rig reference
   that disqualifies "dead". Only survivors enter the report.

3. **Prioritize.**
   - **Recurrence class first.** A class that recurs (three back-edges, four duplicated
     formatters) beats any single severe row: fixing it structurally prevents the family.
     Cross-check `git log` for the same fix repeating.
   - **Then severity:** R3/R4 layering and R8 contract drift over R9 naming.
   - **Cap the action plan at one coherent theme.** Everything else goes to a
     `## Deferred backlog` section with counts. An unscoped 40-item plan never ships.

4. **Write `docs/PLAN-conformance-YYYY-MM-DD.md`** from the template below. Each task names
   the rule + `file:line`, states a **structural** fix (move down into the core / collapse /
   delete / rename), and gives a `done_when` that is observable — *"`shell/yt-search -j` emits
   one line and `grep yt-dlp shell/yt-tui` is empty"* — **never** "a guard test passes".

5. **If a deletion would orphan a helper**, chain it into the same task.

6. **A doc-drift row (R11) is fixed in the doc, not in the code** — unless the code is what is
   wrong, in which case say which one you are proposing to move and why.

---

## Report template

```markdown
# TODO — conformance audit (uting) · <date>

Scope: <path>   ·   Functions graphed: N   ·   Prior report folded: <file|none>

## Inventory (read-confirmed)

| rule | file:line | what | fix |
|------|-----------|------|-----|
| R3 | shell/yt-tui:NNN | … | move … down into shell/ut-play |

## This round — <one coherent theme>

- [ ] **<rule> <file:line>** — <structural fix>. done_when: <observable>.

## Deferred backlog

- R9 naming drift: N · R10 dead code: N · …
```

---

## Terminal summary

No PASS/FAIL — the output is an inventory plus a report to act on.

```
## audit-conformance — <date>

Scope: <path>            Functions graphed: N
Violations: N read-confirmed (M grep candidates dropped on read)
  R1 one-sided var:            N
  R2 redundant state:          N
  R3 wrong surface / back-edge:N   ← [list]
  R4 duplication:              N   ← [list]
  R5 bash 3.2 violation:       N
  R6 swallowed error:          N
  R7 optimistic state:         N
  R8 contract drift:           N   ← [command + observed vs documented]
  R9 naming drift:             N
  R10 dead code:               N
  R11 doc drift:               N
  R12 terminal ownership:      N

Recurring classes (git-log corroborated): [class — count]
Plan this round: <theme> — K tasks
Deferred: N
Report: docs/PLAN-conformance-<date>.md
```

**Cadence:** periodic, not per-commit — the residue accumulates between runs by design. Good
triggers: `git log` shows the same cleanup repeating, before making the repo public, before a
`YT_VERSION` bump, or after any change that touched two surfaces at once.
