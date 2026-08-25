# CLAUDE.md

This file is the single source of truth for repository guidelines, used by Claude Code and all AI coding agents.

## Project Overview

**uting** (u-ting / 你听) — an agent-first media engine with a terminal face. A seven-script bash suite: search a source, play it through `mpv` detached from the terminal, keep controlling it, and save what you found — from a TUI if you are a human, from a single-line JSON contract if you are a program. Two sources ship today (YouTube, Bilibili); a third is a new pair of scripts and no change anywhere else. Durable user-level state (playlists) lives in its own command, `ut-playlist` — never in the player, never in the TUI.

The suite is exposed **directly** to shell-capable agents with no MCP wrapper, so the **CLI contract itself** (argv, exit codes, output shape, process lifecycle) *is* the product and the safety boundary. Every design choice follows from that. Full rationale: `docs/ARCHITECTURE.md`.

**Status: reference implementation.** Not packaged — no installer, no Homebrew formula, and none planned for the shell version (`docs/ROADMAP.md` D1/D2). Users symlink `uting` (the human surface) and `ut-play`/`yt-search`/`yt-resolve`/`bili-search`/`bili-resolve`/`ut-playlist` (the agent surface) onto their own PATH. **No short name ships** (`docs/ROADMAP.md` D10) — the human face carries the project's own name, so `~/bin/uting` is a plain symlink with the same word at both ends. A user wanting a short form writes their own alias.

## Runtime Environment (Required)

- **bash 3.2** — macOS's frozen system `/bin/bash`. This is a deliberate floor, not an accident: zero install step, identical behavior under macOS, Linux, containers, CI, and cron/launchd. Do **not** raise it, and do **not** hardcode a Homebrew bash path. See the portability contract below — it is a hard rule.
- Runtime deps, all external and unvendored: `yt-dlp`, `jq`, `mpv`, `nc` (BSD netcat, stock on macOS), `curl`. `curl` is required by `bili-search` (it IS that engine's transport) and optional elsewhere — the YouTube play-time client probe.
- **macOS first.** Linux is not currently usable: stock netcat has no `-U`, which the mpv IPC path needs. Do not "fix" Linux support by adding a dependency — that decision is gated in `docs/ROADMAP.md` §9.
- The test suite needs `tmux` (`contract.sh`'s TUI boot check) and nothing else — it is shell all the way down, because a suite whose subject depends only on primitives must not need more than its subject does. Nothing in `tests/` is needed at runtime, and **nothing in `tests/` may be a stand-in for a component** (see the testing rules).
- There is **no** build step, no venv, no lockfile, and no CI. The checks below are run by hand — that is the whole reason they are written out — with two of them gated locally by git hooks:

```sh
git config core.hooksPath .githooks   # RUN ONCE PER CLONE — fresh clones have no hooks
```

`.githooks/pre-commit` blocks a staged secret / cookie export, a **bash-4 idiom on an added line**, a staged shell script that does not parse under `/bin/bash -n`, a **non-`.sh` file under `tests/`** (the enforceable half of the no-stand-in rule below), and a force-added `tmp/` file. `.githooks/pre-push` blocks a force-push or deletion of `main` and a syntax error in any script under `shell/` (globbed, not listed), and warns when a `v*` tag is pushed (the tag must match `shell/VERSION`). A direct push to `main` is **not** blocked — see the commit guidelines.

## Build, Test, and Development Commands

```sh
bash -n shell/ut-play shell/yt-search shell/yt-resolve shell/bili-search shell/bili-resolve shell/ut-playlist shell/uting  # syntax check — run before EVERY commit
/bin/bash shell/yt-search -j -n 5 -- "lofi hip hop"           # exercise on the 3.2 floor, explicitly
shell/uting "lofi hip hop"                                   # interactive; needs a real TTY on stdin AND stdout
shell/ut-play --help                                          # the player's own help (it is on PATH)
shell/bili-search -j -n 5 -- "周杰伦"                          # the second engine, same envelope
shell/ut-playlist --ls -j                                     # the store: durable, user-level state
UT_STATE_DIR=$(mktemp -d) shell/ut-playlist --ls -j           # …never against the real one, in a test
shell/uting --version                                        # answers before any dependency gate

tests/contract.sh                                             # the CLI contract, 144 checks
tests/playback.sh                                             # real detached players; silent, ~35s
tests/drive.sh -x 62 -y 20                                    # drive the TUI, reap the player after
tests/drive.sh -k Enter -w Playing                            # …including a real detached play
```

Each suite runs directly and says in its own docstring what it proves. Read the docstring before changing it.

## Architecture & Core Components

| File | Role |
|------|------|
| `shell/ut-play` | **The player** (2.3k lines) — play + detached-playback lifecycle, non-interactive, never prompts. Owns the player lifecycle (id / pid / socket / lock / state dir / reap), the **queue** a player consumes (`--queue/--enqueue/--next`; a lone handle is a queue of one, resolved just in time — `docs/ARCHITECTURE.md` §9.5), the JSON envelope and the exit-code taxonomy, and **its own flag gate** (one verb, so there is no bypass to defend against — `docs/AS-BUILT-contract.md` §2). **Source-agnostic** — it does not search, does not extract, and carries no yt-dlp call, cookie decision or format string. It asks an engine, by name: `--engine yt` → `yt-resolve` |
| `shell/yt-search` | **The YouTube engine, half one** (560 lines) — query → result envelope. Owns its own yt-dlp call, cookie decision, result shaping and duration formatter, and its own flag gate. Zero playback or lifecycle logic |
| `shell/yt-resolve` | **The YouTube engine, half two** (1.0k lines) — handle → `{stream_urls[], http_headers{}, title, duration, format}`, plus `--info` and `--transcript`. Owns the PO-token probe, the cookie decision, the mode→format table and the yt-dlp error vocabulary. Every site-specific fact in the suite lives in this file or in `yt-search`; adding a source is adding a pair like it |
| `shell/bili-search` | **The Bilibili engine, half one** (658 lines) — query → result envelope, over `curl` + `jq`. It talks HTTP rather than shelling out to yt-dlp because yt-dlp's Bilibili search returns **no metadata at all** (flat) and recurses into every part of every collection (non-flat, >120s for 10 results). Sends no credential: one public endpoint, a Referer, and a locally generated random `buvid3` |
| `shell/bili-resolve` | **The Bilibili engine, half two** (778 lines) — handle → the same resolve envelope, over `yt-dlp`. No request signing, no stream selection, no CDN logic: that is a thousand lines to redo what the dependency maintains. Owns the BV/av handle shapes, the cookie decision, the mode→format table. No `--transcript` — the site has no captions, and an engine states a missing capability by not having the verb |
| `shell/VERSION` | The suite version, declared once — a one-line data file, not a shell variable. The player and the engines are independent executables sharing no library, so a variable in any one of them would make the others ask *it* for the version — the wrong dependency direction for a player that must not know its engines |
| `shell/ut-playlist` | **The playlist store** (636 lines) — durable, user-level, engine-agnostic state: `$UT_STATE_DIR/playlists/<name>.json`, one file per list, `mkdir` lock + atomic temp+mv, six verbs (`--ls --show --add --rm --del --rename`) and its own state-error enum (`not_found`, `exists`, `invalid_name`, `invalid_input`, `locked`, `corrupt` — the last four split 1 vs 4 the way the rest of the suite does). Knows **no site and no playback**: its record is `{engine, url, …}`, which is exactly `ut-play --engine E -- URL`, so a stored record is a CALL, not a reference. Input is stdin JSON only — a search envelope, its own `--show` envelope, or an item array. **The queue is NOT here**: a queue is a playlist being consumed and belongs to the player (`docs/ARCHITECTURE.md` §9.5) |
| `shell/uting` | The human face (3.4k lines) — self-rendered list and focus card, live filter, reflowing pagination, three playback states, en/zh chrome, ASCII fallback, themes. **Pure orchestration: zero YouTube logic.** No TUI framework, no fzf |

**Dependency graph — one layer, seven peers. Site knowledge exists ONLY in an engine pair, playback ONLY in the player. An engine's two halves need not use the same primitive: the seam is the ENVELOPE, not the tool behind it:**

```
  ~/bin/yt-search    → shell/yt-search ───► yt-dlp · jq            (engine: query → results)
  ~/bin/yt-resolve   → shell/yt-resolve ──► yt-dlp · jq · curl     (engine: handle → stream URL + headers)
  ~/bin/bili-search  → shell/bili-search ─► curl · jq              (engine: query → results)
  ~/bin/bili-resolve → shell/bili-resolve ► yt-dlp · jq            (engine: handle → stream URL + headers)
  ~/bin/ut-play      → shell/ut-play ─────► <engine>-resolve -j ──► mpv · jq · nc   (player)
  ~/bin/ut-playlist  → shell/ut-playlist ─► jq                    (durable state, optional)
  ~/bin/uting       → shell/uting ──────► (<engine>-search -j | ut-playlist --show -j → render
                                            → ut-play -d -j --engine <the ROW's engine>)
```

The player never runs yt-dlp and mpv never runs it either (`--no-ytdl` + a direct URL): **one extraction, and we make it.** The engine name IS the command prefix, which is what lets the player find `yt-resolve` with a string concatenation instead of a registry.

Each script locates its siblings by a path **relative to its own resolved script location** (self-resolving symlink chain, `cd -P`/`pwd -P` — bash 3.2 has no `readlink -f`), so the checkout can live anywhere and needs no `bin/` entry to work.

**Primitives sit behind seams** (`docs/ARCHITECTURE.md` §5), and the seams are now split by file: `mpv` behind `run_mpv()` in `ut-play` (single play seam) plus the `mpv_supports_vo()` capability probe; `yt-dlp` only in the engines (`fetch_results` in `yt-search`; `dump_once`, `resolve_info`, `resolve_transcript` in `yt-resolve`; `dump_once`, `resolve_info` in `bili-resolve`); the Bilibili HTTP seam is `fetch_page_once` in `bili-search`, the only place in the suite that builds a request by hand; `curl` also backs `probe_raw` in `yt-resolve` (the fetchability probe); `jq` pervasive. Keep new primitive calls inside the existing seams — and a yt-dlp call in `ut-play` or an mpv call in an engine is a layering violation, not a seam.

**Governing principle: correctness is added *down* — in the player if it is about playback, in the engine if it is about a site — so every surface inherits it, never *up* in a UI.** A fix in `uting` that `ut-play` could have made is a bug in the wrong file.

## Hard Rules

### 1. The bash 3.2 portability contract (enforced at review)

`bash -n` and shellcheck do **not** catch this class — these are runtime version behaviors. Only executing under `/bin/bash` on 3.2 does.

```
  Forbidden (bash 4+):  declare -A · ${var,,} / ${var^^} · mapfile/readarray ·
                        ${arr[-1]} · &>> · |& · ${!prefix@}
  Empty array + set -u: a bare "${arr[@]}" on an EMPTY array ABORTS on 3.2. Use
                          ((${#arr[@]})) && cmd "${arr[@]}"      (guard, as in the core)
                          cmd ${arr[@]+"${arr[@]}"}              (inline, as in uting)
  Arithmetic + set -e:  a bare ((expr)) is a COMMAND whose status is 1 when the
                        expression evaluates to 0 — under set -e that aborts. Never
                        ((n += w)) as a statement; write n=$((n + w)). ((x)) as a TEST
                        (in if / && / ||) is fine — there the status is the point.
  read -rsn1 = one BYTE, not one character. A CJK keypress arrives as 2-3 "keys", so any
                        reader accumulating keypresses must reassemble the UTF-8 sequence
                        from its lead byte (uting's utf8_complete). Classify the lead
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

`docs/ARCHITECTURE.md` is the as-built doc of the application and each fact lives in exactly ONE of its sections; everything else points at it. Do not restate a contract in the README, in `usage()`, and in the design doc — state it once and cross-reference. The version is declared once, in `shell/VERSION`; each entry point reads that file and prints its own name, so four entry points can never disagree.

### 3. Scratch stays under `tmp/`

`.gitignore` carries `**/tmp/`. All throwaway scripts, captures, and probe output go there — never the repo root, never `tests/`. A throwaway check graduates into `tests/` only when it earns a permanent place, and then it gets a docstring saying what it proves. Consequently `docs/ARCHITECTURE.md` §27 **names no scratch check by path**: a cited scratch path is a promise the checkout cannot keep. Record the *shape* of a check, not its filename.

### 4. The contract is frozen surface

The single-line JSON envelope, the player record, the exit-code table (0 ok / 1 usage / 2+ propagated tool failure / 4 didn't take effect), and the lifecycle semantics (launch → status → stop, idempotent stop, ambiguity → 4) are the one thing that survives any rewrite (`docs/ROADMAP.md` D3). The whole frozen surface is stated in `docs/AS-BUILT-contract.md`. Changing it is a deliberate, documented act — never a side effect of a feature.

## Testing Guidelines (HARD RULE — enforced at review)

**Functional tests only.** A command-line tool is tested by running it and reading its exit code and its stdout. There is no rig layer, no screen model, no pty harness and no unit tier: every check invokes a real entry point the way a caller does, and asserts on what came back.

Two files, one rule:

| File | Drives | Gate |
|---|---|---|
| `tests/contract.sh` | every command's argv, exit codes and `-j` envelopes; the playlist store under a disposable `UT_STATE_DIR`; the host gate across every discovered engine; the idle lifecycle and the death record; the TUI's boot / resize / quit under tmux | none — run it before every commit |
| `tests/playback.sh` | detached players end to end (launch → status → mutate → stop → stop again), the **live read off a real mpv socket** (the peer has no stand-in, so the claim lives here), and that an engine's `http_headers` actually reach mpv | none — it starts real players, but in a state dir of its own; ~35s and needs the network, so run it when the player changed |

`tests/drive.sh` is the only other file, and it is not a suite — it asserts nothing. It is a
**driver**: it launches the TUI in tmux at a declared geometry, waits on the ready marker, optionally sends keys, and **always reaps the detached player** — which killing the tmux session does not do. Use it whenever a TUI change has to be driven rather than reasoned about.

### Harden before you extend

The default move on a gap is to make an **existing** check stronger, not to add a file. A check that drives one engine when the function behind it is duplicated across engines is a *weak* check, not a missing one — state the claim as an invariant over all **discovered** engines (`<name>-search` + `<name>-resolve` pairs, the registry `uting` already builds) and engine #3 is covered the day it lands. A new check earns its place only by naming a production failure no existing check catches; if you cannot name one, harden instead.

### Reject a check when it:

- asserts on an internal function or a private helper instead of invoking the command;
- **introduces a mock, a fake, a stub or a stand-in of any kind — no exception, including for a peer.** There is exactly one legitimate thing this suite may author: a **fixture**, meaning *data a real command really reads* (a state file for the reaper, a search envelope on `ut-playlist`'s stdin). The moment something in `tests/` *executes* in place of a component — a scripted socket peer, a `sleep` posing as a live pid, a shimmed binary on `PATH` — it is a mock and it does not land. The rule is not "fake the peer, never the subject": it is **no fake at all**. A claim that needs a real peer is proved where the real peer runs (`playback.sh`), or it is not proved. Coverage a real dependency cannot be made to produce on cue is coverage this suite does not have, and saying so is honest; a green check against a scripted peer is not;
- asserts on a rendered **picture** — cell grids, column alignment, glyph widths. Layout is proved when a frame enters a doc, and the `capture-pane` skill owns that; the suite asserts survival, not shape;
- exists only to raise a count, or asserts a default that a behavioural check already exercises;
- times a network-dependent path against YouTube when a local synthetic source (`av://lavfi:sine`) would do — throttling has corrupted a timing measurement here before (`docs/ARCHITECTURE.md` §25.1);
- **cannot fail.** Before it lands, break the thing it guards and watch it go red. A check nobody has seen fail is a check nobody has tested.

### Accept a check when it drives a real surface:

`bash -n` on every script in `shell/`; a real `-j` invocation whose envelope is parsed; the exit code of a real failure path; a real unix socket with real mpv on the far end (`playback.sh`); the TUI under tmux asserted on survival — it booted, it is still up after a resize, it left on `q` with 0.

### Minimum checks before every commit

**The two suites in `tests/` ARE these checks.** A check that exists only as prose for someone to copy out reports green by default. A new check goes in the suite, never in a doc — and a fixed command sequence goes in a script, never in prose.

- `/bin/bash -n shell/*` — enforced by `.githooks/pre-commit` on staged content and by `pre-push` on the worktree, so this is a backstop for a `--no-verify`, not a habit.
- **Any change at all:** `tests/contract.sh` (it also drives the empty-argument paths on the 3.2 floor). It starts no process it did not have to and talks to no peer — every live claim is `playback.sh`'s.
- **Any change to the detached player:** `tests/playback.sh`. It starts real players (silent, `--volume 0`, in a state dir of its own) and does not pass until `pgrep` finds none of them left.
- The shellcheck baseline is a tracked count, not a clean bill — `docs/ROADMAP.md` §6.1.

## Safe-Evolution Methodology (how this suite is changed)

Any structural change follows a staged, reversible order:

```
  A  Build the new path against the CURRENT tools and validate it in a tmux pty
     → an interactive path is never absent.
  B  Repoint callers / wrappers / symlinks; run the headless regression.
  C  Delete the old path — the destructive step, kept LAST and small; grep-gate every
     removed symbol before deleting it; regress again.
  D  Update docs (docs/ARCHITECTURE.md, README.md, usage()).
  E  Final headed (tmux) + headless sweep.
```

Principle: put the single destructive step last and smallest, prove its replacement first, and gate deletions by grep so no dangling reference survives.

## SDLC & Architectural Documentation

**Documents move through four stages, and the prefix says which one a file is in.** A doc that
stops moving is a doc nobody trusts, so each stage names what ends it:

| Stage | Prefix | What it holds | What ends it |
|---|---|---|---|
| research | `RESEARCH-<topic>.md` | surveying the world **outside** this repo — what comparable projects do, measured data, comparisons. Says nothing about what we will build | **distil it into a `ROADMAP.md` entry**, filtered by relevance and business need, then delete the doc |
| roadmap | `ROADMAP.md` | the decided and the sequenced: positioning, non-goals, phases, and the conditions that would reopen a decision | nothing — it is the one doc that outlives a rewrite |
| plan | `PLAN-<topic>.md` | one feature, from open question to built: options and trade-offs are explored **during its authoring** (design is an activity inside this stage, not a doc class), then field names, flags, the verification matrix. **Tracks the life of the feature delivery** — the status line and per-item state are updated as things land | **its content is split into the as-built docs as it lands, then the plan is deleted** — gone, not archived |
| as-built | `ARCHITECTURE.md` + `AS-BUILT-<scope>.md` | what the code actually is and why — a description that chases the code, never a promise the code chases (which is why the prefix is not `SPEC-`: "spec" reads as a normative document implementations conform to). Every fact in exactly ONE section | never; it is **resynced at land, after the code stops moving** — never edited ahead of the build |

Today there are two as-built docs: `docs/ARCHITECTURE.md` (the **application** — what the code
is and why; the umbrella doc a newcomer opens first) and `docs/AS-BUILT-workflow.md` (the
**process** — how a unit of work moves through the repo); the two do not mix, and a further
`AS-BUILT-<scope>.md` splits out when one earns it. The rule that keeps the family honest is
the one that already governs a single file: one fact, one section, everything else points at
it. **The taxonomy is closed**: work in flight is a `PLAN-`, work landed is as-built — no
further doc class is introduced.

`PLAN-`, not `TODO-`, for the third stage: a plan **carries work-in-progress state** — it is
updated as items land and is only deleted when the last one has — whereas a todo is a list of
things not done, with nowhere to record that three of five now are. The stage needs the former.
(`TODO-` is also doubly spoken for: an agent's own in-session task list, and `// TODO` comments.)

The live files:

- `docs/ARCHITECTURE.md` — architecture, every non-obvious decision and why, the function map, the risk/defect register, and the verification matrix. **Kept in sync on every PR that touches architecture or a contract.**
- `docs/AS-BUILT-contract.md` — the frozen CLI contract (ROADMAP D3/D13): command surfaces, gates, every `-j`/`-J` envelope and error shape, exit codes, the configuration surface, and the add-an-engine checklist. The one doc a third-engine author or a port needs.
- `docs/AS-BUILT-workflow.md` — the development process: which discipline each stage of work is bound to (plan → pre-mortem → build → verify → land, plus the periodic audit). The disciplines are normative; the agent skills that automate them are conveniences the checkout does not depend on.
- `docs/ROADMAP.md` — positioning and non-goals, the naming survey, the OSS-readiness assessment, and the conditions under which the core would move to Go. Consult §0 before adding a feature. **In scope (D14/D15, P4):** queue, playlist management, listening history — to be built in the SHELL version, not deferred to a Go rewrite. **Favourites is NOT a feature** (it is a playlist with a fixed name — one capability, one spelling). A downloader and channel subscriptions are unscheduled. What did NOT change: this is still not a general-purpose local/MPD player, and every one of those features must ship an **agent surface** (a verb plus a `-j` envelope) alongside its keybinding — a TUI-only feature is half a feature here. MCP remains a non-goal, gated by §9.
- `docs/PLAN-*.md` — whatever is ready to build or in flight, with its progress recorded inline. Empty is a valid state.
- One repo, one README: there is deliberately no `tests/README.md` — the two suites are described in the root README's `## Tests` section and in their own docstrings.

### Agent skills

**Skills live in `.claude/skills/` — nowhere else.** Claude Code discovers project skills only there (plus `~/.claude/skills/` and plugins); a skill parked anywhere else is invisible and will simply never be invoked. **A skill is for work needing judgement; a fixed command sequence is a script.** Two exist:

| Skill | Use it when |
|---|---|
| `capture-pane` | A terminal frame in `README.md` / `docs/ARCHITECTURE.md` is stale. Capture → clean (`clean_capture.py`, which refuses a mid-fetch frame) → **prove with the skill's own `assert_pane.py`** → splice with a Python replace. Never hand-draw a frame |
| `audit-conformance` | Periodically, not per-commit. Whole-suite scan against 12 rules (surface layering, DRY, bash 3.2, dead code, swallowed errors, contract and doc drift) → `docs/PLAN-conformance-YYYY-MM-DD.md`. Ships `fn_graph.py` (defs vs call sites across every script in `shell/`) as a manual aid — **never** as a gate or a `tests/` member |

A skill may propose a *structural detector as a manual aid*; it may never propose one as a test. The functional-only mandate above binds skills too — and layout proving lives in `capture-pane`, deliberately outside the suite.

**Driving the TUI is not a skill, it is `tests/drive.sh`.** Launching at a fixed geometry, polling the ready marker, sending keys and reaping the detached player are mechanical, and a mechanical sequence written as prose is a runner nobody executes the same way twice.

## Coding Style & Naming Conventions

- Match the surrounding style: 4-space indentation, `snake_case` functions, `UPPER_SNAKE` globals, `local` for everything inside a function, `set -euo pipefail` semantics respected (see the arithmetic rule above).
- **One name per command, and no second spelling of any of them.** `ut-play`, `yt-search`, `yt-resolve`, `bili-search`, `bili-resolve`, `ut-playlist`, `uting` are the canonical identity — help text, errors, docs, and the PATH entry itself. The suite ships **no short form** (D10 — the short names are taken on npm/PyPI/crates, and a second official spelling is a second thing to keep in sync). A user wanting one writes their own alias. Never add a second name for an existing command.
- Per-request choices are **flags**; set-once tuning is an **environment variable** (`YT_*`) — this keeps each verb's flag surface narrow enough for a small model to call safely. Do not add a flag for something a user sets once.
- Never add a runtime dependency. The suite's differentiator is that it depends only on primitives everyone already has.
- Prefer small, incremental edits in the existing scripts over refactors that move logic between files.

## Commit & Pull Request Guidelines

- **`main` is the working branch** — linear, no merges, single author. Commit straight to it for ordinary work; take a branch when the change is structural enough to want the staged A→E order below, or when it may need to be abandoned. No stacked branches.
- Imperative, scoped commit subjects in the existing style — the file or surface first when it helps: `uting: stop Enter stalling a second in utf8_complete`, `add --version, declared once`, `docs: resync DESIGN with the detached-playback TUI`.
- One logical change per commit. Renderer changes come with the proved capture (`capture-pane`) that shows them.
- `bash -n` on every script in `shell/` before every commit; `tests/contract.sh` before every push.
- **Always ask before `git push`.** Never force-push `main`.
- **Versioning is semver 2.0.0 over the CLI contract, not over the code** (`docs/ROADMAP.md` D13 defines what counts as the public API). While the suite is `0.y.z`: a breaking change bumps **y**, an addition or a fix bumps **z**. `shell/VERSION` is bumped deliberately, **alone, in its own commit**, and never once per commit. There is no release process to run and no CHANGELOG: the suite is not packaged (`docs/ROADMAP.md` D1), so a `v<VERSION>` tag is for a real release only — `1.0.0` waits for D1/D2 to reverse.

## Security & Configuration Tips

- The suite runs **unprivileged**. Never introduce `sudo`, a persistent privileged process, or unsafe temp-file handling.
- Player state lives in a per-player state dir with a lock; `players/` holds only `<id>.json` — **no bare token or credential may ever land there**, and the detached mpv log must not grow unbounded.
- Cookies are read from a browser profile via `YT_COOKIE_BROWSER` and presence-checked per platform; if absent, extraction runs anonymously rather than breaking. Never log a cookie path's contents or an extracted token.
- Secrets and credentials belong in `~/env-secrets/`, never in the repo.
- Anything that shells out to `yt-dlp`/`mpv` passes arguments as an array, never through a re-quoted string.
