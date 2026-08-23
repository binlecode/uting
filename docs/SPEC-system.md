# SPEC-system — uting, system scope

`ut-play` · `yt-search` · `yt-resolve` · `bili-search` · `bili-resolve` · `yt-tui` — a
search + terminal-playback CLI suite, designed as much for **LLM/agent callers** as for
humans. This is the **code-synced spec**: architecture, functional structure, supported
workflows, the module contract, and the rationale behind them, kept in step with the code
on every change that touches architecture or a contract. Each fact lives in ONE section;
everything else points at it.

Scope is `system` — the whole suite. A per-surface `SPEC-<scope>.md` splits out only when
one earns it, and the one-fact-one-section rule then holds across the family. What this
document is NOT: a proposal (`DESIGN-<topic>.md`), the sequencing (`ROADMAP.md`), or work
in flight (`PLAN-<topic>.md`). The four stages are defined in `CLAUDE.md`.

- Player (source-agnostic): `shell/ut-play` — plays, and owns the detached lifecycle
- YouTube engine (a pair): `shell/yt-search` (query → results), `shell/yt-resolve`
  (handle → stream URL + headers, plus `--info` / `--transcript`)
- Bilibili engine (a pair): `shell/bili-search`, `shell/bili-resolve` (`--info`; this site
  serves no captions, so there is no `--transcript` half)
- Interactive UI: `shell/yt-tui` (owned glue over the verbs; no extra deps)
- Caller-facing surface: each verb's own `-h`/`--help` · Orientation: `README.md`
- Runtime deps: `yt-dlp`, `jq` and (optionally) `curl` in the ENGINES; `mpv` + `jq` in the
  player; `nc` for `--set-volume`. No fzf / TUI framework — only foundational primitives.

> **Restructure in flight (2026-08-23).** Several things below this line are behind the
> code, all by design (`docs/PLAN-ut-restructure.md`). Names, diagrams and §13's gating
> model are redrawn together in step E, once the shape stops moving; §14 below is the
> exception — a contract is stated when it lands, never later. What has already changed:
>
> - **Step A** — the core file was renamed `shell/yt` → `shell/ut-play`, so a bare `yt` in
>   prose or in a process diagram still means that player. The version moved to
>   `shell/VERSION`.
> - **Step B-1** — search left for the `yt-search` engine, which owns the search yt-dlp
>   call, the cookie decision and the duration formatter, declares `engine`/`status` in its
>   envelope, and merged its former gating wrapper. The player's old D2 contract (bare
>   `yt "query"` → list) went with it.
> - **Step B-2** — extraction left for `shell/yt-resolve`, and **mpv no longer runs yt-dlp
>   at all**: the player passes `--no-ytdl` and opens a direct URL the engine resolved. So
>   §5's seam table, §6.1's invocation stack, §8.1's mode→format table and §8.2's probe all
>   describe work that now happens one process further out, in the engine. `--get-url`,
>   `--info` and `--transcript` are `exec`-forwarded to `yt-resolve` and are its verbs now.
>   The engine token in every envelope is `yt`, not `youtube`: the name IS the command
>   prefix, which is what lets the player find `yt-resolve` without a registry.
> - **Step B-3** — the `yt-play` gating wrapper is **deleted** and `ut-play` is the PATH
>   entry for playback, holding its own gate. Two layers became one, so §13's two-tier
>   gating model and §4's topology are now one tier of four peers. `--get-url` is **retired
>   with no alias**: it was a second spelling of what a bare `yt-resolve` call is. `--info`
>   and `--transcript` are no longer forwarded either — `ut-play` names the engine and exits
>   1 — so §10's resolve-only verb and §12's player spec belong to `yt-resolve` now, and the
>   player's own flag surface is exactly: `-f -S -d -j -l --engine --volume --status --stop
>   --set-volume --id --all --color -h -V`. `-J` went with the verbs that used it.
>
> - **Step C** — a **second engine** exists: `bili-search` + `bili-resolve` (Bilibili).
>   Nothing in the player or the TUI changed to admit it, which was the whole point of the
>   split. Three facts it establishes, all of which §4/§5/§12/§14 will state properly at E:
>   an engine's two halves may use **different primitives** (this one's search half talks
>   HTTP via `curl`, its resolve half shells out to `yt-dlp`) — the seam is the ENVELOPE,
>   not the tool behind it; an engine **declares its capabilities by which verbs exist**
>   (there is no `--transcript` here because the site has no captions, rather than a verb
>   that always answers "none"); and `http_headers` stopped being a theoretical key —
>   this site's CDN answers **403 to a bare stream URL and 206 to the same URL with the
>   envelope's headers**, measured, so the hole D9 closed is now load-bearing.
>   Its follow-on tightened both engines (ROADMAP D12): **`<engine>-resolve` accepts only
>   its own site's hosts**, so §12's handle grammar now carries a host allowlist per engine
>   and a URL from another site is a usage error (1), not an extraction failure. `yt-resolve`
>   had been accepting any http(s) URL and labelling the result `engine:"yt"`.
> - Still true everywhere: the exit-code taxonomy, the lifecycle semantics, and one line
>   per `-j` envelope.

The document flows: **I. System architecture → II. Functional structure →
III. Modular API → IV. Supported workflows → V. Aligned best practice.**

---

# Part I — System architecture

## 1. Why this exists / design goals

The suite is exposed directly to shell-capable agents (Claude Code, OpenCode) with
**no MCP wrapper** — a wrapper would only re-encode what the CLI already provides,
through a narrower and harder-to-maintain interface, while bypassing the agent host's
own permission gating. Consequently the **CLI contract itself** (argv, exit codes,
output shape, process lifecycle) *is* the usability + safety boundary. Every design
choice below follows from taking that contract as the product.

## 2. Ownership model — two surfaces, both 100% owned

No opinionated third-party YouTube client anywhere in the path. All YouTube-specific
orchestration lives in code we own; the external primitives do only universal,
non-YouTube heavy lifting, each isolated behind a single seam (§5).

```
   Human surface     ──►  yt-tui             (interactive: self-rendered menu, detached play)
   LLM/agent surface ──►  yt-search, yt-play (headless: structured JSON, gated verbs)
   Internal engine   ──►  yt (core)          (search / play / resolve / lifecycle; not on PATH)
   Primitives        ──►  yt-dlp · mpv       (foundational, swappable behind seams)
```

**Why ownership matters (D6).** Surveyed alternatives were rejected as runtime
dependencies: `ytfzf` dormant (~21 months, GPL-3.0) — client-level lock-in risk;
`yewtube` a heavier Python app; `yt-x` (MIT, active) used only as a *reference* for
layout/keybinding ideas — no code or dependency taken. All clients are bottlenecked by
`yt-dlp` anyway, so a third-party client buys no capability we can't assemble ourselves
while costing portability. Conclusion: own the glue, depend only on primitives.

## 3. Design decisions (index)

One line each; full rationale lives in the referenced section.

```
  D0  Names: yt, yt-search, yt-play, yt-tui — self-descriptive, and the canonical
      name every doc, help text and error message uses. ONE name per command on
      PATH, and for the two AGENT-facing wrappers that name is the canonical one:
      bin/ carries yt-search and yt-play under their own names, beside ytt for the
      TUI — the one command a human types by hand. yts/ytp are deprecated; they
      were a second spelling of an identity that already existed, which is the very
      thing this decision exists to prevent.  (§4)
      "tui" not "ui": it is precisely a full-screen *terminal* UI.
  D1  The core (yt) is NON-INTERACTIVE. An agent-facing engine that can prompt can
      also hang; removing the capability makes the failure mode impossible.   (§6)
  D2  Bare `yt "query"` → list output; `yt <url>` → play (impl-internal contract;
      wrappers locate `yt` by relative path — see §4 — it is not symlinked into bin/).
  D3  `yt` with no query/URL/action → usage error pointing at yt-tui; never prompts.
  D4  yt-tui renders its OWN menu (no picker/TUI framework) and delegates:
      search → yt-search -j · play → yt-play -f MODE -- url (blocking) ·
      filter → pure bash.                                                     (§11)
  D5  No fzf / interactive dependency anywhere in the suite.                  (§11)
  D6  No third-party YouTube client dependency.                               (§2)
  D7  One shared core; verbs are thin gates that exec into it.                (§4)
  D8  yt-tui composes the VERBS, never the core directly.                     (§13)
  D9  Detached handle = a monotonic mktemp token, NOT the pid: the socket path is
      known before launch and it is immune to pid reuse; pid kept only for
      liveness. Runtime control (--set-volume) rides mpv's per-instance IPC. (§9.3)
  D10 NO EMOJI in the TUI. Every glyph it draws is text-presentation ("non-graphical"),
      and titles are stripped of emoji before display. This is not decoration: it is what
      makes the width tables exact instead of merely conservative, because a
      text-presentation glyph cannot carry a U+FE0F and become two cells behind the
      table's back. 17 glyphs, closed inventory.                              (§21)
  D11 A detached player has NO KEYBOARD. detach_play redirects the child's stdin to
      /dev/null and run_mpv adds --input-terminal=no on the detached path. This is a
      consequence of D9's process group, not an independent choice: `set -m` suppresses
      bash's OWN automatic /dev/null for background jobs, so the child inherited the
      caller's tty and mpv raced yt-tui for every keystroke.                  (§9.1)
```

## 4. Command topology & file layout

Four commands, one engine. `yt` is the full **non-interactive** core (search + play +
resolve + lifecycle), kept internal to `shell/` — not a PATH-exposed surface.
`yt-search`/`yt-play` are narrow real wrappers that gate flags and delegate. `yt-tui`
is the interactive human surface — pure orchestration with **zero** search/play logic.

```
                          PATH entries (user-created)
        ~/bin/
        ├── yt-search → <checkout>/shell/yt-search    agent surface
        ├── yt-play   → <checkout>/shell/yt-play      agent surface
        └── ytt       → <checkout>/shell/yt-tui       human surface
              ONE name per command; ytt is the only short form

        shell/
          yt          CORE engine (all search/play/resolve/lifecycle logic); not
                      symlinked into bin/ — reached only by the wrappers below
          yt-search   narrow wrapper ─┐  each locates `yt` by a path RELATIVE to its
          yt-play     narrow wrapper ─┼─► exec  yt   own script location (not PATH
          yt-tui      menu orchestrator┘  yt-search -j → menu → yt-play  lookup), so it
                                                                          needs no bin/
                                                                          entry to work.

   Dependency graph (search/play logic exists ONCE, in the core):
     yt-search ─┐                       yt-tui ─► yt-search ─► yt
     yt-play  ──┼─► yt (core)           yt-tui ─► yt-play   ─► yt
                                        yt-tui ─► jq        (primitive)
```

**Why symlinks, not copies:** the PATH entries are symlinks with zero logic of their own
(OS branching lives in the core via `uname -s`). One physical copy of every script, so no
two installs can drift.

**Why the PATH name IS the canonical name, and why `ytt` is the exception:** `bin/` once
carried both spellings of all three commands — six symlinks onto three scripts — so every
command answered to two names and each doc, allowlist and habit had to pick one. The rule
that settled it was ONE name per command, and the short forms won on the grounds that they
are what actually gets typed.

That ground holds for exactly one of the three. `yt-tui` is the human surface and `ytt` is
typed by hand every day. `yt-search` and `yt-play` are the AGENT surface: nobody types them,
an agent gains nothing from three letters, and their help text and error messages have always
said `yt-search` / `yt-play`. So for those two the short form was never a second name that
bought typing — it was just a second name, which is what the rule existed to prevent, and it
put the identity and the PATH entry at two different spellings of the same command. They now
sit on PATH under their own names and `yts`/`ytp` are deprecated.

Deprecation costs nothing to honour: no script reads its own `argv[0]` for dispatch (the
symlink chain below is resolved only to LOCATE the siblings), so a leftover `~/bin/yts` goes
on working — it is simply no longer a documented spelling. Consequence:
invoked as `~/bin/ytt`, a script's `$0` is the SYMLINK, not the code — so each script
resolves its own symlink chain first and takes the real file's directory as the place to
look for its siblings. That is the whole mechanism, and it is why the checkout can live
anywhere.

`cd -P` / `pwd -P`, not the logical forms: a relative symlink resolves to something like
`~/bin/../../../elsewhere/shell`, and a logical `cd` would normalise those `..` textually
against `~/bin` rather than against what `~/bin` actually points at — landing in a
directory that does not exist. bash 3.2 has no `readlink -f`, hence the hand-rolled loop.
(This replaced an earlier `../../shell-scripts/` hop that only worked inside one specific
dotfiles layout; extracting the suite into its own repo is what exposed it.)

Anything that calls `yt-search`/`yt-play` by name through PATH — agent tool definitions,
Claude Code Bash allowlist entries — now uses exactly those names. This paragraph used to
read "must use `yts`/`ytp`, or an absolute path into the checkout's `shell/`", and that
sentence was the whole argument for D0's revision: the friction landed on the one surface
that cannot infer a name from context, so an allowlist entry said `yts` while every error
message the agent read back said `yt-search`.

Callers INSIDE the checkout (the rigs in `tests/`, the skills) use the repo-relative
`shell/yt-search` form instead. They run beside the code and must not depend on the user's
PATH at all — a rig that resolved through `~/bin` would be testing the install, not the
suite.

**Why real wrappers, not `$0`-dispatch in one script:** a real, short wrapper makes each
tool *physically* what it claims — `yt-search`'s help is short because the script is
short, and it literally cannot accept `--detach`. Flag-gating lives naturally in it.

**Why `yt-tui` is separate glue, not a mode of the core:** keeping the core
non-interactive means the agent-facing surface can never prompt or hang (D1). `yt-tui`
re-uses the verbs rather than re-implementing search/play — no YouTube logic, no extra
runtime dependency.

**Why `yt` is not symlinked into `bin/`:** it previously was, on the reasoning that it
was "itself a shipped command." In practice every caller — human (`yt-tui`) and
agent (`yt-search`/`yt-play`) — goes through a narrow verb, never `yt` directly; a
PATH-exposed `yt` only invited bypassing the flag-gating the verbs exist to provide
(D7). The wrappers don't need it on PATH either: they resolve `IMPL` via a path
relative to their own `$SCRIPT_DIR`, so `yt` only has to exist as a file in
`shell/`. `yt` keeps its full standalone argument parsing (D2/D3) for
direct debugging from `shell/`, it's just no longer advertised as a surface.

**Why a shared core at all, not per-verb `yt-dlp`/`mpv` (D7):** Search and play
genuinely SHARE logic: per-platform cookie-from-browser detection serves both, and
yt-dlp resolution is not play-only (probe-then-play §8.2 and `--get-url` §10 both use
`yt-dlp -g`). Flattening each verb onto the primitives duplicates that surface — the
exact drift the graph above prevents. The only non-duplicating alternative (a sourced
helper lib + self-contained verbs) is a lateral move: the wrappers already `exec` into
the core — a few ms of bash parse, ZERO extra processes. Governing principle:
**correctness is added *down* in the core, so every surface inherits it — never *up*
in a UI.**

## 5. Primitives & seams (swap points)

| Primitive | Role | Why foundational (not a client) | Seam (single swap point) |
|---|---|---|---|
| **yt-dlp** | extraction / search | de-facto standard; every client uses it | `fetch_results`, `resolve_info`, `resolve_transcript`, `resolve_stream_url`, `probe_media_fetchable`, `detach_title_updater` (6 direct sites) **plus one INDIRECT site inside mpv** — see §6.1 |
| **mpv** | playback | general scriptable player; alt = vlc/ffplay | `run_mpv()` (single play seam) + `mpv_supports_vo()` capability probe |
| jq | JSON shaping | universal JSON tool | pervasive (search/JSON emit, lifecycle, `yt-tui` rows) |

Only **mpv** sits behind a single function (`run_mpv` — all five `play_*_url` modes route
through it), so swapping it (mpv→vlc) is a nearly localized edit; two mpv-specific details
sit outside it by necessity — `mpv_supports_vo()` asks mpv what terminal VOs it has, and
`play_viz_url` passes mpv's `--lavfi-complex` showwaves filter through `run_mpv`. **yt-dlp** is invoked at
the ~5 sites above rather than one seam — but it is the extraction standard every client
depends on, so replacing it isn't a realistic goal; the value is that each site is a
plain `yt-dlp …` array, not buried in a third-party client. The seventh invocation is not
ours at all: **mpv resolves the played stream by running yt-dlp itself** (§6.1), so the
core's only channel to that call is `--ytdl-format` / `--ytdl-raw-options`. **jq** is pervasive. The
in-list filter uses no primitive at all (§11).

---

# Part II — Functional structure

## 6. End-to-end control flow

```
   $ yt-search -j "lofi"                 $ yt-play --get-url "https://youtu.be/ID"
        │                                     │
        ▼                                     ▼
   ┌─────────────────────┐              ┌─────────────────────┐
   │ WRAPPER (yt-search) │              │ WRAPPER (yt-play)   │
   │ • search-only help  │              │ • play-only help    │
   │ • reject play flags │              │ • reject search flg │
   │ • reject URL arg    │              │ • require URL arg   │
   │ • default -l        │              │ • detect --action   │
   │ • flags before query│              │ • flags before URL  │
   └──────────┬──────────┘              └──────────┬──────────┘
              │  exec yt <gated argv>              │
              └───────────────┬────────────────────┘
                              ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ yt  (core)                                                         │
   │  (a) long-opt NORMALIZATION loop                                   │
   │      --json→-j  --json-full→-J  --detach→-d  --color/--volume→vars │
   │      --status/--stop/--get-url/--info/--set-volume → set_action     │
   │      `--` → END OF OPTIONS: rest copied verbatim (getopts stops too)│
   │  (b) getopts  ":n:m:M:s:f:S:dljJh"  → NUM_RESULTS, MODE, …         │
   │  (c) VALIDATION  ints, enums (sort, color), -M>-m, ascii VO,       │
   │      one action only, --id/--all only w/ lifecycle, -d not w/ an    │
   │      action, -d not w/ ascii|viz                                    │
   │  (d) IS_URL? + action/URL guards + empty-query (D3) guard          │
   │  (e) ROUTING (first match wins):                                   │
   │        empty query & not URL & no action → die (D3)                │
   │        ACTION=status → do_status   (jq only; exit 0)               │
   │        ACTION=stop   → do_stop     (jq only; exit 0|4)             │
   │        ACTION=set-volume → do_set_volume (jq+nc only; exit 0|4)       │
   │        IS_URL:                                                     │
   │           ACTION=geturl → resolve_stream_url   (no play)           │
   │           DETACH        → detach_play          (background)        │
   │           OUTPUT=json   → play_url_json        (structured)        │
   │           else          → play_url_directly    (prose)             │
   │        else (non-URL, query present):                              │
   │           OUTPUT=list      → fetch_results → print_list  (default) │
   │           OUTPUT=json|full → fetch_results → emit_search_json      │
   └──────────────────────────────────────────────────────────────────┘
```

**Non-interactive core (D1/D2/D3).** The core never prompts. The empty-query guard runs
*before* the yt-dlp/mpv dependency check so the message is about the missing input, not
a missing player.

**`--` is honoured by the core, not merely consumed by the wrappers.** The normalization
loop stops at `--` and copies everything after it verbatim (including the `--` itself, so
`getopts` stops there too — verified on bash 3.2). Both wrappers *forward* `--` ahead of
the positional. Without this the loop kept scanning past `--` and a query that merely
LOOKED like a long flag became an action: `yt-search -- --status` listed players instead of
searching for that text, and a query starting with a single dash was eaten by `getopts`.

**One action per call.** `set_action` records which flag claimed the call and rejects a
second, different one (`--status --stop` → "conflicting actions"), where the old
last-flag-wins parse silently discarded the first. `--id`/`--all` are rejected outside
`--stop`/`--set-volume`, and `-d` is rejected alongside any action — all three used to be
accepted and ignored.

**Why a normalization loop before getopts:** bash `getopts` only understands single
letters. The loop maps the long options that DO have a short form to it
(`--json`→`-j`, `--json-full`→`-J`, `--detach`→`-d`, `--list`→`-l`, `--help`→`-h`) and
consumes the no-short-form ones — the actions
(`--status`/`--stop`/`--get-url`/`--info`/`--set-volume`, plus `--id`/`--all`) and the
value-carrying `--color`/`--volume` — straight into globals, so getopts never sees them.
There is deliberately no `-c` short flag for color (it is `--color` only); `-S` (not
`-F`) is the format-sort override.

**Why wrappers place flags before the positional:** `getopts` stops at the first
non-option argument. If the query/URL preceded a flag (e.g. the injected `-l`), that
flag would be swallowed into `QUERY` and silently ignored (a real past bug: it dropped
`yt-search` into the old menu). Both wrappers collect option and positional tokens
separately, emit `<flags> <positional>`, and delegate with a `--` guard so a query/URL
beginning with `-` is safe.

### 6.1 Invocation stack — which processes run, and where yt-dlp actually runs

§6 above answers *"which function handles this argv"*. This answers *"which **processes** get
spawned, and at which of them does yt-dlp run"*. The two views differ in one load-bearing
way: **the core never resolves the stream that is played — mpv does, by running yt-dlp
itself.** Everything downstream in this section follows from that.

**A. Search and the read-only verbs — one process, exactly one yt-dlp**

```
   $ yt-search -j -- "lofi"                       $ yt-play --info -j -- <url>
         │                                              │
         │   exec  (the wrapper is REPLACED, not forked: the core's exit
         │          code IS the wrapper's; nothing to forward)
         ▼                                              ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ PROCESS 1 :  yt  (core)                                          │
   │                                                                  │
   │    fetch_results        ──►  yt-dlp "ytsearch<N>:<query>"   [#1] │
   │    resolve_info         ──►  yt-dlp --dump-single-json      [#2] │
   │    resolve_transcript   ──►  yt-dlp --skip-download …       [#3] │
   │    resolve_stream_url   ──►  yt-dlp -g -f <fmt>             [#4] │
   │            │                                                     │
   │            └── jq ──►  single-line envelope on stdout            │
   └──────────────────────────────────────────────────────────────────┘
         one core process · exactly one yt-dlp per call · mpv never starts
```

**B. Detached playback — three processes, and the stack breaks twice**

```
   $ yt-play -d -j -- <url>
         │   exec
         ▼
   ┌───────────────────────────────────────────────────────────────────────────┐
   │ PROCESS 1 :  yt (core) — the RETURNING parent                             │
   │    detach_play:  ensure_state_dir · new_player_id · lock_player_state     │
   │         │                                                                 │
   │         ├── nohup bash "$SELF" -f MODE -- <url> &     ◄─ BOUNDARY 1       │
   │         │      a FRESH CORE PROCESS, not mpv directly. set -m + disown,   │
   │         │      so the player survives this parent's exit (§9.1)           │
   │         │                                                                 │
   │         ├── detach_title_updater &                                        │
   │         │      └── yt-dlp --print "%(title)s" --skip-download       [#5]  │
   │         │      background sibling; patches players/<id>.json .title       │
   │         │      under the lock, only while the pid still matches           │
   │         │                                                                 │
   │         └── emit {status:"started", id, pid, …}  and EXIT                 │
   └───────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼
   ┌───────────────────────────────────────────────────────────────────────────┐
   │ PROCESS 2 :  yt (core again, YT_DETACHED=1, YT_IPC_SOCK=<sock>)           │
   │    play_url_directly → play_url_with_probe                                │
   │         ├── no cookies ─────────────────────────────► probe SKIPPED       │
   │         └── cookies + curl → probe_media_fetchable                        │
   │                  yt-dlp -g  (with cookies)                          [#6]  │
   │                  yt-dlp -g  (anonymous, only if #6 failed)          [#6'] │
   │                  the resolved URL is DISCARDED — the probe only picks     │
   │                  WHICH CLIENT mpv will be told to use (§8.2)              │
   │         └── play_mode_url → run_mpv                                       │
   │                  mpv --ytdl-format=<fmt> --ytdl-raw-options=<k=v,…>       │
   │                      --input-ipc-server=<sock>  <PAGE URL>   ◄─ BOUNDARY 2│
   └───────────────────────────────────────────────────────────────────────────┘
                        │   mpv brings its own extractor
                        ▼
   ┌───────────────────────────────────────────────────────────────────────────┐
   │ PROCESS 3 :  mpv                                                          │
   │    player/lua/ytdl_hook.lua                                               │
   │         ├── runs yt-dlp as a subprocess   ◄── THE resolution that is      │
   │         │      page URL ─► direct media URL + http_headers    PLAYED [#7] │
   │         └── set_http_headers()  ─► file-local-options/user-agent          │
   │                                    file-local-options/http-header-fields  │
   │                                    (whitelist: User-Agent + Cookie,       │
   │                                     Referer, X-Forwarded-For — nothing    │
   │                                     else is forwarded, and the whole      │
   │                                     block is skipped if the caller        │
   │                                     already set either option)            │
   │    demux → decode → audio out;  serves JSON IPC on the unix socket        │
   └───────────────────────────────────────────────────────────────────────────┘
```

**C. Lifecycle control — no yt-dlp, and no new mpv**

```
   $ yt-play --status -j    |    --set-volume 60 --id <id>    |    --stop --all
         │   exec
         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ PROCESS 1 :  yt (core)                                           │
   │    reap_dead_players → resolve_target                            │
   │    read_player_live → live_props ──► nc -U <sock> ──┐            │
   │    do_stop → stop_group ──► kill the process group  │            │
   │         │                                            ▼           │
   │         └── jq ──► envelope            (the ALREADY-RUNNING mpv) │
   └──────────────────────────────────────────────────────────────────┘
         no yt-dlp · no new mpv · one socket round-trip per player
```

`yt-tui` adds no fourth shape: it runs **A** (`yt-search -j`) and **B** (`yt-play -d -j`) as
child processes, then talks to the player's socket with its own `nc -U` rather than going
back through `yt-play` (§11).

**The seven invocation sites**

| # | Where | Command | Whose process | What the result is used for |
|---|---|---|---|---|
| 1 | `fetch_results` | `yt-dlp ytsearch<N>:…` | core | the search envelope |
| 2 | `resolve_info` | `yt-dlp --dump-single-json` | core | the `--info` envelope |
| 3 | `resolve_transcript` | `yt-dlp --skip-download` | core | caption file → text |
| 4 | `resolve_stream_url` | `yt-dlp -g` | core | the `--get-url` envelope |
| 5 | `detach_title_updater` | `yt-dlp --print "%(title)s"` | core (bg sibling) | `.title` in the player record |
| 6 | `probe_media_fetchable` | `yt-dlp -g` (×1, ×2 on fallback) | detached child | **discarded** — only picks the client (§8.2) |
| 7 | `ytdl_hook.lua` | `yt-dlp` | **mpv** | **the stream that is actually played** |

**Three consequences worth stating plainly**

1. **Site 7 is not ours.** The only channel from the core to it is `--ytdl-format` and
   `--ytdl-raw-options`; the core cannot append arbitrary yt-dlp argv to the call that
   matters. Anything a future extractor needs at play time has to fit through those two.
2. **Headers reach mpv but not a `--get-url` caller.** Site 7's `http_headers` are applied
   by `set_http_headers`, so playback of a CDN that demands a `Referer` works. Site 4 emits
   the URL alone and the envelope has no field for headers (§10, §14) — so the same video
   can play correctly and hand a caller a URL that the CDN refuses.
3. **One detached play can run yt-dlp up to four times** (#5, #6, #6', #7), each an
   independent extraction of the same video. #6/#6' are skipped without cookies or without
   `curl`; #5 exists only because the core is handed a URL, never a title.

---

## 7. Search subsystem

```
  QUERY, NUM_RESULTS, MIN/MAX_DURATION, SORT_FIELD, FORMAT_SORT, cookies
        │
        ▼
  ┌─────────────────────────────────────────────────────────────┐
  │ fetch_results()                                              │
  │  yt-dlp "ytsearch<N>:<QUERY>"                                │
  │     [--match-filter "duration > MIN [and duration < MAX]"]   │  ← only if asked
  │     [--cookies-from-browser <B>] --flat-playlist             │
  │     --dump-single-json -f ba --skip-download --quiet …       │
  │     stderr → captured; non-zero rc ⇒ error envelope + exit   │
  │        │                                                     │
  │        ▼  ONE jq program (JQ_PRELUDE + shaping):             │
  │           bounds select → + {duration_fmt: dur|fmt_dur}      │
  │           → sort_by(duration|view_count)|reverse             │
  │  FILTERED_JSON  (array; internal shape — NEVER changed)      │
  └───────────────┬───────────────────────┬──────────────────────┘
      OUTPUT=list │            OUTPUT=json │ json_full
                  ▼                        ▼
           print_list()            emit_search_json()
        "♫ N. title / dur /       {query,count,results:[ project ]}
         views / url"             json: 8 lean fields; json_full: raw
```

`print_list()` reads the **`FILTERED_JSON` variable**, not the emitted `-j` stream.
Projection happens only at the emit point, so the JSON contract can change without
touching that consumer. (Schemas → §14.)

**One jq program, not a per-entry loop.** Shaping used to run a bash `while read` loop that
forked jq twice per entry, and `print_list` forked jq five times per row — 175 processes
for `-n 25`, measured ~40× slower than the single program that replaced them, with
`duration_fmt` re-derived in `print_list` even though `FILTERED_JSON` already carried it.

**Duration formatting lives in ONE place: the `JQ_PRELUDE` jq function** (`fmt_dur`), reused
by search shaping and `--info`. It is jq rather than bash because every consumer is already
shaping JSON with jq, so a bash implementation existed only to be forked once per row. The
bash `convert_seconds` it replaced is gone. An unknown duration now yields **`null`**, not a
fake `00h:00m:00s`, and each surface decides how to render that: `print_list` prints `LIVE`
for a live stream / `--` otherwise (it used to leak a raw `null views` into human output),
and `yt-tui` shows `● LIVE`.

**Duration bounds (`-m`/`-M`) are enforced CLIENT-SIDE, in that same jq pass.**
`--match-filter` is only a cheap server-side pre-filter, and is sent **only when a bound was
actually requested** (the old always-on `duration > 0` filtered nothing). Reason: with
`--flat-playlist` yt-dlp marks entries "incomplete", so a filter on a field a flat entry
does not carry — a live stream has no duration — cannot decide and KEEPS the entry. Verified:
`-m 999999` used to still return a live result; now `-m`/`-M` exclude unknown-duration
entries as the flag implies.

**Search has an error contract like every other surface.** A yt-dlp failure used to abort on
`set -e` with raw stderr even under `-j`, handing an agent a jq parse error. `fetch_results`
captures stderr, classifies it with the shared `classify_playback_error` taxonomy, and emits
`{status:"error", query, count:0, results:[], reason}` for `-j`/`-J` (prose: the captured
stderr plus a `die`). Exit is 2+ — never 1, which §15 reserves for usage/validation.

## 8. Playback subsystem

### 8.1 Mode → format → mpv

```
  PLAYBACK_MODE   format_for_mode()          mpv option set
  ─────────────   ───────────────────        ───────────────────────────────
  audio           YT_AUDIO_FORMAT (ba/b)      --no-video (audio only)
  video           YT_VIDEO_FORMAT (bv*+ba/b)  default VO
  fast            YT_VIDEO_FORMAT_FAST        default VO (progressive, fast start)
  ascii           YT_VIDEO_FORMAT             --vo=<YT_ASCII_VO> --profile=sw-fast
  viz             YT_AUDIO_FORMAT             --vo=tct + showwaves lavfi filter

  run_mpv(url, format, mpv_opts…):
     mpv --ytdl-format=<format>
         [--ytdl-raw-options=cookies-from-browser=<B>]   # when login on (the default)
         [--ytdl-raw-options=extractor-args=youtube:player_client=android] # anonymous fallback
         <mpv_opts…> <url>
```

mpv drives yt-dlp internally (its `ytdl_hook`); cookies (when login is on) pass through
`--ytdl-raw-options` (one comma-joined key/value flag).

**Terminal-noise quieting & viewport shielding (video and audio modes).** `video`/`fast` render the media
**title** as a video OSD via libass. When the title carries glyphs no font covers (emoji —
pervasive on YouTube), libass emits a per-frame `[osd/libass] fontselect: failed to find
any fallback with glyph …` warning and macOS CoreText emits a `CoreText note: … .LastResort
…` line. Furthermore, mpv's default startup dumps 8–10 lines of metadata (`File tags:`, `Date:`,
`Uploader:`), which pushes `yt-tui`'s menu into scrollback and displaces the progress bar.
The fix keeps the on-window OSD/OSC and terminal progress bar stable via two parts:

1. **`--msg-level=display-tags=warn,osd/libass=error`** suppresses the libass `fontselect` warnings
   and multi-line metadata tag dumps (`File tags:`) at the source, keeping error level for the `-j` classifier (§8.3).
2. **A stderr filter in `run_mpv`** drops the leftover CoreText notes — which no mpv flag
   can reach — with `2> >(grep -vE 'CoreText note|\.LastResort|fontselect' >&2)`.

The split is what makes this safe: mpv prints the useful `--term-osd-bar`/`AV:` status on
**stdout** and the noise on **stderr**, so filtering stderr never touches the progress bar.
Process substitution (not a pipe) leaves `$?` as mpv's own exit code, so `q` (130) and real
failures still propagate.

**The filter runs only when a human is watching this terminal** — i.e. not under `-j` and
not in a detached child. Two reasons. It buys nothing there: `play_url_json` captures
stdout+stderr into a temp file that is never displayed, and a detached child writes to its
log. And it costs correctness: the process substitution is not waited on, so
`play_url_json` — which reads that temp file the instant mpv exits — could miss a
late-flushed error line and classify a real 403 as `unknown`. The filter drops only
non-error lines, so on the prose path the `-j` error taxonomy is unaffected — the classifier still sees `403`/unavailable/etc., and the JSON status line
(emitted on real stdout) is never routed through the filter. `audio` mode avoids vertical menu
displacement (`--no-video` + suppressed tags), keeping `yt-tui`'s menu intact while mpv's in-place
status bar (`A: ...`) updates directly below it; `ascii` uses `--really-quiet`.

Three alternatives were tested and rejected: **`--osd-level=0`** kills the noise at the root
but also disables the on-window OSD/OSC (no seek bar/controls in the window);
**`--msg-level=all=error`** silences the noise but over-suppresses the useful status bar
(blank playback); **`OS_ACTIVITY_MODE=disable`** does NOT stop the CoreText notes (emitted
below the `os_log` activity layer). Measured on an emoji-titled video (window VO): 12
`fontselect` + 7 `CoreText` → 0/0, with the status bar and window OSD both intact, and the
`-j` JSON contract verified (single valid line, correct `reason`, exit code propagated).

### 8.2 Login, PO tokens, and the probe-then-play client pick

**Login is ON by default (`YT_COOKIE_BROWSER=chrome`)** so login-gated / members /
age-restricted videos — invisible to an anonymous client — play. The trade-off: with
cookies, yt-dlp switches to YouTube's authenticated client set, whose googlevideo media
URLs can require a **GVS Proof-of-Origin (PO) token**, minted by Google's BotGuard
attestation (yt-dlp's PO Token Guide; `bgutil-ytdlp-pot-provider` is the standard
provider). Without a provider, the authenticated URLs **403 on a plain GET** for *some
public videos*, while the anonymous client's URLs need no token and fetch cleanly
(HTTP 206). Verified on this machine: same public video → 403 with cookies, 206 without.

The naive fix — play, let mpv 403, replay anonymous — works but dumps mpv's error wall
on screen before the retry. Instead the default **probes which client can actually
fetch the media BEFORE launching mpv**, then plays **once** with the winner.
`probe_media_fetchable` resolves the direct media URL (`yt-dlp -g`) and issues an
**open-ended ranged request** (`curl -I -r 0-`): 206/200 ⇒ authorized; 403 ⇒ missing PO token — the
same verdict mpv would reach mid-load (and for HLS `.m3u8` playlists, probes the first segment).
Anonymous fallback and anonymous probe use `extractor-args=youtube:player_client=android` to ensure
YouTube's CDN serves streams that do not 403 on range requests.

```
   play_url_with_probe(url, mode):
      PLAYBACK_RETRIED=0
      cookies OFF (none) ──────────────► play_mode_url(url, mode)   # nothing to weigh, no probe
      curl present:                                                 # PROBE-THEN-PLAY (default)
        probe cookies  (resolve + ranged check) ── 206 ─► keep cookies       # e.g. login-gated
                                              └─ 403 ─► probe anonymous ── 206 ─► drop cookies + use android client
                                                                              PLAYBACK_RETRIED=1
        (neither fetches → keep cookies, let mpv emit the real error / exit code)
        play_mode_url(url, mode)  ──► rc     # a SINGLE play, with the chosen client
      curl absent:                                                  # graceful fallback
        play_mode_url(url, mode)  ── rc!=0 & cookies in use ─► retry once anonymous (old path)
      return rc
```

Implementation notes: `local YT_COOKIE_ARGS=()` shadows the global (bash dynamic
scoping) so `run_mpv` drops cookies for the chosen play without touching the real
setting; `PLAYBACK_RETRIED` surfaces as `retried` in the playback JSON. Cost: one extra
resolve + 1-byte GET per play (two on a cookie-403 video). `curl` is a soft dependency —
without it the probe is skipped and the old play-fail-replay retry runs (the error-dump
regression reappears only there). `YT_COOKIE_BROWSER=none` forces anonymous-only (no
keychain read, no probe); a configured browser with no local profile auto-degrades to
anonymous rather than erroring.

### 8.3 Playback output modes & error taxonomy

```
   yt-play <url>        → play_url_directly  → prose ("Playing audio: …") [DEFAULT]
   yt-play -j <url>     → play_url_json      → one final JSON line, chatter suppressed
   yt-play -d <url>     → detach_play        → background; JSON/prose "started"
   yt-play --get-url    → resolve_stream_url → stream URL(s), no playback
```

`play_url_json` captures the player's stdout+stderr (suppressing chatter) and emits one
JSON line, reusing `play_url_with_probe` unchanged. `classify_playback_error(text, rc)`
maps captured output to a fixed enum — never raw mpv wording, which is not a contract:

```
   rc == 130 ......................................... stopped_by_user
   "HTTP Error 403" | "Forbidden" ................... forbidden
   "Video unavailable"|private|removed|members-only . unavailable
   "Requested format is not available" .............. format_unavailable
   name-resolution|connection|timeout ............... network
   (anything else — conservative default) ........... unknown
   rc == 0 .......................................... reason = null (status ok)
```

`exit_code` is the real mpv exit status; the process exit code stays truthful (130 is
normalized to 0 — an intentional stop). (Schema → §14.)

## 9. Detached playback lifecycle

### 9.1 Process-group model (why, not a PID tree)

A detached playback is `bash yt` with the probe's short-lived `yt-dlp`/`curl` children,
then `mpv` — and, on a curl-less machine, possibly a **second (retry) mpv spawned
later**. Two facts break naive process-tree killing:

1. A late-spawned mpv appears *after* any one-time PID snapshot.
2. Once the parent `bash` exits, mpv **reparents to init** (`ppid=1`) — a walk from the
   original PID can no longer find it → orphan that keeps playing.

Solution: launch the child as its **own process-group leader** and operate on the whole
group. `pgid` is invariant under reparenting, so it always reaches every descendant.

**The process group costs the child its free stdin, and that has to be paid back
explicitly.** bash redirects a background job's stdin to `/dev/null` on its own — but only
while job control is OFF, which is exactly what `set -m` turns on for the sake of the group
above. So the two lines that buy the pgid silently hand the child the LAUNCHER's stdin, and
for an interactive caller that is the terminal. mpv then keeps `input-terminal` on and reads
the same tty its launcher reads: under `yt-tui` the two processes raced for every byte, and
mpv's own default bindings own `[`/`]` (playback **speed**), `9`/`0`, `Space`, `q`, `s` and
`m` — the same keys the TUI binds. Whichever `read()` won got the byte, so keys "did
nothing" nondeterministically and `[`/`]` silently changed the speed of the stream when mpv
won. Verified with `lsof` under a pty: before, wrapper and mpv both held `/dev/ttysNNN` and
mpv answered `input-terminal=true`; after, both hold `/dev/null` and it answers `false`.
`</dev/null` goes on the launch rather than only into mpv's flags because the launch is the
one place every detached player passes through, and it covers the whole child tree —
the probe's `yt-dlp`/`curl` and any late retry mpv included. The mpv flag is kept as well:
it states the same fact where mpv can be read, and survives anyone who later launches the
child differently.

```
   detach_play():
      ensure_state_dir()              # 0700 STATE_DIR + players/ (socket = a control channel)
      id = new_player_id()            # mktemp token; socket path known before launch
      set -m                          # monitor mode: backgrounded job = pgroup leader
      YT_IPC_SOCK=mpv-<id>.sock YT_DETACHED=1 \
        nohup bash SELF -f MODE [--volume N] [-S SORT] -- URL \
            </dev/null >mpv-<id>.log 2>&1 &        # pgid == pid ($!); stdin: see below
      set +m ; disown
      players/<id>.json ← {id,pid,url,mode,format,started_at,log,sock,title:null,volume}
      rm PLAYERS_DIR/<id>              # drop bare mktemp token; state lives in <id>.json
      detach_title_updater(id,pid,url) >/dev/null 2>&1 &   # async backfill; fds MUST be closed

   ┌─ process group  pgid = 57678  (player <id>) ───────────┐
   │  57678  bash yt -f audio URL   (leader)                │
   │    ├─ (probe: yt-dlp + curl, short-lived)               │
   │    └─ 57712  mpv --input-ipc-server=mpv-<id>.sock       │  ← reparents to init
   └──────────────────────────────────────────────────────────┘     but pgid stays

   stop_group(pgid):  kill -INT -pgid ; wait (pgrep -g); escalate kill -KILL -pgid
   group_alive(pgid): pgrep -g pgid has ≥1 member
```

**`YT_DETACHED=1` (why the child must know it is detached).** A detached player has no
terminal, so nobody ever reads mpv's status line — but mpv kept writing it into
`mpv-<id>.log`: ~2.4 MB/h measured on a 24/7 stream, i.e. unbounded growth in `$TMPDIR` for
exactly the long-lived players `-d` exists for. The child's `run_mpv` therefore appends
`--no-term-osd-bar --msg-level=all=error` (after the mode options, so they win) and skips
the stderr noise filter. Measured after: 59-byte log, zero growth over 12s, and a real
failure still recorded (`[ytdl_hook] ERROR: …`). `-S` is forwarded to the child like
`--volume` — it used to be silently dropped on the detached path — and the URL is passed
after `--`.

**The title updater's fds must be redirected (`>/dev/null 2>&1 &`).** A background job
inherits the shell's stdout, and a caller that *captures* our output — `out=$(yt-play -d -j
…)`, exactly what `yt-tui` does — blocks until every writer closes that pipe, not just until
we exit. Without the redirect the updater held the pipe for its whole ~3s yt-dlp round trip,
so the "instant" detach measured **1.67s captured vs 0.04s uncaptured**, reintroducing the
very latency the async backfill exists to remove. Measured after the fix: **0.03s captured**.

### 9.2 State machine (multi-player)

```
   Multiple detached players coexist, each its own id/pgid/socket/state/log. A 2nd -d
   is NOT refused — it starts an independent player. Lifecycle verbs pick a target.

        ┌───────────────── (no live players) ◄─────────────────┐
        │              yt-play -d URL   (any number of times)    │
        │                             ▼                          │
        │                   ┌────────────────────┐               │
        │  --status → list  │ N live players      │ --set-volume N│
        │  players[] ───────│  players/<id>.json  │  [--id ID] ───┤ (live volume via IPC)
        │                   └─────────┬──────────┘               │
        │   --stop --id ID  │ stop that one       │  --stop --all │ stop every player
        │   (1 live ⇒ --id  ▼ (2+ live & no --id  ▼               │
        │    optional)      resolve_target        → {ambiguous,   │
        └──── rm its state/sock/log               players:[...]} exit 4)

   • --status ALWAYS exit 0. --stop exits 0 for every case EXCEPT an ambiguous target
     (2+ live players, no --id) which exits 4 — see the next bullet. Idempotent otherwise:
     a polling agent must not read a non-ambiguous non-zero exit as failure. Every
     lifecycle call reaps players whose group is gone.
   • --set-volume / an ambiguous --stop exit 4 (did-not-take-effect; -j reason says why).
   • a player that dies ON ITS OWN leaves a tombstone: --status reports it once in
     failed[] instead of just going empty (see below).
   • state: ${TMPDIR:-/tmp}/yt-cli-$(id -u)/players/<id>.json (+ mpv-<id>.sock, mpv-<id>.log)
            plus players/dead/<id>.json for the tombstones
```

**The other half of the lifecycle: a player that dies unasked (`failed[]`).** `launch →
status → stop` describes every path the caller drives. It said nothing about the path the
caller does not drive, and that path was silent: `-d -j` returns `{"status":"started"}` and
exit 0 long before yt-dlp resolves anything, so a private or removed video fails INSIDE the
child; `reap_dead_players` then deleted the record and the log, and `--status` went empty —
byte-identical to a track that finished normally. The reason existed only in a log that had
just been deleted.

Two pieces close it, and the split is forced by what each process knows:

- **The child writes its own epitaph** (`detached_epitaph`). Only the child knows `rc`, and
  `rc` is exactly what a log cannot show: "played fine" and "failed in a way we do not
  recognise" are the same text to `classify_playback_error` (both `unknown`). The child's
  stdout IS the log, so it appends one line —
  `{"yt_event":"exit","rc":2,"reason":"unavailable","ended_at":"…"}` — with `reason` from the
  shared taxonomy (§14), classified from the tail of the log it was handed as
  `YT_DETACHED_LOG`. Nothing is written when `rc` is 0 or 130.
- **The reaper turns it into a tombstone** (`record_player_death`), read at the one moment
  both the record and the log still exist, and writes `players/dead/<id>.json`.

The bounds are the contract, not politeness — they are what keeps this an error record rather
than the listening history `ROADMAP.md` §0 rules out: **failures only** (a normal finish
writes no epitaph; a `--stop` kills the process group before the child can write one — the
same rule from the other side), **at most 8**, **nothing older than an hour**, and it lives
in the state dir, so it dies with it. No epitaph means no tombstone: a truncated log or a
`kill -9` is reported as silence rather than as an inferred death.

**Async title backfill (why detach stays instant).** The title is the semantic handle a
caller — a small model especially — uses to refer to what's playing ("is the Adagio still
on?"); a URL-only status is a wrong-reference hazard. But resolving the title is a ~3s
yt-dlp round-trip, and detach must return immediately (measured ~0.2s vs ~3s if fetched
inline). So `detach_play` writes `title:null` and spawns `detach_title_updater(pid,url)` as
an INDEPENDENT background job (not the play child): it fetches the title and patches it into
that player's `players/<id>.json` a few seconds later. `--status` shows `title:null` until it
lands, then the real title. The updater is playback-independent (neither blocks detach nor is
killed by stop_group) and self-guarding — it patches only while the state file's `.pid` still
equals its pid, so a `--stop` during the fetch window wins and is never clobbered (jq emits
nothing on a pid mismatch; the empty temp is dropped). Best-effort: any fetch failure just leaves
`title:null`, which every caller tolerates. This is the LLM-first counterpart to rejecting
`--url-only` — add the grounding handle, but never on the hot path.

**`-d` rejects `-f ascii|viz`.** A detached process has no controlling terminal, so the
terminal-rendering modes have nowhere to draw; the guard is now enforced at parse time
(`die`) instead of silently starting a player that scribbles escape sequences into its log.
`audio` is the norm; `video`/`fast` are accepted because their mpv window is a GUI surface
that does not need this terminal. `yt-tui` validates `-f` against the same list.

**The `-d -j` envelope carries `sock` and `log`.** They are already in the state file, and
without them in the envelope a client had to RECONSTRUCT the socket path from the core's
private state layout — which `yt-tui` did, hardcoding
`$TMPDIR/yt-cli-$(id -u)/mpv-<id>.sock` in a second script that would have broken silently
if the core moved its state dir (§9.3). (Schemas → §14.)

### 9.3 Runtime IPC control (`--set-volume`)

`--volume N` sets only mpv's *starting* volume; `--set-volume N [--id ID]` changes it
live on a running detached player without a kill+relaunch. It works across **multiple
concurrent** players, each independently addressable.

**Why concurrent detached players are possible (mpv imposes no obstacle).** mpv is
non-exclusive by default (`--audio-exclusive=no`); the default coreaudio / PulseAudio /
PipeWire outputs are shared, the OS mixes the streams, and each instance's `volume` is
independent **per-process software volume**. Crucially mpv's IPC is per-instance:
`--input-ipc-server=<sock>` is a per-process flag, so pointing each mpv at its own
socket path yields N independent control channels for free. Multi-player is therefore
entirely a **yt-layer** concern — mpv needs no special mode. (This is why the old
"refuse a 2nd `-d` unless `--replace`" single-slot guard was dropped along with
`--replace` itself: a 2nd `-d` just starts another player; `--stop --all` silences
everything; swapping a track is `--stop --id X` + a fresh `-d`.)

**Data flow (one `--set-volume` round-trip).**

```
   LLM caller          yt-play (wrapper)     yt (impl)                    mpv #<id>
      |-- --set-volume 70 --id <id> ------->|                                 |
      |                   |-- exec yt --set-volume 70 --id <id>               |
      |                   |                 |-- resolve_target <id> (reap dead)|
      |                   |                 |-- sock = players/<id>.json.sock  |
      |                   |                 |-- [[ -S sock ]]  (socket-ness)   |
      |                   |                 |-- {"command":["set_property","volume",70],"request_id":1}
      |                   |                 |     | nc -U -w1 sock ----------->|
      |                   |                 |<-- {"request_id":1,"error":"success"} ---|
      |                   |                 |-- atomic temp+mv patch .volume=70 |
      |<-- {"status":"ok","id":<id>,"volume":70} (exit 0) --------------------|
```

Per-file state (a directory of `players/<id>.json`) is chosen over one shared JSON
array on purpose: writes stay atomic per-file (the temp-file+`mv` idiom), there is no
read-modify-write race *across* players, and reaping a dead player is just
`rm <id>.json` (+ its `.sock`/`.log`). Socket/log paths derive from the id, so nothing
else stores them. Within a *single* player's file one RMW hazard remains: the async
title backfill (`detach_title_updater`) and a `--set-volume` can both temp+mv-patch the
same `<id>.json` at once, and whichever `mv` lands last silently clobbers the other's
field. A per-id `mkdir` lock (`lock_player_state`/`unlock_player_state` on
`STATE_DIR/lock-<id>`; `mkdir` is atomic on POSIX and needs no `flock` binary, which
stock macOS lacks) serializes those two writers. It bounded-spins ~5s then proceeds
unlocked, so a crashed lock holder can't wedge callers — the same best-effort risk the
patches carried before the lock existed. `detach_title_updater` *additionally* pid-guards
(it patches only while the file's `.pid` still equals its own pid), so a `--stop` during
the fetch window wins and its reap is never clobbered by a late title write.

**The IPC socket is a PUBLIC part of the `-d` contract (and `volume` is read live).**
`yt-tui` drives pause / seek / volume / progress straight over the socket rather than
forking a verb per keypress: its Now-Playing views refresh once a second and would
otherwise need three `yt-play` → `yt` process chains per tick. That is a deliberate
exception to D8, so the socket path is *handed to the client* in the `-d -j` envelope
(`sock`) instead of being reconstructed from the state-dir layout, and this document — not
an implementation detail — is where the JSON-RPC channel is sanctioned. Consequence for
`--status`: the state file's `volume` only knows about launch `--volume` and `--set-volume`,
so a client moving volume over the socket would make it lie. `--status` therefore reports
**live** volume, falling back to the recorded value. It is soft-gated on `nc`, keeping
`--status`'s jq-only dependency (§15). Verified: two `0` presses in `yt-tui` moved a player
launched at `--volume 0` to `10`, and `--status` reported `10` (it used to report `0`
forever).

**Four properties, one round trip (`live_props` / `read_player_live`).** The same argument
covers `pause`, `time-pos` and `duration`, only worse: the state file has never held them at
all, so the socket was the *only* place they existed and only `yt-tui` was reading it. They
are now part of the player record (§14), read by `live_props(sock, prop…)` — which sends the
whole property list down ONE connection and emits `<request_id><US><value>` lines — and
correlated by `read_player_live`, which both `--status` output modes share so the
normalisation exists once. Three rules are load-bearing:

- **Correlate by `request_id`, never by line order** — mpv interleaves async events into
  every client's stream (the same rule `do_set_volume` carries).
- **`head -n <count>` is what closes the pipe.** mpv answers each command exactly once and
  `jq` has already dropped the id-less events, so the last expected line is where `head`
  exits, SIGPIPEs `nc`, and ends the read. Measured against `tests/mpv_ipc_mock.py`, a peer
  that never closes its side: **1.11s → 0.03s**. The caller breaking its own read loop does
  NOT achieve this — nothing writes again to notice the reader is gone.
- **`|| true` around the pipeline**, or `set -euo pipefail` turns an `nc` timeout into an
  abort at the assignment.

`null` and `false` are kept distinct throughout: `paused:false` means playing, `paused:null`
means the question could not be asked (no `nc`, dead socket, no answer). Reporting `false`
there would be a fabricated reading, which is the failure mode the live read exists to end.
A useful side effect: `paused != null` is now the honest readiness probe for a freshly
detached player — `volume` answers from the state file before mpv is even listening.

**Handle = a monotonic token, not the pid (D9).** `new_player_id` mints the handle via
`basename "$(mktemp "$PLAYERS_DIR/XXXXXX")"` — atomic and collision-free. This solves
two problems at once: (1) the socket must be **named at launch** via `YT_IPC_SOCK`, but
the child's pid isn't known until `$!` *after* launch — the token breaks that
chicken-and-egg; and (2) it makes pid reuse a *narrow residual risk* rather than a live hazard: liveness is
checked against the pid stored inside `<id>.json` and the file is reaped the moment its
group is gone, so the window is only "a reaped-but-not-yet-scanned record whose pid has
already been recycled *by a process-group leader*". It is not full immunity — `group_alive`
is still `pgrep -g <stored pid>` — and in that window a `--stop` would signal an unrelated
group. Closing it properly needs a second invariant (process start time, or probing the
player's own socket); it is accepted, not solved. `mktemp` leaves a **bare** `<id>` file to reserve the id; after
`<id>.json` is written that bare token is `rm`'d — the `*.json` reap glob would never
touch it, so it would otherwise leak one file per launch.

**`do_set_volume` mechanism.** Validate `0-100` (symmetry with the launch `--volume`) →
`resolve_target` → `[[ -S "$sock" ]]` (tests socket-ness, not mere existence, so a stale
socket from a `SIGKILL`'d mpv reports `ipc_failed` instead of hanging) → one-shot `nc` →
check `.error=="success"` → atomic `temp`+`mv` patch of `.volume` (same temp+mv idiom as
`detach_title_updater`, serialized against it by a per-id `mkdir` lock — see below) →
`{status:"ok",id,volume}`; any miss → exit 4.

**`request_id` correlation (why `head -1` alone is wrong).** mpv multiplexes **async
events** to every connected client, interleaved with command replies (mpv `ipc.rst`), so
a bare `head -1` on the socket output can grab an event instead of the ack. The reply is
selected by tagging the command with `"request_id":1` and filtering
`jq -c 'select(.request_id==1)' | head -1`. The pipeline needs a trailing `|| true`:
under `set -euo pipefail` a `nc` timeout / `SIGPIPE` makes the pipeline non-zero and
would abort the script *at the assignment* (same guard idiom as the probe/resolve paths).

**`resolve_target` return-value discipline.** The single place that maps a request to a
player (shared by `--set-volume` and `--stop`). It communicates entirely through
**out-param globals**, printing nothing itself: on success it sets `RESOLVED_ID` and
returns 0; on failure it sets `RESOLVE_ERR` (`not_playing` | `ambiguous`) — plus
`RESOLVE_PLAYERS_JSON` (the candidate list) on ambiguity — and returns non-zero. Callers
invoke it as `if ! resolve_target "$id"; then …; fi` and render the error themselves from
those globals (so `--stop` can treat `not_playing` as idempotent success while
`--set-volume` treats it as exit 4 — the same fd1 must not be pre-committed to one
shape). The globals are set rather than echoed for the same reason `reap_dead_players`
uses globals: a bash-3.2 array (`RESOLVE_PLAYERS_JSON`'s candidates) doesn't survive
`$(...)` capture cleanly, and the caller must not swallow the result into a subshell.
Selection rules: `--id` given → that player (if live), else `not_playing`; no `--id` +
exactly 1 → that one (keeps the common case zero-friction); 0 → `not_playing`; 2+ →
`ambiguous`. Every call first runs `reap_dead_players`, so players whose group is gone
are cleared before selection.

**`nc` over `socat` (no new dep).** Prior-art mpv wrappers use
`socat - UNIX-CONNECT:$sock` (clean EOF, no `-w` latency floor), but socat isn't stock on
macOS. We stay on stock BSD `nc -U -w1` and buy robustness with the `request_id` filter —
cheaper than a dependency the rest of the toolchain doesn't need. Latency is a floor, not
a ceiling (~≤1s/call): mpv holds the socket open, so `nc` may sit until `-w1` if no
follow-on event arrives after the reply — fine for human-driven adjust, not for a tight
loop. Linux `nc -U` differs and is an accepted known gap (§26). `nc` is gated lazily at
dispatch (`require_cmd nc`), never in global `require_deps`, so a bare `yt <query>` search
never demands it (§15).

**References (mpv IPC).**

- mpv `DOCS/man/ipc.rst` (normative) — `request_id` is the sanctioned reply-correlation
  mechanism; events interleave with replies (why `head -1` alone is wrong).
- mpv `DOCS/man/ao.rst` — default output is shared (concurrent instances mix);
  `--audio-exclusive` defaults to `no`.
- purarue/mpv-sockets, wis/mpvSockets — closest prior art: one IPC socket per instance
  (borrowed the per-instance socket naming + jq extraction).
- lwilletts/mpvc — reference for the `set_volume` command shape; its reply parsing
  (greps `"success"`, no `request_id`) is deliberately **not** copied.

## 10. Resolve-only (`--get-url`)

Non-blocking, side-effect-free composability primitive:

```
   resolve_stream_url(url):
      yt-dlp -g -f <format_for_mode(MODE)>
             [--cookies-from-browser B]   # only when login opted in
             --no-warnings --quiet url
      prose: print stream URL(s)          (die on failure)
      -j:    {status, url, mode, format, stream_urls:[…]}   (exit = yt-dlp rc)
```

### 10.1 Metadata-only (`--info`)

Sibling of `--get-url`: read-only, non-blocking, side-effect-free, needs yt-dlp+jq
but NOT mpv (dispatched before the playback dependency check, like `--status`/`--stop`).
Reason it exists: without it an agent that wants to know *what* a video is (description,
chapters, uploader, date, like count) has to leave the ecosystem and drop to raw
`yt-dlp --dump-json` — the same escape-hatch failure the JSON search surface removed.
LLM-first, not human ergonomics (contrast the rejected `--url-only`, which strips
grounding signal): `--info` *adds* the grounding an agent reasons over. `duration_fmt` comes
from the shared `JQ_PRELUDE` `fmt_dur` (§7), so `--info` and search cannot drift on the
format — and it is `null`, not `"00h:00m:00s"`, when the duration is unknown.

```
   resolve_info(url):
      yt-dlp --dump-single-json --skip-download
             [--cookies-from-browser B]   # only when login opted in
             --no-warnings --quiet url
      prose: readable block (title/channel/date/duration/views/likes/live/url,
             then Chapters M:SS, then Description)          (die on failure)
      -j:    lean, high-signal projection mirroring search -j field discipline:
             {status,id,title,url,channel,uploader,upload_date,duration,duration_fmt,
              view_count,like_count,live_status,description,chapters}
             chapters = [{start_time,end_time,title}] | null
      -J:    full raw yt-dlp record (fidelity escape hatch, same role as search -J)
      error: -j/-J → {status:"error",url,reason} exit 1 ; prose → die
```

## 11. `yt-tui` orchestration (owned glue, zero YouTube logic)

The diagram is *what*; the bullets after it are the non-obvious *why*.

```
   yt-tui "lofi" -n 40
        │  parse: SEARCH_ARGS=(-n 40) ; PLAY_MODE=audio ; reject cross-flags
        │  require: jq + verbs; TTY on BOTH -t 0 and -t 1 (reads keys AND draws)
        │  no query on argv → prompt "❯ Search YouTube: " via read_query_input
        │  (Esc / empty / Ctrl-D on an empty line all cancel, exit 0) — the SAME reader
        │  the `n` prompt uses, so Esc means the same thing at the first prompt as
        │  everywhere else; that is why the prompt sits after the input layer is defined
        ▼
   SEARCH  fetch_json:  json = yt-search -j -n "$RESULT_N" "${SEARCH_ARGS[@]}" -- "lofi"
        │  the ONLY search path — the initial fetch, `n` new-search, and `m` more-results
        │  all use it, then the same build_all_rows → load_rows, so they can never drift
        │  spin_start/spin_stop bracket the call, so all four fetch paths (startup, n, m,
        │  o) animate their own `…` line for free — one spinner, no per-caller copies
        ▼
   ALL_ROWS  jq: .results[] → [url, title, duration_fmt, view_count, channel, live_status]
        │  SIX RAW FIELDS, no rendered display string: the row draws title + duration
        │  rail, print_details draws the rest, apply_filter synthesizes its own haystack.
        │  Joined by US (0x1f), NOT tab — `IFS=$'\t' read` collapses runs of tabs, and a
        │  live row's empty duration_fmt would shift every field after it.
        │  NO leading number — the menu numbers rows by visible position, which stays
        │  correct after a filter re-orders them.
        ▼
   load_rows → urls[] · R_TITLE/R_DUR/R_VIEWS/R_CHAN/R_LIVE · NUM_ENTRIES / NUM_PAGES
        ▼
    ┌─ SELF-RENDERED MENU LOOP (yt-tui draws every line, reads every key; plain ─────┐
    │  text + ANSI — 2-view switchable cycling: List ↔ Now Playing card              │
    │  display_menu:                                                                 │
    │    List View:     title · status · live Now-Playing banner · result rows       │
    │                   (fixed index field + title + right-rail duration) ·          │
    │                   pagination dots · details section for the SELECTED row ·     │
    │                   live filter input. An ACCENT rail sits under the             │
    │                   key-hint block (chrome | content boundary, with it or not).  │
    │    Card:          full-screen rail-bounded card, label-less body (title,       │
    │                   channel, one dot-separated meta row), progress bar &         │
    │                   interactive controls                                         │
    │  read_nav_input: one keypress; decodes ESC-[/O arrow sequences                 │
    │    ↑/↓  move selection (paginate at edges)      ←/→  page (list) / seek 5s (card)│
    │    [ ] seek   ∓10s from ANY view                ↑/↓  volume (card)             │
    │    Enter → play_selected:   yt-play -d -j -f MODE -- url  (NON-BLOCKING)       │
    │    Tab/p → toggle view:     List View ◄──► Now Playing card                    │
    │    Space → toggle pause:    sends IPC cycle pause over UNIX socket             │
    │    s     → stop playback:   yt-play --stop --id ID                             │
    │    9/0   → volume:          read-modify-set over socket IPC, clamped 0-100     │
    │    v     → cycle_mode:      PLAY_MODE audio→video→fast (local; next Enter)     │
    │    n     → new_search:      read query → fetch_json → reload (music continues) │
    │    m     → more_results:    re-fetch CURRENT query, RESULT_N += 25 (else keep) │
    │    o     → cycle_sort:      rotate SORT_FIELD, re-fetch (relevance→views→dur)  │
    │    t     → cycle_theme:     rotate palette family live (minimal→…→mono), any   │
    │                             view; no-op when colors are off (COLORS_ON gate)   │
    │    /     → filter_live:     LIVE narrow — type to filter, Esc clears           │
    │    q     → exit 0           reaps background players cleanly on trap EXIT      │
    └────────────────────────────────────────────────────────────────────────────────┘
```

- **PLAY is asynchronous & non-blocking via `yt-play -d -j`.** `play_selected` reads
  `id`/`pid`/**`sock`** out of that envelope in one `jq` pass and never rebuilds the socket
  path itself (§9.3). Playback launches in an
  independent, detached process group so `yt-tui` retains full terminal control. Audio
  streams uninterrupted while users browse results, change pages, or initiate a new search
  (`n`). A single `Enter` on any track cleanly stops the previous player and starts the
  new selection without latency.
- **TWO SWITCHABLE VIEWS toggled with `Tab` (or `p`):**
  - **List View (Search & Browse)**: Interactive multi-row list with a top Now-Playing banner.
  - **Now Playing card**: Clean distraction-free card with word-wrapped title within
    one adaptive divider rail, live `playtime / total time (pct%)`, and a progress bar that
    is itself a rail. There is exactly ONE static rail, under the header; nothing separates
    the progress bar from the hints, so the readout labels the bar above it and the hints
    flow straight after it (the redundant rail between bar and hints went in the theme pass;
    the bottom rail went with the bracket removal below, since the full-width bar already
    gives the card a closing horizontal and `\033[J`, not a rail, is what clears stale rows).
  - **There was a third view, and deleting it was the point.** A "mini player" rendered the
    same four facts as the card in three lines. Two renderers for one state is the F7 shape
    (duplication that drifts): they had already disagreed about where the progress bar was
    built, and every card change had to be made twice or knowingly skipped. `Tab` cycling
    through three states also meant two presses to get back to the list from the card, on a
    key whose whole job is "away and back". Nothing the mini did is unreachable now — it was
    the card minus the rails.
  - **Anti-Flicker in-place rendering — now BOTH views, and no `clear` left in the app.**
    Real-time 1s timer refreshes time and progress bars smoothly via `\033[H` (cursor home)
    without full-screen blanking or flashing. Because nothing is blanked, **every row a frame
    emits must carry `\033[K`** — blank spacer rows included. The card grows by two rows the
    moment the progress bar appears (mpv has no `time-pos` for the first second or so), and an
    uncleared spacer kept displaying the divider rail the previous, shorter frame had drawn on
    that line.

    The LIST used to be the exception: it opened every redraw with `clear`, which blanks the
    screen and then repaints it — two visible states per frame. Any keypress flashed the whole
    list, and pause/resume made that obvious, because the only thing that actually changed was
    one glyph in the banner. The DCS frame hold hides a blank-then-draw on terminals that honour
    it, which is why this survived so long; under tmux, where sync is off by default, nothing
    did. `display_list_menu` now homes the cursor and erases as it draws like the card, closing
    with one `\033[J`, and pause/resume repaints exactly one row (one changed row, zero `ED`
    sequences — `tests/tui_pane.sh` counts the `ED`s in `tmux pipe-pane`'s stream between two
    marks, since tmux emits its own clear when the pane opens). The view-switch `clear` on Tab/Esc went with
    it — both renderers end in `\033[J`, so the incoming frame covers the outgoing one, and the
    switch was the last blank frame in the app.

    Two details the list needed and the card did not:
    - **`\033[K` goes FIRST on a result row, not last.** The duration rail is placed with CHA
      (`\033[<n>G`), which jumps over the cells between title and rail without writing them, so
      a trailing erase leaves the previous frame's longer title showing through the gap. Erase,
      then draw, is the only order that covers a hole the draw itself never touches.
    - **The filter caret closes the frame with `\033[J` alone.** It erases the rest of that line
      AND every line below in one sequence, and leaves the cursor where the next typed character
      has to land — a `\033[K` first would be redundant, and a cursor move would be wrong.

    **What this did NOT change: a keypress still recomputes and rewrites the whole frame, and
    that is deliberate.** What went away is the number of states the terminal *shows* (blank,
    then drawn → drawn), not the work. Every key handler ends in `continue`, the top of the loop
    calls `display_menu`, and `display_menu` is the only writer to the screen — there is no
    dirty-region tracking and no partial-draw path. Measured on a 100x30 pty: a pause emits
    **2413 bytes in 15-24 ms**, byte-for-byte the same frame an arrow-down emits when four rows
    genuinely changed.

    The recompute is what the reflow costs. List geometry is *measured* per frame, not fixed:
    `PAGE_SIZE` is `LINES_N` minus the measured chrome, `print_hints` packs to the width (1-4
    lines, and the count moves with the chrome language), and the details block is however far
    the selected title wraps — so a frame reads `stty size`, runs the hint packing, runs
    `print_details` twice (measure, then draw) and walks every row through `truncate_disp`. Any
    state change *could* move that geometry, so the renderer recomputes instead of trying to know
    when it cannot.

    Pause is the one change that provably cannot move it — one glyph and one word inside a line
    whose length elision already fixed. Repainting just that row was considered and rejected: it
    needs the banner's absolute screen row (today `chrome_h` accumulates *while drawing*; it is
    not a row map anything can query), a CUP or save/restore to reach it, and the banner's title
    elision recomputed anyway, because that depends on `nav_cols` and on whether the nav block
    was dropped. The result is a second draw path covering a subset of the first — the F7 shape
    (§25.1), where the copies drift and every banner change has to be made twice. 2.4 KB and
    ~20 ms per keypress is invisible at typing rates, and the only redraws that repeat on their
    own (the card's clock, the `Starting` tick) run at 1 Hz. Revisit if a frame ever has to be
    drawn faster than that, not because the byte count looks large.
  - **The progress bar IS the card's live rail.** `render_prog_bar pct total` takes the FULL
    cell width it may occupy: the card passes `cols`, the divider rail's own width, and prints
    it at column 0 like the rail — so the bar lays exactly over the rail's footprint rather
    than sitting at a hardcoded width. Two changes got it there, both 2026-08. It is drawn as
    a rule, not as body text: it took the 4-cell body indent until then, which left its left
    edge hanging inside the rails while only its right edge was flush. And the `[`/`]` ends
    are gone: a bracket is a boundary, and a line whose job is to be exactly rail-wide and
    boundary-less cannot have ends. `━` elapsed and `─` remaining are the divider's own stroke
    family, so the played part reads as the rail thickening behind the `●` playhead — the same
    glyph the status row uses — instead of a widget parked on the card. The brackets were also
    2 cells of the caller's width spent on punctuation; they now buy 2 more cells of
    resolution (`width = total`, not `total - 2`). The rendered string is *always* exactly that
    many cells — the head glyph is part of the track and `filled` is capped at `width-1`,
    where the old fixed-42 bar measured 46 cells at 0%, 44 at 50% and 47 at 100%, making
    the line jitter on every refresh. `repeat_glyph` builds the runs because
    `printf 'x%.0s' $(seq 1 0)` still prints one cell (printf always walks its format once).
  - **A live stream has no position, so it gets no position readout.** mpv reports
    `time-pos` on the *broadcast's* timeline with `duration` = the live edge, so
    `percent-pos` is ~99.98% from the first second and a progress bar is pinned full —
    measured on a 24/7 radio: `time-pos=77390 duration=77403 percent-pos=99.98` (a VOD at
    the same age reads 0.03%). The card therefore keys off the row's own
    `live_status` (carried raw in `R_LIVE`; `play_selected` is what turns it into the
    `GL_LIVE` badge on `CURRENT_PLAY_DURATION`), shows
    `MM:SS · ● LIVE` in place of the position pair — wall-clock since *this* listener
    attached, which mpv cannot provide — and draws no bar. `CURRENT_PLAY_IS_LIVE`/`CURRENT_PLAY_STARTED` carry it;
    both reset on stop.
  - **The client learns of the player's death by asking, once per loop turn.** A detached
    player owns its own lifecycle: nothing calls back into `yt-tui` when a track ends or mpv
    crashes, and the IPC layer is deliberately quiet about it (`send_mpv_ipc` swallows every
    failure, `mpv_get_prop` answers empty on a dead socket) so a lost player cannot kill the
    UI. Quiet is not the same as noticed — so `check_player_alive` runs at the top of the main
    loop *and* at the top of `filter_live`'s own key loop (that loop never returns to the main
    loop while `/` is open), and clears the whole `CURRENT_PLAY_*` block through
    `clear_play_state` the moment the player is gone. The test is `kill -0` on the envelope's
    pid, which is the **bash wrapper's**: the wrapper blocks on mpv, so "wrapper alive" is
    exactly "still playing", and this is the same truth the core reaps on (§9.3, process group
    alive) reached from the client side for one builtin and no fork — cheap enough for the
    card's 1 s tick. An **empty** pid means "unknown", not "dead" (`play_selected` requires
    only id and sock), so it leaves the chrome alone. Pid reuse can false-positive it, exactly
    as §25 records for the core's own `group_alive`. The clear is silent: the empty states
    already say it, and in list view it lands on the next keypress because that read blocks.
  - **The TUI owns the terminal's echo, and every typed character is assembled before it is
    a key.** `read -rsn1` hands back one BYTE on bash 3.2, so a CJK character typed at the
    filter or the new-search prompt used to arrive as two or three separate keypresses —
    the filter matched nothing, the prompt echoed mojibake. `utf8_complete` finishes the
    character off its lead byte (classified by table membership, §28) before either reader
    calls it a key, with the continuation reads on a timeout so a torn sequence cannot wedge
    the card's once-a-second tick. Backspace then works in characters, not bytes: `${q%?}`
    already strips a whole one on 3.2, but the `\b \b` erase is one CELL and a CJK glyph
    occupies two, so the removed character is measured with `disp_w` and that many cells are
    erased. And the driver's own echo is off for the whole session (`stty -echo`, restored
    through the same trap as the cursor): `read -s` suppresses it per read only, so between
    reads the driver echoes whatever a burst left queued — on top of the echo this UI already
    draws itself. The filter's catch-all had to widen from `?)` (one byte, so never a whole
    CJK character) to `*)`, which is exactly why the two shipped together — and it stops short
    of escape sequences the arrow arms did not claim, or PageUp would type `[5~` into the query.
  - **Terminal size comes from `stty size </dev/tty`, not `$(tput cols)`.** Inside command
    substitution ncurses can miss the window-size ioctl and answer with terminfo's default
    80x24 — measured: a 60-column pane reported 80, so the card drew 80-wide rails and every
    line (rails, title, bar) wrapped. `term_size()` reads the real ioctl through the TTY this
    UI already requires, with `tput` and then 80x24 as fallbacks. (`yt`'s `viz` mode sizes
    its showwaves filter the same way.)
  - **The chrome speaks ONE language per run.** Its labels used to be Chinese literals
    while help text, errors and field labels were English, so the tool read as two
    languages at once. `init_ui_strings` resolves every label ONCE into globals — bash 3.2
    has no associative arrays, and a per-draw lookup would fork or re-branch on every
    redraw — choosing from `YT_LANG=en|zh`, else a `zh*` locale, else English (which also
    covers cron/CI, where `LANG` is unset). That is only the STARTING language: `set_ui_lang`
    is split from the initial choice so the **`l` key** re-fills the table live, from any
    view, without touching playback. Wrapped-row indents are measured with `disp_w`, not
    `${#var}`: "导航:" is 3 characters but 5 cells.

    **The rule is now exhaustive: nothing drawn as chrome is a literal at its print site.**
    It was not, for two passes — the hint rows went through the table while the play state
    (`Playing`/`Paused`/`Starting`, drawn twice: the list banner's label and the card's status), the card
    header, and every *transient* line (the startup prompt, the `n` prompt, `searching…`, the
    `m`/`o` action echoes, the no-matches copy, the filter banner, `Press any key…`,
    `Quitting…`) stayed English inside a Chinese frame. They were easy to miss precisely
    because they are transient: they print into the scroll area and the next redraw wipes
    them, so they never appear in a captured frame. Three constraints shaped the fix:
    - **The table cannot reference `GL_*`.** `set_ui_lang` runs during option parsing;
      `init_glyphs` runs after it, so a glyph inside a label aborts under `set -u` on the
      first call. A sentence with a glyph in the MIDDLE is therefore two entries composed at
      the print site (`$S_NO_MATCH $GL_DASH $S_NO_MATCH_KEYS`) — baking a literal em dash in
      would survive `YT_ASCII=1`, which is the one thing the glyph table exists to prevent.
    - **One entry per SITE, not per word.** `S_MORE_ACT`/`S_SORT_ACT` repeat `S_MORE`/`S_SORT`'s
      Chinese value on purpose: the hint row spells the keys lower case and the action heading
      Title case, a distinction English has and Chinese does not. Sharing one entry would have
      changed the English output to close a Chinese gap.
    - **Word order that survives translation.** The `m` echo's count phrase moved from
      `for 50 results` to `· 50 results` so ONE fixed `printf` format serves both languages
      (Chinese wants "，共 50 条"); a per-language format string would have put the layout
      back inside the table. This is the pass's only deliberate change to English output.

    What stays English **by design**: help text, error sentences (`Play failed:`, `no results`,
    `search failed`) and the `k=v` field labels of the header/status rows.
  - **The chrome speaks ONE theme per run — and it is the terminal's theme, not ours.**
    The default palette (`minimal`) is ANSI 16 indexed codes only; deliberately no
    RGB or 256-color (grep gate: the only escapes the minimal/mono paths can emit
    are 0/1/2/32/34/36 and 1;3x compounds), so by default yt-tui renders in
    whatever scheme the user's terminal already has — One Dark, Catppuccin,
    anything — instead of imposing a second palette inside it. The community
    themes (`catppuccin | tokyonight | nord | gruvbox | onedark`) are a second
    layer: they emit their SIGNATURE ACCENT in 24-bit RGB (38;2), but ONLY when
    the terminal advertises `COLORTERM=truecolor` — otherwise they fall back to
    the nearest ANSI-16 index, so the chrome is never garbage on a limited
    terminal. Every theme, community included, passes through the same minimalist
    filter: hierarchy by gray levels (dim → normal → bold) and hue is ONE accent
    (`C_CYAN`: headers, selection marker, play status, and the card's rails — the static
    rail and the live progress rail are one object in two states, so a dim rail above an
    accent bar read as two unrelated lines that merely shared a width); the rest of a community
    palette (its yellow/red/purple/…) is dropped on purpose. The play status was
    the last two-hue holdout — `C_GREEN` for playing, `C_YELLOW` for paused — and
    a second hue reads as "not this theme" wherever the accent is not green
    (gruvbox's orange chrome beside an olive status). Both status sites (the list
    banner's label and the card's meta row) now take the accent, with the GLYPH
    carrying the state: `●` (card) / `▶` (banner) playing, `❚❚` paused, and a turning
    quadrant while the stream is still coming up — the last two dim-accent, because
    neither is the steady state. So
    `C_GREEN` is gone outright — a live variable holding a real color that nothing
    prints is a trap, not a spare, and its ten per-theme hexes are recoverable from
    git — while `C_YELLOW` stays defined as `""`: no site reads it any more, but a
    stale read costs nothing, whereas deleting it is edits for zero behavior
    change. `C_MARK` is
    the compound selection/filter style (bold + accent). `YT_THEME` picks the
    family (`mono` = hue zero, bold/dim carry everything); `--theme` beats env,
    and the **`t` key** cycles the family live from any view — the same `set_theme`
    re-resolve startup uses, gated on `COLORS_ON` so a color-less session
    (`--color never` / NO_COLOR / non-TTY) stays colorless.
    Official hexes per theme (catppuccin mocha/latte mauve & green, tokyonight
    night/day blue & green, nord frost8/frost1 & aurora14, gruvbox orange &
    green, onedark/one-light blue & green).
  - **Light and dark terminals get a readable accent.** `YT_BG=auto` chain: explicit
    `YT_BG=light|dark` wins; else `$COLORFGBG` (rxvt family, bg==15); else an OSC 11
    background query (`\033]11;?\033\`); else dark. For `minimal`/`mono`, light
    swaps cyan for blue — yellow is unreadable on white, which is exactly why the
    retired hue is retired; for community themes, light picks the theme's OWN light
    variant (mocha→latte, night→day, polar-night→snow-storm, gruvbox light,
    onedark→one-light). The probe is bash-3.2 shaped: `read -t` takes only WHOLE
    seconds there, so one unanswered query costs 1 s once at startup, and it is
    skipped under tmux / `TERM=dumb`, which cannot answer. The reply
    (`rgb:RRRR/GGGG/BBBB` kitty 16-bit, `rgb:RR/GG/BB` xterm 8-bit, BEL or ST
    terminated) is assembled byte-by-byte (no `read -d` on 3.2); RGB sum > 384
    (mid-gray) is the light/dark boundary.
  - **The protocol layer is polite.** `--color auto` honors `NO_COLOR` (explicit
    `--color always|never` still wins). Downsampling is the `COLORTERM` gate: a
    community theme is 24-bit only when the terminal advertises it, and ANSI-16
    otherwise — the palette never guesses. Full-screen redraws are wrapped in the
    Kitty synchronized-output pair (DCS `=1q` / `=2q`) so a repaint cannot flash a
    half-rendered frame; `YT_SYNC=0|1` overrides, and it defaults off under tmux
    (which buffers output and needs terminal-overrides passthrough anyway).
  - **One width rule, in one place: `char_w`.** A non-ASCII character counts as **two**
    cells — exact for CJK (East-Asian Wide), conservative for everything else. That default
    direction *is* the safety property: over-counting packs a row a cell or two early and can
    never run off the edge, while under-counting overflows. So two is the fallback, and only
    characters **measured** to be otherwise get a table.
    The rule used to be written inline at four sites (`disp_w`, `truncate_disp`, and both of
    `wrap_print`'s loops), where a fix to one silently disagreed with the other three;
    measurement disagreeing with line-breaking is worse than a uniform over-count, so they
    all call `char_w` now.
  - **The chrome's own glyphs are tabled at their true one cell**, which is what makes the
    layout exact rather than merely safe. This is only sound because the suite's glyph
    inventory is deliberately **non-graphical** — text presentation, no emoji anywhere in
    `yt` / `yt-search` / `yt-play` / `yt-tui` — so none of these characters can carry a
    U+FE0F and become a 2-cell emoji glyph behind the table's back. All 17 measured at one
    cell (`tmux display-message -p '#{cursor_x}'`):

    **The closed inventory (D10)** — every glyph the chrome can draw, generated from the
    `GL_*` declarations plus the bar and divider, with the class read off the UCD
    (`unicodedata.east_asian_width`) rather than guessed. A scan of every non-comment line
    finds no other non-ASCII character but the Chinese label text, so the list is complete,
    not curated.

    **One deliberate exception: the brand wordmark (`YT_BRAND=1`).** Both view
    headers render `𝗬 𝗧  𝗧 𝗨 𝗜` (mathematical sans-serif bold, U+1D5D4 block) when
    opted in. It lives OUTSIDE the closed inventory on purpose: the UCD class is Neutral
    (one cell "in principle"), but real terminal fonts render this block via fallback
    fonts at whatever width they like — so it is NOT measured and NOT in the table, and
    `char_w`'s conservative 2-cell default applies to it (over-count packs the query
    elision a cell or two early; it can never overflow). It is opt-in precisely because
    a font without the block shows tofu and only the user's eyes can judge that.
    `YT_ASCII=1` wins over `YT_BRAND` — a font that cannot draw ♫ cannot draw these.

    **Neutral EAW — one cell in every terminal, unconditionally (8)**

    | glyph | cp | declared as | name |
    |---|---|---|---|
    | `↵` | U+21B5 | `GL_ENTER` | Downwards Arrow With Corner Leftwards |
    | `♫` | U+266B | `GL_NOTE` | Beamed Eighth Notes |
    | `❚` | U+275A | `GL_PAUSE` (drawn `❚❚`) | Heavy Vertical Bar |
    | `❯` | U+276F | `GL_CARET` | Heavy Right-Pointing Angle Quotation Mark Ornament |
    | `▖` | U+2596 | `GL_SPIN` | Quadrant Lower Left |
    | `▗` | U+2597 | `GL_SPIN` | Quadrant Lower Right |
    | `▘` | U+2598 | `GL_SPIN` | Quadrant Upper Left |
    | `▝` | U+259D | `GL_SPIN` | Quadrant Upper Right |

    The four quadrants are the fetch spinner AND the `Starting` play state — one animation
    reused, so the wait for a search and the wait for a stream look like the same thing — and
    their EAW class is the reason they were chosen: U+2596..U+259F is the one Neutral island inside the Block Elements, so the
    animation is one cell in every terminal and under every setting. The obvious alternatives
    are not — `◐◓◑◒` and the `▁▃▅▇` bars are Ambiguous, so `YT_AMBIG_WIDE=1` (or a terminal
    that treats Ambiguous as wide) would let the frames jump between one and two cells. They
    are in `CW_NARROW` even though nothing measures the spinner line, so the "every glyph has
    a known width" invariant holds by construction and not by where the glyph happens to print.

    **Ambiguous EAW — one cell by default, two only under `YT_AMBIG_WIDE=1` (13)**

    | glyph | cp | declared as | name |
    |---|---|---|---|
    | `·` | U+00B7 | `GL_SEP` | Middle Dot |
    | `—` | U+2014 | `GL_DASH` | Em Dash |
    | `•` | U+2022 | `GL_BULLET` | Bullet |
    | `…` | U+2026 | `GL_ELL` | Horizontal Ellipsis |
    | `←` | U+2190 | `GL_AH` | Leftwards Arrow |
    | `↑` | U+2191 | `GL_AV` | Upwards Arrow |
    | `→` | U+2192 | `GL_AH`, `GL_ARROW` | Rightwards Arrow |
    | `↓` | U+2193 | `GL_AV` | Downwards Arrow |
    | `─` | U+2500 | bar track, card divider | Box Drawings Light Horizontal |
    | `━` | U+2501 | bar fill | Box Drawings Heavy Horizontal |
    | `▶` | U+25B6 | `GL_PLAY` | Black Right-Pointing Triangle |
    | `○` | U+25CB | `GL_DOT_OFF` | White Circle |
    | `●` | U+25CF | `GL_DOT`, `GL_LIVE`, bar head | Black Circle |

    The Ambiguous 13 are the **entire** configuration-dependent surface: the only characters
    whose cell count a terminal setting can move, and the only ones `YT_AMBIG_WIDE` touches.
    The Neutral 8 are one cell by definition of their class, so no setting reaches them.
    `♫` U+266B belongs there and not with the arrows — it is Neutral, so it stays one cell
    even under `YT_AMBIG_WIDE`.

    Everything the TUI draws is therefore in one of four buckets: ASCII (1 cell), these 21
    (tabled), CJK label text (2, exact), or untabled and conservatively over-counted.
    `YT_ASCII=1` (auto-on for a non-UTF-8 locale) replaces all 21 with ASCII equivalents, so
    the inventory has exactly two states and no font-dependent middle ground — which is why
    every drawn glyph must have a `GL_*` name. Page dots were the last hardcoded literals
    (`●` / `○` inline, with `○` having no name at all); they now go through
    `GL_DOT` / `GL_DOT_OFF`.

    One cell is the **default** in every terminal in use here: Ghostty
    (`grapheme-width-method = unicode`), and Terminal.app / iTerm2 / tmux, where "treat
    ambiguous-width as double-width" is an opt-in that ships off. `YT_AMBIG_WIDE=1` restores
    the conservative 2 for the Ambiguous row only — Neutral glyphs are one cell regardless.
    It is an explicit knob rather than a locale guess, because the locale says nothing:
    Ghostty under `zh_CN.UTF-8` still renders these one cell. `render_prog_bar` had already
    baked in this assumption — it promises a string of exactly `total` cells built from
    `━ ─ ●`, which only holds at one cell each. Measured effect at 60 columns with the
    Chinese chrome: the navigation row fits one more item on its first line
    (`导航: … v 模式  n 搜索` = 58 cells measured, 58 actual) instead of wrapping it.
  - **What the exactness rests on, precisely.** The tabled glyphs are one cell only in TEXT
    presentation: measured in the same terminal, `▶` is 1 cell but `▶️` (U+25B6 U+FE0F) is 2,
    and the table would call it 1. So the load-bearing part of `build_all_rows`'s `clean`
    is not its emoji block ranges — it is stripping U+FE00–FE0F and U+200D, which is what
    guarantees nothing reaching a measurement is in emoji presentation. Anything that
    survives `clean` is text presentation, hence either tabled correctly or (being
    untabled) over-counted, so the no-overflow property holds for arbitrary YouTube titles
    without the filter having to enumerate every emoji codepoint. If that stripping is ever
    relaxed, the table needs a base+VS16 rule first: a base followed by U+FE0F is 2 cells,
    whatever the table says. Failure directions are asymmetric and this is the only unsafe
    one — adding a glyph to `GL_*` and forgetting the width table just falls back to 2
    (over-count, safe); putting a character in a width table without measuring it is what
    overflows.
  - **The zero-width class is corrected**, because there "two cells" is wrong in every
    terminal. With the base still counted as two, each of these makes the whole sequence come
    out EXACT rather than merely conservative — verified against the terminal's own cursor
    advance (`tmux display-message -p '#{cursor_x}'`):

    | sequence | old | now | terminal |
    |---|---|---|---|
    | `Ocean Coffee ☕️ Vibe` (U+FE0F) | 22 | **20** | 20 |
    | `flag 🇨🇳 cn` (regional indicators) | 12 | **10** | 10 |
    | `👍🏽 ok` (skin-tone modifier) | 6 | **5** | 5 |
    | `café latte` (decomposed, U+0301) | 12 | **10** | 10 |
    | `family 👨‍👩‍👧 here` (ZWJ) | 22 | 18 | 14 |
    | `● LIVE` (chrome, Ambiguous) | 7 | **6** | 6 |
    | `▶ ❚❚ ❯ ♫ ·` (chrome) | 16 | **10** | 10 |

    Zero cells: U+200D ZWJ, U+FE0E/U+FE0F, skin tones U+1F3FB–U+1F3FF, combining marks
    U+0300–U+036F / U+20D0–U+20F0 / U+FE20–U+FE2F. One cell: regional indicators
    U+1F1E6–U+1F1FF. Combining marks outside those blocks (Arabic, Devanagari, Thai) are not
    in the table and stay over-counted — conservative, never short. A ZWJ emoji sequence
    still over-counts; collapsing it needs a real grapheme-cluster walk, which is not worth
    its weight in bash 3.2. The tables are byte-built at startup (`cw_range`) rather than
    written as literals: a source line full of invisible combining marks is unreadable.
    Pure-ASCII strings skip the per-character walk entirely, so the shared helper is FASTER
    than the inline test it replaced (300 measurements of a packed hint row: 94 ms
    before, 5 ms after).
    Accumulate with `n=$((n + CHAR_W))`, never `((n += CHAR_W))`: an arithmetic command
    evaluating to 0 returns exit status 1, so a leading zero-width character would abort the
    script under `set -e`.
  - **Cuts land on grapheme boundaries (`cluster_back`).** Severing a base character from its
    combining mark, joiner or flag partner does not merely mis-measure, it draws the WRONG
    glyph: half a flag renders as a lone letter tile, an orphaned VS16 or ZWJ attaches itself
    to the ellipsis. `truncate_disp` walks the cut point left until it is a real boundary. An
    RI blocks the cut only when the character before it is also an RI — otherwise every cut
    landing in front of a flag would needlessly eat the character before it. `wrap_print`
    needs no walk: a zero-width character adds 0 cells, so it can never trip a budget test
    and never starts a continuation line — marks stay attached to their base for free.
  - **All chrome rows are laid out to the measured width, not written as fixed strings.**
    `disp_w` measures PLAIN text (a non-ASCII cell counts as two — the labels are CJK, so
    they run out of room sooner than their character count suggests) and returns through a
    global, since this runs several times per redraw and `$(...)` would fork. On top of it:
    `print_hints` packs `key<TAB>label` items (or bare fields) into as few lines as fit,
    with a first/continuation prefix and `HINT_SEP` between items (two spaces unless the
    caller overrides it — the same one-call override shape as `HINT_KEY_COLOR`, and both
    the printer and the packer's fit test read the same value, so a separator the packer
    did not know about cannot wrap an item one slot early); `truncate_disp` elides a
    variable-length value that
    shares a one-line budget with fixed chrome. Applied to the navigation row, the card's
    hint block, the empty-state copy, and the list's
    status row (whose `min=`/`max=` now appear only when set — at their `0s` default they
    were pure width). The card's meta row measures itself and DROPS fields rather than
    wrapping (see the label-less card below), and the Now-Playing banner gives the title
    whatever the fixed parts leave, dropping its inline hint block before it would squeeze
    the title below 12 cells. Result: every chrome line fits at 46 columns, where the old
    fixed strings wrapped mid-item from ~72 down.
  - **EVERY row in the list view is one physical line, result rows included.** They were the
    last rows printed unmeasured, and the ones that mattered most: at 62 columns a
    `title · duration · views · channel` row takes two or three lines, so ten entries filled
    21 lines and scrolled the header, the status row, the Now-Playing banner and the entire
    navigation block off the top — every hint the layout had just packed, spent on rows that
    then scrolled away. Each row's TITLE is elided to what its index field, a two-cell gap
    and the duration rail leave (`cols - iw - 1 - 2 - rail`). The title
    row (a long query used to wrap) and the filter caret's copy are elided the same way, so
    the whole view is measurable line-for-line.
  - **A row is a title and a duration; everything else is a section below it.** One physical
    line per row was necessary but not sufficient: the row was still
    `title · duration · views · channel` composed into ONE string and elided from the right,
    so the elision ate the metadata FIRST and at 62 columns a row was a chopped title with
    nothing beside it — the whole truncation budget spent on the three fields that got cut.
    Now the row carries the title and a right-rail duration, and the full title, channel,
    view count and video id live in a **details section** under the pagination dots, for the
    selected row only. The rail prints a bare `LIVE` where the details line prints
    `● LIVE · live now`: a numeric column wants no status glyph in it, and in a prose line
    the same glyph reads as a badge. Both use `short_dur`, so the envelope's zero-padded
    `06h:10m:58s` never reaches the screen — and neither does a row disagree with its own
    details block, since both render from the same fields rather than from each other.
  - **The index is a fixed-width column; the marker gets its own slot in front of it.**
    The prefixes were per-row literals — `> 1. ` when selected, `  1. ` when not — so their
    width was `4 + <digits>` and a page that reached two digits started every 1-digit title
    one cell left of the rows around it. Ragged, in the one column the eye scans *down*.
    Now the number is right-aligned in a fixed sub-field of `iw - 2` cells (digits of the
    largest index + 1 for the dot), the marker slot in front of it is a constant 2 (`"> "`
    where an unselected row leaves `"  "`), and one space separates the field from the title:
    `iw + 1` cells of prefix on every row, `iw = ${#NUM_ENTRIES} + 3`. The width comes from
    `NUM_ENTRIES`, not from the page, so it does not move as you page; and because it is one
    number, `row_w` and the CHA rail jump both read it instead of re-deriving the prefix. On a
    single-digit page the sub-field needs no padding, so the output is byte-identical to the
    old literals — the field only shows itself once the total crosses into two digits, which
    is exactly the case it exists for.

    **Every row keeps its number, the selected one included.** A first cut replaced the
    number with `>` on the selected row, reasoning that you only ever type an index for a row
    you are *not* on. That reasoning is about the keyboard and the column is not: blanking the
    number on the row under the cursor removes the one label that says *which* row that is,
    which is the thing a reader looks for when they want to say where they are. Reverted; the
    marker got its own slot instead, which is what the fixed sub-field made room for.
  - **The focus card's hint line is dot-joined and bracket-free.** Six keys with
    `[bracketed]` keys, two-space joins and sentence labels (`back to list`,
    `pause / resume`, `stop playback`) measured 110 cells — two lines at every width the
    card supports, and at short heights that second line came out of the body. The keys
    keep their place and size; what changed is the shape: brackets dropped (the bold-key /
    dim-label weight split already separates the two, so the brackets spent 2 cells per
    item saying it twice), labels cut to one word each, and items joined by the suite's
    `GL_SEP` (` · `, dim) instead of two spaces — 63 cells, one line down to 63 columns
    (69 under `YT_AMBIG_WIDE=1`, where `←`/`→`/`·` each cost two cells instead of one).
    Below that it wraps to two, the same graceful path every other chrome block takes.
    The zh labels were re-cut, not trimmed mechanically: `返回列表选单` → `列表`,
    `快退 / 快进 5s` → `跳转`, so the zh line measures 63 too. `S_QUIT` is deliberately
    untouched — the list view's navigation block shares it, and it was already one word.
    The empty state (`nothing playing`) takes the same treatment for consistency, though
    with two items it fit either way.
  - **The card's body carries no labels.** `Title:` / `Channel:` / `Time:` / `Mode:` /
    `Status:` (and the hint block's `Controls:`) are gone; typography carries the same
    structure — bold title, dim channel, one dim meta row `3:21 / 9:27 (37%) · audio ·
    ● Playing` joined by `GL_SEP`, with the status keeping its colour. Three things fall out
    of that. The title gets ~11 more cells before it wraps, because `text_w` is now
    `cols - 4` (the deepest body indent) instead of `cols - 15` (indent + an 8-cell label
    field + a 3-cell gap). The one-line/two-line branch is deleted: the labels and their
    gaps were ~30 cells of the row's width, and without them it fits at every width the card
    supports — where it still would not, the guard DROPS the mode segment and then elides
    the time, never wraps, and never drops the status (the readout the card exists for).
    And the F11 translation problem shrinks to a string swap: `%-8s` pads to eight *bytes*
    on bash 3.2, so a CJK label rendered a different width than the fit estimate assumed —
    with no labels there is no pad to get wrong. The title also loses its `▶`: play state
    lives in the meta row's coloured status, and two indicators for one fact is the same
    duplication in miniature.
  - **The list's key-hint block loses its label too, and gains the keys it never wrote
    down.** `Navigation:` was the last label on the chrome band, and it went for the reason
    the card's `Controls:` did: the keys ARE the content, and its neighbours — the banner
    above, the rail below — carry no label either, so the word only announced what the reader
    could already see. It also cost 12 cells on the widest line in the view. `S_NAV` is
    deleted from both language tables rather than left defined, since nothing reads it. The
    separator becomes `GL_SEP`, matching the card's block, so the two views print one object
    instead of two that merely list the same keys — and `HINT_SEP` is set around the MEASURE
    call as well as the print call, never just one: ` · ` is 3 cells against the default 2,
    which across 11 gaps is 11 cells, enough to move the block from one line to two, and a
    measure pass that under-counts the chrome is precisely how the header scrolls off the top.
    Three keys were also **missing from the one view whose job is to write keys down**:
    `9/0` volume, `Space` pause and `[ ]` seek are all handled by the menu loop's universal
    case, so they always worked here — the card's hint block and the banner's short-terminal
    fallback both documented volume and pause, and §12.4 and §18 documented all three, which
    is what makes their absence a gap rather than a decision. They cluster at the end beside
    `s`, being the playback keys in a list otherwise about moving and searching. The seek keys
    print as `[ ]`, **not** `[/]`: `/` is this line's "or" separator (`9/0`, `↑/↓`), but these
    two keys ARE brackets, so a slash wrapped in them read as "a bracketed `/`" and collided
    with the real `/ filter` entry three items earlier. A space says "two keys" without
    spending a character that already means something else on the line. `S_SEEK5` is renamed
    `S_SEEK`: its value was always the bare word, and it now serves the card's ±5s arrows and
    the list's ±10s brackets both, so a name claiming one step size was the only thing the old
    name did. Still undocumented on purpose: `p`/`P` (a pure `Tab` alias) and `Esc` (a no-op
    in this view).
  - **The banner's tail is a POSITION, not a duration.** It used to print the track length
    alone (`▶ Playing: … · 3:34`), which is the one number already on the row three lines
    below it; it now prints `1:12 / 3:34`, the same pairing the card's meta row shows, so the
    two views cannot disagree about where the track is. It costs no IPC of its own: `PT_CUR`
    and `PT_TOTAL` are whatever the shared clock last left, at most a second old, which is the
    resolution the line is drawn at. Empty `PT_CUR` means no reading has landed yet — the
    first frame after Enter, before the first tick — and falls back to the duration alone
    rather than printing a bare `/`; `PT_TOTAL` falls back the same way, and because
    `fetch_play_times` seeds it from the row's own `short_dur` and only replaces it with
    `fmt_sec` once mpv answers, the readout never changes SHAPE a second into playback. Live
    keeps the card's live form (`12:34 · LIVE`, no slash): mpv's clock describes the
    broadcast, not this listen, so there is no total to divide by. **This also made
    `clear_play_state` incomplete.** It reset `PT_PCT` for the rail's sake but left `PT_CUR`
    and `PT_TOTAL` standing, and `play_selected` reaches it through `stop_current_playback`
    *before* launching the next track — so the banner would have shown the PREVIOUS track's
    elapsed time until the first tick overwrote it. All three clear together now, and empty is
    also exactly the "no reading yet" signal the fallback reads.
  - **The rail is placed with an absolute column jump, not computed padding.** Right-aligning
    by padding emits `room - DISP_W` spaces, which lands the column wherever OUR measurement
    says — and the width rule over-counts *by design*. A title of mathematical-bold letters
    (`𝗖𝗛𝗜𝗟𝗟`: 2 cells measured, 1 drawn) parked its duration ~10 columns left of the row
    above it: ragged, on the one column that exists to be scanned. `\033[<n>G` (ECMA-48 CHA)
    moves the cursor to column *n* regardless of what was printed before it, so the rail
    lands on the same cell on every row even when a title mismeasures. Columns are 1-based,
    so a right-flush field of `rail_w` cells starts at `cols - rail_w + 1`. The title is
    still truncated to leave the rail room *by construction* — the jump repairs measurement
    drift, it does not license overflow — and in the theoretical case of a title rendering
    WIDER than measured, CHA moves backwards and cleanly overwrites the title's tail instead
    of pushing the rail into a wrap, which is the failure direction we want. It is a cursor
    move, not text: it never enters `disp_w` and does not disturb `\033[K` handling.
  - **The details section is variable-height chrome, measured BEFORE the rows are drawn.**
    Recovering the FULL title is the reason it exists — the one field a row can never show
    whole — so it is wrapped, not elided, and takes the height it needs: rail + however many
    lines the title wraps to + one metadata line. That makes it chrome whose height depends
    on the *selection*, and chrome measured after the rows costs the header instead of a row.
    `print_details` therefore honours `DETAIL_MEASURE` exactly the way `print_hints` honours
    `HINT_MEASURE`, reporting `DETAIL_LINES` without drawing (which needed a `WRAP_MEASURE`
    mode on `wrap_print`, funnelled through one `wrap_emit` so the counter cannot drift from
    the printer). The ordering is what keeps it non-circular: clamp `selected` (needs no page
    geometry) → measure the block for it → derive `PAGE_SIZE` → derive `page` from `selected`.
    Because the page follows the selection, the row the block describes is always on screen,
    so the page can never move the selection out from under the measurement — nothing to
    settle over multiple frames. `PAGE_SIZE` therefore changes by one as the selection
    crosses a one-line/three-line title; that is the accepted cost of an uncapped title, and
    the reflow already recomputes it every redraw. On a terminal too short to pay for both,
    the block goes and the rows stay — the same trade the navigation hints make.
  - **Six raw fields per row, US-separated — never a rendered string, and never tab.** The
    details section needs channel, views, liveness and an id per row, so a row stopped being
    one display string. `IFS=$'\t' read` **collapses runs of tabs** (tab is an IFS
    *whitespace* character), so one empty field silently shifts every field after it — and a
    live row's `duration_fmt` IS empty, which is exactly how a prototype came to read a
    channel name as a view count. ASCII US (0x1f) is not IFS whitespace, so empty fields
    survive; `clean`/`oneline` collapse whitespace in the two free-text fields so no field can
    contain a newline and split one record into two. The video id is derived from the url
    rather than carried as a seventh field. `play_selected` reads the arrays directly, which
    also retired its old habit of re-parsing the composed display string by splitting on
    ` · ` — a title containing that separator mis-split. The same tab trap was latent in the
    `yt-play -d -j` envelope parse (`id`/`pid`/`sock`, all defaulting to `""`, `@tsv`-joined:
    a player reporting no pid put its socket path in `pid` and the guard then rejected a play
    that had actually started); it reads US now too.
  - **An absent view count is not zero views.** The envelope reports `view_count: null` when
    the count was not published (every live row, some uploads). `// 0` turned that into
    "0 views", stating a number we do not have; the field is emitted empty and the details
    line omits the segment.
  - **How many rows fit is MEASURED, not guessed (the reflow).** `PAGE_CAP = LINES_N - 8`
    hardcoded the chrome at 8 lines, but the chrome is variable-height *by construction*:
    `print_hints` packs to the terminal width, so the status and navigation blocks take 1–4
    lines depending on width and chrome language. The constant is only right at ≳72 columns in
    English. Measured with the real script in tmux: at 40×20 the chrome is 11 lines, so ten
    one-line rows plus the footer came to 21 lines in a 20-line terminal and scrolled the
    header off — the same failure one-line rows were meant to end, arriving from the other
    side. 50×14 and 62×12 broke the same way. `display_list_menu` now counts the chrome as it
    prints it (`print_hints` reports `HINT_LINES`), then derives `PAGE_SIZE` from what is
    left, recomputes `NUM_PAGES`, and clamps the page — **every redraw**, so a resize or an
    `l` language switch repages instead of overflowing (`PAGE_SIZE` was previously computed
    once at startup and never revisited). The pagination-dots row is only charged when there
    is more than one page, checked against the no-dots size first so the reservation cannot be
    circular; one line is reserved for the cursor's resting row, because filling the last line
    and emitting its newline scrolls the screen by one and costs the header again. The details
    section is charged the same way, from its own measure pass, in the order above.
    The hint block's own fit test has to reserve that pagination row too: the lines after the
    block are the blank line, one result row, the blank line after the rows, the cursor's
    resting row **and** the page indicator whenever the list paginates at all — the test only
    bites on a short terminal, and on a short terminal more than one entry always means more
    than one page. Measured without it (true of the shipped version as well): a 62×10 terminal
    kept the block, printed 7 chrome lines, one row, a blank and `page 1/17`, and put eleven
    lines into ten — the header off the top, which is the failure this reflow exists to
    prevent.
  - **When the budget cannot pay for a row, the FOOTER gives lines back.** Every other block
    in the reflow can drop itself — the navigation hints do, the details section does. The rows
    cannot: a list with no rows is not a list, so `psize` has a hard floor of 1. That floor
    used to win against a budget of zero and the frame came out one line too tall, which
    scrolls the header off — the failure the reflow exists to prevent, arriving from
    underneath, and it survived the whole hardening pass as a "pre-existing" rig failure.
    Measured at 62×12 with `/` open: chrome 8 + spacer 1 + filter hint 1 + caret 1 + dots 1 +
    one row = 13 lines in a 12-row pane, and the title row went. So the footer is no longer one
    number: the spacer, the filter's instruction line, the caret and the pagination row are
    charged separately, and when the budget cannot cover the rows the list owes, they are
    reclaimed in value order — the spacer carries nothing, the filter hint teaches a mode the
    caret below it already demonstrates, the pagination row is real state and goes last, and
    the caret is never dropped because it echoes what the user is typing. At 62×12 that buys
    back exactly the two lines needed: header, one row, the dots and the caret all survive.
    Only when there is nothing left to drop does the floor overflow, and there the overflow is
    honest — no arrangement of that terminal shows a header, a row and a caret at once.
    The reclamation loop's "does the list owe a dots row" test is `NUM_ENTRIES > 1`, not the
    `> psize` test the dots are charged with afterwards: the loop only runs in the regime where
    `psize` lands on 1, where the two agree. It is not a second opinion about the footer, it is
    the same opinion evaluated early enough to spend.
  - **Across a repage the SELECTION is the anchor, not the page number.** The user is looking
    at a row. Deriving `page` from `selected` keeps that row on screen; clamping the selection
    into the old page number teleports it — measured: resizing 24→12 rows dropped the page
    from 10 entries to 2 and snapped the selection from row 15 back to row 4.
  - **A terminal too short for the hint block gets its rows instead.** `HINT_MEASURE=1` runs
    `print_hints`' identical packing and reports the height without drawing, so the list view
    can ask "how tall would this be?" before committing the space. Below ~12 rows the
    navigation block is 4 lines of a 10-line screen and would push the header off no matter how
    the rows are repaged, so it goes and the results stay — the same trade the Now-Playing
    banner already makes with its inline hints, and the card view still documents the keys.
    Verified at 40×10 and 62×8. Sub-40-column terminals remain out of scope by design (the
    `layout_cols` floor); at 35 columns the hint block wraps mid-item as documented.
  - **`truncate_disp` never exceeds the max it is given.** Clamping the leftover budget up to
    1 broke the one promise the function makes: at `max=1` it emitted a character *and* the
    ellipsis, two cells. When the budget cannot hold the mark, the mark goes. No caller
    reaches that today (all clamp to >= 8) — it is the guard on the contract.
  - **One clamp, one fetch, one rail.** `layout_cols [max]` is the single width clamp (floor
    40, optional cap — the player cards pass 80 so their rails do not stretch across an
    ultrawide window, the list passes nothing and uses the full width for its rows; passing
    the cap as an argument is what makes that asymmetry visible instead of looking like a
    lost line). `fetch_play_times` is the single `time-pos` / `duration` / `percent-pos`
    fetch behind `PT_CUR` / `PT_TOTAL` / `PT_PCT`, and the single `pause` read behind
    `CURRENT_PLAY_PAUSED`, including the live special case: both player views had inlined the
    same three `nc | jq` pipelines and had already drifted, and the live path used to fetch
    mpv's clock only to discard it (it describes the broadcast, not this listen). The live
    path now asks for `pause` and nothing else — one property on one connection — because the
    pause chrome was the one thing that path got WRONG for free: `toggle_pause` flips a local
    flag, so anything else driving the socket (`yt-play`, an agent's own `nc`, a second TUI)
    left the banner asserting a state the player had left. The local flip stays — it is what
    repaints the banner on the keypress rather than up to a second later — and the tick's
    read corrects it. Optimism, then truth. The card's
    divider rail is built by `repeat_glyph` and cached on `(width, glyph mode)` instead of
    `printf '─%.0s' $(seq 1 "$cols")` — a fork, plus precisely the idiom `repeat_glyph` exists
    to replace, run twice so the Unicode rail could be thrown away in ASCII mode.
    `repeat_glyph` and `render_prog_bar` now return through globals (`GLYPH_RUN`, `PROG_BAR`)
    like the rest of the width layer, so a redraw costs no subshell for them.
  - Pressing `Tab` toggles the two views; pressing `Esc` in the card instantly returns to List View.
- **PROCESS CLEANUP GUARANTEE.** An `EXIT INT TERM HUP` trap ensures any background player
  spawned during the `yt-tui` session is automatically and cleanly stopped upon quit (`q`).
- **FILTER is a LIVE pure-bash narrow** of the fetched rows — no network, no re-fetch, no
  external tool (this is what makes D5 hold). `/` enters filter mode; **each keystroke** re-runs
  `apply_filter` over `ALL_ROWS` and redraws, so the list narrows *as you type* (best practice
  for a local list-narrow — fzf / command-palette style, not Enter-to-apply). `↑↓←→` move
  within the filtered set (the shared `move_selection`), `Enter` plays the highlighted match,
  `Esc` clears the filter and exits. The input sits at the **bottom** of the screen (fzf-style,
  below the list), rendered with no trailing newline so the **real terminal cursor** is the
  caret — no fake block. The selected row is marked by a `> ` caret (ASCII, font-proof), not a
  reverse-video bar. Community-standard match semantics: case-insensitive
  (`shopt -s nocasematch`, scoped), space-separated **AND** tokens, empty query restores all.
  Tokens are quoted in the glob (`*"$tok"*`) so a user's `*`/`[`/`?` match literally — no
  injection. The haystack is **synthesized per row per keystroke**, not stored as a seventh
  field: the row already has the pieces, the string is never printed, and a stored key would
  be one more thing to keep in step with the renderer. It holds title, channel, view count
  and BOTH duration forms — the envelope's `11h:53m:45s` for parity with what the filter
  always matched, and `short_dur`'s `11:53:45` because that is the form the rail shows, and a
  filter that will not match what is on the screen is a filter that looks broken. It also
  holds the literal word `LIVE` for a live row, which is what keeps typing `live` working now
  that no row carries a rendered `● LIVE` string to match against. Matched rows are re-emitted
  unchanged, so `ALL_ROWS` stays the single source and a filter can never degrade a row. `n` (new search)
  stays Enter-submit — it hits the network — so the two prompts diverge on purpose (in-page
  filter is live; a remote search submits).
- **Chrome: pagination + cursor.** Pagination dots (`●○○`, current filled) render ONLY when
  there's more than one page — a lone dot conveys nothing — and fall back to numeric `page X/Y`
  in ASCII mode or past a readable dot cap. The terminal cursor is hidden while the menu is
  drawn (so no stray block parks below the footer) and shown only for the bottom filter input,
  typed prompts, and playback; a `trap … EXIT` restores it on quit / error / Ctrl-C.
- **Fetch spinner.** A search is the only moment the TUI has nothing to draw — at startup it is
  the only thing on an otherwise blank terminal — and a still `searching "lofi"…` reads as hung,
  which is why the line now ends in a rotating quadrant (`▘▝▗▖`, `|/-\` under `YT_ASCII=1`).
  Three decisions worth keeping: (1) it brackets `fetch_json`, not its callers, so the startup
  fetch, `n`, `m` and `o` all animate from one implementation and a fifth caller would get it
  automatically; (2) the ANIMATION is what runs in a background subshell, not the search —
  backgrounding the search would need an rc file and a done-marker, because `kill -0` still
  succeeds on an unreaped child and the poll would never end, and `fetch_json`'s three distinct
  return codes would have to be smuggled back through a file; (3) the timer is `sleep 0.12`
  because bash 3.2 has no other one — `read -t` truncates a fractional timeout there (measured:
  `-t 0.2` sat through a 5 s pipe), and a 1 s frame is not an animation. Each frame prints its
  glyph and backspaces onto it, so the line never grows; `spin_stop` erases the last frame and
  closes the line, which is what keeps `report_fetch_failure`'s sentence on a clean row. Echo
  goes off at `spin_start` and is deliberately NOT restored — a key pressed mid-fetch would
  otherwise land inside the spinner line, and every caller is heading into the menu loop, which
  runs with echo off anyway.
- **ONE clock, shared by every view.** `read_nav_input`'s `-t 1` used to be granted per
  view — card always, list only while `CURRENT_PLAY_LOADING`. That is why the list could carry
  no live element at all, and two grants of the same timeout are two places to change the
  cadence, which drift (the F7 shape). There is now a single condition, and it does not ask
  which view is up: it asks whether anything on screen can change **without a keypress**,
  which is playback. `[[ -n "$CURRENT_PLAY_ID" ]] || ((CURRENT_PLAY_LOADING))` — the play id
  covers a running player, LOADING covers the pre-socket window where a spinner has to advance
  before there is anything to poll. It cuts both ways on purpose: the list now ticks for the
  whole of playback (its rail is live, below), and the card *stops* ticking when nothing is
  playing, where it used to repaint a static `(nothing playing)` once a second forever. The
  live filter comes along for free, since `filter_live` drives the same reader.
  - **`read_query_input` is deliberately excluded.** The `n` new-search prompt has its own
    reader and stays untimed: a tick there would repaint the screen mid-keystroke while a
    query is being typed.
  - **The clock owns the polling, not the renderer** (`nav_tick`). The card polls inside its
    own renderer because its whole body IS the readout; every other view needs only the
    percent for its rail, so that poll happens on the tick instead. `fetch_play_times` is an
    `nc` + `jq` pair — two forks — and putting it in the list renderer would have charged
    every arrow keypress one IPC round-trip. A view that repaints between ticks reuses the
    last values, at most one second old, which is the resolution the rail is drawn at anyway.
    Exactly one poll per tick in every view: the card's from its renderer, everyone else's
    from `nav_tick`.
- **The list's rail is the same rail, and it goes live during playback.** The boundary under
  the navigation block is drawn in the accent now, not dim — a rail is a rail in every view,
  and the card's carries the accent because it pairs with the live progress rail, so matching
  here keeps one rail language (`print_details`' rail joins it). While a track plays that
  boundary *is* the live rail: the clock leaves the percent in `PT_PCT`, so the line doubles as
  the position readout and the list needs no bar of its own. It never changes width or
  disappears — no percent (a live stream, or the first second before mpv answers) draws the
  static divider at the identical `nav_cols` width, and `clear_play_state` resets `PT_PCT` so a
  stopped player cannot leave a position drawn behind it.
- **Three play states, not two.** `-d` returns as soon as the core
  has forked, but mpv still has to resolve the stream through yt-dlp and fill its cache, and on
  a cold URL that is *seconds* (measured: ~9 s on a first-play lofi mix). The banner claimed
  `▶ Playing` for the whole silent window. There is now a `Starting` state between launched and
  audible, carrying the fetch spinner's quadrant frames so the wait looks like the wait that
  preceded it. Four things make it work:
  - **`core-idle`, not `time-pos`.** mpv answers IPC long before it plays a note. `core-idle` is
    true while the core is producing nothing — loading, seeking, waiting on cache — and flips
    false the instant output begins, which is exactly the edge the label should turn on.
    `time-pos` goes non-null when the file is merely *loaded*, so it would call a still-buffering
    stream "playing" and put the problem back where it started.
  - **This state is what first made a ticking list necessary** (see the shared clock above).
    A banner that only refreshed on a keypress would be the same staleness bug
    `check_player_alive` exists to prevent.
  - **One decider, two views.** `play_state_marks` picks glyph/label/colour; the banner and the
    card pass in their own "playing" glyph (`▶` / `●`, the two they already used) and draw what
    comes back. With three states and two views, the alternative was six branches in two places.
  - **No rail during the window, deliberately.** The list keeps its static divider — the
    live rail needs a percent and there is none yet — and the card draws no bar, which costs
    the card a one-time two-row growth when the first percent lands. Considered and declined:
    an animated "indeterminate" rail would be a SECOND state indicator beside the spinner and
    the label, the same duplication the card's title dropped its `▶` for, with the added cost
    that a sweep sitting at 40% is indistinguishable from a track at 40%. The list's own line
    never changes width either way, which is what makes the static choice free there.
  - **Two ways out besides success.** A pause during the window clears the state — `core-idle`
    stays true while paused, so the probe could never clear it, and `Starting` over a player the
    user just paused is the wrong sentence. And a 20 s cap clears it regardless: on a stream that
    slow the choice is between an animation that never resolves and the optimistic label this
    showed before the state existed, and the cap picks the second, once.
- **URL plumbing:** the url is field 1 of the US-separated record and `load_rows` splits it
  back into `urls[]` alongside the five `R_*` field arrays, so a pick is a direct array index
  — never re-parsing a rendered line. Titles cannot break the field boundary because `clean`
  collapses whitespace (so no tabs or newlines survive) and the separator is a control
  character no title carries.
- **Refuse-don't-hang:** requires a TTY on **both** stdin and stdout or dies, so an
  agent/pipe invocation exits cleanly instead of blocking on key input. `-h` works
  without a TTY.

---

# Part III — Modular API (the contract surface)

## 12. Command specifications

### 12.1 `yt` — core engine (full, non-interactive)
- **Owns:** search (list/JSON), URL playback (prose + JSON + taxonomy), stream resolve,
  detached lifecycle. Full flag set; the wrappers delegate to it.
- **Flags:** `-n -m -M -s -S -l -j -J -f -d` + long `--json --json-full --detach
  --status --stop --get-url --info --transcript --sub-lang --set-volume --id --all
  --color --volume` (color is
  `--color` only — no `-c` short form; `-S` is the format-sort override — no `-F`).
  `--` ends option parsing: everything after it is the query/URL, verbatim (§6). At most
  one action per call; `--id`/`--all` belong to `--stop`/`--set-volume`; `-d` combines with
  neither an action nor `-f ascii|viz`.
- **Behavior:**
  ```
   yt <url>            play (prose)         yt -j <url>    playback status JSON
   yt --get-url <url>  resolve stream URL   yt -d <url>    detach; concurrent players OK
   yt --status         list players         yt --set-volume N [--id ID]  live volume
   yt --stop [--id ID | --all]  stop one/all  (--id from --status)
   yt --info <url>     metadata (prose)     yt --info -j <url>  metadata JSON (-J raw)
   yt --transcript <url>  captions as text   yt --transcript -j <url>  + timed segments
   yt "query"          LIST (D2, default)   yt -j "query"  search JSON envelope
   yt -J "query"       full-field JSON      yt             → error (D3)
  ```

### 12.2 `yt-search` / 12.3 `yt-play` — headless verbs
Narrow gates over the core; the full allow/reject surface is the table in §13.

### 12.4 `yt-tui` — interactive terminal UI
- Surface: `yt-tui [-n N] [-m S] [-M S] [-s field] [-f audio|video|fast] [--volume N]
  [-p ROWS] [--color auto|always|never] [query]` — search-shaping flags forwarded to `yt-search`;
  `-f`/`--volume` playback settings forwarded to `yt-play` on every play; `-p`
  rows/page; rejects all else. `--volume` is launch-time only (no live cycle key,
  unlike `-f`'s `v` — see §26). Query optional (prompts if
  absent). Requires a TTY on both stdin and stdout, `jq`, and the sibling verbs.
  `-f` is validated against `audio|video|fast`: playback is detached, and `ascii`/`viz`
  need a terminal (§9.2).
  Keys: arrows nav/page · Enter non-blocking play · `Tab`/`p` toggle the two views ·
  `Esc` back to list · `Space` pause · `[`/`]` seek ∓10s · `9`/`0` volume · `s` stop ·
  `v` cycle mode (audio→video→fast) · `l` switch chrome language (en↔zh, any view) ·
  `t` cycle palette family (any view) · `n` new search · `m` more results · `o` sort ·
  `/` filter · `q` quit.

## 13. Wrapper gating model

Each wrapper accepts only its own surface and points the caller at the correct tool on
a cross-flag — this is what makes the two contracts non-overlapping.

```
   yt-search                                  yt-play
   ─────────────────────────────────         ─────────────────────────────────
   allow: -n -m -M -s -S -l -j -J            allow: -f -d -j -J --detach --get-url
          --color -h                                --info --transcript --sub-lang
                                                    --status --stop --set-volume
                                                    --id --all --color -h --volume
   reject (→ "use yt-play"):                  reject (→ "use yt-search"):
          -f -d --detach --status                   -n -m -M -s -S -l --list
          --stop --get-url --info                 also rejects -f/-d/--volume when
          --transcript --sub-lang                 they appear alongside --transcript,
          --set-volume --id --all                 which is read-only and never plays
   positional: a QUERY (reject URLs)         positional: a URL
   default: inject -l if no -l/-j/-J         URL required unless
                                             --status/--stop/--set-volume
   both: emit `<flags> -- <positional>`  (the `--` is FORWARDED, not just consumed)
```

**`--` stops FLAG parsing, not argument validation.** Each wrapper re-applies its
positional check inside its own `--` drain loop, and the reason is that the check is the
wrapper's whole purpose. `yt-search` always did (`reject_url` runs on every token after
`--`); `yt-play` did not, so `yt-play -- "some query"` walked past the "not a URL" rejection
that `yt-play "some query"` gives, reached the core, and ran a SEARCH — printing a prose list
or, under `-j`, a full search envelope from the verb whose contract says it plays URLs. That
is the same bypass D7 removed `yt` from PATH to prevent (§4), reappearing *inside* the verb
that exists to prevent it, and reachable by adding two characters. A gate that only guards
the spelling without `--` is not a gate.

The core implements the *full* set; the wrapper only restricts which subset each verb
exposes. **Unified `-j` semantics** work because the wrapper guarantees the operation
type: `yt-search` guarantees non-URL → core `-j` = SEARCH envelope; `yt-play`
guarantees URL → core `-j` = PLAYBACK status.

**Why yt-tui composes the verbs, never the core (D8).** The same guarantee is what the
TUI relies on. `fetch_json` parses the search envelope, and only `yt-search`'s URL
rejection makes "core `-j` = search envelope" unconditional — a URL pasted into the
TUI's `n` (new search) prompt would otherwise route to `play_url_json`: a *blocking
playback* while the TUI waits for search JSON. Calling the core directly would force that URL guard up
into the UI — the wrong direction per §4's governing principle. Two side benefits, at
zero cost (the wrappers `exec` into the core): the human surface exercises the exact
agent contracts daily, so a broken verb contract is caught by human use before an agent
trips on it; and yt-tui depends on two narrow contracts instead of the core's wide
polymorphic surface.

## 14. Data contracts (JSON schemas)

Search envelope (`yt-search -j` / `yt -j "query"`):
```json
{ "query": "lofi", "count": 25,
  "results": [ { "id":"…", "title":"…", "url":"https://www.youtube.com/watch?v=…",
    "channel":"…", "duration":213, "duration_fmt":"00h:03m:33s",
    "view_count":12345, "live_status":"not_live" } ] }
```
`-j` = the 8 fields above (high-signal, ~4× smaller than the raw ~23-field yt-dlp
entry). `-J`/`--json-full` = same envelope, `results` holds every raw field.
`duration` and `duration_fmt` are **`null` together** when the duration is unknown (a live
stream); `view_count` can be `null` too. On failure the envelope is instead
`{status:"error", query, count:0, results:[], reason}` with the same `reason` enum as
playback, and the exit code is 2+ (§7/§15).

Resolve envelope (`<engine>-resolve -j -f MODE -- <handle>`) — **new at PLAN step B-2**:
```json
{ "status":"ok", "engine":"yt", "id":"dQw4w9WgXcQ",
  "url":"https://www.youtube.com/watch?v=dQw4w9WgXcQ",
  "title":"…", "duration":213, "mode":"audio", "format":"ba/b",
  "stream_urls":["https://rr2---sn-….googlevideo.com/videoplayback?…"],
  "http_headers":{"User-Agent":"…","Accept-Language":"…"},
  "retried":false }
```
This is the whole vocabulary the player has for "what am I playing", and every key is
load-bearing:

- **`stream_urls` is an array, VIDEO FIRST.** One element for a single stream; two when the
  engine's format merged a video-only and an audio-only track, in which case element 1 is
  the audio. The player joins them with mpv's `--audio-file` — the EDL synthesis
  `ytdl_hook` used to do for free (§8.1).
- **`http_headers` is a REQUIRED key**, possibly `{}`. This closes the hole the old
  `--get-url` left open: a bare stream URL is not enough to fetch on a host that checks
  `Referer` or pins a `User-Agent`, and the player has no way to invent them. An engine
  must NOT return a credential header here — the player puts these on mpv's argv, where
  `ps` can read them.
- **`format`** is the format string the engine actually used. The player records it in the
  player state file verbatim and never reads it: `bv*+ba/b` is a yt-dlp expression and the
  player does not know that language.
- **`retried`** = the engine fell back to an anonymous client (§8.2). The player relays it
  into the playback envelope's `retried`; it no longer observes it.
- **`engine`** = the token that is also the command prefix, so a caller holding a search
  result can reach the matching resolver by concatenation (`yt` → `yt-resolve`).
- Failure → `{status:"error", engine, url, mode, reason}` with the same `reason` enum as
  playback and **exit 2+** — floored to 2, because yt-dlp exits 1 for an unavailable video
  and 1 is reserved for usage errors.

Playback status (`ut-play -j -- <handle>`):
```json
{ "status":"ok"|"error", "url":"…", "mode":"audio",
  "exit_code":0, "reason":null, "retried":false }
```
`reason` enum: `forbidden | unavailable | format_unavailable | network |
stopped_by_user | unknown | null(ok)`. **`network` covers HTTP 429 rate limiting** as well
as connectivity: both are retryable, which is the only branch a caller takes on it, so 429
did not earn a new enum member in a contract three verbs publish. It is deliberately NOT
grouped with `forbidden` — 403 says these credentials never work, 429 says not right now.
`--transcript` is what surfaced this (it fetches a caption file per language and can trip
YouTube's limiter within a handful of calls) but playback and search could always reach it,
reporting `unknown` — the one reason a caller cannot act on.

**The enum is the shared fact; the classifiers are not.** Since B-2 there are three readers
of it and they live in different files on purpose: `yt-search` and `yt-resolve` each carry a
`classify_yt_dlp_error` that knows extractor wording (*video unavailable*, *requested
format*, *sign in to confirm*), and `ut-play` carries a much smaller
`classify_playback_error` that knows only mpv — transport failures and rc 130. A resolve
that fails is classified once, by the half that can read the wording, and the player replays
that verdict rather than re-deriving it from prose. **No member may be added by any of the
three that this section does not already list.**

Lifecycle / resolve:
```
   -d       : {status:"started", id, pid, url, mode, started_at, title:null, sock, log}
              sock/log are handed over so a client never rebuilds the state-dir layout
   --status : {status:"players",
               players:[{id,pid,url,mode,volume,paused,position,duration,title,started_at}…],
               failed:[{id,url,mode,started_at,ended_at,exit_code,reason}…]}
              empty arrays when nothing playing / nothing failed (still exit 0)
              title is null for the first second or two after a detach: the detached CHILD
              resolves (the parent must return in milliseconds) and patches `title` and
              `format` into its own record from the resolve envelope the moment it has one
              volume, paused, position and duration are read LIVE off the player's socket in
              ONE round trip (§9.3). volume falls back to the recorded launch/--set-volume
              value; the other three are null when the socket could not be asked or the
              player answered null — null is "could not ask", NOT false/0. position and
              duration are integer seconds and are null until mpv starts decoding (~8s on a
              cold start); duration stays null for a live stream.
              failed[] is the tombstone list — players that DIED on their own, newest first,
              at most 8, nothing older than an hour (§9.2). reason is the shared playback
              enum. A player that finished normally or was --stopped is never in it, so the
              array is an error record and not listening history (ROADMAP.md §0).
   --set-volume : {status:"ok", id, volume}          (live-adjusted via mpv IPC socket)
                | {status:"not_playing"}             (no target; exit 4)
                | {status:"ambiguous", reason:"multiple_players", players:[{id,pid,title,url}…]}  (exit 4)
                | {status:"error", reason:"ipc_failed"}   (dead/missing socket; exit 4)
   --stop   : {status:"stopped", id, stopped:bool}   (single target)
            | {status:"stopped", scope:"all", stopped:bool}   (--all)
            | {status:"ambiguous", …}                (2+ players, no --id; exit 4)
   (--get-url was retired at B-3: resolving a stream URL is what a bare `yt-resolve` call
    IS, and the player publishing a second spelling of it was one contract with two names.
    --info / --transcript below are `yt-resolve` verbs — the player does not forward them.)
   --info   : {status,engine,id,title,url,channel,uploader,upload_date,duration,duration_fmt,
              view_count,like_count,live_status,description,chapters} ; -J = raw record
              chapters = [{start_time,end_time,title}] | null ; error → {status,engine,url,reason}
   --transcript : {status:"ok", engine, id, url, lang, is_auto, chars, segment_count, text}
              -J = the SAME envelope plus segments:[{start,duration,text}…] (seconds) —
              a strict superset, the same relation search's -J has to its -j (a caller
              that widens never loses a field it was already reading).
              text is the segment texts joined by a space — the SAME string the default
              (prose) mode prints, so the two output modes cannot drift.
              `segments` is absent from -j because it is the same words TWICE: on a
              444-cue auto track the full envelope is 52,732 bytes, of which `text` is
              16,916 and `segments` is 35,647 carrying that identical text plus its
              timings. -j is 17,074 bytes — 3.1x smaller, no information lost for the
              summarise-this case the verb exists for (§22, token efficiency). `chars`
              and `segment_count` keep the lean form self-describing: a caller can budget
              context and knows what -J would add without fetching it.
              The raw json3 document is deliberately NOT what -J returns: it carries no
              status/lang/is_auto, so widening would LOSE fields — the one thing the -J
              contract never does anywhere else in this suite.
              lang is the track that was actually written, which is the first entry of the
              --sub-lang priority chain the video turned out to have.
              is_auto = the track came from YouTube's auto-generated captions rather than
              a human-authored one; decided from the printed human-caption dict, not from
              the file (manual and auto land under the same name).
              error → {status:"error", url, reason} with exit 1, mirroring --info. reason
              is the shared enum plus `no_subtitles_available`, which also covers a track
              that parses to zero usable cues (an empty transcript is a miss, not an
              empty success — a caller handed {"text":""} would summarise silence).
```

**Why `--transcript` is one yt-dlp call.** `--print` implies `--simulate`, and a simulating
yt-dlp writes no subtitle file — so `--no-simulate` is what lets a single invocation both
write the captions and report the metadata needed to describe them. (`--dump-json` carries
the same implication, which is why it cannot be the vehicle here: it is the natural-looking
recipe that silently produces no captions at all.) The printed field is `%(subtitles)j`
alone — `%(automatic_captions)j` runs to 940 languages / 3.2 MB on a popular video once
YouTube's machine translations are counted, and the human dict's keys already answer
`is_auto`. Captions are requested as `--sub-format json3` so the cleanup stays a jq program:
json3 carries the timing as structured fields, where VTT/SRT would need a timeline parser.
Three shapes get dropped — the leading window-definition event (no `segs`), auto-caption
rollup events (`aAppend`, whose only seg is `"\n"`), and inline style markup — and all three
fall out of the same two filters: cleaned text, then drop the empties. Filtering on the
cleaned text rather than on `aAppend == 1` is deliberate: it removes every rollup marker
observed while keeping any `aAppend` event that actually carries words.

**One envelope, one line.** Every `-j` / `-J` payload the suite writes to stdout is a single
line of JSON — search, `--info`, `--transcript`, `--get-url`, `-d`, `--status`, `--stop`,
`--set-volume`, and every error shape above. That is what makes the output usable as NDJSON:
a caller can read one line, parse it, and be done, without a streaming parser or a brace
counter. It also makes `-J` a *strict superset of `-j`* in shape as well as in fields.

The rule was violated for a long time by the two oldest read verbs. Search emitted 26 lines
for `-j -n 3` and 76 for `-J`, `--info -j` emitted 16, `--get-url -j` was pretty too, and
`--status` was compact only while the player list was **empty** — it pretty-printed as soon
as a player existed, i.e. exactly when something is polling it. Every one of those was a bare
`jq` where the lifecycle verbs had always used `jq -nc`; the fix was `-c` at five sites
(`emit_search_json` ×2, `resolve_info`, `resolve_stream_url`, the `--status` `jq -s`). The
state files under `players/` are *not* covered by this rule and stay pretty — they are an
on-disk record read by jq, not an envelope.

## 15. Exit codes, TTY, dependencies

```
   0    success; also --status/--stop (always); 130 normalized (SIGINT; clean q already exits 0)
   1    usage/validation error (die), wrapper flag-gating rejection, resolve failure
        (prose), empty-query (D3), yt-tui non-TTY refusal, conflicting actions,
        --info / --transcript fetch failure (incl. no_subtitles_available),
        --id/--all outside a lifecycle verb, -d with an action or with -f ascii|viz
   2+   propagated yt-dlp / mpv failure (playback, resolve -j, SEARCH failure — search
        reports 2 even when yt-dlp exits 1, so a tool failure is never confused with 1)
   4    --set-volume / --stop: did not take effect — no such player, no player,
        ambiguous target, or mpv IPC failure. The -j status/reason says which.
        Distinct from 1 (usage) and 2+ (propagated player failure). --stop treats
        "nothing playing" as idempotent success (exit 0); only ambiguity is exit 4.

   TTY  : yt-tui requires BOTH stdin and stdout (§11); the core never needs a TTY —
          it errors on empty input rather than prompting (D1/D3).
   deps : core needs yt-dlp jq mpv before search/play/geturl; --status/--stop need
          only jq (--status uses nc opportunistically for the live read and degrades to
          the recorded volume plus three nulls without it), --set-volume needs jq+nc (nc gated lazily so a
          bare search never demands it), and --info / --transcript need only yt-dlp+jq
          (all checked before the mpv gate). yt-tui needs only jq and the verbs. curl is an OPTIONAL soft dep for
          the play-time client probe (§8.2). BSD `nc -U` is stock on macOS; the Linux
          netcat `-U` gap is a known, documented limitation (§26 / script comment).
```

## 16. Configuration surface

Per-request choices are flags; set-once tuning is environment variables — deliberately
kept out of flags to keep each verb's flag surface narrow.

```
   Flags (per call):  -n -m -M -s -f -S -l -j -J -d --color --theme
                      --detach --status --stop --get-url --info --set-volume --id --all --volume
   Env (set once):    YT_COOKIE_BROWSER   (default chrome = login on; "none" = anon-only)
                      YT_AUDIO_FORMAT (ba)  YT_VIDEO_FORMAT (bv*+ba/b)
                      YT_VIDEO_FORMAT_FAST  YT_ASCII_VO (tct)  YT_MPV_INPUT_CONF
                      YT_ASCII (1 = ASCII glyph fallbacks; auto-on for a non-UTF-8 locale;
                        read by BOTH the core and yt-tui — legacy alias YT_TUI_ASCII).
                        Covers the WHOLE glyph set: ♫ ● ○ ❯ · ▶ ❚❚ • … → — ↑/↓ ←/→ ↵ ▘▝▗▖
                        and the bar/rail runs. Verified by asserting a rendered pane
                        holds no non-ASCII beyond the label text.
                      YT_LANG (en|zh) = language of yt-tui's menu chrome; default zh
                        under a zh* locale, English otherwise. Help output, errors and
                        the card's field labels stay English in both.
                      YT_THEME (minimal|mono|catppuccin|tokyonight|nord|gruvbox|
                        onedark) = yt-tui palette family (§11: one accent + one status
                        hue; community themes are 24-bit only under COLORTERM=truecolor).
                        --theme beats env; the t key cycles it live at runtime.
                      YT_BG (auto|light|dark) = background mode; auto chain:
                        $COLORFGBG → OSC 11 query → dark. Light = the theme's own light
                        variant (minimal swaps cyan for blue).
                      YT_SYNC (0|1|auto) = synchronized redraws (DCS 1q/2q; auto: on,
                        off under tmux).
                      YT_BRAND (=1: header wordmark in math sans-serif bold, §11 glyph
                        section; opt-in, ASCII mode wins).
                      NO_COLOR (=1: --color auto renders plain; explicit --color wins).
   Internal (set by the core for its own detached child, not a user knob):
                      YT_IPC_SOCK (per-player mpv IPC socket)  YT_DETACHED (=1: no
                      terminal, so quiet mpv + no stderr filter)
   (color MODE is the --color flag, NOT an env var — the scripts hardcode
    COLOR_MODE=auto at startup and only --color changes it, so a COLOR_MODE env
    value is never read. Theme and background ARE env-read: YT_THEME / YT_BG.)
```

Cookie handling: `YT_COOKIE_BROWSER` is presence-checked per platform (does the
browser's profile dir exist); if absent, extraction runs without cookies rather than
breaking. Reading a browser's cookie DB while it is running can yield a locked read and
silently degrade to unauthenticated extraction — closing the browser is the workaround.

## 17. Function map & provenance

```
   Core (shell/ut-play)
     Setup/util : usage, die, is_non_negative_int, validate_enum,
                  require_cmd/require_deps, mpv_supports_vo, normalize_playback_mode,
                  set_action, JQ_PRELUDE (jq p2/fmt_dur — the one duration formatter)
     Search     : fetch_results, print_list, emit_search_json
     Playback   : run_mpv, play_{audio,video,fast,ascii,viz}_url,
                  play_mode_url, have_probe_tools, probe_media_fetchable,
                  play_url_with_probe, play_url_directly,
                  play_url_json, classify_playback_error, format_for_mode
     Lifecycle  : group_alive, stop_group, ensure_state_dir, live_props (multi-property
                  IPC read), read_player_live (correlate + normalise, shared by both
                  --status modes), detached_epitaph (the child's last log line),
                  record_player_death / prune_dead_players / collect_failed_players
                  (tombstones, §9.2),
                  player_state/player_sock/player_log/player_lock_dir,
                  lock_player_state/unlock_player_state, new_player_id, detach_play,
                  detach_title_updater, reap_dead_players, resolve_target,
                  do_status, do_stop, do_set_volume
     Resolve    : resolve_stream_url (--get-url), resolve_info (--info),
                  resolve_transcript / transcript_fail (--transcript)
   Wrappers     : yt-search, yt-play   (parse → gate → exec yt)
   Interactive  : yt-tui   (fetch_json → build_all_rows → load_rows → menu loop:
                  display_menu · read_nav_input · move_selection · play_selected ·
                  new_search [read_query_input, Esc cancels] · filter_live → apply_filter)
                  Startup prompt: same read_query_input, run with echo off before the
                  first fetch — one reader, one Esc contract, no second implementation
     Views      : display_list_menu (rows + banner + reflow; in-place \033[H/K/J),
                  display_now_playing_card, display_menu (dispatch, DCS frame hold)
     Width layer: char_w/disp_w/truncate_disp/cluster_back, cw_range/init_cell_tables
     Fetch UX   : spin_start/spin_stop (background subshell, sleep 0.12 frames)
                  wrapped around fetch_json — every fetch path animates
     Chrome     : layout_cols, print_hints (HINT_MEASURE), wrap_print/wrap_emit
                  (WRAP_MEASURE), print_details (DETAIL_MEASURE), card_divider,
                  repeat_glyph, render_prog_bar
     Input      : read_nav_input/read_query_input, utf8_complete + init_lead_tables
                  (one key per CHARACTER), tty_echo_off/tty_echo_restore,
                  cursor_hide/cursor_show
     Player     : send_mpv_ipc, mpv_get_prop, fetch_play_times (one connection for
                  pos/dur/pct + pause; pause ALONE on the live path),
                  player_check_ready (core-idle → clears the Starting state, 20 s cap),
                  play_state_marks (playing/paused/starting → glyph+label+colour, both views),
                  toggle_pause, seek_relative, adjust_volume, stop_current_playback,
                  check_player_alive, clear_play_state, elapsed_since_play,
                  cleanup_on_exit
     Chrome i18n/
     theme      : set_ui_lang/cycle_ui_lang (the S_* table), init_theme/init_colors/
                  detect_bg/init_colorterm/cycle_theme, init_glyphs, init_sync
     Failures   : report_fetch_failure, play_failed_notice, press_any_key
     Formatters : fmt_sec (clock), short_dur (duration_fmt → 6:10:58), commas
```

Not every helper is listed — `print_usage`, `die`, `is_uint` and the other one-line guards
are omitted on purpose. Every *subsystem* is, which is the point of the map: a function this
file discusses by behaviour should be findable by name from here.

**Provenance.** The suite descends from an all-in-one `yt-search-n-play.sh`: its
non-interactive core moved into `yt` behind the verbs, and its self-rendered TUI
(menu chrome, `display_menu`, `read_nav_input`, `read_query_input`, arrow-key paging,
blocking-play semantics) was re-homed in `yt-tui` — same menu, now delegating to the
verbs. Little of that original's *playback* behaviour survives: play is detached now, so
"no `clear` before play" and "no stdin flush after playback" describe a foreground mpv the
TUI no longer runs, and rows are measured and elided rather than left to wrap. What did
survive is the menu's shape and its key map; the `/` filter, the two-view toggle and the
whole width layer are net-new.

---

# Part IV — Supported workflows

## 18. Human — interactive browse & play

```
   $ yt-tui "lofi hip hop" -n 40 [-f video] [-p 15] [--theme nord]
     → self-rendered menu (§11), TWO views toggled with Tab/p:
       List  : ↑/↓ nav · ←/→ page · Enter play (DETACHED, non-blocking — the menu keeps
               its terminal and the music keeps playing across n / m / o / filter) ·
               / filter (live narrow) · n new search · m more results · o sort ·
               v cycle mode (audio→video→fast, applies to the next Enter)
       Card  : ←/→ seek ∓5s · ↑/↓ volume · Esc back to the list
       Both  : Space pause/resume · s stop · 9/0 volume · [ ] seek ∓10s ·
               l chrome language (en↔zh) · t palette family · q quit (reaps its player)
```

## 19. Agent — search, then play

```
   # 1) Search → structured, token-frugal envelope; pick programmatically:
   url=$(yt-search -j -n 10 "lofi" | jq -r '.results[0].url')
   # 2) Play (blocking prose), or capture a machine-readable outcome:
   yt-play "$url"                       # prose
   yt-play -j "$url" | jq -r .reason    # → null on ok; enum on failure
```

## 20. Agent — compose without playing (resolve)

```
   # Resolve a direct stream URL and hand it to another tool (non-blocking):
   yt-play --get-url "$url"                         # prose: stream URL(s)
   yt-play -j --get-url "$url" | jq -r '.stream_urls[0]'   # structured
```

## 21. Agent — background playback with lifecycle control

```
   yt-play -d "$u1"                       # detach player 1 (returns immediately)
   yt-play -d "$u2"                       # detach player 2 (NOT refused — runs concurrently)
   yt-play -j --status                    # {"status":"players","players":[{id,…},{id,…}]} (exit 0)
   id=$(yt-play -j --status | jq -r '.players[0].id')
   yt-play -j --set-volume 70 --id "$id"  # live volume on player 1 → {"status":"ok",id,volume:70}
   yt-play --stop --id "$id"              # stop just player 1 (idempotent)
   yt-play --stop --all                   # stop every player; leaves zero orphans
```

Why this shape: a blocking-only player isn't composable for an agent. `--get-url`
(resolve), `-d`+`--status`/`--stop`/`--set-volume` (background + poll + live control),
and `-j` (structured outcome) are the escapes from "returns only when the video
ends," and `--status` (always) and `--stop` (except an ambiguous target, which is
exit 4) exit 0 so a polling loop never misreads a normal state as failure.

---

# Part V — Aligned best practice

## 22. 2026 agentic-tooling scorecard

| Dimension | Rationale | Status |
|---|---|---|
| Discoverability | `--help` is ground truth for a caller with no tribal knowledge | ✅ per-verb narrow help + full `yt -h` |
| Structured output | parse without string-matching prose | ✅ search (`-j`/`-J`) + playback (`-j`) |
| Token efficiency | high-signal beats complete | ✅ 8-field `-j` (~4× smaller); `-J` opt-in; `--transcript -j` drops the duplicated `segments` (3.1×) |
| Exit-code contract | success/failure must be detectable | ✅ `cmd \|\| rc=$?`; 130 normalized |
| Trust boundary | agent strings never hit a shell interpolation point | ✅ query/URL single argv elements; `--` guard |
| Refuse-don't-hang | never block on absent stdin | ✅ core non-interactive; `yt-tui` requires a TTY |
| Contract stability | changes fail loud, not silently | ✅ invalid enum + cross-flag rejection |
| Process lifecycle | background / query / stop long playback | ✅ `-d`/`--status`/`--stop`, group-stop |
| Composability | playback that only blocks isn't composable | ✅ `--get-url` resolve-only |
| Error taxonomy | branch on a cause, not raw wording | ✅ fixed `reason` enum |
| Config surface | per-request in flags; set-once as env | ✅ flags per-call; env for tuning |
| Ownership | no client lock-in; both surfaces portable | ✅ owned core + glue; primitives behind seams |
| Entry-point shape | separate verbs beat one mode-flagged command | ✅ narrow real wrappers + owned glue |

## 23. Clean / Safe / Modular / DRY adherence

```
   Clean   : the core shed ~334 lines of fragile ESC-parsing/paging; each command is
             single-purpose; no menu state machine in the agent path.
   Safe    : exit-code contracts preserved; TTY guards; interactive path never absent
             during change (§24); destructive edits grep-gated.
   Modular : four commands, one explicit dependency graph; each primitive behind a
             single seam.
   DRY     : search/play/lifecycle logic exists ONCE, in the core; wrappers + yt-tui
             only shape argv and delegate.
```

## 24. Safe-evolution methodology (how this suite is changed)

The refactor that produced this architecture followed a staged, reversible order — a
reusable template for future structural change:

```
   A  Build the new interactive path (yt-tui) against the CURRENT tools; validate in a
      tmux PTY.  → an interactive path is never absent.
   B  Rename core → yt; repoint wrappers/glue + symlinks; run the headless regression.
   C  Delete the old bespoke TUI + add non-interactive routing (the destructive step —
      kept LAST and small); grep-gate every removed symbol before deleting; regress.
   D  Update docs (this file, READMEs, usage()).
   E  Final headed (tmux) + headless sweep.
```

Principle: put the single destructive step last and smallest; prove its replacement
first; gate deletions by grep so no dangling reference survives.

## 25. Risk register (design mitigations)

```
   Risk                                    Mitigation
   ──────────────────────────────────────  ─────────────────────────────────────────
   Dangling ref after TUI deletion          grep-gate every removed symbol first
   Title with tab/newline breaks the row    jq @tsv escapes; IFS=$'\t' split in load_rows
   URL mis-recovery from a rendered line     url/display kept in parallel arrays (index pick)
   Filter over-matches / injects a glob      pure-bash: nocasematch + AND tokens + quoted "$tok"
   URL pasted as a search query               yt-search rejects URLs → no blocking mis-play (D8)
   yt-tui run without a TTY (agent/pipe)     require -t 0 && -t 1 → die (no hang)
   Core rename breaks wrapper locate         Step B repoints + validates before Step C
   yt-dlp prefix "ytsearch<N>:" clobbered    literal in core only; never rewritten
   Orphan fallback mpv after stop            process groups (pgid), not a PID-tree walk
   Empty arg array under set -u (bash 3.2)   guard array expansion before use
   Peer connects to a player's IPC socket    STATE_DIR/players 0700; macOS $TMPDIR is
                                             already per-user (Linux /tmp fallback pinned)
   pid reuse false-positives a dead player   NARROWED, not closed: handle is a monotonic
                                             token, liveness checks the pid stored IN
                                             <id>.json, and the record is reaped as soon as
                                             its group is gone — but group_alive is still
                                             pgrep -g, so a recycled pid leading a group
                                             inside that window would look live (§9.3)
   Captured -d stdout blocks on a bg job     detach_title_updater's fds redirected to
                                             /dev/null (a command substitution waits for
                                             every writer of the pipe, not just for us)
   Detached mpv status line fills the disk   YT_DETACHED → --no-term-osd-bar
                                             --msg-level=all=error in the child (§9.1)
   Search failure hands an agent no shape    captured stderr → classify_playback_error →
                                             {status:"error",…,reason} envelope (§7)
   Query that looks like a flag becomes an   `--` ends option parsing in the CORE and is
   action                                    forwarded by both wrappers (§6)
   Client moves volume behind --status'      --status reads volume live off the socket,
   back                                      recorded value only as fallback (§9.3)
   Concurrent title-backfill + set-volume  per-id mkdir lock (lock_player_state)
   clobber the same <id>.json              serializes the two temp+mv patches (§9.3)
   Stale socket after SIGKILL'd mpv          [[ -S sock ]] test → ipc_failed, never hangs
   nc waits full -w1 if the peer does not  request_id filter + head -1; a HEALTHY mpv
   close (a wedged mpv, not a healthy one)   closes on half-close, so a call is ~0.016s.
                                             yt-tui's redraw path is a tight loop, so it does
                                             not WAIT for nc at all: it reads the replies out
                                             of a process substitution and breaks on the last
                                             one, which bounds the wedged case too (§25.1 F19)
```

### 25.1 Open defect register — `yt-tui` hardening pass

Audited against `shell/yt-tui`. **Batch 1 (the one-line edits), batch A (the cheap
correctness/UX edits), batch B (the IPC layer), batch C (the liveness poll), batch D (the
failure reporters), batch E (the input layer), the views-cleanup pass and the i18n pass are
ALL fixed — the register is empty** — this is a register of known defects, not a description of the code. It is kept here rather than as a loose `PLAN-` file
because the findings are statements about *this* design's seams, and each one is only
actionable next to the section it sits in. The open rows below have since been re-audited
against the code and re-measured on the machine's own bash 3.2.57. **Seven of them asserted
something false** — F2's reason source, F5's round-trip cost, F10's byte-ordering trick (and
its replacement, table membership over lone bytes, was measured before it was written rather
than assumed a second time), F11's padding unit, F13's positional reply read, the whole of F15,
and then F19's own replacement figure, which was measured against a probe rather than against
mpv — so the
corrections are recorded inline rather than quietly swapped: each of those was a premise a fix
would have been built on. The F19 round is the sharpest of them: a wrong number was found by
re-measuring, replaced with another wrong number from a rig that did not behave like the
program, and only the real player settled it.

**Reproduced, not inferred:**

- Space → pause → unpause exits the script with status 1 (`set -e` kills it on the second
  toggle).
- `play_selected` returning 1 from a case arm exits the script with status 1 — no output,
  no cleanup message.
- `read -rsn1` on bash 3.2 delivers one **byte**: 你 arrives as `e4 bd a0`, three keys.
- `${q%?}` under a UTF-8 locale strips a whole **character** on 3.2 (你好 → `e4 bd a0`), so
  the F10 backspace needs no byte-repair fallback.
- One `nc -U -w1` round trip costs **~0.016 s against real mpv** — the "~1.02 s" once
  recorded here was measured against a probe that never closes the connection, i.e. a wedged
  player, not a healthy one (F19; the correction is in the closed list below).
- `printf '%-8s'` pads to eight **bytes**, not eight characters (F11).

**The `set -e` family — fixed.** All three were the same trap (§28): a non-zero status
reaching `set -e` from a place that reads like an expression, not a command. See the closed
list at the end of this section. F2's *reporting* half — a failed Enter that was a
survivable no-op with no message — shipped in batch D, in the same "press any key" style as
the `n`/`m`/`o` failures, which is why it was batched with F7. **Correction, kept because a fix
was very nearly built on it:** the reason cannot come from the envelope's `reason`. The §14
taxonomy belongs to the *blocking* play path; for a synchronous `-d` failure the core `die`s
with prose on **stderr** and emits nothing on stdout (verified: `yt-play -d -j -f ascii --
<url>` → rc 1, empty stdout). yt-tui captures that stderr, the way `fetch_json` already does
for search.

Audited clear in the same pass: every other case-arm function returns 0 on all paths
(`move_selection`, `cycle_mode`, `cycle_sort`, `new_search`, `more_results`, `filter_live`,
`stop_current_playback`, `apply_filter`); `mpv_get_prop` ends in `|| true` and is only ever
used in command substitution.

**Call-stack boundary — yt-tui reaching past a seam it already has.** Empty: this category is
closed. Both members shipped — the liveness poll (F3, batch C) and the input layer's byte-split
readers (F10 + F9, batch E).

**Shape — duplication and unfinished rules.** None left; F11 was the last row and closed with
the i18n pass below.

**Withdrawn — F15 was not a defect.** It read the (since-deleted) mini player's
`${#total_time}` bar sizing as
an ambiguous-width bug on the grounds that `total_time` can be `● LIVE`. It could not: the
live branch of `fetch_play_times` returns early with `PT_PCT=""`, and that view's `bar_total`
was only computed inside `if [[ -n "$PT_PCT" ]]`, where every part of the prefix is ASCII
(`fmt_sec` / `SHORT_DUR`). Neither the variable nor the view exists now — the card sizes its
bar from `cols`, never from `${#var}`. The `·` separator on that line is likewise live-only, i.e. bar-free. What was
wrong there was only the comment, which stated the conclusion ("all the prefix cells are
ASCII") without the early-return that makes it true; it now names that early return. No
arithmetic changed.

**Accepted, not defects** (recorded so they are not re-litigated): the filter swallowing
`q`/`s`/`9`/`0`/`l` is intentional modality; a failed play in filter mode consuming one
keystroke on "press any key" matches the `n`/`m`/`o` failure behavior. Pid reuse can
false-positive the shipped `check_player_alive`'s `kill -0`, exactly as §25 records for the
core's own `group_alive` — narrowed by the monotonic id, not closed, and not worth a second
mechanism in the client.

**Order — by ROI, not by severity.** None left. F11 — the cosmetic i18n pass — was ranked last
because it was the largest edit and the only purely cosmetic one; by the time its turn came the
views-cleanup pass had deleted the label layout that made it large, and it shipped as a string
swap plus the nine transient sites the register had never listed.

(Five batches stood in front of it and shipped first: the cheap correctness/UX edits — F18,
F14, F16 — the IPC layer — F19, F13, F5, which the re-audit had promoted from last to first
once a round trip turned out to cost a second rather than the borrowed ~10 ms — the liveness
poll, F3, the failure reporters, F2b + F7, and the input layer, F10 + F8 + F9. See the closed
lists below.)

Each step ends `bash -n` clean, re-runs the `set -e` repros (the third one drives the IPC
readers against a live peer, a stale socket and no socket), and the interactive smoke pass in
§27. Patch bodies and open questions lived in a working sketch pad,
`macos/docs/TODO-yt-tui-fixes.md`, which was deleted when this register emptied — as its own
rule said it would be. Everything the sketch pad was tracking is either in a closed list below
or, where it was a design decision rather than a defect, folded into §11.

**Closed by the batch-1 pass** (one edit, `bash -n` clean, both `set -e` repros green):

- **F1** — `toggle_pause` now assigns (`CURRENT_PLAY_PAUSED=$((1 - …))`) instead of running a
  bare `((x = 0))`, whose status-1 result killed the script on every *un*pause.
- **F17** — `send_mpv_ipc` returns 0, not 1, when the socket file is gone: it is the last
  command of `toggle_pause`/`seek_relative`/`adjust_volume`, and fire-and-forget was already
  its contract (the `nc` failure below it was always swallowed).
- **F2, crash half** — both Enter arms are now `play_selected || true`. A failed play became a
  survivable no-op; batch D gave that no-op something to say (F2b, below).

**Closed by the batch-A pass** (`bash -n` clean, both `set -e` repros green, each finding
re-verified in a real pty against the pre-edit file — the abort reproduces there and does not
after):

- **F18** — `wrap_print`'s word loop is now `${words[@]+"${words[@]}"}`, the guard §28 requires
  and every other array expansion in the file already used. Reproduced first: an emoji-only
  title cleans to `""` in `build_all_rows`, `read -ra words <<< ""` leaves `words` **unset**,
  and moving the selection onto that row exited with `words[@]: unbound variable`. It now
  renders the details rail and metadata line with an empty title.
- **F14** — `more_results` saves `page_index`/`selected` and restores them after
  `apply_search_results`. Measured on a 40-result page-2 selection: `m` used to snap back to
  row 1, and now stays on the row the user was looking at. `cycle_sort` keeps the reset and
  now carries the comment saying why.
- **F16** — `-m`, `-M` and `--volume` are validated at startup in the core's own wording,
  including the core's `-M > -m` cross-check. They were forwarded verbatim, so the core did
  reject them — but only at the first fetch (as "search failed") or the first Enter (as a play
  that silently never starts).
- **F6** — `require_cmd jq nc`.
- **F9, Tab half** — `$'\t')` no-op arm above the catch-all, so Tab no longer lands a literal
  tab in the filter query.
- **F12** — the duplicated `print_hints` sentence is gone. It had *drifted* by then: the theme
  pass rewrote the first copy to "not key-bold" and left the second saying "not key-yellow",
  which is the F7 argument in miniature.

**Closed by the batch-B pass — the IPC layer** (`bash -n` clean, the `set -e` repros green
against a live peer, a stale socket, a vanished socket and no socket at all; then a real tmux
pane driving the real backends — yt-dlp search, detached mpv):

**Correction first, because F19 was filed on a false measurement.** The "~1.02 s per round
trip, ~3 s per card redraw" figure came from a hand-written socket peer that
**never closes**. Real mpv does close once the client half-closes, so `nc` returns at once and
the *old* code cost **0.026 s** for `fetch_play_times` and **0.016 s** for a single property —
measured against a live mpv socket, and confirmed in tmux, where the pre-fix build ticked the
card's time readout 6 times in 6 one-second samples, exactly like the fixed one (that row
carried a `Time:` label at the time; the i18n and views-cleanup passes since removed it). The second
was never charged to a healthy player. What the probe actually modelled is a **wedged** peer
that stops closing; that is the case the old code paid `-w1` for, per call.

So F19 stands as a real but much smaller change, and F5 is the defect of this batch:

- **F19 (and F13 with it)** — `fetch_play_times` now sends its three `get_property` lines down
  **one** connection instead of three, and every reader takes replies out of a process
  substitution and breaks on the last one it wants, so a peer that has stopped closing costs
  the redraw nothing instead of `-w1` per call. Against real mpv: `fetch_play_times`
  **0.026 s → 0.017 s**, `mpv_get_prop` and `send_mpv_ipc` unchanged at ~0.016 s. Against the
  never-closing probe, which is the wedged-player case: **3.12 s → 0.07 s**, and the card
  repaints 5 of 5 one-second samples where it managed 1. Replies are matched by `request_id`,
  never by line order — mpv multiplexes async events into every client's stream, and this is
  what makes batching safe at all (F13's `map(.data)[]` sketch would have seated an event
  where a property belongs). Verified against a peer that answers the three requests **in
  reverse** with events interleaved, and a fresh player whose `time-pos` is null still renders
  `--:--` without sliding duration into the position slot. `send_mpv_ipc` also gained the
  delivery confirmation it never had.
- **F5** — `adjust_volume` is read-modify-set with a 0–100 clamp instead of `add volume ±5`,
  so the socket path can no longer walk past the contract the rest of the suite speaks (mpv's
  own ceiling is 130). Verified end to end against real mpv: a player launched at
  `--volume 10`, then twenty `0` presses, reads **volume 100** in `yt-play --status` — the old
  `add` would have left it at 110. The extra round trip is what tied this to F19; at 0.016 s
  it was affordable either way, which is the one place the false measurement changed a
  decision rather than just a sentence.

**Closed by the batch-C pass — the liveness poll** (`bash -n` clean, `shellcheck` clean of new
findings, the three `set -e` repros green, a unit test over the real function bodies, and a real
tmux pane driving real yt-dlp + detached mpv):

- **F3** — a dead player no longer leaves its chrome behind. `check_player_alive` polls
  `kill -0` on the envelope's wrapper pid at the top of the main loop **and** at the top of
  `filter_live`'s key loop, and clears through the new `clear_play_state`; see §11 for why the
  wrapper pid is the right thing to test and why an empty pid means "unknown, assume alive".
  Verified in tmux against a player killed by its process group: the **card** empties inside
  one 1 s tick with **no keypress at all**, the **list** banner survives until the next
  keypress (the read blocks — accepted, and now asserted rather than assumed) and then goes,
  and with `/` open one filter keystroke clears the banner *without leaving filter mode*,
  which is the half a single-call-site fix would have missed. A live player, an empty pid and
  an id-less state are all left untouched. The unit test extracts the real function bodies
  (an `awk` pass over the script, so it cannot drift from a copy) and also asserts that
  `clear_play_state` covers **every** declared `CURRENT_PLAY_*` global — which is how the
  pre-existing gap it folds in was found: `stop_current_playback` had never cleared
  `CURRENT_PLAY_URL`, so "cleared" had two definitions and one of them was wrong. A tmux pane
  rig covers the end-to-end path.
- Also in this pass, the last crumb of the withdrawn **F15**: the mini player's bar-sizing
  comment now names the live early-return that makes `${#var}` safe there, instead of only
  stating the conclusion. No arithmetic changed. (That view was deleted in the
  views-cleanup pass; the card's bar was never sized from `${#var}`.)

**Closed by the batch-D pass — the failure reporters** (`bash -n` clean, no new `shellcheck`
findings, the `set -e` repros and the batch-C tests still green, and a fixture-stub tmux rig
with 23 assertions, run three times for flake):

- **F7** — `report_fetch_failure rc [query]` replaces three copies of "no results / the error /
  press any key" in `new_search`, `more_results` and `cycle_sort`. The copies had already
  drifted — `m` and `o` said "no results" where `n` said `no results for "…"` — which is the
  usual signal that a block wants to be a function. Each caller still restores its own mutated
  global *before* reporting, so the query is passed in as an argument rather than read off
  `QUERY_LABEL`, which by then is back to the one that still works. Verified per key: the
  message, then the state (label, `RESULT_N`, `SORT_FIELD`) intact behind it.
- **F2b** — a failed Enter now says why. `play_selected` keeps the core's stderr in a temp file
  the way `fetch_json` keeps the search's, and reports its **last line** with the core's own
  `Error: ` prefix stripped (`die` can print context above the reason). Empty stderr degrades to
  "playback failed"; `rc` 0 with an envelope carrying no id or sock reports "malformed launch
  envelope" instead of dropping the keypress. The `|| true` at both call sites stays — that is
  the F2a guard, and this only gives it something to say.
- Both end in one shared `press_any_key`. That pause is the whole mechanism: a message printed
  into the scroll area lives exactly until the next redraw, and the next redraw is one keypress
  away.
- Not colored. The plan called for `C_YELLOW` on the play reason; the theme pass retired that
  variable (it is `''` in every theme), and the `n`/`m`/`o` failures it sits beside print plain,
  so reading a retired global would have bought nothing. The status-accent pass took the last
  real read of it with the card's paused branch, so it is now assigned and never read.
- **Correction — the plan's own repro for F2b was already unreachable.** It said to force
  `-f ascii` through the detached path and watch the core refuse. F16 (batch A) validates `-f`
  against `MODE_CYCLE` at startup, so `ascii` now dies in argument parsing and never reaches
  `play_selected`: one shipped fix closed the door the next one wanted to test through. The
  reason path is observable only from a stub, so the rig carries fixture stand-ins for
  `yt-search`/`yt-play` in a directory behind a `yt-tui` symlink — `SCRIPT_DIR` resolves the siblings, which is
  what makes stub injection possible at all — each failure selected by a marker file so the
  TUI's own startup fetch still succeeds and the failure lands on a keypress. Its `want`
  assertions poll rather than sleep: the reporters print below a
  full-height frame, so the pane scrolls and the header is briefly off-screen until the next
  `display_menu` lands — a fixed sleep there was measurably flaky.

**Closed by the batch-E pass — the input layer** (`bash -n` clean, no new `shellcheck`
findings, every earlier rig still green, plus a unit test over the real function bodies and two
new tmux rigs; the premise was measured before a line was written):

- **F10** — `utf8_complete` finishes a character off its lead byte and both readers go through
  it, so a CJK character typed at the filter or the new-search prompt is one key instead of two
  or three garbage ones. The lead-byte classes are built once with `cw_range ''` and tested by
  membership, the way `char_w` tests its cell tables. **The premise the plan flagged as
  unsettled held:** `cw_range` with an EMPTY prefix does build lone 0x80–0xFF bytes on 3.2.57,
  and `[[ "$CLASS" == *"$byte"* ]]` compares bytes even though the haystack is invalid UTF-8 —
  every lead byte C2–F4 lands in exactly one class, and continuation bytes, 0xC1, 0xF5–0xFF and
  ASCII land in none. The `printf -v n "%d" "'$b"` fallback was not needed. Continuation reads
  time out, so a torn sequence cannot wedge the card's 1 s tick; an incomplete sequence passes
  through rather than being discarded, because a discard would silently eat a keypress and the
  catch-alls already ignore what they cannot use. Backspace's echo now erases the number of
  cells `disp_w` measures, not one — a CJK glyph is two.
- **F8** — `read_query_input` returns 0/1. The Esc-vs-EOF distinction (2 vs 1) was never read
  by its one caller.
- **F9** — the filter's catch-all is widened from `?)`, which matched one BYTE and so could
  never match an assembled character. **Deviation from the plan, and the reason for it:** a bare
  `*)` would have made every escape sequence the arrow arms did not claim into query text —
  PageUp would have typed `[5~`, F1 `OP`, a modified arrow `[1;5A`. An `"["?* | "O"?*)` arm
  above it drops those; the introducer alone still falls through and is appended, exactly as
  before, because a sequence always carries something after it.
- **Found while testing, fixed here: the terminal driver was echoing on top of us.** `read -s`
  turns the driver's echo off for the duration of ONE read and restores it after, so between
  reads the driver echoes whatever is still queued — which any burst leaves behind. Measured by
  pasting 咖啡 as six bytes at the new-search prompt: the terminal received the last character
  **twice**, ours plus the driver's (`e5 92 96 e5 95 a1 e5 95 a1` for a query that was correctly
  `咖啡` internally). This is **not new** — the pre-batch-E byte-at-a-time reader sprayed U+FFFD
  across the line on the same burst — it was simply invisible while every multi-byte key was
  mojibake anyway. A UI that draws its own input has no use for the driver's echo, so `stty
  -echo` now covers the whole session and is restored through the same trap as the cursor
  (a two-path rig asserts the restore after `q` AND after a signal, because a yt-tui that
  exits without putting `echo` back leaves the user typing blind in their shell).
- **A harness lesson, recorded because it produced a false failure first.** The signal-path test
  reported the tty left at `-echo` when nothing was wrong: the harness blocked in `sleep`, a
  CHILD process, and bash defers a trap until the current command finishes. The TUI blocks in
  `read`, a builtin a signal interrupts, so the harness had to block the same way to be
  measuring the same thing. Same family as the batch-B probe that never closed its connection:
  a harness that differs from the program in one detail measures that detail.
- The other rig lesson: `wait_for "Navigation"` is not proof that the filter was left, because
  the menu is drawn *during* filtering too — and sending the next key too early let
  `read_nav_input`'s ESC continuation read swallow it as the sequence's second byte. Wait for
  the filter's own prompt to go.
- **The third lesson, found much later and the worst of the three: the echo rig had been
  passing for the wrong reason, and burning a core to do it.** Its blocking loop was
  `while true; do IFS= read -rsn1 _ || true; done`, meant to block in `read` the way the TUI
  does (the first lesson above). It never blocked. The caller starts it as a background job of
  a NON-INTERACTIVE shell, so bash redirects its stdin from `/dev/null` and every read returns
  EOF at once; `|| true` swallowed that, and "block like the program" became a tight spin at
  100% of a core. Worse, the spin OUTLIVED its pane: the rig installs the TUI's own
  `trap … INT TERM HUP` set, and a bash trap handler *returns to the loop* rather than exiting,
  so `SIGTERM` — the very signal the test sends — restored the tty and carried on spinning. One
  orphan leaked per run; seven were found alive, up to 1h21m each, at 8.5 load on 16 cores.
  And the test's own `kill -TERM` step passed only BECAUSE of the leak: it looks the harness up
  with `ps` first, and only a spinning process is there to find. Three rules come out of it:
  read the **terminal**, not stdin, when the claim is "blocks like the TUI"; never `|| true` a
  read whose failure is the interesting case (a failed read means the tty is gone, which is a
  reason to *leave*); and a signal trap in a harness must re-raise (`trap - $sig; kill -s $sig
  $$`) so the caller observes a real signal death instead of a survivor. The generalisation is
  the uncomfortable one: **a green assertion is not evidence the mechanism ran.** Both earlier
  lessons were about a rig measuring the wrong thing; this one is about a rig measuring nothing
  and reporting success, which no amount of re-reading the assertion would have caught — it
  took looking at what the machine was actually doing.
- **A fourth, from the in-place-render pass: a PTY with no window size renders a ONE-ROW list,
  and every frame assertion made on it is worthless.** A bare `pty.fork()` starts at 0x0, and
  `LINES`/`COLUMNS` in the environment do not fix it — `term_size` reads `stty size` through
  `/dev/tty` on purpose (§ the width layer), so the reflow had no rows to spend and drew exactly
  one. The frames looked plausible enough to trust: header, banner, ONE result, footer. The rig
  has to `ioctl(fd, TIOCSWINSZ, …)` before the first read; after that the same drive produced the
  full ten-row page and the row diffs meant something. Same family as the three above — the
  harness differed from a real terminal in one detail, and that detail was the whole subject of
  the test. Second half of the same lesson: assert on a CELL GRID, not on the byte stream. "Pause
  changed exactly one row" is a claim about cells after `\033[K` / `\033[J` / CHA have been
  applied — grepping emitted bytes cannot make it, and the byte stream of a correct in-place
  frame looks nothing like the screen it produces. The rig that taught this was a `pyte`
  model over a hand-rolled pty; it is gone, and the lesson is why. Emulating a terminal to
  test a terminal program leaves a harness that can differ from a real one in exactly the
  detail under test. `tmux` is a real terminal: `capture-pane` gives the grid for the screen
  claims and `pipe-pane` gives the stream for the byte claims, with no model in between.

**Closed by the reflow floor fix — the "pre-existing" rig failure** (`bash -n` clean, no
`shellcheck` delta, every suite green, and the list rig is finally 22/22 instead of 21/1):

- **The defect.** `psize`'s floor of 1 beat a row budget of 0 and the frame came out one line
  too tall, scrolling the header off at 62×12 with `/` open (and at 46×14 and 40×14). The fix
  is in §11: the footer is charged as four separately droppable parts and gives lines back in
  value order when the rows cannot be paid for.
- **The methodology lesson, which is the expensive part.** That failure was on screen for the
  whole hardening pass. Every batch from C onward ran the list rig, saw `21 passed, 1 failed`,
  confirmed the failure reproduced on the previous commit, wrote "pre-existing, not this
  pass's" and moved on — five times. Each of those statements was *true*, and together they
  were a way of never looking. **"Reproduces on HEAD" answers "did I break it", which is not
  the same question as "is it broken".** A suite that is allowed to sit at one failure teaches
  everyone reading it that one failure is the baseline; the number to defend is zero, and the
  cheapest moment to defend it is the first time it moves.
- **Two assertions in the input-layer rig could never fail, and pruning them was part of the
  same sweep.** `no "ï¿½"` ("no replacement characters on screen") searched for U+FFFD's UTF-8
  bytes read back as Latin-1 — six bytes that cannot occur in a UTF-8 pane however badly the
  reader mangles input. Correcting the needle to a real U+FFFD did not save it: the list view
  echoes nothing, so the pre-F10 build whose reader really did split characters leaves that
  pane clean too. The mangling is only visible on a line that echoes what you type, which is
  why the exact-prompt assertions are the ones that matter — measured on the pre-F10 build, the
  `n` prompt reads `❯ New search (Esc or empty to cancel): 咖啡??啡?啡啡???`. The second
  removal was a `want "New search"` sitting one line above that exact check: strictly weaker,
  same instant, and it passed on the broken build, since the mangled line contains "New
  search" too. Same family as the echo-rig lesson below — **a green assertion is not evidence
  the mechanism ran** — with the sharper corollary that a *weak* assertion beside a strong one
  is not free: it is the one that will be believed when the strong one is edited away.

**Closed by the i18n pass — F11, and the three quarters of it the register never wrote down**
(`bash -n` clean, no new `shellcheck` findings — same 15 as HEAD, occurrence for occurrence;
every earlier suite still green; two new rigs, 14 + 19 assertions):

- **F11 as filed** was `Playing`/`Paused` and `NOW PLAYING FOCUS`: three strings, `S_PLAYING` /
  `S_PAUSED` / `S_CARD_HEAD`, drawn at four sites (the state appears in both the list banner
  and the card). Both sites already MEASURE what they print — the banner elides its title
  against `disp_w`'d fixed parts, the card's meta row drops fields against a measured
  `tail_w` — so a translated string degrades the way the layout is designed to, and in fact
  Chinese is *narrower* here (播放中 = 6 cells vs `Playing`'s 7), which only moves the card's
  mode-drop threshold by one cell. The card header deliberately reuses the wording of the key
  hint that reaches it (`S_FOCUS`, "focus card" / "专注卡片"): one view, one name.
- **What the register had missed: nine more sites, all transient.** The startup prompt, the `n`
  prompt, `searching…`, the `m` and `o` action echoes, the no-matches copy, the filter banner,
  `Press any key…` and `Quitting…` (two call sites) were English literals too. They survived
  three audits because they print into the SCROLL AREA and the next redraw wipes them — none
  of them is in a captured frame, so every frame-diffing check the earlier passes ran was
  blind to them. **The register was not wrong about F11; it was incomplete, and the incomplete
  part was the part no rig could see.** Recorded because it generalises: an audit that reads
  only what a redraw draws cannot see chrome that a redraw destroys.
- **The rig had to change shape to catch them, twice.** A tmux poll of the `m`/`o` echoes
  passes for the wrong reason — 更多 and 排序 are also in the Navigation hint row, so grepping
  the pane finds the word without the sentence ever having been drawn. The echoes are asserted
  at the FUNCTION level instead: a rig calls the real `more_results` / `cycle_sort` /
  `new_search` / `press_any_key` with `fetch_json` stubbed, in both languages, and asserts the
  whole line plus the absence of every English literal. The pane rig keeps what only a pane
  can show: the startup prompt before any redraw, the
  `l` flip mid-session, the forced-failure tail, and `YT_ASCII=1` + zh, where the no-matches
  copy has to come out with the ASCII dash — the reason that sentence is two table entries
  composed at the print site rather than one entry with the dash baked in.
- Design consequences are in §11 (the exhaustive-table rule, the three constraints, and the
  one deliberate English change: `for 50 results` → `· 50 results`, so a single `printf`
  format serves both word orders).

**Closed by the views-cleanup pass** (`bash -n` clean, no new `shellcheck` findings, the
batch-C/D/E suites still green, and three new rigs: 25 card assertions, 9 list captures, 19
end-to-end tmux assertions — see §27):

- The **third view is deleted** and the **card's labels with it**; the list's index became one
  fixed-width column. All three are §11 decisions, recorded there rather than here because
  they are shape, not defects — but two of them shrank open findings. F11 stopped being a
  layout problem and became a two-string swap (there is no `%-8s` left to pad in bytes), and
  the F7 duplication the mini player embodied is gone rather than documented.
- **A harness lesson, again from a false failure.** Broadening the row regex to accept a
  marker where the number used to be (`^ *(\d+\.|>) `) made four filter-mode assertions fail:
  the filter's own caret line is `> <query>` at column 0, so the loosened pattern matched it as
  a result row and then reported it had no duration rail. The lesson outlived the shape it was
  learned on — the marker revert put the number back on every row, so the rigs now match
  `^(> |  ) *[0-9]+\. `, which excludes the caret for a better reason: a result row always has
  a number and the caret never does. Either way the point is the same as the two batch-E
  lessons: the assertion has to name the thing it means, not a string the thing happens to
  contain.

**Closed by the list-view rail/details work:** the original audit also carried F4 — play
metadata re-derived by re-splitting the *display* string, which only parsed correctly
because `clean` collapses whitespace, and which threw away the `views` field it parsed
(proof the split was never a contract). `play_selected` now reads the row's own fields
(§11), and the tab-collapse hazard the fix had to dodge is why the record separator is US
rather than tab. The same audit noted this document's §11 diagram naming `s`/`S` for
new-search/more-results instead of `n`/`m`; also corrected.

**Closed by the input-latency pass — the Enter key was being read as a UTF-8 lead byte:**

- **A one-byte read of Enter is the EMPTY string.** `read` strips its `\n` delimiter, and
  ICRNL turns Return into `\n` even in the non-canonical mode `read -n1` sets up — which is
  why every case arm downstream already lists `""` beside `$'\n'` and `$'\r'`. `utf8_complete`
  then tested that empty string against the lead-byte tables, and **`*""*` matches EVERY
  pattern**, so Enter was classified as a 2-byte lead and sat in the `read -rsn1 -t 1` below
  waiting for a continuation byte that cannot arrive. Cost: a full second of dead screen after
  every Enter, plus a SWALLOWED keystroke whenever the user pressed something inside that
  second (it was appended to `CHAR_IN` and read as one wrong key). Fixed with an early return
  on empty.
- **The bug was localised by an A/B the user had already run without knowing it.** The report
  was "a big delay after the startup prompt, but none with the query on argv" — two paths that
  share `fetch_json` entirely and differ only in `read_query_input`. Timed over a pty, Enter to
  the `searching` line: **1038 ms vs 20 ms**, and the fix takes the prompt path to 32 ms. The
  same second was also being paid before every `play_selected`, since `read_nav_input` routes
  Enter through the same call — invisible there, because a play takes seconds anyway, which is
  why it was reported as a *prompt* bug.
- The other three `== *"$var"*` globs (`char_w`, `cluster_back`) were audited in the same pass
  and are unreachable with an empty argument: all of them only ever receive `${s:$i:1}` for
  `i < ${#s}`.

**Closed by the detached-input pass — the player was eating the TUI's keys:**

- **The defect is in §9.1's launch, and the symptom was in the TUI.** `[` and `]` "did
  nothing". They decoded correctly (`0x5b`/`0x5d`, verified with an instrumented copy) and the
  IPC worked (`time-pos` `30.47 → 20.47 → 10.45 → 20.43` across `[ [ ]`), so neither the
  binding nor the wire was at fault: mpv was sitting on the caller's tty and winning the race
  for the byte. See §9.1 for the mechanism (`set -m` suppressing bash's automatic `/dev/null`)
  and the `lsof` evidence. Worth recording that the keys had been in **§12.4 and §18 all
  along** — the design documented three keys the UI never told anyone about, and once they were
  added to the hint block the collision surface with mpv became visible.
- **Correction, kept because two further defects were nearly filed on it.** This pass first
  concluded that mpv holding the tty also broke bash's `read -t 1`, and therefore killed the
  list view's one-second clock — the evidence being a `PT_CUR` that stayed empty and reads that
  blocked 12 s and 41 s. Both halves were wrong. An A/B with mpv on and off the tty times out
  **4/4 either way**, and the tick chain runs 6/6 against a local synthetic source; the long
  reads were YouTube throttling this session's own repeated searches to 57–90 s, which stalled
  the harness inside `play_selected`'s command substitution and left no idle second for a tick
  to fire in. **A measurement taken through a saturated network is not a measurement of the
  program** — the same family as the echo-rig and probe-vs-mpv lessons above, and the reason
  the clock was finally verified against `av://lavfi:sine` instead of a video.

## 26. Non-goals / known constraints

- Detached `ascii`/`viz` (no terminal to render into) — rejected at parse time (§9.2);
  `audio` is the norm and `video`/`fast` open their own GUI window.
- Blocking playback (`yt-play <url>` / `-j`) returns only when playback ends; use
  `--detach`+`--status`/`--stop` or `--get-url` for non-blocking agent flows.
- `yt-tui` rows are one jq pass over the cached results per search — fine for small N;
  not intended for thousands of results.
- No MCP wrapper (§1). No third-party YouTube client dependency (§2).
- Runtime volume control on DETACHED players IS supported (`--set-volume N [--id ID]`,
  §9.2/§14): each detached mpv runs with `--input-ipc-server=mpv-<id>.sock`, and
  `do_set_volume` sends one `set_property volume` command over that per-instance socket.
  `nc -U` is gated lazily so a bare search never pays for it (§15). `--volume N` remains
  the launch-time STARTING volume; `--set-volume` adjusts it live thereafter.
  Deliberately still OUT of scope:
    - Live volume for FOREGROUND playback — it has a real TTY, so mpv's own volume keys
      already work; no IPC needed. (`yt-tui` is no longer foreground: it plays detached
      and adjusts volume over the socket, which `--status` then reports live.)
    - `--pause` / `--seek` / mute and other runtime properties as *verbs* — the same
      per-instance socket carries them today, and `yt-tui` uses it directly (a verb per
      keypress would mean a process chain per 1s refresh tick). The socket is therefore a
      documented part of the `-d` contract (§9.3) and is handed to clients in the `-d -j`
      envelope; a verb is added only when a caller genuinely cannot speak to the socket.
      **That condition is not met today**: a shell-capable agent can drive the socket
      itself (`printf … | nc -U "$sock"`), and the socket path is handed to it precisely
      so it can. The caller that genuinely cannot is one confined to a declared tool
      surface — an MCP face — which `ROADMAP.md` §0 still lists as a non-goal, gated by
      its §9 triggers. So these verbs are blocked on THAT decision, not on effort.
      Two constraints, decided in advance so the decision does not have to be reopened
      to design them:
        - `--seek` must require a SIGNED value for a relative move (`+30` / `-15`) and a
          distinct spelling for an absolute one (`--seek-to 120`). A bare `--seek 30`
          reading as absolute contradicts both mpv's own default (relative) and
          `yt-tui`'s `seek_relative`, and would silently jump a caller who meant +30s —
          the failure mode §22's *contract stability* row exists to prevent.
        - `--toggle-pause` is NOT to be added. mpv's `cycle pause` returns no value, so
          the resulting state in the envelope could only be a guess. `--pause` /
          `--resume` are strictly better for a machine caller anyway: idempotent, with no
          read-modify-write race. Toggling stays a `yt-tui` keypress.
      Their prerequisite is now MET: `--status` reports live `paused` (§9.3/§14), so an
      agent that paused could observe that it had. The verbs stay blocked on the decision
      above, not on observability.
    - Linux `nc -U` portability — macOS-primary tool; BSD `nc -U` is stock, GNU netcat
      variants differ (`ncat -U` works; `netcat-traditional` has no Unix-socket support).
      Accepted as a known gap, noted in a script comment rather than solved now.

## 27. Verification matrix

**No *scratch* rig is named by path here, on purpose.** The exception is the five harnesses
that earned a permanent home and are committed under `tests/` — `contract.sh`, `tui_pane.sh`,
`lifecycle.sh`, `assert_pane.py`, `mpv_ipc_mock.py` — which the root README describes by name
because a contributor cannot run what nothing points at. Everything else this suite has been
verified with is a throwaway under a `tmp/` the repo does not track (`.gitignore`:
`**/tmp/`), so citing one of those by path is a promise the checkout cannot keep — it resolves on exactly one machine, until that
machine's scratch directory is cleaned. What is durable is the *shape* of each check, and that
is what the entries below record: what was driven, how it was observed, and the count of
assertions that survived. A rig is cheap to rebuild from its description and expensive to trust
when the file it names is gone; §25.1's harness lessons are here for the same reason — they are
the part of a rig worth keeping.

```
   Syntax     : bash -n on core + all three wrappers/glue (+ repo-wide shell check)
   Search     : yt-search -j → 8-field envelope + count; -J → full; default list;
                flag-after-query ordering; empty-query error; zero-result query →
                count:0; a live entry renders "LIVE"/"n/a views" (never a raw null);
                -m 999999 excludes unknown-duration (live) entries; yt-dlp failure →
                {status:"error",…,reason:"network"} under -j, exit 2 (prose: stderr + die)
   Argv       : `yt -l -- --status` SEARCHES for that text (does not list players);
                same via `yt-search -- --status`; --status --stop → conflicting actions;
                --status --id X / --all --status → rejected; -d --stop → rejected;
                -d -f ascii|viz → rejected
   Core       : yt "q" → list (D2); yt (no args) → D3 error; yt <url> prose play;
                yt -j "q" → envelope; -p rejected; invalid --color rejected
   Gating     : yt-search rejects -f/--detach/URL; yt-play rejects -n/-s/bare-query —
                each of those in BOTH spellings, bare and after `--`: `yt-play -- "a query"`,
                `-j -- "a query"`, `-d -- "a query"`, `--get-url -- "not a url"` and
                `--transcript -- "a query"` all exit 1 with the "use yt-search" redirect,
                and `yt-search -- <URL>` still exits 1 with the mirror message
   Envelopes  : every -j/-J payload is ONE line (§14) — search -j/-J, a zero-result search,
                --info -j/-J, --get-url -j, -d -j, --status with 0 AND with 2 players,
                --stop, an ambiguous --set-volume — measured with `| wc -l`, and each still
                parses with the same fields (jq -e on .query/.count/.results[0], .status)
   Resolve    : yt-play --get-url (prose + -j envelope, no playback)
   Transcript : yt-play --transcript → one line of clean text on stdout, ZERO bytes on
                stderr; -j → single-line {status,id,url,lang,is_auto,text,segments} with
                is_auto:false on a human-captioned video and 60 cues recovered; -J → the
                SAME envelope + segments, asserted a strict superset (del(.segments) is
                byte-equal to -j) — 17,074 vs 52,732 bytes on a 444-cue track;
                --sub-lang on a language
                the video does not carry → {status:"error",reason:"no_subtitles_available"}
                exit 1 under -j and a die() sentence in prose mode — note yt-dlp exits 0
                for an absent language, so the miss is detected by NO FILE WRITTEN, never
                by the exit status; --transcript with -d/-f/--volume rejected by the
                wrapper; --transcript --info → conflicting actions; a bad --sub-lang is
                refused in 0.016s (before any network round trip); the temp caption dir
                under the 0700 state dir is gone afterwards on every path
                Parser: driven offline against a saved human track and a saved auto track
                — 60 and 52 cues, zero residual tags, newlines or empty cues in either,
                and the auto track's rollup duplicates absent from the output
   Playback   : yt-play -j <bad-id> → {status:error, reason:unavailable, retried:false}
                (both probes fail to resolve → keep cookies, mpv emits the real error)
   Lifecycle  : -d ×2 → --status lists BOTH players → --set-volume --id (only that
                player changes) → ambiguous --set-volume w/o --id (exit 4) →
                --stop --id one → --stop --all → --status(empty); assert ZERO orphan
                mpv after stop; players/ holds only <id>.json (no bare token leak)
                Detach latency: `out=$(yt-play -d -j -- URL)` returns in ~0.03s (the
                title updater must not hold the captured pipe) and --status shows the
                title a few seconds later; -d -j envelope carries sock+log
                Detached log: mpv-<id>.log stays ~59 bytes with ZERO growth while
                playing, and still records a real ytdl_hook ERROR
                IPC window : --set-volume --id on a JUST-launched player answers
                {status:"error",reason:"ipc_failed"} with exit 4 until mpv is actually
                listening — measured at t=3s vs exit 0 from t=6s on a cold URL. That is the
                taxonomy working (4 = did not take effect), not a defect; a rig that sets a
                property inside the start-up window reads it as a false red
   Live volume: yt-tui 9/0 on a --volume 0 player → --status reports the
                moved value (not the stale launch value); from 98, three 0 presses stop
                at 100 and never reach mpv's own 130 ceiling
   Live read  : the four properties in ONE round trip (§9.3), driven against the IPC mock
                over a real socket: replies out of order land in the right slots
                (--reverse), a property answered null renders JSON null and NOT false
                (--null pause), async events interleaved change nothing (--noisy), and a
                peer that never closes its side costs 0.03s rather than the full nc -w1
                second (1.11s before `head -n <count>` closed the pipe). Against a real
                player: an external `set_property pause true` over the socket shows up as
                paused:true on the next --status, a dead socket reports paused/position/
                duration null with volume falling back to the record, and with `nc` off
                PATH --status still exits 0 with the same three nulls. position/duration
                are null until mpv starts decoding (~8s cold) and duration stays null on a
                live stream — the honest reading, not a fabricated 0
   Death record: a detached player that dies unasked (`-d -j -- <bad id>`) is reported once
                in --status failed[] with reason "unavailable" and exit_code 2, and
                --status still exits 0. Boundaries, driven through the real verb with
                fabricated state files: rc 0 (a normal finish) writes no tombstone, a log
                with NO epitaph line (the kill -9 / --stop shape) writes none either, and
                10 failures leave 8 on disk and 8 in the envelope, newest first. A real
                --stop of a live player leaves failed[] empty and zero orphan mpv
   yt-tui     : (tmux PTY) Enter → background play + banner; Tab → card (live
                time/progress via the envelope's sock) → Tab → list; Esc → list;
                IPC: against real mpv the card's meta row shows a new reading on
                every one-second sample (6/6 on a VOD row — the LIVE branch returns
                before any IPC and proves nothing here), fetch_play_times costs
                ~0.017s (one connection, not three), and `pgrep nc` leaves none
                behind. Against a peer that never closes (a wedged player) the
                readers still break on the reply instead of waiting out `nc -w1`:
                5/5 one-second repaints vs 1, ≤2 concurrent nc, 0 after a second.
                Replies land in the right slots when that peer answers out of order
                with async events interleaved, and a null time-pos shows --:--
                Widths (measured in display cells, CJK-aware): at 100/72/60 cols the
                card's rails and progress bar are equal and flush (80/72/60), the bar
                holds that exact width at 0/1/50/99/100%, the spacer row above it is
                blank (not a stale rail); YT_ASCII=1 renders [#---] at the same
                width
                Live stream: the card shows "MM:SS · ● LIVE · audio · ● Playing" with
                the counter ticking and NO bar (never mpv's ~99.98% percent-pos); a VOD
                in the same build shows "3:21 / 9:27 (37%) · audio · ● Playing" + a
                rail-flush bar
                Short terminals, the reflow's floor: 62x{10,11,12,13,14,16,20,24} and
                46x/40x{12,14,16,20}, each with and without `/` open — the header stays
                on line 1, at least one result row is drawn, and in filter mode the caret
                survives (24 captures). The same matrix on the pre-fix build fails three
                of them (62x12, 46x14, 40x14, all with the filter open), which is the
                assertion earning its place
                In-place render (`tmux capture-pane` over a 100x30 pane, so the assertion
                is what a TERMINAL ends up showing, not what the script emitted): pause →
                resume changes exactly ONE screen row (the banner) and a keypress emits
                ZERO ED sequences — no `clear` in a frame, none on a Tab/Esc view
                switch. Same rig: arrow-down changes 4 rows (two row lines, two details
                lines), a filter narrowing 25 → 3 results leaves no stale rows under the
                shorter frame, and list↔card in both directions leaves nothing of the
                outgoing view. Cost of a frame, same rig: a pause writes 2413 bytes in
                15-24 ms — the same full frame an arrow-down writes, which is the measured
                form of "the redraw is whole-frame ON PURPOSE" (§11)
                Fetch spinner / play states (same pty rig, real network): the four fetch
                paths (startup, n, m, o) each animate their own `…` line; Enter → the
                banner reads `Starting` with a turning quadrant for the whole mpv
                start-up window (~9 s on a cold URL) and flips to `Playing` with NO
                keypress; Tab mid-window shows the same state on the card; Space during
                it wins and the 1 s tick stops; YT_ASCII=1 draws both animations as
                |/-\
                Views cleanup (card matrix + index captures + view-cycle pane): the card
                renders NO label text at 40/60/80/120 cols x en/zh x vod/live/empty
                (25 assertions), always ONE meta row, dropping "· mode" at 40 rather
                than wrapping; list titles start on the SAME column across 1-, 2- and
                3-digit indexes and selected/unselected rows with the rail still
                right-flush, and the selected row shows BOTH its marker and its number
                (9 captures); Tab/p/Esc reach only two views and the card
                still repaints on its 1 s tick (19 assertions)
                Narrow terminals: at 100/72/60/46 columns EVERY chrome line fits the
                width in both views (max measured = the rails/bar themselves) —
                nav + hints + empty-state repack, the card's meta row drops fields,
                the banner elides its title
                YT_ASCII=1: a rendered pane contains no non-ASCII beyond the label text
                (>, ||, *, Up/Dn, Lt/Rt, Enter, -, ..., ->, [#---], |)
                Language: LANG=zh_CN starts Chinese, LANG=en_US starts English, YT_LANG
                overrides both, YT_LANG=fr dies; the `l` key flips the chrome in the
                list AND card views with playback uninterrupted
                i18n exhaustiveness (function-level rig + pane rig): the m/o/n/
                press-any-key lines assert whole-sentence in en AND zh at the function
                level, plus the absence of every English literal under zh (14); in a
                real pane, the startup prompt before any redraw, the / filter banner,
                the no-matches copy, the forced-failure tail, the `l` flip back to en,
                the quit line, and YT_ASCII=1 + zh rendering the no-matches dash as
                "-" (19). The card matrix runs its 40/60/80/120 x
                en/zh x vod/paused/live/empty grid against the translated status and
                header, and fails if the other language's string leaks (33)
                9/0 volume; ] seek; q → exits and reaps ONLY its own player;
                music keeps playing across `n` (new search) and `/` (live filter);
                Enter on another row switches track without a gap;
                full chrome draws (title w/ ♫ accent · status · hints · '>'-caret selected row · ●○○ pages · bottom filter input);
                List rows: the duration rail ends in the SAME column on every row of a
                page — asserted on a fixture carrying a mathematical-bold title (drawn
                narrower than measured, the row that ragged a padding-computed rail), a
                fullwidth title, a CJK title and a live row; geometry matrix
                40×10 62×8 40×20 50×14 62×12 62×24 80×24 100×30 120×40 plus a width
                sweep at 40/45/52/62/80/100/120 — header on line 1, no line over the
                pane width, and the details block DROPPED (not overflowed) at 62×8/62×10
                Details section: walking ↓ across titles that wrap to 1, 2 and 3 lines
                keeps the header on line 1 and every line within the pane — the row
                count is EXPECTED to change, what is asserted is that the reflow pays
                for the taller block out of the rows (10 → 8 at 62×24); a live row shows
                "● LIVE · live now", a null-view-count row omits the views segment
                WRAP_MEASURE parity: measured == printed lines over 10 widths × 5 texts
                (ascii, long-wrapping, CJK, one unbreakable word, mathematical bold)
                Filter parity: a token matching a title, a channel, the envelope
                duration (11h:53), the DISPLAYED duration (11:53) and LIVE
                Resize 62×24 → 12 → 10 → 8 → 24 → 14 (with a redraw keystroke, since the
                list-view read has no timeout) keeps the selection anchored on the same
                row and repages every time
                ↑/↓ nav + ←/→ page (assert page count w/ -p); n/m/o → re-fetch;
                v → PLAY_MODE flip (local, no re-fetch; status/hint update on redraw);
                / → LIVE filter (type narrows per-keystroke; multi-term AND; mixed-case;
                    ↑↓ move within filtered; backspace widens; Esc clears + exits);
                -c never → no ANSI; Enter → DETACHED play: the envelope's id/pid/sock
                land in CURRENT_PLAY_*, the banner appears on the next redraw and the
                menu never blocks; Enter on another row switches track without a gap;
                a launch that fails prints the core's own last stderr line and waits on
                "press any key"; non-TTY (piped stdin or stdout) → dies cleanly
   Input      : (pty, timed) Enter at the startup prompt reaches the `searching` line in
                32 ms against 1038 ms before the utf8_complete guard; the same query on
                argv measures ~20 ms either way, which is what localised the stall to
                read_query_input rather than to the fetch the two paths share
   Detach fd  : (pty) lsof on the wrapper AND mpv — fd 0 is /dev/null and mpv answers
                input-terminal=false; before the fix both held /dev/ttysNNN with
                input-terminal=true. The A/B names `set -m` and not the `&` as the cause:
                the same mpv backgrounded WITHOUT set -m gets /dev/null for free
   Clock      : read -rsn1 -t 1 times out 4/4 at 1 s with a live detached player attached
                and the parent on the tty; the whole tick chain (timeout → three-property
                one-connection fetch → advancing pos/dur/pct) runs 6/6 against a LOCAL
                synthetic source (av://lavfi:sine), which keeps YouTube throttling out of
                a timing measurement it had already corrupted once (§25.1)
   Banner     : the tail's fallback ladder, 8/8 at the function level — no reading yet →
                duration alone; --:-- + seeded total; elapsed/total; mpv's own total
                winning over the row's; empty total → duration; live with and without a
                reading; and a 1:02:03 / 11:53:45 long-form pair
   Nav block  : real renders at 130 cols (label-less, dot-separated, two lines with the
                three added keys), at 60x12 (the gate DROPS the block, header still on
                line 1, nothing scrolled), and in zh after the S_SEEK rename
                (9/0 音量 · Space 暂停 · [ ] 跳转) with no set -u abort
```

## 28. Portability contract — bash 3.2

**All four scripts must run under bash 3.2** (macOS's frozen system `/bin/bash`, which
`#!/usr/bin/env bash` resolves to on stock macOS). This is a deliberate floor: zero
install step, identical behavior across macOS, Linux, containers, CI, and cron/launchd
(where PATH may not surface a newer bash). We do *not* depend on Homebrew bash — a
managed interpreter adds an interpreter-drift failure mode (same script, bash 5
interactively vs 3.2 under cron) without buying any feature this suite needs.

Rules for anyone editing these scripts:

```
   Forbidden (bash 4+):  declare -A (assoc arrays) · ${var,,}/${var^^} · mapfile/
                         readarray · ${arr[-1]} · &>> · |& · ${!prefix@}
   Empty-array + set -u:  a bare "${arr[@]}" on an EMPTY array ABORTS on 3.2
                          ("unbound variable"). Use one of the two portable forms:
                            ((${#arr[@]})) && cmd "${arr[@]}"          (guard, as in core)
                            cmd ${arr[@]+"${arr[@]}"}                  (inline, as in yt-tui)
   Arithmetic + set -e:   a bare ((expr)) is a COMMAND, and its exit status is 1 when
                          the expression evaluates to 0. Under set -e that aborts the
                          script. So never write ((x = 1 - x)) or ((n += w)) as a
                          statement — use x=$((1 - x)) / n=$((n + w)). ((x)) as a TEST
                          (in `if`, `&&`, `||`) is fine: there the status is the point.
   read -rsn1 = one BYTE: not one character, on 3.2. A CJK character typed at a prompt
                          arrives as 2-3 separate "keys" (verified: 你 → e4 bd a0), so
                          any reader that accumulates keypresses into text has to
                          reassemble the UTF-8 sequence from its lead byte (yt-tui's
                          utf8_complete). Classify the lead byte by TABLE MEMBERSHIP,
                          the way char_w does — NOT by byte-range comparison:
                            `LC_ALL=C [[ … ]]`  is not valid bash at all. An assignment
                              prefix applies to a simple command and [[ is a reserved
                              word, so bash tries to run the raw byte as a command name;
                              the test never runs under C collation and answers wrong.
                            `( LC_ALL=C … )`    is correct but forks per keypress and
                              cannot set a global.
                          Build the classes once with cw_range '' <lo> <hi> and test with
                          [[ "$CLASS" == *"$byte"* ]] — verified byte-exact on 3.2.57 even
                          though the haystack is invalid UTF-8.
   read -s is per-read:   it turns the terminal driver's echo off for the duration of ONE
                          read and restores it after. Between reads the driver echoes
                          whatever is still QUEUED, which any burst (a paste, a fast
                          multi-byte character) leaves behind — measured: pasting 咖啡 at
                          a prompt echoed the last character twice, and byte-at-a-time it
                          sprayed U+FFFD. A UI that draws its own input must own the echo
                          for the whole session (stty -echo) and restore it from the same
                          trap that restores the cursor.
   Verify:                run the empty-argument paths under /bin/bash explicitly —
                          this class is a runtime bash-version behavior, so `bash -n`
                          and shellcheck do NOT catch it; only executing on 3.2 does.
                          Same for the two rules above: both are runtime behaviors.
```

If a future feature genuinely needs bash 4+, the honest move is to assert
`((BASH_VERSINFO[0] >= 4))` at the top with a `brew install bash` hint and let PATH
provide it — never hardcode `/opt/homebrew/bin/bash` (breaks Intel macOS + Linux).
