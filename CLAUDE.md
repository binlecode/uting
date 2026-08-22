# CLAUDE.md

This file is the single source of truth for repository guidelines, used by Claude Code and all AI coding agents.

## Project Overview

**uting** (u-ting / 你听) — an agent-first YouTube engine with a terminal face. A four-script bash suite: search YouTube through `yt-dlp`, play it through `mpv` detached from the terminal, and keep controlling it — from a TUI if you are a human, from a single-line JSON contract if you are a program.

The suite is exposed **directly** to shell-capable agents with no MCP wrapper, so the **CLI contract itself** (argv, exit codes, output shape, process lifecycle) *is* the product and the safety boundary. Every design choice follows from that. Full rationale: `docs/DESIGN.md`.

**Status: reference implementation.** Not packaged — no installer, no Homebrew formula, and none planned for the shell version (`docs/ROADMAP.md` D1/D2). Users symlink `yts`/`ytp`/`ytt` onto their own PATH.

## Runtime Environment (Required)

- **bash 3.2** — macOS's frozen system `/bin/bash`. This is a deliberate floor, not an accident: zero install step, identical behavior under macOS, Linux, containers, CI, and cron/launchd. Do **not** raise it, and do **not** hardcode a Homebrew bash path. See the portability contract below — it is a hard rule.
- Runtime deps, all external and unvendored: `yt-dlp`, `jq`, `mpv`, `nc` (BSD netcat, stock on macOS). `curl` is an optional soft dep for the play-time client probe.
- **macOS first.** Linux is not currently usable: stock netcat has no `-U`, which the mpv IPC path needs. Do not "fix" Linux support by adding a dependency — that decision is gated in `docs/ROADMAP.md` §9.
- Verification rigs need `python3` and, for `tests/tui_screen.py`, `pyte` (`pip install pyte`). Nothing in `tests/` is needed at runtime.
- There is **no** build step, no venv, no lockfile, and no CI. The checks below are run by hand — that is the whole reason they are written out — with two of them gated locally by git hooks:

```sh
git config core.hooksPath .githooks   # RUN ONCE PER CLONE — fresh clones have no hooks
```

`.githooks/pre-commit` blocks a staged secret / cookie export, a **bash-4 idiom on an added line**, a staged shell script that does not parse under `/bin/bash -n`, and a force-added `tmp/` file. `.githooks/pre-push` blocks a force-push or deletion of `main` and a syntax error in any of the four scripts, and warns when a `v*` tag is pushed (the tag must match `YT_VERSION`). A direct push to `main` is **not** blocked — see the commit guidelines.

## Build, Test, and Development Commands

```sh
bash -n shell/yt shell/yt-search shell/yt-play shell/yt-tui   # syntax check — run before EVERY commit
/bin/bash shell/yt-search -j -n 5 -- "lofi hip hop"           # exercise on the 3.2 floor, explicitly
shell/yt-tui "lofi hip hop"                                   # interactive; needs a real TTY on stdin AND stdout
shell/yt --help                                               # core help (core is internal, not on PATH)
shell/yt-tui --version                                        # answers before any dependency gate

python3 tests/tui_screen.py                                   # screen-model assertions (needs pyte)
python3 tests/pty_drive.py                                    # stream + timing assertions
python3 tests/assert_pane.py <capture.txt> <pane_width> [list|card]
python3 tests/mpv_ipc_mock.py --reverse                       # fake IPC peer for the awkward shapes
```

Every rig runs directly and says in its own docstring what it proves. Read the docstring before changing the rig.

## Architecture & Core Components

| File | Role |
|------|------|
| `shell/yt` | **CORE engine** (1.7k lines) — all search / play / resolve / lifecycle logic, non-interactive, never prompts. Owns the detached player lifecycle (id / pid / socket / lock / state dir / reap), the JSON envelope, the exit-code taxonomy, and `YT_VERSION`. **Not on PATH** and not symlinked into `bin/`: every caller goes through a narrow verb, and a PATH-exposed `yt` only invites bypassing the flag-gating the verbs exist to provide |
| `shell/yt-search` | Narrow headless verb — gates flags (rejects `-f` / `--detach` / a URL) and `exec`s the core. Short because the script *is* short |
| `shell/yt-play` | Narrow headless verb — gates flags (rejects `-n` / `-s` / a bare query) and `exec`s the core. Owns the lifecycle verbs' argv surface (`--detach`, `--status`, `--stop`, `--set-volume`, `--get-url`, `--info`) |
| `shell/yt-tui` | The human face (2.8k lines) — self-rendered list and focus card, live filter, reflowing pagination, three playback states, en/zh chrome, ASCII fallback, themes. **Pure orchestration: zero YouTube logic.** No TUI framework, no fzf |
| `tests/tui_screen.py` | Drives the TUI in a real pty and asserts on the **screen** — a pyte cell grid after `\033[K` / `\033[J` / CHA have been applied. Claims like "pause repaints exactly one row, and no frame blanks the screen" are counted here |
| `tests/pty_drive.py` | Asserts on the **stream and its timing** — spinner frames arriving, `Starting` → `Playing` flipping with no keypress, the 1 s tick stopping, exit codes on cancel paths |
| `tests/assert_pane.py` | Layout invariants on a captured pane, measured in **cells** (east-asian-width), not characters: nothing exceeds the pane width, titles start on one column, the duration rail is right-flush |
| `tests/mpv_ipc_mock.py` | A fake mpv JSON-IPC peer that does what the real one will not do on cue: answer out of order, report a property null, interleave async events, walk the clock, never close its side |

**Dependency graph — search/play logic exists ONCE, in the core:**

```
  ~/bin/yts → shell/yt-search ─┐
  ~/bin/ytp → shell/yt-play  ──┼─► exec shell/yt (core) ─► yt-dlp · mpv · jq
  ~/bin/ytt → shell/yt-tui ────┘   (via yt-search -j → render → yt-play -d -j)
```

Each wrapper locates the core by a path **relative to its own resolved script location** (self-resolving symlink chain, `cd -P`/`pwd -P` — bash 3.2 has no `readlink -f`), so the checkout can live anywhere and needs no `bin/` entry to work.

**Primitives sit behind seams** (`docs/DESIGN.md` §5): `mpv` behind `run_mpv()` (single play seam) plus the `mpv_supports_vo()` capability probe; `yt-dlp` at ~5 named sites (`fetch_results`, `resolve_stream_url`, `resolve_info`, `probe_media_fetchable`, `detach_title_updater`); `jq` pervasive. Keep new primitive calls inside the existing seams.

**Governing principle: correctness is added *down* in the core, so every surface inherits it — never *up* in a UI.** A fix in `yt-tui` that the core could have made is a bug in the wrong file.

## Hard Rules

### 1. The bash 3.2 portability contract (enforced at review)

`bash -n` and shellcheck do **not** catch this class — these are runtime version behaviors. Only executing under `/bin/bash` on 3.2 does.

```
  Forbidden (bash 4+):  declare -A · ${var,,} / ${var^^} · mapfile/readarray ·
                        ${arr[-1]} · &>> · |& · ${!prefix@}
  Empty array + set -u: a bare "${arr[@]}" on an EMPTY array ABORTS on 3.2. Use
                          ((${#arr[@]})) && cmd "${arr[@]}"      (guard, as in the core)
                          cmd ${arr[@]+"${arr[@]}"}              (inline, as in yt-tui)
  Arithmetic + set -e:  a bare ((expr)) is a COMMAND whose status is 1 when the
                        expression evaluates to 0 — under set -e that aborts. Never
                        ((n += w)) as a statement; write n=$((n + w)). ((x)) as a TEST
                        (in if / && / ||) is fine — there the status is the point.
  read -rsn1 = one BYTE, not one character. A CJK keypress arrives as 2-3 "keys", so any
                        reader accumulating keypresses must reassemble the UTF-8 sequence
                        from its lead byte (yt-tui's utf8_complete). Classify the lead
                        byte by TABLE MEMBERSHIP the way char_w does — `LC_ALL=C [[ … ]]`
                        is not valid bash at all, and a ( LC_ALL=C … ) subshell forks per
                        keypress and cannot set a global.
  read -s is per-read:  it restores echo after ONE read, so the driver echoes whatever is
                        still queued between reads (a paste, a fast multi-byte char). A UI
                        that draws its own input owns the echo for the whole session
                        (stty -echo) and restores it from the same trap as the cursor.
```

If a feature genuinely needs bash 4+, the honest move is `((BASH_VERSINFO[0] >= 4))` at the top with a `brew install bash` hint — never a hardcoded interpreter path.

### 2. One fact, one place

`docs/DESIGN.md` is the systematic reference and each fact lives in exactly ONE of its sections; everything else points at it. Do not restate a contract in the README, in `usage()`, and in the design doc — state it once and cross-reference. `YT_VERSION` is declared once, in the core; the wrappers and the TUI ask it and print their own name, so four entry points can never disagree.

### 3. Scratch stays under `tmp/`

`.gitignore` carries `**/tmp/`. All throwaway scripts, captures, and probe output go there — never the repo root, never `tests/`. A rig graduates into `tests/` only when it earns a permanent place, and then it gets a docstring saying what it proves. Consequently `docs/DESIGN.md` §27 **names no rig by path**: a cited scratch path is a promise the checkout cannot keep. Record the *shape* of a check, not its filename.

### 4. The contract is frozen surface

The single-line JSON envelope, the player record, the exit-code table (0 ok / 1 usage / 2+ propagated tool failure / 4 didn't take effect), and the lifecycle semantics (launch → status → stop, idempotent stop, ambiguity → 4) are the one thing that survives any rewrite (`docs/ROADMAP.md` D3). Changing them is a deliberate, documented act — never a side effect of a feature.

## Testing Guidelines (HARD RULE — enforced at review)

These are **verification rigs, not a unit-test suite.** What this code gets wrong is renderer and protocol behaviour, which only a real pty and a real socket can show.

**Every rig MUST answer "what production failure mode does this catch that no other rig catches?"** If you cannot name it, do not add it.

### Reject a check when it:

- drives an internal shell function directly instead of the command's real entry point, or asserts on a private helper's output in isolation;
- greps the **byte stream** for a claim that is about the **screen** ("changed exactly one row", "nothing blanked") — the byte stream of a correct in-place frame looks nothing like the picture it produces. Assert on the pyte cell grid;
- measures a title's width in characters rather than display cells — a CJK title is two cells, and `len()` passes a line that visibly wraps;
- fakes the data or the logic under test. A fake **peer** (`mpv_ipc_mock.py`) is legitimate — it produces shapes the real mpv will not produce on cue. A fake renderer or a stubbed core is not;
- exists only to raise a count, or asserts a default value that a behavioral check already exercises;
- times a network-dependent path against YouTube when a local synthetic source (`av://lavfi:sine`) would do — throttling has corrupted a timing measurement here before (`docs/DESIGN.md` §25.1).

### Accept a check when it drives a real surface:

a pty running the actual script; a real mpv or the IPC mock over a real unix socket; `bash -n` on all four scripts; the JSON envelope parsed out of a real `-j` invocation; the exit code of a real failure path; a captured pane measured in cells.

### Two lessons that each cost a wrong green result first

1. **A pty starts at 0×0, and `LINES`/`COLUMNS` do not fix it.** The TUI reads `stty size` through `/dev/tty` on purpose, so without `TIOCSWINSZ` the reflow has no rows to spend and draws a one-row list — whose frames look plausible enough to trust.
2. **Assert on the screen model, not the byte stream.** (Same root as the reject rule above; it is listed twice because it is the mistake that recurs.)

### Minimum checks before every commit

- `bash -n` on the core and all three wrappers.
- Run the empty-argument and empty-array paths under `/bin/bash` explicitly (the 3.2 floor).
- For any renderer change: a real pty capture plus `tests/assert_pane.py` at 40/62/80/100 cols, and `tests/tui_screen.py`.
- For any lifecycle change: `-d` twice → `--status` lists both → `--set-volume --id` → `--stop --id` → `--stop --all` → `--status` empty, and assert **zero orphan mpv** afterwards.
- For any contract change: the `-j` envelope stays one line, and the exit code matches the taxonomy.

## Safe-Evolution Methodology (how this suite is changed)

The refactor that produced this architecture followed a staged, reversible order — reuse it for any structural change:

```
  A  Build the new path against the CURRENT tools and validate it in a tmux pty
     → an interactive path is never absent.
  B  Repoint callers / wrappers / symlinks; run the headless regression.
  C  Delete the old path — the destructive step, kept LAST and small; grep-gate every
     removed symbol before deleting it; regress again.
  D  Update docs (docs/DESIGN.md, README.md, usage()).
  E  Final headed (tmux) + headless sweep.
```

Principle: put the single destructive step last and smallest, prove its replacement first, and gate deletions by grep so no dangling reference survives.

## SDLC & Architectural Documentation

- `docs/DESIGN.md` — architecture, every non-obvious decision and why, the function map, the data contracts, the risk/defect register, and the verification matrix. **Kept in sync on every PR that touches architecture or a contract.**
- `docs/ROADMAP.md` — positioning and non-goals, the naming survey, the OSS-readiness assessment, and the conditions under which the core would move to Go. Consult §0 before adding a feature: **no queue, no playlist management, no listening history, no favourites, no downloader, no channel subscriptions** — their absence is a scope decision, not a gap.
- `docs/PLAN-*.md` — scoped implementation plans (e.g. the low-cost agent-tooling surface). A plan is Planning until its contract lands in `docs/DESIGN.md`.
- One repo, one README: there is deliberately no `tests/README.md` — the rigs are described in the root README's `## Tests` section and in their own docstrings.
### Agent skills

**Skills live in `.claude/skills/` — nowhere else.** Claude Code discovers project skills only there (plus `~/.claude/skills/` and plugins); a skill parked anywhere else is invisible and will simply never be invoked. Four exist:

| Skill | Use it when |
|---|---|
| `run-yt-tui` | You need to *see* the TUI. It requires a real TTY on both stdin and stdout, so a Bash-tool call proves nothing — this covers the tmux drive, the pty-size trap, the ready markers, the keymap, and the detached-player cleanup a session kill does **not** do |
| `capture-pane` | A terminal frame in `README.md` / `docs/DESIGN.md` is stale. Capture → clean (`clean_capture.py`, which refuses a mid-fetch frame) → **prove with `tests/assert_pane.py`** → splice with a Python replace. Never hand-draw a frame |
| `verify-suite` | Before a push, before a `YT_VERSION` bump, after touching the core / a wrapper / the renderer. The four-phase sweep this repo has instead of CI; phase 4 starts audible playback and is run deliberately |
| `audit-conformance` | Periodically, not per-commit. Whole-suite scan against 12 rules (surface layering, DRY, bash 3.2, dead code, swallowed errors, contract and doc drift) → `docs/TODO-conformance-YYYY-MM-DD.md`. Ships `fn_graph.py` (defs vs call sites across all four scripts) as a manual aid — **never** as a gate or a `tests/` member |

A skill may propose a *structural detector as a manual aid*; it may never propose one as a test. The rigs-only mandate above binds skills too.

## Coding Style & Naming Conventions

- Match the surrounding style: 4-space indentation, `snake_case` functions, `UPPER_SNAKE` globals, `local` for everything inside a function, `set -euo pipefail` semantics respected (see the arithmetic rule above).
- Long names (`yt`, `yt-search`, `yt-play`, `yt-tui`) are the canonical identity used in help text, errors, and docs. Short names (`yts`, `ytp`, `ytt`) are what goes on PATH. Do not mix the two in one sentence, and never add a second name for an existing command.
- Per-request choices are **flags**; set-once tuning is an **environment variable** (`YT_*`) — this keeps each verb's flag surface narrow enough for a small model to call safely. Do not add a flag for something a user sets once.
- Never add a runtime dependency. The suite's differentiator is that it depends only on primitives everyone already has.
- Prefer small, incremental edits in the existing scripts over refactors that move logic between files.

## Commit & Pull Request Guidelines

- **`main` is the working branch** — 54 commits, zero merges, single author. Commit straight to it for ordinary work; take a branch when the change is structural enough to want the staged A→E order below, or when it may need to be abandoned. No stacked branches.
- Imperative, scoped commit subjects in the existing style — the file or surface first when it helps: `yt-tui: stop Enter stalling a second in utf8_complete`, `add --version, declared once`, `docs: resync DESIGN with the detached-playback TUI`.
- One logical change per commit. Renderer changes come with the capture or the rig output that proves them.
- `bash -n` on all four scripts before every commit; the relevant rig before every push.
- **Always ask before `git push`.** Never force-push `main`.
- There is no release process to run: the shell suite is not packaged (`docs/ROADMAP.md` D1). `YT_VERSION` in `shell/yt` is bumped deliberately, alone, when the contract or a user-visible surface changes — not once per commit.

## Security & Configuration Tips

- The suite runs **unprivileged**. Never introduce `sudo`, a persistent privileged process, or unsafe temp-file handling.
- Player state lives in a per-player state dir with a lock; `players/` holds only `<id>.json` — **no bare token or credential may ever land there**, and the detached mpv log must not grow unbounded.
- Cookies are read from a browser profile via `YT_COOKIE_BROWSER` and presence-checked per platform; if absent, extraction runs anonymously rather than breaking. Never log a cookie path's contents or an extracted token.
- Secrets and credentials belong in `~/env-secrets/`, never in the repo.
- Anything that shells out to `yt-dlp`/`mpv` passes arguments as an array, never through a re-quoted string.
