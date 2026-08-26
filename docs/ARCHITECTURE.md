# ARCHITECTURE — uting

`ut-play` · `yt-search` · `yt-resolve` · `bili-search` · `bili-resolve` · `uting` — a
search + terminal-playback CLI suite, designed as much for **LLM/agent callers** as for
humans. This is the umbrella **as-built doc**: architecture, functional structure, supported
workflows, the module contract, and the rationale behind them — a description that chases
the code, resynced at every landing that touches architecture or a contract. Each fact
lives in ONE section; everything else points at it.

Scope is the whole suite. A per-surface `AS-BUILT-<scope>.md` splits out when this doc
grows heavy enough that one earns it, and the one-fact-one-section rule then holds across
the family. Two have: `AS-BUILT-contract.md` (the frozen CLI surface — Part III below is
tombstones) and `AS-BUILT-engine.md` (everything site-specific: search, resolve, the
login/PO-token probe, handle grammar — §7, §8.2 and §10 below are tombstones). A moved
section keeps its NUMBER, so an old citation changes filename and nothing else. What this
document is NOT: the sequencing (`ROADMAP.md`) or work in flight (`PLAN-<topic>.md`). The
four stages are defined in `CLAUDE.md`.

- Player (source-agnostic): `shell/ut-play` — plays, and owns the detached lifecycle
- YouTube engine (a pair): `shell/yt-search` (query → results), `shell/yt-resolve`
  (handle → stream URL + headers, plus `--info` / `--transcript`)
- Bilibili engine (a pair): `shell/bili-search`, `shell/bili-resolve` (`--info`; this site
  serves no captions, so there is no `--transcript` half)
- Interactive UI: `shell/uting` (owned glue over the verbs; no extra deps)
- Caller-facing surface: each verb's own `-h`/`--help` · Orientation: `README.md`
- Runtime deps: `yt-dlp` + `jq` in the engines, and `curl` — REQUIRED by `bili-search`
  (it is that engine's transport), optional in `yt-resolve` (the probe); `mpv` + `jq` in the
  player; `nc` for `--set-volume`. No fzf / TUI framework — only foundational primitives.
- The version is declared once, in `VERSION`; every entry point reads it and prints
  its own name (§4).

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

No opinionated third-party media client anywhere in the path. All site-specific
orchestration lives in code we own; the external primitives do only universal,
site-agnostic heavy lifting, each isolated behind a single seam (§5).

```
   Human surface     ──►  uting                      (interactive: self-rendered menu, detached play)
   LLM/agent surface ──►  ut-play                    (playback + lifecycle, source-agnostic)
                     ──►  <engine>-search            (query → results)
                     ──►  <engine>-resolve           (handle → stream URL + headers, metadata, captions)
   Primitives        ──►  yt-dlp · mpv · curl        (foundational, swappable behind seams)
```

Every one of those is a PATH-exposed peer; there is no hidden core underneath them and no
shared library between them (§4).

**Why ownership matters (D6).** Surveyed alternatives were rejected as runtime
dependencies: `ytfzf` dormant (~21 months, GPL-3.0) — client-level lock-in risk;
`yewtube` a heavier Python app; `yt-x` (MIT, active) used only as a *reference* for
layout/keybinding ideas — no code or dependency taken. All clients are bottlenecked by
`yt-dlp` anyway, so a third-party client buys no capability we can't assemble ourselves
while costing portability. Conclusion: own the glue, depend only on primitives.

**Where the ownership line now falls (D7).** It used to be "own the core"; since the
player/engine split it is **own the seam**. Site knowledge is owned and confined to an
engine pair; playback and lifecycle are owned and confined to the player; what crosses
between them is a JSON envelope this document specifies (AS-BUILT-contract.md §3), not a function call.

## 3. Design decisions (index)

One line each; full rationale lives in the referenced section. **These `D#` are this
document's own series** — `ROADMAP.md` keeps a separate one, and a reference to it is always
written `ROADMAP D9`, never a bare `D9`.

```
  D0  Names: ut-play, yt-search, yt-resolve, bili-search, bili-resolve, ut-playlist,
      uting —
      the canonical name every doc, help text and error message uses. ONE name per
      command, and NO short form ships: yts/ytp/ytt are all retired (ROADMAP D10).
      Three naming rules, one per audience: the human face is the release name
      (`uting`), the player carries the suite prefix (`ut-`), an engine carries its
      SITE's name — because that is the one thing a caller must know about it. (§4)
      "tui" not "ui": uting is precisely a full-screen *terminal* UI.
  D1  Everything except uting is NON-INTERACTIVE. An agent-facing verb that can
      prompt can also hang; removing the capability makes the failure mode
      impossible.                                                             (§6)
  D2  RETIRED at the split. Was: bare `yt "query"` → list output. Searching is a
      verb of its own now (`<engine>-search`), and `ut-play` given a non-handle
      names that verb instead of guessing.                                    (§6)
  D3  A verb with nothing to act on → usage error naming the RIGHT verb; never a
      prompt. `ut-play` with no handle and no action points at yt-search/uting. (§6)
  D4  uting renders its OWN menu (no picker/TUI framework) and delegates:
      search → <engine>-search -j · play → ut-play -d -j --engine ·
      filter → pure bash.                                                     (§11)
  D5  No fzf / interactive dependency anywhere in the suite.                  (§11)
  D6  No third-party media-client dependency.                                 (§2)
  D7  RETIRED and inverted at the split. Was: one shared core, verbs are thin gates
      that exec into it. There is no core: eight peers, each self-gating, each owning
      its own primitive calls. What they share is the ENVELOPE, not code.     (§4)
  D8  uting composes the VERBS only — never an engine's internals, never mpv
      except through the socket the player published.                        (AS-BUILT-contract.md §2)
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
      caller's tty and mpv raced the TUI for every keystroke.                 (§9.1)
  D12 The engine NAME is the command prefix. `--engine yt` reaches `yt-resolve` by
      string concatenation, so adding a source adds no registry, no mapping table
      and no case arm anywhere in the player or the TUI.                       (§4)
  D13 An engine states a capability by HAVING the verb. `bili-resolve` has no
      --transcript because the site serves no captions — rather than a verb that
      always answers "none", which a caller cannot distinguish from a bad day. (AS-BUILT-contract.md §1)
  D14 DURABLE state is a command of its own, and lives outside $TMPDIR. `ut-playlist`
      owns the user-level store; the player's `players/` stays runtime-only and dies
      with the reboot. The stored record is {engine, url, …} — the two arguments of
      `ut-play`, so a record is a CALL, not a reference. The queue is the deliberate
      exception: it is a playlist being consumed, so it belongs to the player, in the
      player's runtime state and dying with it.  (§9.4, §9.5)
```

## 4. Command topology & file layout

**Eight commands, one layer, no library.** There is no core and there are no wrappers. Each
file is a complete, PATH-exposed executable that gates its own flags and calls its own
primitives. They divide by *what kind of knowledge they hold*, not by who calls whom:

- **the player** (`ut-play`) holds playback and the detached lifecycle, and knows **no site**;
- **an engine** is a PAIR — `<name>-search` (query → results) and `<name>-resolve`
  (handle → stream URL + headers, plus whatever read-only verbs the site supports) — and
  holds **all** of one site's knowledge;
- **the stores** (`ut-playlist`, `ut-history`) hold durable user-level state and know neither
  site nor playback — a record is `{engine, url}`, which is a CALL rather than a reference
  (§9.4); the playlist is what a person put there, the log is what a player wrote (§9.6);
- **the human face** (`uting`) holds rendering and holds none of them.

```
                          PATH entries (user-created symlinks)
        ~/bin/
        ├── uting        → <checkout>/shell/uting          human surface
        ├── ut-play      → <checkout>/shell/ut-play        agent surface
        ├── yt-search    → <checkout>/shell/yt-search      agent surface
        ├── yt-resolve   → <checkout>/shell/yt-resolve     agent surface
        ├── bili-search  → <checkout>/shell/bili-search    agent surface
        ├── bili-resolve → <checkout>/shell/bili-resolve   agent surface
        ├── ut-playlist  → <checkout>/shell/ut-playlist    agent surface (optional)
        └── ut-history   → <checkout>/shell/ut-history     agent surface (optional)
              ONE name per command; no short form ships (ROADMAP D10)

   Runtime graph — site knowledge ONLY in an engine pair, playback ONLY in the player:

     uting ──► <engine>-search -j ──► render ──► ut-play -d -j --engine <row's engine>
        │  ▲                                           │
        │  ├──── ut-playlist --show -j   same rows, other source (§9.4)
        │  └──── ut-history  --ls   -j   same rows again (§9.6)
        └──► nc -U <sock>  (the player published the path; §9.3)
                                                       ▼
                                   ut-play ──► <engine>-resolve -j -f MODE
                                        │            (yt-dlp / curl live HERE)
                                        ├──► mpv --no-ytdl <direct URL>
                                        └──► ut-history --record -   (one row per track)
```

**The engine name IS the command prefix (D12).** `--engine yt` reaches `yt-resolve` by
concatenation (`ut-play` line ~228: try `$SCRIPT_DIR/$ENGINE-resolve`, then PATH, else exit
1 naming the engine). This is the whole registry. A third source is a new pair of files and
**no edit** to the player or the TUI — which is the claim the Bilibili engine was built to
test, and it held: step C changed neither file.

**How `uting` finds engines without holding a list.** At start-up it scans its own directory
and PATH for `<name>-search` and keeps the name only if `<name>-resolve` exists beside it —
a half-installed engine is not an engine. `e` cycles the source and re-fetches; with one
engine installed the affordance is not drawn. The `--engine` it hands to `ut-play` comes from
the search envelope's own `engine` field, never from a default (§11).

**Why four engine commands and not `yt search|resolve` subcommands.** A narrow verb has a
narrow flag surface, which is what makes it safe for a small model to call: `yt-search`
literally cannot accept `--detach`, and `ut-play` literally cannot search. A subcommand
dispatcher re-merges those surfaces into one argv grammar and puts the gate back inside the
program, which is where it was before the split. `resolve` is exposed but is not aimed at
models: in practice `ut-play` is its caller, and what a model sees is `<engine>-search` plus
`ut-play`.

**Why the player must not be able to name its engines.** `ut-play` never reads an engine's
file, sources nothing from it, and holds no list of valid names — an unknown `--engine` is
discovered by the concatenated path not existing. This is the same dependency-direction rule
that put the version in `VERSION`: a one-line data file, because a variable inside any
one of eight independent executables would make the other seven ask *that* file for the version,
and the player asking an engine anything except "resolve this" is the coupling the split
removed.

It sits at the **repo root**, not beside the scripts: it is the version of the suite, not of
`shell/`, and the root is where a reader — and every other project — looks for it. Each entry
point reaches it one level up from its own RESOLVED location, which is why the symlink-chain
walk in front of `SCRIPT_DIR` is load-bearing rather than decorative: `~/bin/ut-play` is a
symlink into the checkout (ROADMAP D1/D2), so a plain `dirname` yields `~/bin`, which holds no
`VERSION` and no engines. `ut-play` was the one entry point that did not do that walk and
answered `--version` with `unknown` through a symlink; it now resolves the way its six
siblings always did. `tests/contract.sh` pins the value to the file **through a real symlink**,
because eight entry points all printing `unknown` agree with each other perfectly.

**Why each verb holds its own gate (D7, inverted).** The old shape was one core plus two
gating wrappers, and the gate was a *layer*. With search and extraction moved out, the player
has one verb left, so there is no bypass left to defend against — and the arms that used to
live in the wrapper are now the arms that produce a good error in the one place a caller
reaches: `-n`/`-m`/`-M`/`-s` in `ut-play` answers "that is a search flag — use yt-search",
`--info`/`--transcript` answers "that is an engine verb", and `--get-url` answers with the
`yt-resolve` call that replaced it. A gate that names the right verb is worth more than a
gate that only says no.

**Self-locating siblings, not PATH lookup.** Invoked as `~/bin/uting`, a script's `$0` is the
SYMLINK, not the code — so each script resolves its own symlink chain first and takes the real
file's directory as the place to look for its siblings. That is the whole mechanism, and it is
why the checkout can live anywhere and needs no `bin/` entry to work.

`cd -P` / `pwd -P`, not the logical forms: a relative symlink resolves to something like
`~/bin/../../../elsewhere/shell`, and a logical `cd` would normalise those `..` textually
against `~/bin` rather than against what `~/bin` actually points at — landing in a
directory that does not exist. bash 3.2 has no `readlink -f`, hence the hand-rolled loop.
(This replaced an earlier `../../shell-scripts/` hop that only worked inside one specific
dotfiles layout; extracting the suite into its own repo is what exposed it.)

Anything that calls these by name through PATH — agent tool definitions, Claude Code Bash
allowlist entries — uses exactly the eight names above. Callers INSIDE the checkout (the suites in
`tests/`, the skills) use the repo-relative `shell/<name>` form instead: they run beside the
code and must not depend on the user's PATH at all — a check that resolved through `~/bin`
would be testing the install, not the suite.

**Governing principle, unchanged by the split — only sharpened:** correctness is added
*down*, in the player if it is about playback and in the engine if it is about a site, so
every surface inherits it; never *up* in a UI. A fix in `uting` that `ut-play` could have
made is a bug in the wrong file.

## 5. Primitives & seams (swap points)

**The seams are split by file now.** No file holds two of these roles, and a yt-dlp call in
`ut-play` or an mpv call in an engine is a layering violation, not a seam.

| Primitive | Role | Who may call it | Seam (the only call sites) |
|---|---|---|---|
| **yt-dlp** | extraction | engines only | `fetch_results` (`yt-search`); `dump_once`, `resolve_info`, `resolve_transcript` (`yt-resolve`); `dump_once`, `resolve_info` (`bili-resolve`) |
| **mpv** | playback | player only | `run_mpv()` (single play seam) + `mpv_supports_vo()` capability probe |
| **curl** | HTTP transport | `bili-search` (its transport); `yt-resolve` (probe only) | `fetch_page_once` (`bili-search`) — the one place in the suite that builds a request by hand; `probe_raw` (`yt-resolve`, the fetchability probe) |
| **nc** | mpv JSON-IPC | player, and `uting` as a client | `live_props` / `do_set_volume` (`ut-play`); the TUI's own client (§11) |
| jq | JSON shaping | everyone | pervasive |

**mpv sits behind one function.** All five `play_*_url` modes route through `run_mpv`, so
swapping it (mpv→vlc) is a nearly localized edit; two mpv-specific details sit outside it by
necessity — `mpv_supports_vo()` asks mpv what terminal VOs it has, and `play_viz_url` passes
mpv's `--lavfi-complex` showwaves filter through `run_mpv`.

**mpv no longer runs yt-dlp** (step B-2). `run_mpv` passes `--no-ytdl` and a direct media URL
the engine already resolved. Before this, the LAST extraction in any playback was one we did
not make, could not classify, and could only influence through `--ytdl-format` /
`--ytdl-raw-options`. Now: **one extraction per play, and we make it** — which is also what
makes the reason enum honest, because the call that can fail is a call we read the stderr of.

**An engine's two halves need not use the same primitive.** `bili-search` talks HTTP through
`curl` while `bili-resolve` shells out to `yt-dlp`; the YouTube pair uses `yt-dlp` for both.
The seam between a half and its caller is the ENVELOPE (AS-BUILT-contract.md §3), not the tool behind it — which
is why the split is by *operation* rather than by site (ROADMAP D11).

**yt-dlp is invoked at the sites in the table rather than one seam** — but it is the
extraction standard every client depends on, so replacing it is not a realistic goal; the
value is that each site is a plain `yt-dlp …` array, not buried in a third-party client, and
that all of them are inside an engine. **jq** is pervasive. The in-list filter uses no
primitive at all (§11).

---

# Part II — Functional structure

## 6. End-to-end control flow

Each verb parses its own argv; nothing execs into anything else. The player's parse is the
largest and is the one shown here — the engines use the same three-stage shape (long-option
normalization → `getopts` → validation) with their own flag sets (AS-BUILT-contract.md §1).

```
   $ ut-play -d -j --engine yt -- "https://youtu.be/ID"
        │
        ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ ut-play                                                          │
   │  (a) long-opt NORMALIZATION loop                                 │
   │      --json→-j  --detach→-d  --list→-l  --help→-h --version→-V   │
   │      --color/--volume/--engine/--id → vars                       │
   │      --status/--stop/--set-volume   → set_action                 │
   │      --get-url / --info / --transcript → die, naming yt-resolve  │
   │      unknown --flag → die, LISTING the play flags                │
   │      `--` → END OF OPTIONS: rest copied verbatim (getopts too)   │
   │  (b) getopts  ":f:S:dljhV"  → MODE, FORMAT_SORT, OUTPUT_MODE     │
   │      unknown -n/-m/-M/-s → die "that is a search flag"           │
   │      unknown -J          → die "that is an engine flag"          │
   │  (c) VALIDATION  --color enum, --volume 0-100, one action only,  │
   │      --id only w/ stop|set-volume, --all only w/ stop,           │
   │      -d not w/ an action, -d not w/ ascii|viz                    │
   │  (d) IS_HANDLE?  non-empty AND contains no whitespace            │
   │      (that is the WHOLE test — see below)                        │
   │  (e) ROUTING (first match wins):                                 │
   │        no handle & no action → die naming yt-search / uting (D3) │
   │        ACTION=status     → do_status      (jq only; exit 0)      │
   │        ACTION=stop       → do_stop        (jq only; exit 0|4)    │
   │        ACTION=set-volume → do_set_volume  (jq+nc;  exit 0|4)     │
   │        require_deps jq mpv        ◄─ NOT yt-dlp; that is the     │
   │        IS_HANDLE:                    engine's dependency         │
   │           DETACH      → detach_play      (background)            │
   │           OUTPUT=json → play_url_json    (structured)            │
   │           else        → play_url_directly (prose)                │
   │        else → die "'<x>' is not a video id or URL — run          │
   │                    'yt-search -- <x>' to search for it"          │
   └──────────────────────────────────────────────────────────────────┘
```

**The player deliberately cannot tell a good handle from a bad one.** `IS_HANDLE` is
"non-empty and contains no whitespace" and nothing more. Id *shape* (`dQw4w9WgXcQ`,
`BV1FPjy6TEiE`) is engine knowledge, and giving it up is the point of the split — so an
unresolvable handle surfaces as a **propagated engine failure (2+)**, not a usage error (1).
What the player still rejects as usage is what is not a handle at all: empty, or containing
whitespace, which is a search query and belongs to another verb.

**Non-interactive by construction (D1/D3).** No verb but `uting` ever prompts. The
no-handle guard runs *before* the mpv dependency check so the message is about the missing
input, not a missing player — and `-V` is answered before any dependency gate at all, because
needing yt-dlp installed to learn which version you have is backwards.

**`--` is honoured by every verb.** The normalization loop stops at `--` and copies
everything after it verbatim (including the `--` itself, so `getopts` stops there too —
verified on bash 3.2). Without this a query that merely LOOKED like a long flag became an
action: `-l -- --status` listed players instead of searching for the text, and a handle
starting with a single dash was eaten by `getopts`. This used to be a guard the wrappers
relied on; it is now each verb's own.

**One action per call.** `set_action` records which flag claimed the call and rejects a
second, different one (`--status --stop` → "conflicting actions"), where the old
last-flag-wins parse silently discarded the first. `--id`/`--all` are rejected outside
`--stop`/`--set-volume`, and `-d` is rejected alongside any action — all three used to be
accepted and ignored.

**Why a normalization loop before getopts:** bash `getopts` only understands single
letters. The loop maps the long options that DO have a short form to it
(`--json`→`-j`, `--detach`→`-d`, `--list`→`-l`, `--help`→`-h`, `--version`→`-V`) and
consumes the no-short-form ones — the actions (`--status`/`--stop`/`--set-volume`, plus
`--id`/`--all`) and the value-carrying `--color`/`--volume`/`--engine` — straight into
globals, so getopts never sees them. There is deliberately no `-c` short flag for color (it
is `--color` only); `-S` (not `-F`) is the format-sort override, and it is forwarded to the
engine verbatim because format-sort is yt-dlp's language, not the player's.

**Why an unknown long flag dies in the loop.** Every long flag is handled there, so an
unmatched one can never be valid — and left to fall through it reached `getopts` as `-`,
which reported the useless "invalid option: --". The arm names the real flags instead: the
half of a gate that helps a caller recover.

### 6.1 Invocation stack — which processes run, and where the extraction happens

§6 answers *"which function handles this argv"*. This answers *"which **processes** get
spawned, and where does the extraction that is actually played happen"*. Since step B-2 the
answer to the second half is short: **in the engine, exactly once, and we read its stderr.**

**A. Search and the read-only verbs — one process**

```
   $ yt-search -j -- "lofi"        $ bili-search -j -- "周杰伦"      $ yt-resolve --info -j -- <url>
         │                               │                                  │
         ▼                               ▼                                  ▼
   ┌────────────────────────┐   ┌────────────────────────┐   ┌────────────────────────┐
   │ yt-search              │   │ bili-search            │   │ yt-resolve             │
   │  fetch_results         │   │  fetch_page_once       │   │  resolve_info          │
   │   └─ yt-dlp            │   │   └─ curl (search/type)│   │   └─ yt-dlp            │
   │      "ytsearch<N>:…"   │   │      + random buvid3   │   │      --dump-single-json│
   │  jq → one-line envelope│   │  jq → one-line envelope│   │  jq → one-line envelope│
   └────────────────────────┘   └────────────────────────┘   └────────────────────────┘
        one process · one primitive call · mpv never starts · the player is not involved
```

`yt-resolve --transcript` has the same shape (one `yt-dlp --skip-download --no-simulate`,
AS-BUILT-contract.md §3). `bili-resolve` has no `--transcript` half at all (D13).

**B. Playback — the player asks an engine, then plays a direct URL**

```
   $ ut-play -j --engine yt -- <handle>
         │
         ▼
   ┌───────────────────────────────────────────────────────────────────────────┐
   │ PROCESS 1 :  ut-play                                                      │
   │    resolve_via_engine:  "$SCRIPT_DIR/$ENGINE-resolve" (else PATH)         │
   │         │               unknown engine → exit 1, naming it                │
   │         ▼                                                                 │
   │  ┌──────────────────────────────────────────────────────────────────┐     │
   │  │ PROCESS 2 :  <engine>-resolve -j -f MODE -- <handle>             │     │
   │  │    host allowlist: not this site's host → exit 1 (ROADMAP D12)   │     │
   │  │    resolve_stream ──► yt-dlp --dump-single-json -f <fmt>   [#1]  │     │
   │  │    (yt only) probe ──► curl 1 byte; on failure re-resolve  [#1'] │     │
   │  │                        anonymously and set retried:true   (§8.2) │     │
   │  │    jq ──► {stream_urls[], http_headers{}, title, duration, …}    │     │
   │  └──────────────────────────────────────────────────────────────────┘     │
   │    reads the envelope; classifies a failure from the engine's `reason`,   │
   │    never by re-reading yt-dlp prose (AS-BUILT-contract.md §3)                                 │
   │         ▼                                                                 │
   │    run_mpv:  mpv --no-ytdl <stream_urls[0]>                               │
   │              [--audio-file=<stream_urls[1]> when the format merged]       │
   │              [--http-header-fields=… from http_headers]                   │
   └───────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼
              PROCESS 3 : mpv — decodes a direct URL. Runs NO extractor.
```

**B′. Detached playback — one more process, and the parent returns in milliseconds**

```
   $ ut-play -d -j --engine yt -- <handle>
         │
         ▼
   PROCESS 1 : ut-play, the RETURNING parent
        detach_play: ensure_state_dir · new_player_id · lock_player_state
             ├── nohup bash "$SELF" -f MODE --engine <name> -- <handle> &
             │      a FRESH ut-play, not mpv directly. set -m + disown, so the
             │      player survives this parent's exit (§9.1); stdin → /dev/null (D11)
             └── emit {status:"started", id, pid, sock, log, title:null} and EXIT
                        │
                        ▼
   PROCESS 2 : ut-play (YT_DETACHED=1, YT_IPC_SOCK=<sock>) → B above, and it
               patches `title` and `format` into its OWN record from the resolve
               envelope, under the lock, while the pid still matches.
```

**The background title updater is gone.** It existed only because the thing being played was
a URL and nobody upstream had the title; the resolve envelope carries `title`, so the child
patches its own record and a whole extra `yt-dlp --print "%(title)s"` per detached play
disappeared with it.

**C. Lifecycle control — no extraction, no new mpv**

```
   $ ut-play --status -j    |    --set-volume 60 --id <id>    |    --stop --all
         │
         ▼
   ┌──────────────────────────────────────────────────────────────────┐
   │ ut-play                                                          │
   │    reap_dead_players → resolve_target                            │
   │    read_player_live → live_props ──► nc -U <sock> ──┐            │
   │    do_stop → stop_group ──► kill the process group  │            │
   │         │                                            ▼           │
   │         └── jq ──► envelope            (the ALREADY-RUNNING mpv) │
   └──────────────────────────────────────────────────────────────────┘
         no yt-dlp · no new mpv · one socket round-trip per player
```

`uting` adds no fourth shape: it runs **A** (`<engine>-search -j`) and **B′**
(`ut-play -d -j --engine`) as child processes, then talks to the player's socket with its own
`nc -U` rather than going back through `ut-play` (§11).

**The extraction sites**

| # | Where | Command | Whose process | What the result is used for |
|---|---|---|---|---|
| 1 | `fetch_results` (`yt-search`) | `yt-dlp ytsearch<N>:…` | engine | the search envelope |
| 2 | `fetch_page_once` (`bili-search`) | `curl` on `search/type` | engine | the search envelope |
| 3 | `resolve_stream` / `dump_once` | `yt-dlp --dump-single-json -f` | engine | **the stream that is played** |
| 4 | `probe_raw` (`yt-resolve`) | `curl` 1 byte, then a 2nd resolve if it failed | engine | picks the client; sets `retried` (§8.2) |
| 5 | `resolve_info` | `yt-dlp --dump-single-json --skip-download` | engine | the `--info` envelope |
| 6 | `resolve_transcript` (`yt-resolve`) | `yt-dlp --skip-download --no-simulate` | engine | caption file → text |

**Three consequences worth stating plainly**

1. **Every extraction is ours now.** The old site #7 — `ytdl_hook.lua` inside mpv — is gone
   with `--no-ytdl`, and with it the asymmetry where the last and most important extraction
   of a play was one we could neither classify nor pass arbitrary argv to. Anything a future
   extractor needs at play time is an engine change, not an mpv flag.
2. **Headers are contract, not luck.** `http_headers` is a required key of the resolve
   envelope and the player puts it on mpv's argv. The old `--get-url` handed out a bare URL
   with no field for headers, so the same video could play correctly and hand a caller a URL
   the CDN refused with 403 — measured on Bilibili, which is why the key is load-bearing
   rather than theoretical (AS-BUILT-contract.md §3).
3. **A detached play runs yt-dlp once, twice at worst** (#3, plus #4′ when the cookie'd
   client fails the probe) — down from four. mpv contributes none.

## 7. Search subsystem — a verb of the ENGINE
Moved → `AS-BUILT-engine.md` §7, with the Bilibili transport at §7.1.

## 8. Playback subsystem

### 8.1 Mode → format → mpv — **the mode is shared, the format table is the engine's**

`-f MODE` is a player flag and travels to the engine unchanged; what a mode MEANS as a
format string is site knowledge, so `format_for_mode()` lives in each `<engine>-resolve`,
never in `ut-play`. The player never sees a format string except as an opaque value it
records in the player file and never reads (AS-BUILT-contract.md §3).

```
  MODE (player flag)   <engine>-resolve: format_for_mode()   ut-play: mpv option set
  ──────────────────   ─────────────────────────────────     ───────────────────────────────
  audio                YT_AUDIO_FORMAT (ba/b)                 --no-video (audio only)
  video                YT_VIDEO_FORMAT (bv*+ba/b)             default VO
  fast                 YT_VIDEO_FORMAT_FAST                   default VO (progressive)
  ascii                YT_VIDEO_FORMAT                        --vo=<YT_ASCII_VO> --profile=sw-fast
  viz                  YT_AUDIO_FORMAT                        --vo=tct + showwaves lavfi filter
                       (-S SORT, when given, is forwarded verbatim as --format-sort)

  run_mpv(mpv_opts…):   # reads the RESOLVED_* globals the engine call filled in
     mpv --no-ytdl
         [--volume=N] [--input-ipc-server=<sock>]            # detached only
         [--http-header-fields-append=K:V …]                 # from http_headers
         [--force-media-title=<title>]                       # from the envelope
         <stream_urls[0]> [--audio-file=<stream_urls[1]>]     # merged formats
         [--no-term-osd-bar --msg-level=all=error]           # detached only: bounded log
```

**`--no-ytdl`, and the three things `ytdl_hook` used to do for free.** mpv is handed a
direct URL and makes no extraction of its own (§6.1). Three jobs the hook did implicitly are
now explicit, each from a field of the resolve envelope: headers (`--http-header-fields-append`,
repeated rather than one comma-joined `--http-header-fields`, because that option is a LIST and
a header value containing a comma would split into two broken headers), the media title
(`--force-media-title`, or the OSD would read a googlevideo path), and the video+audio pair
(`--audio-file`, mpv's native join, where the hook synthesised an EDL).

**Header values land on mpv's argv and are therefore visible in `ps`.** An engine must not
return a credential header (`Cookie`, `Authorization`) in `http_headers`; the YouTube engine
returns only `User-Agent` / `Accept` / `Accept-Language` / `Sec-Fetch-Mode`. This is a
contract on engines, stated once here and once in AS-BUILT-contract.md §3.

**Cookies are no longer an mpv concern at all.** They were passed through
`--ytdl-raw-options` when mpv did the extracting; now the cookie decision belongs entirely to
the engine that makes the yt-dlp call (§8.2), and the player has no cookie code, no
`YT_COOKIE_BROWSER` read, and no way to leak one.

**Terminal-noise quieting & viewport shielding (video and audio modes).** `video`/`fast` render the media
**title** as a video OSD via libass. When the title carries glyphs no font covers (emoji —
pervasive on YouTube), libass emits a per-frame `[osd/libass] fontselect: failed to find
any fallback with glyph …` warning and macOS CoreText emits a `CoreText note: … .LastResort
…` line. Furthermore, mpv's default startup dumps 8–10 lines of metadata (`File tags:`, `Date:`,
`Uploader:`), which pushes `uting`'s menu into scrollback and displaces the progress bar.
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
displacement (`--no-video` + suppressed tags), keeping `uting`'s menu intact while mpv's in-place
status bar (`A: ...`) updates directly below it; `ascii` uses `--really-quiet`.

Three alternatives were tested and rejected: **`--osd-level=0`** kills the noise at the root
but also disables the on-window OSD/OSC (no seek bar/controls in the window);
**`--msg-level=all=error`** silences the noise but over-suppresses the useful status bar
(blank playback); **`OS_ACTIVITY_MODE=disable`** does NOT stop the CoreText notes (emitted
below the `os_log` activity layer). Measured on an emoji-titled video (window VO): 12
`fontselect` + 7 `CoreText` → 0/0, with the status bar and window OSD both intact, and the
`-j` JSON contract verified (single valid line, correct `reason`, exit code propagated).

### 8.2 Login, PO tokens, and the probe-then-play client pick
Moved → `AS-BUILT-engine.md` §8.2 — it was always engine knowledge filed under a
player heading.

### 8.3 Playback output modes & error taxonomy

```
   ut-play -- <handle>       → play_url_directly → prose ("Playing audio: …") [DEFAULT]
   ut-play -j -- <handle>    → play_url_json     → one final JSON line, chatter suppressed
   ut-play -d -- <handle>    → detach_play       → background; JSON/prose "started"
   (resolving a stream URL without playing is `<engine>-resolve -j`, not a player verb —
    §10; the old `--get-url` spelling is retired and answers with that call.)
```

`play_url_json` captures the player's stdout+stderr (suppressing chatter) and emits one
JSON line. `classify_playback_error(text, rc)` maps captured output to the fixed enum —
never raw mpv wording, which is not a contract:

```
   rc == 130 ......................................... stopped_by_user
   text matches yt_reason=<member> ................... that member, VERBATIM
                                                       (the engine already classified it)
   "HTTP Error 403" | 403 | "Forbidden" .............. forbidden
   name-resolution|connection|timeout|429 ............ network
   (anything else — conservative default) ............ unknown
   rc == 0 ........................................... reason = null (status ok)
```

**Two classifiers, one enum, and the player's is the small one.** Since B-2 the wordings that
identify *why an extraction failed* — video unavailable, requested format, sign in to confirm
— are only ever seen by the engine, which classifies them and reports a `reason`. The player
replays that verdict through the `yt_reason=` marker rather than re-deriving it from prose
it would have to guess at; what it classifies itself is only what mpv can fail at with a URL
already in hand: transport, and rc 130. `forbidden` stays reachable on both sides because a
signed media URL can expire or be refused between resolve and open. **No member may be added
by either classifier that AS-BUILT-contract.md §3 does not already list.**

`exit_code` is the real mpv exit status; the process exit code stays truthful (130 is
normalized to 0 — an intentional stop). (Schema → AS-BUILT-contract.md §3.)

## 9. Detached playback lifecycle

### 9.1 Process-group model (why, not a PID tree)

A detached playback is `bash ut-play` with the engine's short-lived
`<engine>-resolve`/`yt-dlp`/`curl` children, then `mpv` — and, on a curl-less machine,
possibly a **second (retry) mpv spawned later**. Two facts break naive process-tree killing:

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
the same tty its launcher reads: under `uting` the two processes raced for every byte, and
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
      YT_IPC_SOCK=mpv-<id>.sock YT_DETACHED=1 YT_PLAYER_ID=<id> \
        nohup bash SELF -f MODE --engine NAME [--volume N] [-S SORT] -- HANDLE \
            </dev/null >mpv-<id>.log 2>&1 &        # pgid == pid ($!); stdin: see below
      set +m ; disown
      players/<id>.json ← {id,pid,url,mode,format:null,started_at,log,sock,title:null,volume}
      rm PLAYERS_DIR/<id>              # drop bare mktemp token; state lives in <id>.json
                                       # title/format are backfilled BY THE CHILD (below)

   ┌─ process group  pgid = 57678  (player <id>) ───────────┐
   │  57678  bash ut-play -f audio --engine yt HANDLE (leader)│
   │    ├─ <engine>-resolve  (yt-dlp + curl, short-lived)     │
   │    └─ 57712  mpv --no-ytdl --input-ipc-server=…sock      │  ← reparents to init
   └──────────────────────────────────────────────────────────┘     but pgid stays

   stop_group(pgid):  kill -TERM pgid (the leader, ALONE — §9.5 fact 2) ; then each 0.2s
                      tick: kill -TERM pgid + kill -INT -pgid ; escalate kill -KILL -pgid
   group_alive(pgid): pgrep -g pgid has ≥1 member
```

**`YT_DETACHED=1` (why the child must know it is detached).** A detached player has no
terminal, so nobody ever reads mpv's status line — but mpv kept writing it into
`mpv-<id>.log`: ~2.4 MB/h measured on a 24/7 stream, i.e. unbounded growth in `$TMPDIR` for
exactly the long-lived players `-d` exists for. The child's `run_mpv` therefore appends
`--no-term-osd-bar --msg-level=all=error` (after the mode options, so they win) and skips
the stderr noise filter. Measured after: 59-byte log, zero growth over 12s, and a real
failure still recorded (`[ytdl_hook] ERROR: …`). `-S` and `--engine` are forwarded to the child like
`--volume` — `-S` used to be silently dropped on the detached path — and the handle is passed
after `--`.

**`title` and `format` are backfilled by the CHILD, not by a background sibling
(`patch_player_meta`).** The parent must return in milliseconds and therefore cannot know
either field; the child learns both from the resolve envelope it was going to fetch anyway,
and patches its own record. It self-guards the way the old updater did: the jq program emits
nothing unless the record's `pid` is still this process, so a `--stop` landing inside the
resolve window wins and is never clobbered. It waits for the record with a bounded poll
(50 × 0.1s) rather than a fixed sleep, because `detach_play` writes `players/<id>.json`
*after* launching the child and a fast resolve can arrive first; the ordinary case costs one
`stat`.

> **What the retired background updater cost, kept because the trap is generic.** It was a
> whole extra `yt-dlp --print "%(title)s"` per detached play, run as a background job — and a
> background job inherits the shell's stdout, so a caller that *captures* our output
> (`out=$(ut-play -d -j …)`, exactly what `uting` does) blocks until every writer closes that
> pipe, not just until we exit. Before its fds were redirected the "instant" detach measured
> **1.67s captured vs 0.04s uncaptured**. The envelope-fed backfill has no background job at
> all, so the trap cannot reappear here — but any future `… &` inside a verb that a caller may
> capture must close its fds.

### 9.2 State machine (multi-player)

```
   Multiple detached players coexist, each its own id/pgid/socket/state/log. A 2nd -d
   is NOT refused — it starts an independent player. Lifecycle verbs pick a target.

        ┌───────────────── (no live players) ◄─────────────────┐
        │              ut-play -d -- HANDLE   (any number of times)│
        │                             ▼                          │
        │                   ┌────────────────────┐               │
        │  --status → list  │ N live players      │ --set-volume N│
        │  players[] ───────│  players/<id>.json  │  [--id ID] ───┤ (live volume via IPC)
        │                   └─────────┬──────────┘               │
        │   --stop --id ID  │ stop that one       │  --stop --all │ stop every player
        │   (1 live ⇒ --id  ▼ (2+ live & no --id  ▼               │
        │    optional)      resolve_target        → {ambiguous,   │
        └──── rm its state/sock/log               players:[...]} exit 4)

   • a player consumes a QUEUE (§9.5): --queue at launch, --enqueue and --next after.
     A lone handle is a queue of one, so `queue` is never null and the state machine
     above is unchanged — one player, one lifecycle, however many tracks it plays.
   • --status ALWAYS exit 0. --stop exits 0 for every case EXCEPT an ambiguous target
     (2+ live players, no --id) which exits 4 — see the next bullet. Idempotent otherwise:
     a polling agent must not read a non-ambiguous non-zero exit as failure. Every
     lifecycle call reaps players whose group is gone.
   • --set-volume / an ambiguous --stop exit 4 (did-not-take-effect; -j reason says why).
   • a player that dies ON ITS OWN leaves a tombstone: --status reports it once in
     failed[] instead of just going empty (see below).
   • state: ${TMPDIR:-/tmp}/uting-$(id -u)/players/<id>.json (+ mpv-<id>.sock, mpv-<id>.log,
            queue-<id>.json) plus players/dead/<id>.json for the tombstones — where a
            queued TRACK that failed is <id>-q<pos>.json, the same shape (§9.5)
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
  shared taxonomy (AS-BUILT-contract.md §3), classified from the tail of the log it was handed as
  `YT_DETACHED_LOG`. Nothing is written when `rc` is 0 or 130.
- **The reaper turns it into a tombstone** (`record_player_death`), read at the one moment
  both the record and the log still exist, and writes `players/dead/<id>.json`.

The bounds are the contract, not politeness — they are what keeps this an **error record** and
not a listening history: **failures only** (a normal finish
writes no epitaph; a `--stop` kills the process group before the child can write one — the
same rule from the other side), **at most 8**, **nothing older than an hour**, and it lives
in the state dir, so it dies with it. No epitaph means no tombstone: a truncated log or a
`kill -9` is reported as silence rather than as an inferred death.

> **This bound survived the scope change and matters more because of it.** Listening history
> used to be a `ROADMAP.md` §0 non-goal, which made "`failed[]` is not history" easy. Since
> ROADMAP D14 it is a FEATURE, and it has landed (§9.6) — so the rule is now a **separation**
> rule rather than an absence one, and both sides of it are real files: history is durable,
> user-level, every track, in `$UT_STATE_DIR`; `failed[]` stays ephemeral, bounded,
> failures-only, in `$TMPDIR`. The two are written at the same instant by the same child and
> are not a duplication. Growing this array into the history feature would have put a
> user-facing record in a directory that is erased on reboot.

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
that does not need this terminal. `uting` validates `-f` against the same list.

**The `-d -j` envelope carries `sock` and `log`.** They are already in the state file, and
without them in the envelope a client had to RECONSTRUCT the socket path from the player's
private state layout — which `uting` did, hardcoding
`$TMPDIR/uting-$(id -u)/mpv-<id>.sock` in a second script that would have broken silently
if the player moved its state dir (§9.3). (Schemas → AS-BUILT-contract.md §3.)

### 9.3 Runtime IPC control (`--set-volume`, `--pause` / `--resume`, `--seek` / `--seek-to`)

`--volume N` sets only mpv's *starting* volume; the five runtime verbs change a running
detached player without a kill+relaunch. They work across **multiple concurrent** players,
each independently addressable, and they share one shape: resolve the target (or exit 4),
one command over that player's socket, then a second round trip that READS BACK the property
the envelope reports (`ipc_command` → `do_set_volume` / `do_playback_verb`;
AS-BUILT-contract.md §3 has the envelopes, §26 the retired criterion that had kept the four
playback verbs out).

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
   LLM caller                    ut-play                              mpv #<id>
      |-- --set-volume 70 --id <id> --->|                                    |
      |                                 |-- resolve_target <id> (reap dead)  |
      |                                 |-- sock = players/<id>.json.sock    |
      |                                 |-- [[ -S sock ]]  (socket-ness)     |
      |                                 |-- {"command":["set_property","volume",70],"request_id":1}
      |                                 |     | nc -U -w1 sock ------------->|
      |                                 |<-- {"request_id":1,"error":"success"} ---|
      |                                 |-- atomic temp+mv patch .volume=70  |
      |<-- {"status":"ok","id":<id>,"volume":70} (exit 0) -------------------|
         one process, not two: the gating wrapper is gone (§4)
```

Per-file state (a directory of `players/<id>.json`) is chosen over one shared JSON
array on purpose: writes stay atomic per-file (the temp-file+`mv` idiom), there is no
read-modify-write race *across* players, and reaping a dead player is just
`rm <id>.json` (+ its `.sock`/`.log`). Socket/log paths derive from the id, so nothing
else stores them. Within a *single* player's file one RMW hazard remains: the child's
metadata backfill (`patch_player_meta`) and a `--set-volume` can both temp+mv-patch the
same `<id>.json` at once, and whichever `mv` lands last silently clobbers the other's
field. A per-id `mkdir` lock (`lock_player_state`/`unlock_player_state` on
`STATE_DIR/lock-<id>`; `mkdir` is atomic on POSIX and needs no `flock` binary, which
stock macOS lacks) serializes those two writers. It bounded-spins ~5s then proceeds
unlocked, so a crashed lock holder can't wedge callers — the same best-effort risk the
patches carried before the lock existed. `patch_player_meta` *additionally* pid-guards
(it patches only while the file's `.pid` still equals its own pid), so a `--stop` during
the resolve window wins and its reap is never clobbered by a late title write.

**The IPC socket is a PUBLIC part of the `-d` contract (and `volume` is read live).**
`uting` drives the per-tick READ (progress + pause) and the held-down volume keys straight
over the socket rather than forking a verb per keypress: its Now-Playing views refresh once
a second and would otherwise pay a process chain per tick. Its pause and seek keys DID move
to the verbs — one call per keypress is affordable where one per tick is not — and §26
carries the measurement that drew the line between the two cases. That is a deliberate
exception to D8, so the socket path is *handed to the client* in the `-d -j` envelope
(`sock`) instead of being reconstructed from the state-dir layout, and this document — not
an implementation detail — is where the JSON-RPC channel is sanctioned. Consequence for
`--status`: the state file's `volume` only knows about launch `--volume` and `--set-volume`,
so a client moving volume over the socket would make it lie. `--status` therefore reports
**live** volume, falling back to the recorded value. It is soft-gated on `nc`, keeping
`--status`'s jq-only dependency (AS-BUILT-contract.md §4). Verified: two `0` presses in `uting` moved a player
launched at `--volume 0` to `10`, and `--status` reported `10` (it used to report `0`
forever).

**Four properties, one round trip (`live_props` / `read_player_live`).** The same argument
covers `pause`, `time-pos` and `duration`, only worse: the state file has never held them at
all, so the socket was the *only* place they existed and only `uting` was reading it. They
are now part of the player record (AS-BUILT-contract.md §3), read by `live_props(sock, prop…)` — which sends the
whole property list down ONE connection and emits `<request_id><US><value>` lines — and
correlated by `read_player_live`, which both `--status` output modes share so the
normalisation exists once. Three rules are load-bearing:

- **Correlate by `request_id`, never by line order** — mpv interleaves async events into
  every client's stream (the same rule `do_set_volume` carries).
- **`head -n <count>` is what closes the pipe** *against a peer that holds the connection
  open*. mpv answers each command exactly once and `jq` has already dropped the id-less
  events, so the last expected line is where `head` exits, SIGPIPEs `nc`, and ends the read.
  **Correction (2026-08-24), recorded rather than quietly dropped:** the **1.11s → 0.03s**
  this line long carried was measured against a *scripted* peer whose idle timer ran the
  `nc -w1` clock out. That peer was deleted with the no-stand-in rule, and against **real
  mpv** the same read costs **0.04s with `head` or with a bare `cat`**. The guard is
  therefore defence against a peer that behaves that way, not a measured win, and
  `tests/playback.sh` deliberately carries **no** check for it — none can go red. A
  measurement is only as durable as the thing it was taken against. The caller breaking its
  own read loop does NOT achieve it either — nothing writes again to notice the reader is gone.
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
`patch_player_meta`, serialized against it by a per-id `mkdir` lock — see below) →
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
never demands it (AS-BUILT-contract.md §4).

**References (mpv IPC).**

- mpv `DOCS/man/ipc.rst` (normative) — `request_id` is the sanctioned reply-correlation
  mechanism; events interleave with replies (why `head -1` alone is wrong).
- mpv `DOCS/man/ao.rst` — default output is shared (concurrent instances mix);
  `--audio-exclusive` defaults to `no`.
- purarue/mpv-sockets, wis/mpvSockets — closest prior art: one IPC socket per instance
  (borrowed the per-instance socket naming + jq extraction).
- lwilletts/mpvc — reference for the `set_volume` command shape; its reply parsing
  (greps `"success"`, no `request_id`) is deliberately **not** copied.

### 9.4 The durable state layer (`ut-playlist`) — and the line between it and `players/`

§9.1–§9.3 describe state that is SUPPOSED to die: a player record lives in
`${TMPDIR:-/tmp}/uting-$(id -u)`, it is reaped when its process group goes, and the whole
directory is erased on reboot. That is correct for a running process and fatal for a list a
user spent six months building. So the first listening feature (ROADMAP P4) begins with a
second, separate store:

```
   $UT_STATE_DIR/                      default ${XDG_STATE_HOME:-~/.local/state}/uting
     playlists/<name>.json             one file per playlist, atomic temp+mv
     playlists/.lock-<name>/           mkdir lock, same primitive as lock_player_state
```

**The record is a call, not a reference.** An item is `{engine, id, url, title, duration,
added_at}` — a subset of a search result with the envelope's `engine` folded in, because
`engine` + `url` are exactly the two arguments of `ut-play --engine E -- URL`. Storing a bare
URL would throw the routing fact away and force some later surface to guess it, which since
ROADMAP D12 is a hard usage error rather than the silent mislabel it used to be. `channel`,
`view_count` and `live_status` are deliberately not stored: playback does not need them and
they expire into wrong answers. Schemas → AS-BUILT-contract.md §3.

**Why a seventh command rather than a flag on something that exists.** The store shares
nothing with the player but the lock primitive, and nothing with an engine at all. Inside
`ut-play` it would give the player cross-playback state and a second kind of file to own;
inside `uting` it would be state written by a renderer — correctness added UP, in a UI,
where only one of the two surfaces inherits it. As its own verb it is one call for an agent
and the same call for the TUI.

**Three differences from the player's lock, all forced by durability.**
`lock_player_state` proceeds unlocked on timeout, because its writes are best-effort field
patches. This one (a) FAILS on timeout — exit 4, `locked` — because an unlocked write here
can drop the track the user just added; (b) STEALS a lock older than a minute, because the
EXIT trap releases it on every normal death including `die`, so a stale dir means a SIGKILL,
and a playlist that can never be written again is worse than a torn write nobody has seen;
(c) is proved by a check that was watched to fail — with the lock stubbed out, eight
concurrent `--add` calls leave ONE item (measured), which is exactly the read-modify-write
race the pattern exists to stop.

**The name IS the filename.** No slug: a slug makes the name on screen and the name on disk
two facts, and then one of them is wrong. The cost is a validator (no `/`, no control
characters, no leading `.`, ≤64 characters) and one accepted limitation — on a
case-insensitive filesystem, macOS's default, `Rock` and `rock` are the same playlist. It is
documented rather than normalised: bash 3.2 has no `${var,,}` and `tr` is wrong on UTF-8, so
any normalisation written here would be a lie for exactly the names most likely to need it.

**What the TUI does and does not do with it.** `uting` gained two keys — `a` adds the focused
row, `b` opens a playlist as the row source — and **stores nothing itself**: both shell out
to `ut-playlist` with JSON, the way `play_selected` shells out to `ut-play`. The item handed
to `--add` is cut from the SEARCH ENVELOPE by url, not rebuilt from the row arrays: the
envelope carries the engine tag and the exact field spellings, so the TUI never learns the
item record — and the row arrays are filtered and re-ordered, so an index into them is not
an index into `.results`.

The row record grew a seventh field, `engine`, and that is what makes a mixed playlist
playable: `play_selected` passes the ROW's engine, where the session engine would send a
Bilibili URL to `yt-resolve`. Because a playlist envelope produces the same seven-field row
a search does, the list view, the filter and the paging are unchanged — the only keys that
had to learn about the new source are the three that RE-FETCH a query (`m`, `o`, `e`), which
a playlist does not have, and `Esc`, which is the way back out of one.

**And `Esc` is what leaves it.** A store REPLACES the rows on screen, so without a back key
the only exits were `n` (retype a query) and `q` — a one-way door, and the same door `h`
opens (§9.6). Everything a store replaces is local state (the envelope, the rows built from
it, the label, the cursor position), so the openers stash it and `Esc` restores it: no
refetch, which would spend a network round trip rebuilding rows still in hand and could
silently hand back a DIFFERENT set of results than the one the user left. The stash is taken
only while the rows are still the search's, so `h` then `b` then `Esc` lands on the search
rather than on the history, and the key is offered in the hints only while a store is on
screen — the rule `e`, `a`/`b` and `h` already follow.

**What is NOT here: the queue.** A queue is a playlist being consumed, and it belongs to the
player, in the player's runtime state. A queue that survives a reboot IS a playlist — that
judgement is what keeps the two stores apart. It is built in §9.5.

### 9.5 The queue — a playlist being consumed (`--queue`, `--enqueue`, `--next`)

A detached player plays a QUEUE. A lone handle is a queue of one, so there is one code path
rather than two: every `-d` launch writes a queue file before it forks, which is what lets
`--enqueue`, `--next` and `--status` address any player without a does-this-one-have-a-queue
branch, and why `--status`'s `queue` key is never `null` on a live player.

```
   ${TMPDIR:-/tmp}/uting-$(id -u)/queue-<id>.json    {schema:1, pos, items:[{engine,url,…}]}
                                  lock-queue-<id>/   its own mkdir lock
```

**Not under `players/`, and that is not a filing preference.** `players/*.json` IS the player-
record namespace: `reap_dead_players` walks the glob, and a `<id>.queue.json` parked there
would be read as a record whose `.id` is empty — and then deleted. The queue sits beside the
socket and the log instead, and `rm_player_files` removes all three (plus both lock dirs) in
ONE function, because three call sites clean up after a player — the reaper and both `--stop`
paths — and a file added to two of them is a leak in the third.

**Why the queue is the PLAYER's, and the two homes that were costed first.** The criterion is
one sentence: **a queue that survives a restart IS a playlist** (§9.4). A queue does not, so it
is runtime state by definition and lives beside the socket and the log rather than in the
durable store. The two rejected models are recorded because both are reasonable enough to be
proposed again:

- **The player reads an EXTERNAL queue file.** Keeps the single-owner invariant over
  `players/` (§9.2) untouched and inherits the agent surface for free — the queue rides in the
  `--status` envelope either way. It fails on ownership: the player would read a file it does
  not own, mid-track, and "who may write it, and when" becomes a rule the suite would have to
  invent and then defend.
- **A seventh command, `ut-queue`.** Matches the suite's usual shape — a capability is a file —
  and the player would not change by a line. It fails on the same invariant from the other
  side: TWO processes would then drive one player, and `players/` having exactly one owner is
  hard here (§9.2). That path has to answer "who reaps, and who writes the state file" before
  it can start, and answering it means moving the lifecycle out of the player.

**Two locks, never nested.** The queue does not share `lock_player_state`: the record and the
queue are updated at rates an order of magnitude apart (one title backfill per track against
one advance per track plus every `--enqueue`), and one lock for both would make each wait on
the other's clock. The hard rule is that no path holds both — take one, write, release, take
the other. One lock can only stall; two can deadlock, and under these bounded spins the
symptom would not even be a hang, it would be two five-second pauses followed by a SILENT
unlocked write.

**JIT resolve, one track at a time.** A stream URL expires in hours, so a queue resolved up
front would 403 halfway down; each item is resolved when it is reached. The price is a gap
between tracks, and it is paid on purpose. Two consequences are contractual (AS-BUILT-contract.md §3):
a resolve failure ADVANCES the queue instead of killing the player — otherwise an upstream's
bad minute is welded to the player's lifetime — and the track that failed gets its own
tombstone in `failed[]`, keyed `<id>-q<pos>`. The advance happens BEFORE the tombstone is
written: when the queue is exhausted it is the PLAYER that died, and that record belongs to
the parent, from the epitaph in the log. Written the other way round, one failure was
recorded twice — measured, as `<id>` and `<id>-q0` for a single bad handle.

**The record follows the track.** `patch_player_meta` patches `url` as well as `title` and
`format`, so a `--status` taken ten minutes in describes what is playing rather than what was
launched.

**Three bash 3.2 facts shape the child loop, and each was measured rather than reasoned.**

1. **A trap is not dispatched while a FOREGROUND child runs.** A `sleep 5` sent SIGUSR1 ran
   its handler five seconds later and still returned 0; `cmd & wait "$!"` entered the handler
   inside a second and `wait` returned 158. So the child runs mpv in the BACKGROUND and
   `wait`s on it — otherwise `--next` would mean "skip a track once this one is over", which
   is not a skip.
2. **An async command cannot trap SIGINT — ONLY WITHOUT JOB CONTROL, which is not this
   child.** The rule as usually stated (bash starts an async command with SIGINT set to
   `SIG_IGN`, and a signal ignored on entry can never be trapped) is what this file believed
   for two revisions, and it is half of the truth: bash applies that `SIG_IGN` only when
   **job control is off**, and `detach_play` launches under `set -m`. Measured on 3.2.57,
   the same child with and without monitor mode: WITH it, `trap … INT` fires and `wait`
   returns 130; WITHOUT it, a group INT does not reach the child at all. So the detached
   child's INT is an ordinary, trappable signal — and an UNtrapped one is a plain kill.

   That distinction was invisible until the child had something to say before dying. Once it
   writes a listening row (§9.6), it showed up as data loss: `--stop` sends the leader a TERM
   and the group an INT back to back, and on 3.2 the second signal takes the process down
   BETWEEN the two handlers, before the first one runs a line. Measured, reproducibly: 0 rows
   out of 2 for a `--stop --all` over two players, while either signal ALONE reached the
   handler every time. Two changes, and both are load-bearing rather than defensive: the child
   traps `TERM INT` (same handler, `stopped` is final either way), and `stop_group`'s FIRST
   tick is TERM alone — the 0.2s before the INT joins it is the child's whole opportunity to
   record what happened. mpv does not need that tick, because the child's own handler kills it.

   The escalation still repeats BOTH signals on every 0.2s tick, because the group is not a
   fixed set: the engine call between two tracks spawns a fresh yt-dlp, then its anonymous
   retry, then curl for the probe, and one that started a millisecond after the first signal
   never saw it. While such a straggler runs the child's own trap cannot run either (fact 1
   again), so a single late process is enough to make a stop wait out the whole escalation.
   Measured after the change: `--stop --all` over three players, 956 ms — the same
   ~0.3s-per-player it was before, with every row written.
3. **Both signals can be pending at once, and the order is not ours to pick.** The engine call
   between two tracks is a foreground command, so a `--next` delivered during it waits, and a
   `--stop` arriving behind it waits too; when the resolve returns bash runs both handlers.
   A `next` allowed to land after a `stopped` restarts the loop on a player that was told to
   die — 3.5s to stop instead of 0.4s, reproduced 3/3. So **`stopped` is final** in
   `child_signal`: once set, no later signal may downgrade it.

**The reason a track ended comes from `CHILD_REASON`, never from mpv's exit code.** mpv 0.41
answers 4 for "quit due to a signal" — one code covering "`--next` killed it", "`--stop`
killed it" and "the user killed it" alike. The handler sets the reason BEFORE it kills mpv, so
the epitaph describes what happened instead of guessing. A sentinel file was considered and
rejected: that is another lock, and it would let the death record lie in a new way.

**The gap between two tracks is a JIT resolve, and it was measured rather than budgeted.**
median **4.3 s**, p90 **5.7 s**, range 3.2–5.8 (n=12) — against a written budget of "about 3
seconds", which is 1.4× off and is why an unmeasured "about 3 seconds" is the next timing
incident. The measurement is defined at the EARS, not in the code: from the last `position`
the old track reports to the first one the new track reports, read off a real player's
`--status`, on a 5-item queue alternating yt and bili, three runs, each track sent to
`duration-3` so it ends by itself (a `--next` is a different path and not what this measures).
**92% of the gap is the engine round trip** (resolve median 3.8 s), so the only place left to
cut is prefetch — nothing else in the loop is big enough to matter. The direction asymmetry is
real and is why a mixed queue is the only honest fixture: **→bili 3.4 s, →yt 5.3 s**, because
`yt-resolve` reads a browser cookie and may spend a PO-token probe and an anonymous retry
where `bili-resolve` needs one yt-dlp call. **Prefetch is therefore NOT in v1**, on the
trigger condition written before the number existed and honoured after: it is paid for only
when p90 passes **8 s**, because resolving track N+1 during track N means a second background
job and a cache that expires (a stream URL dies in hours). The number hangs off live sites;
an upstream change means re-measuring, and the trigger does not move.

**N extractions instead of one.** JIT resolve turns one play into N chances for yt-dlp to be
having a bad minute, and repeated extraction can itself invite throttling. That is the real
price of keeping the queue in the player, and it is absorbed by ADVANCING on a failed track
rather than by retrying — a retry is the gap above, doubled.

**`--next` moves the position in the PARENT, then signals.** The envelope therefore reports a
queue it read off disk rather than one it predicted — the rule `--seek` already follows for
`position` (§9.3). The child's own end-of-track advance is a compare-and-swap against the
position it just played, so if a track ends in the same instant a `--next` lands, whoever
moves first wins and the other is a no-op: nothing is ever skipped twice. The signal is
SIGUSR1 to the child's PID and never to the group — USR1's default disposition is to
terminate, so a group-wide one would kill the mpv the loop is supposed to advance past.

### 9.6 The listening log (`ut-history`) — the second half of the durable store

A playlist is what a person put there. The log is what a player wrote. They share the state
root, the item record and nothing else:

```
   $UT_STATE_DIR/history/<YYYY-MM>.jsonl      append-only, one line per listening
```

**JSONL, and it is the one place in the suite that breaks "one entity, one file".** A
listening is not an entity, it is an EVENT: one file per event is thousands of inodes by
spring. Three consequences follow, and all three are load-bearing:

1. Appending is not a read-modify-write, so this is the **one write in the suite that takes
   no lock** — `>>` opens `O_APPEND` and a single write under `PIPE_BUF` lands whole. A JSON
   array on disk would make every write a race, which is the shape ROADMAP P4 already ruled out.
2. Therefore **every line must stay under 4096 bytes.** That is not a style rule, it is the
   premise of point 1. The title is truncated to 200 bytes on a UTF-8 boundary (the jq
   spelling of what `utf8_complete` does for a keypress — a truncation that can leave a broken
   sequence produces a line that is not JSON, the one thing an append-only log cannot
   recover from), and the finished row is then MEASURED, with the free-text fields dropped in
   order until it fits. A premise checked only on typical input is not a premise, so
   `tests/contract.sh` records an 8 KB title and asserts on the bytes on disk.
3. Sharding by month makes `--clear --before` mostly an `rm`, not a rewrite of the whole log.

**The record point is "a track ended", not "a player died" — and that is the whole design.**
`--stop` takes the process group down, so a row written only on a natural finish would record
just the tracks nobody interrupted: a systematically skewed log, and more misleading than
none, because "what I listen to" would read out as "what I never skipped". The call therefore
sits after EVERY play in the child's loop, before the branch that leaves it, and the reason
comes from `CHILD_REASON` — never from mpv's exit code, which spells a skip and a stop the
same way (§9.5). A clean finish carries no reason at all; a skip and a stop are both
`stopped_by_user`, and `seconds` is what separates a skip at 0:05 from a stop at 3:20. What it
cost to make that true under `--stop` is §9.5's fact 2.

**A track that never opened and never failed is not a listening.** A stop or a skip landing in
the gap between two tracks — the engine round trip — writes nothing; the same gap ending in a
FAILURE does write a row, because "I tried to play this and it would not play" is exactly what
a history is for, and it is the one row whose `seconds` being 0 says something true.

**The player writes, the store stores.** `ut-play` calls `ut-history` BY NAME, the way it
calls an engine, and knows nothing about JSONL or month shards; `ut-history` never plays.
Absent from PATH, nothing is logged and nothing is said — a capability this suite does not
have is declared by not having the command, the rule that also gives `bili-resolve` no
`--transcript`. The write runs inside a subshell that has ignored INT and TERM first, and
`SIG_IGN` survives `exec`, so once it is forked the row lands even if the child that produced
it is killed a millisecond later.

**`UT_HISTORY=0` turns it off, and the default is on** — a history that ships off is not a
history, because nobody finds the knob before the feature has ever produced a row. What it
buys is bounded on purpose: a local file, on this machine, with a `--clear` verb of its own.
The reopen condition is a SHARED account, where "what this login listened to" stops being one
person's record.

**Volume, so nobody adds a rotation nobody needs.** A row is ~200 bytes; 50 tracks a day is
about 300 KB a year. Month shards plus `--clear --before` are the whole size story — there is
no rotation, no compaction and no cap, because at that rate none of them would ever fire.

**The TUI reads it and stores nothing** (`h`, §11). The log's `--ls` envelope is the same
`.items` shape a playlist's `--show` is, so `build_playlist_rows` renders it unchanged and
every key that works on a stored row works here — which is why the view cost one loader, one
predicate (`stored_rows`) and no renderer at all.

## 10. Resolve — the engine's half two
Moved → `AS-BUILT-engine.md` §10 (with §10.1 `--info` and §10.2 `--transcript`).

## 11. `uting` orchestration (owned glue, zero SITE logic)

The diagram is *what*; the bullets after it are the non-obvious *why*.

**Engine discovery, and why this file holds no source list.** At start-up `scan_engines`
globs its own directory for `*-search` and keeps a name only if `<name>-resolve` is
executable beside it — a half-installed engine is not an engine. PATH is scanned only if the
checkout yielded nothing, so the ordinary case costs one glob and a bare checkout runs with
nothing installed. Zero engines is a fatal start-up error naming the pair that is missing.
The session starts on `UT_DEFAULT_ENGINE` — **the same variable `ut-play` reads**, not a
second one, because a user who set a default source once should not set it again per surface
— falling back to the first installed engine when that name is not present. `e` cycles
(`cycle_engine`) and re-fetches, restoring the previous engine if the new one's fetch fails;
with fewer than two engines it returns immediately and the affordance is not drawn.

```
   uting "lofi" -n 40
        │  parse: SEARCH_ARGS=(-n 40) ; PLAY_MODE=audio ; reject cross-flags
        │  discover engines; ENGINE ← --engine | UT_DEFAULT_ENGINE | ENGINES[0]
        │  ENGINE_SEARCH ← engine_search_bin(ENGINE)   # "<name>-search", concatenated
        │  require: jq + verbs; TTY on BOTH -t 0 and -t 1 (reads keys AND draws)
        │  no query on argv → prompt "❯ Search: " via read_query_input
        │  (the prompt says "Search", not "Search YouTube" — the last site-specific
        │   string in the UI went with the engine registry)
        │  (Esc / empty / Ctrl-D on an empty line all cancel, exit 0) — the SAME reader
        │  the `n` prompt uses, so Esc means the same thing at the first prompt as
        │  everywhere else; that is why the prompt sits after the input layer is defined
        ▼
   SEARCH  fetch_json:  json = "$ENGINE_SEARCH" -j -n "$RESULT_N" "${SEARCH_ARGS[@]}" -- "lofi"
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
    ┌─ SELF-RENDERED MENU LOOP (uting draws every line, reads every key; plain ─────┐
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
    │    [ ] seek   ∓10s, ut-play --seek ±N           ↑/↓  volume (card)             │
    │    Enter → play_selected:   ut-play -d -j --engine E -f MODE -- url (NON-BLK) │
    │    Tab/p → toggle view:     List View ◄──► Now Playing card                    │
    │    Space → toggle pause:    ut-play --pause | --resume --id ID (reads back)   │
    │    s     → stop playback:   ut-play --stop --id ID                             │
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

- **PLAY is asynchronous & non-blocking via `ut-play -d -j --engine`.** The engine is taken
  from the search envelope, never left to the player's default (AS-BUILT-contract.md §2). `play_selected` reads
  `id`/`pid`/**`sock`** out of that envelope in one `jq` pass and never rebuilds the socket
  path itself (§9.3). Playback launches in an
  independent, detached process group so `uting` retains full terminal control. Audio
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
    sequences — measured by counting the `ED`s in `tmux pipe-pane`'s stream between two marks,
    since tmux emits its own clear when the pane opens; that check lived in the renderer rig
    and went with it, so this is now a recorded measurement rather than a guarded one). The view-switch `clear` on Tab/Esc went with
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
    player owns its own lifecycle: nothing calls back into `uting` when a track ends or mpv
    crashes, and the IPC layer is deliberately quiet about it (`send_mpv_ipc` swallows every
    failure, `mpv_get_prop` answers empty on a dead socket) so a lost player cannot kill the
    UI. Quiet is not the same as noticed — so `check_player_alive` runs at the top of the main
    loop *and* at the top of `filter_live`'s own key loop (that loop never returns to the main
    loop while `/` is open), and clears the whole `CURRENT_PLAY_*` block through
    `clear_play_state` the moment the player is gone. The test is `kill -0` on the envelope's
    pid, which is the **bash wrapper's**: the wrapper blocks on mpv, so "wrapper alive" is
    exactly "still playing", and this is the same truth the player reaps on (§9.3, process group
    alive) reached from the client side for one builtin and no fork — cheap enough for the
    card's 1 s tick. An **empty** pid means "unknown", not "dead" (`play_selected` requires
    only id and sock), so it leaves the chrome alone. Pid reuse can false-positive it, exactly
    as §25 records for the player's own `group_alive`. The clear is silent: the empty states
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
    erased. And the driver's own echo is off for the whole session — with canonical mode,
    `stty -echo -icanon min 1 time 0`, restored to the `stty -g` state saved on the way in
    through the same trap as the cursor: `read -s` suppresses echo per read only, so between
    reads the driver echoes whatever a burst left queued — on top of the echo this UI already
    draws itself. ICANON goes down with the echo because `-echo` while canonical mode is
    still on is the termios signature of `getpass()`, and terminals act on that pair (§25,
    §28); `min 1 time 0` keeps a raw read blocking on one byte instead of spinning on zero.
    The filter's catch-all had to widen from `?)` (one byte, so never a whole CJK character)
    to `*)`, which is exactly why the two shipped together — and it stops short of escape
    sequences the arrow arms did not claim, or PageUp would type `[5~` into the query.
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
    are 0/1/2/32/34/36 and 1;3x compounds), so by default uting renders in
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
    `ut-play` / `yt-search` / `yt-resolve` / `bili-*` / `uting` — so none of these characters can carry a
    U+FE0F and become a 2-cell emoji glyph behind the table's back. All 17 measured at one
    cell (`tmux display-message -p '#{cursor_x}'`):

    **The closed inventory (D10)** — every glyph the chrome can draw, generated from the
    `GL_*` declarations plus the bar and divider, with the class read off the UCD
    (`unicodedata.east_asian_width`) rather than guessed. A scan of every non-comment line
    finds no other non-ASCII character but the Chinese label text, so the list is complete,
    not curated.

    **One deliberate exception: the brand wordmark (`YT_BRAND=1`).** Both view
    headers render `𝗨 𝗧 𝗜 𝗡 𝗚` (mathematical sans-serif bold, U+1D5D4 block) when
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
    fallback both documented volume and pause, and AS-BUILT-contract.md §1.4 and §18 documented all three, which
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
  - **Seven raw fields per row, US-separated — never a rendered string, and never tab.** The
    details section needs channel, views, liveness and an id per row, so a row stopped being
    one display string. The seventh field is the row's own `engine`, added when a playlist
    became a second row source (§9.4): a stored list can mix sources, so "which engine plays
    this row" is a property of the ROW, not of the session. `IFS=$'\t' read` **collapses runs of tabs** (tab is an IFS
    *whitespace* character), so one empty field silently shifts every field after it — and a
    live row's `duration_fmt` IS empty, which is exactly how a prototype came to read a
    channel name as a view count. ASCII US (0x1f) is not IFS whitespace, so empty fields
    survive; `clean`/`oneline` collapse whitespace in the two free-text fields so no field can
    contain a newline and split one record into two. The video id is derived from the url
    rather than carried as a field of its own. `play_selected` reads the arrays directly, which
    also retired its old habit of re-parsing the composed display string by splitting on
    ` · ` — a title containing that separator mis-split. The same tab trap was latent in the
    `ut-play -d -j` envelope parse (`id`/`pid`/`sock`, all defaulting to `""`, `@tsv`-joined:
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
    pause chrome was the one thing that path got WRONG for free: anything else driving the
    socket (`ut-play`, an agent's own `nc`, a second TUI) left the banner asserting a state
    the player had left. `toggle_pause` no longer guesses either: it calls
    `ut-play --pause`/`--resume` and takes `paused` out of the envelope, so the banner
    repaints from a READING on the keypress. The blind flip survives only as the fallback for
    a call that answered nothing, and the tick's read still corrects that. Optimism, then truth. The card's
    divider rail is built by `repeat_glyph` and cached on `(width, glyph mode)` instead of
    `printf '─%.0s' $(seq 1 "$cols")` — a fork, plus precisely the idiom `repeat_glyph` exists
    to replace, run twice so the Unicode rail could be thrown away in ASCII mode.
    `repeat_glyph` and `render_prog_bar` now return through globals (`GLYPH_RUN`, `PROG_BAR`)
    like the rest of the width layer, so a redraw costs no subshell for them.
  - Pressing `Tab` toggles the two views; pressing `Esc` in the card instantly returns to List View.
- **PROCESS CLEANUP GUARANTEE.** An `EXIT INT TERM HUP` trap ensures any background player
  spawned during the `uting` session is automatically and cleanly stopped upon quit (`q`).
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
- **Three play states, not two.** `-d` returns as soon as the player
  has forked, but mpv still has to resolve the stream through yt-dlp and fill its cache, and on
  a cold URL that is *seconds* (measured: ~9 s on a first-play lofi mix). The banner claimed
  `▶ Playing` for the whole silent window. There is now a `Starting` state between launched and
  audible, carrying the fetch spinner's quadrant frames so the wait looks like the wait that
  preceded it. Four things make it work:
  - **`core-idle`, not `time-pos`.** mpv answers IPC long before it plays a note. `core-idle` is
    true while the player is producing nothing — loading, seeking, waiting on cache — and flips
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

**Moved:** the whole contract surface — command specifications, the gating model, the JSON
data contracts, the exit-code table and the configuration surface — now lives in
`docs/AS-BUILT-contract.md`, the frozen surface of ROADMAP D3/D13. The section numbers
below are kept as tombstones so old citations still resolve.

## 12. Command specifications
Moved → `AS-BUILT-contract.md` §1.

## 13. Gating model
Moved → `AS-BUILT-contract.md` §2.

## 14. Data contracts (JSON schemas)
Moved → `AS-BUILT-contract.md` §3.

## 15. Exit codes, TTY, dependencies
Moved → `AS-BUILT-contract.md` §4.

## 16. Configuration surface
Moved → `AS-BUILT-contract.md` §5.

## 17. Function map & provenance

```
   Player (shell/ut-play) — no yt-dlp, no site knowledge
     Setup/util : usage, die, is_non_negative_int, validate_enum,
                  require_cmd/require_deps, mpv_supports_vo, normalize_playback_mode,
                  set_action
     Engine call: engine_resolve_bin (name → executable, by concatenation),
                  resolve_media (run <engine>-resolve -j, fill the RESOLVED_* globals),
                  patch_player_meta (child backfills title/format into its own record)
     Playback   : run_mpv (the single mpv seam), play_{audio,video,fast,ascii,viz}_url,
                  play_mode_url, play_url_directly, play_url_json,
                  classify_playback_error (mpv wordings + the engine's yt_reason marker),
                  emit_play_json (the ONE writer of the playback envelope)
     Lifecycle  : group_alive, stop_group, ensure_state_dir, live_props (multi-property
                  IPC read), read_player_live (correlate + normalise, shared by both
                  --status modes), detached_epitaph (the child's last log line),
                  record_player_death / prune_dead_players / collect_failed_players
                  (tombstones, §9.2),
                  player_state/player_sock/player_log/player_lock_dir,
                  lock_player_state/unlock_player_state, new_player_id, detach_play,
                  reap_dead_players, resolve_target, do_status, do_stop, do_set_volume,
                  do_playback_verb (the four socket verbs, one shape), rm_player_files
                  (sock+log+queue+both locks, the ONE cleanup, §9.5)
     Queue      : player_queue/queue_lock_dir, lock_queue_state/unlock_queue_state (the
                  SECOND lock, never nested with the first, §9.5), read_queue_items
                  (stdin → items, the three shapes, all rejections are usage errors),
                  queue_write_new/queue_append/queue_bump (the parent's writers),
                  queue_advance_from (the child's compare-and-swap), queue_current,
                  queue_snapshot ({pos,len,next} for every envelope that reports one),
                  queue_note_failure (a TRACK's tombstone, <id>-q<pos>),
                  child_signal + detached_child_loop (the child: one player, one queue),
                  do_enqueue, do_next
     History    : history_bin (find ut-history by name, once, or answer "not installed"),
                  history_record (one row per track, after EVERY play, inside a subshell
                  that has ignored INT/TERM — §9.6). The player's only knowledge of the
                  log is the row shape; the file is ut-history's.

   Store, the log (shell/ut-history)
     Verbs      : do_ls (newest first across month shards, reading only as many as -n
                  needs; one unreadable line is counted and skipped, never fatal),
                  do_record (the row is CONSTRUCTED field by field, so a caller's stray
                  key cannot reach disk; then measured against LINE_MAX), do_clear
                  (whole shards by rm, only the boundary shard rewritten)
     Shape      : JQ_TRUNC (truncate to a BYTE budget on a UTF-8 boundary), line_bytes,
                  count_rows, collect_history_files (shards newest first — YYYY-MM sorts
                  lexicographically exactly as it sorts chronologically, which is the whole
                  reason the shard is named that way), ensure_store

   Engine, search half (shell/yt-search · shell/bili-search)
     Shared shape: die, is_non_negative_int, validate_enum, require_cmd/require_deps,
                  cleanup_scratch/ensure_scratch, fetch_results, print_list,
                  emit_search_json, print_usage, reject_url, JQ_PRELUDE (fmt_dur — each
                  engine's own copy of the one duration formatter)
     yt-search  : classify_yt_dlp_error
     bili-search: classify_http_error, search_fail, ensure_buvid (locally generated
                  random cookie — a correctness requirement, not an optimisation, AS-BUILT-contract.md §1),
                  fetch_page_once (the ONLY hand-built HTTP request in the suite),
                  fetch_page

   Engine, resolve half (shell/yt-resolve · shell/bili-resolve)
     Shared shape: die, validate_enum, require_cmd/require_deps,
                  cleanup_scratch/ensure_scratch, normalize_playback_mode,
                  format_for_mode (the mode→format table), url_host, is_own_host,
                  normalize_target (handle grammar + host allowlist, ROADMAP D12),
                  dump_once, emit_stream, resolve_fail, resolve_stream, resolve_info,
                  classify_yt_dlp_error, print_usage
     yt-resolve only : have_probe_tools, probe_raw (the PO-token probe, §8.2),
                  resolve_transcript / transcript_fail (§10.2)
     bili-resolve    : no transcript half at all — the capability rule (D13)

   Store (shell/ut-playlist) — no site knowledge, no playback, jq only
     Setup/util : die, require_cmd, validate_enum, now_utc, print_usage, set_action,
                  fail (the state-error envelope: not_found | exists | invalid_name |
                  invalid_input | locked | corrupt — its OWN enum, §9.4), JQ_PRELUDE (fmt_dur)
     Store      : playlist_file/playlist_lock, ensure_store, validate_name,
                  read_playlist (the ONE reader: parse guard + schema gate, so jq's exit
                  code can never become this command's),
                  lock_playlist/release_lock (fails on timeout, steals a stale dir; holds a
                  SET, because --rename locks source AND destination in a fixed order),
                  write_playlist (temp+mv), read_items (stdin → the item record; returns
                  through a GLOBAL because a command substitution would swallow its
                  error envelope in a subshell)
     Verbs      : do_ls, do_show, do_add, do_rm, do_del (idempotent), do_rename

   Interactive  : uting   (fetch_json → build_all_rows → load_rows → menu loop:
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
     Input      : read_nav_input/read_esc_tail (the ESC-[/O decoder, split out so the
                  PENDING_ESC re-entry is not a second copy of it)/read_query_input,
                  utf8_complete + init_lead_tables
                  (one key per CHARACTER), tty_echo_off/tty_echo_restore,
                  cursor_hide/cursor_show
     Queue      : enqueue_selected (`+`), skip_next (`>`), focused_payload (the focused
                  row as a one-item envelope — ONE builder, because ut-playlist --add and
                  ut-play --enqueue read exactly the same two shapes), apply_player_record
                  / refresh_player_record (the track can change with no keypress here, so
                  media-title rides the round trip fetch_play_times already makes and only
                  a CHANGE costs an ut-play --status, §26)
     Player     : play_verb (the WRITE side: one keypress, one ut-play verb),
                  send_mpv_ipc, mpv_get_prop, fetch_play_times (one connection for
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
     Engines    : scan_engines / engine_seen / engine_search_bin (discovery by pair,
                  §11), cycle_engine (the `e` key: switch source and re-fetch)
     Stores     : build_playlist_rows (a stored envelope → the same seven-field row a
                  search builds; a playlist's --show and the log's --ls are one shape, so
                  one builder serves both), add_to_playlist (`a`), browse_playlists /
                  open_playlist (`b`), open_history (`h`, no prompt — the log is one
                  thing), stash_search / back_to_search (`Esc`: a store replaces the
                  rows, and what it replaced is local state, so going back is restoring
                  it rather than re-searching), stored_rows (the predicate search_only is the other half of:
                  "these rows came from a store", the three-site test that would otherwise
                  be three drifting copies), prompt_name (the `n` prompt's reader, reused),
                  have_store / have_history / store_notice — all of them shelling out to
                  ut-playlist or ut-history, storing nothing here (§9.4, §9.6)
```

**The repetition across the four engine files is deliberate, not drift.** `die`,
`require_deps`, `fmt_dur`, `ensure_scratch` and the envelope emitters appear once per
engine. A shared library would be a seventh file that every engine — and therefore,
transitively, the player looking for an engine — would have to know about; the split's whole
claim is that an engine is a self-contained pair you can drop in. What must NOT diverge is
the ENVELOPE, and that is pinned by AS-BUILT-contract.md §3 and by `tests/contract.sh` running the same
assertions against both engines, rather than by shared code.

Not every helper is listed — `print_usage`, `die`, `is_uint` and the other one-line guards
are omitted on purpose. Every *subsystem* is, which is the point of the map: a function this
file discusses by behaviour should be findable by name from here.

**Provenance.** The suite descends from an all-in-one `yt-search-n-play.sh`: its
non-interactive core became `shell/yt` behind two gating verbs, then split again into the
player and the engine pairs this document describes; its self-rendered TUI (menu chrome,
`display_menu`, `read_nav_input`, `read_query_input`, arrow-key paging, blocking-play
semantics) was re-homed in what is now `uting` — same menu, now delegating to the verbs. Little of that original's *playback* behaviour survives: play is detached now, so
"no `clear` before play" and "no stdin flush after playback" describe a foreground mpv the
TUI no longer runs, and rows are measured and elided rather than left to wrap. What did
survive is the menu's shape and its key map; the `/` filter, the two-view toggle and the
whole width layer are net-new.

---

# Part IV — Supported workflows

## 18. Human — interactive browse & play

```
   $ uting "lofi hip hop" -n 40 [-f video] [-p 15] [--theme nord] [--engine bili]
     → self-rendered menu (§11), TWO views toggled with Tab/p:
       List  : ↑/↓ nav · ←/→ page · Enter play (DETACHED, non-blocking — the menu keeps
               its terminal and the music keeps playing across n / m / o / filter) ·
               / filter (live narrow) · n new search · m more results · o sort ·
               v cycle mode (audio→video→fast, applies to the next Enter) ·
               e switch source and re-fetch (only drawn when 2+ engines are installed)
       Card  : ←/→ seek ∓5s · ↑/↓ volume · Esc back to the list
       Both  : Space pause/resume · s stop · 9/0 volume · [ ] seek ∓10s ·
               l chrome language (en↔zh) · t palette family · q quit (reaps its player)
```

## 19. Agent — search, then play

```
   # 1) Search → structured, token-frugal envelope; pick programmatically.
   #    Take the ENGINE from the same envelope — never assume it.
   env=$(yt-search -j -n 10 -- "lofi")
   url=$(jq -r '.results[0].url'  <<<"$env")
   eng=$(jq -r '.engine'          <<<"$env")
   # 2) Play (blocking prose), or capture a machine-readable outcome:
   ut-play --engine "$eng" -- "$url"                       # prose
   ut-play -j --engine "$eng" -- "$url" | jq -r .reason    # → null on ok; enum on failure
```

Another source is the same three lines with `bili-search`; nothing else changes, which is
what the `engine` field is for (AS-BUILT-contract.md §3). Getting it wrong is loud rather than silent: a
Bilibili URL sent to `yt-resolve` exits 1 saying so (§10).

## 20. Agent — compose without playing (resolve)

```
   # Resolve a direct stream URL and hand it to another tool (non-blocking).
   # This is an ENGINE verb — the player has no resolve-only spelling (§10).
   yt-resolve -- "$url"                                  # prose: stream URL(s)
   yt-resolve -j -- "$url" | jq -r '.stream_urls[0]'     # structured
   yt-resolve -j -- "$url" | jq -r '.http_headers | to_entries[] | "\(.key): \(.value)"'
```

**Take the headers with the URL.** A bare stream URL is not enough on a host that checks
`Referer` or pins a `User-Agent` — measured: Bilibili's CDN answers 403 to the URL alone and
206 to the same URL with these headers. The old `--get-url` had no field for them, which is
the hole this envelope closes (AS-BUILT-contract.md §3).

```
   # Read-only metadata and captions are engine verbs too:
   yt-resolve --info -j -- "$url" | jq -r '.chapters[]?.title'
   yt-resolve --transcript -j -- "$url" | jq -r .text     # ready to drop into a prompt
```

## 21. Agent — background playback with lifecycle control

```
   ut-play -d --engine yt -- "$u1"        # detach player 1 (returns immediately, ~0.03s)
   ut-play -d --engine bili -- "$u2"      # a SECOND engine's player, side by side
   ut-play -j --status                    # {"status":"players","players":[{id,…},{id,…}]} (exit 0)
   id=$(ut-play -j --status | jq -r '.players[0].id')
   ut-play -j --set-volume 70 --id "$id"  # live volume on player 1 → {"status":"ok",id,volume:70}
   ut-play --stop --id "$id"              # stop just player 1 (idempotent)
   ut-play --stop --all                   # stop every player; leaves zero orphans
```

`players/` has exactly one owner, so `--status` and `--stop --all` see every player
regardless of which engine started it — the player is the only thing that ever writes there
(§9.2).

Why this shape: a blocking-only player isn't composable for an agent. `<engine>-resolve`
(resolve without playing), `-d`+`--status`/`--stop`/`--set-volume` (background + poll + live
control), and `-j` (structured outcome) are the escapes from "returns only when the video
ends," and `--status` (always) and `--stop` (except an ambiguous target, which is
exit 4) exit 0 so a polling loop never misreads a normal state as failure.

---

# Part V — Aligned best practice

## 22. 2026 agentic-tooling scorecard

| Dimension | Rationale | Status |
|---|---|---|
| Discoverability | `--help` is ground truth for a caller with no tribal knowledge | ✅ per-verb narrow help; each one names the OTHER verbs a caller may have wanted |
| Structured output | parse without string-matching prose | ✅ search (`-j`/`-J`) + playback (`-j`) |
| Token efficiency | high-signal beats complete | ✅ 8-field `-j` (~4× smaller); `-J` opt-in; `--transcript -j` drops the duplicated `segments` (3.1×) |
| Exit-code contract | success/failure must be detectable | ✅ `cmd \|\| rc=$?`; 130 normalized |
| Trust boundary | agent strings never hit a shell interpolation point | ✅ query/URL single argv elements; `--` guard |
| Refuse-don't-hang | never block on absent stdin | ✅ every verb but `uting` is non-interactive; `uting` requires a TTY |
| Contract stability | changes fail loud, not silently | ✅ invalid enum + cross-flag rejection |
| Process lifecycle | background / query / stop long playback | ✅ `-d`/`--status`/`--stop`, group-stop |
| Composability | playback that only blocks isn't composable | ✅ `<engine>-resolve` (stream URL **+ headers**), `-d` + lifecycle |
| Error taxonomy | branch on a cause, not raw wording | ✅ fixed `reason` enum |
| Config surface | per-request in flags; set-once as env | ✅ flags per-call; env for tuning |
| Ownership | no client lock-in; both surfaces portable | ✅ owned player + engines + glue; primitives behind seams |
| Entry-point shape | separate verbs beat one mode-flagged command | ✅ eight narrow verbs, no dispatcher, no wrapper tier |
| Extensibility | a new capability must not edit the caller | ✅ a new source = one engine PAIR; player and TUI unchanged (proved by step C) |

## 23. Clean / Safe / Modular / DRY adherence

```
   Clean   : each command is single-purpose; no menu state machine in the agent path;
             the player carries no `if site ==` anywhere.
   Safe    : exit-code contracts preserved across two restructures; TTY guards;
             interactive path never absent during change (§24); destructive edits
             grep-gated.
   Modular : eight peers, one layer, one explicit dependency graph; each primitive behind
             a single seam, and the seams split by file (§5).
   DRY     : the rule is one fact one PLACE, which is not the same as one COPY.
             Playback and lifecycle exist once (the player). One site's knowledge exists
             once (its engine pair). Boilerplate — die, require_deps, fmt_dur — is
             duplicated per engine ON PURPOSE (§17): a shared library would be a file
             every engine, and transitively the player, would have to know about, which
             is exactly the coupling the split removed. The ENVELOPE is what must not
             diverge, and AS-BUILT-contract.md §3 plus a check stated over every DISCOVERED engine is what
             holds it — engine #3 is covered the day it lands.
```

## 24. Safe-evolution methodology (how this suite is changed)

The refactor that produced this architecture followed a staged, reversible order — a
reusable template for future structural change:

```
   A  Build the new path against the CURRENT tools; validate it in a tmux pty.
      → an interactive path is never absent.
   B  Repoint callers / wrappers / symlinks; run the headless regression.
   C  Delete the old path — the destructive step, kept LAST and small; grep-gate every
      removed symbol before deleting it; regress again.
   D  Update docs (this file, README, usage()).
   E  Final headed (tmux) + headless sweep.
```

Principle: put the single destructive step last and smallest; prove its replacement
first; gate deletions by grep so no dangling reference survives.

**Used twice, and the second time is the evidence it works.** The player/engine split
(ROADMAP D9) ran A → E over six steps with the destructive one late and alone: rename the
core (A), lift search out non-breakingly (B-1), lift extraction out and retire `ytdl_hook`
in the one coupled step (B-2), **delete the `yt-play` wrapper** (B-3), add a second engine to
prove the seam (C), then the TUI's registry and rename (D). Two properties made it
reversible: every step but B-3 left the old path working, and the second engine was added
*after* the seam existed, so "a new source changes nothing else" was a test rather than a
hope.

## 25. Risk register (design mitigations)

```
   Risk                                    Mitigation
   ──────────────────────────────────────  ─────────────────────────────────────────
   Dangling ref after TUI deletion          grep-gate every removed symbol first
   Title with tab/newline breaks the row    jq @tsv escapes; IFS=$'\t' split in load_rows
   URL mis-recovery from a rendered line     url/display kept in parallel arrays (index pick)
   Filter over-matches / injects a glob      pure-bash: nocasematch + AND tokens + quoted "$tok"
   URL pasted as a search query               <engine>-search rejects URLs → no blocking mis-play (D8)
   uting run without a TTY (agent/pipe)      require -t 0 && -t 1 → die (no hang)
   A rename breaks sibling location          every script resolves its own symlink chain
                                             (§4); step B repoints before step C deletes
   yt-dlp prefix "ytsearch<N>:" clobbered    literal in yt-search only; never rewritten
   One engine's URL sent to another's        explicit host allowlist per engine → exit 1,
   resolver (silently mislabelled engine)    never a resolved stream (§10, ROADMAP D12)
   A new source needs edits in the player    it cannot: the player finds a resolver by
   or the TUI                                concatenating the engine name (§4), and the
                                             TUI discovers pairs by glob (§11)
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
   Captured -d stdout blocks on a bg job     no background job remains on the detach path:
                                             the child backfills its own record from the
                                             resolve envelope (§9.1). Any FUTURE `… &`
                                             in a capturable verb must redirect its fds —
                                             a command substitution waits for every writer
                                             of the pipe, not just for us
   Detached mpv status line fills the disk   YT_DETACHED → --no-term-osd-bar
                                             --msg-level=all=error in the child (§9.1)
   Search failure hands an agent no shape    captured stderr → classify_yt_dlp_error /
                                             classify_http_error → {status:"error",…,reason}
                                             envelope, exit 2+ (§7)
   Query that looks like a flag becomes an   `--` ends option parsing in EVERY verb, and
   action                                    each re-applies its positional check after
                                             it (§6, AS-BUILT-contract.md §2)
   An engine invents a new reason value      the enum is AS-BUILT-contract.md §3's and is closed; three
                                             classifiers implement it, none may extend it
   Client moves volume behind --status'      --status reads volume live off the socket,
   back                                      recorded value only as fallback (§9.3)
   Concurrent meta-backfill + set-volume   per-id mkdir lock (lock_player_state)
   clobber the same <id>.json              serializes the two temp+mv patches; the
                                           backfill additionally pid-guards (§9.3)
   A credential header reaches mpv's argv  engines must not put Cookie/Authorization in
   (visible in ps)                         http_headers; stated in §8.1 and AS-BUILT-contract.md §3
   Stale socket after SIGKILL'd mpv          [[ -S sock ]] test → ipc_failed, never hangs
   nc waits full -w1 if the peer does not  request_id filter + head -1; a HEALTHY mpv
   close (a wedged mpv, not a healthy one)   closes on half-close, so a call is ~0.016s.
                                             uting's redraw path is a tight loop, so it does
                                             not WAIT for nc at all: it reads the replies out
                                             of a process substitution and breaks on the last
                                             one, which bounds the wedged case too (§25.1 F19)
```

### 25.1 Open defect register — TUI hardening pass

Audited against `shell/uting`. **Batch 1 (the one-line edits), batch A (the cheap
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
was very nearly built on it:** the reason cannot come from the envelope's `reason`. The AS-BUILT-contract.md §3
taxonomy belongs to the *blocking* play path; for a synchronous `-d` failure the player `die`s
with prose on **stderr** and emits nothing on stdout (verified: `ut-play -d -j -f ascii --
<url>` → rc 1, empty stdout). uting captures that stderr, the way `fetch_json` already does
for search.

Audited clear in the same pass: every other case-arm function returns 0 on all paths
(`move_selection`, `cycle_mode`, `cycle_sort`, `new_search`, `more_results`, `filter_live`,
`stop_current_playback`, `apply_filter`); `mpv_get_prop` ends in `|| true` and is only ever
used in command substitution.

**Call-stack boundary — uting reaching past a seam it already has.** Empty: this category is
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
player's own `group_alive` — narrowed by the monotonic id, not closed, and not worth a second
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
  command of `adjust_volume` (and was of `toggle_pause`/`seek_relative` before those moved to
  `ut-play`'s verbs; `play_verb` carries the same rule), and fire-and-forget was already
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
- **F16** — `-m`, `-M` and `--volume` are validated at startup in the verbs' own wording,
  including the search half's `-M > -m` cross-check. They were forwarded verbatim, so the verb did
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
  `--volume 10`, then twenty `0` presses, reads **volume 100** in `ut-play --status` — the old
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
  pre-existing gap it folds in was found: `stop_current_playback` had never cleared one of the
  fields the poll path did, so "cleared" had two definitions and one of them was wrong. A tmux pane
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
- **F2b** — a failed Enter now says why. `play_selected` keeps the player's stderr in a temp file
  the way `fetch_json` keeps the search's, and reports its **last line** with the player's own
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
  `-f ascii` through the detached path and watch the player refuse. F16 (batch A) validates `-f`
  against `MODE_CYCLE` at startup, so `ascii` now dies in argument parsing and never reaches
  `play_selected`: one shipped fix closed the door the next one wanted to test through. The
  reason path is observable only from a stub, so the rig carries fixture stand-ins for
  the engine verbs in a directory behind a `uting` symlink — `SCRIPT_DIR` resolves the siblings, which is
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
  (a two-path rig asserts the restore after `q` AND after a signal, because a uting that
  exits without putting `echo` back leaves the user typing blind in their shell).
- **Echo off was only half of it, and the other half read as a password prompt.** Reported as
  "a lock icon on the spin glyph" — and it was never a glyph we drew: a tmux capture of that
  frame holds `▖` and nothing else. A terminal cannot see an application, only the pty's two
  switches, and it polls them: echo off while canonical mode is still ON is what `getpass()`
  looks like, so Ghostty flipped macOS Secure Input on that heuristic
  (`macos-auto-secure-input`) and iTerm2 drew a padlock at the cursor. `bash`'s `read -rsn1`
  clears ICANON for the duration of its own read and puts it back, so the only moments uting
  did NOT look like a password prompt were the moments a key was being read: every gap between
  keystrokes advertised one, and so did the whole length of a fetch, where no read is running
  at all. The padlock landed on the spinner because the spinner parks the cursor on its own
  glyph (`printf '%s\b'`, so each frame overwrites in place) and the cursor is where the
  indicator is drawn. **Not merely cosmetic on Ghostty** — Secure Input really engaged for the
  length of every search, taking the keyboard from every other app on the machine. What the
  code does now is stated once, in §11; the trap for anyone writing terminal code here is in
  §28; the check that keeps it fixed is in §27. The lesson worth carrying: this UI had been
  reasoning about what it *draws*, and the terminal was reading what it *sets* — a UI owning a
  tty owns every flag on it, not only the one it meant to change.
- **A harness lesson, recorded because it produced a false failure first.** The signal-path test
  reported the tty left at `-echo` when nothing was wrong: the harness blocked in `sleep`, a
  CHILD process, and bash defers a trap until the current command finishes. The TUI blocks in
  `read`, a builtin a signal interrupts, so the harness had to block the same way to be
  measuring the same thing. Same family as the batch-B probe that never closed its connection:
  a harness that differs from the program in one detail measures that detail.
- The other rig lesson: `wait_for "Navigation"` is not proof that the filter was left, because
  the menu is drawn *during* filtering too — and sending the next key too early let
  `read_nav_input`'s ESC continuation read swallow it as the sequence's second byte. Wait for
  the filter's own prompt to go. **That swallow was a defect in the app, and this is where it
  sat written down as a property of the rig** — the reader keeps the early byte now (the
  view-transition pass below); the wait is still the right rig discipline, because what a
  frame shows and what the reader has consumed are two different clocks.
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
  and the `lsof` evidence. Worth recording that the keys had been in **AS-BUILT-contract.md §1.4 and §18 all
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

**Closed by the view-transition pass — every edge between the views walked, not just the one
that was reported** (`bash -n` clean, `contract.sh` green, each fix driven under tmux):

- **The store was a one-way door.** `b` and `h` REPLACE the rows, and no key put them back:
  `m`/`o`/`e` correctly refuse (there is no query to re-fetch), `Esc` was a documented no-op
  in the list, and the only exits were `n` (retype a query) and `q`. Fixed in §9.4 — the
  openers stash what they are about to overwrite and `Esc` restores it. **Reported by a user,
  not by a check**, which is the finding under the finding: every existing TUI check drove a
  key and asserted the app survived it, and survival is exactly what a one-way door does.
  `contract.sh` now asserts the ROUND TRIP, both halves.
- **The filter loop did half the main loop's per-frame work.** `filter_live` is a second key
  loop over the same screen and it called `check_player_alive` but not `player_check_ready`,
  so for the whole time `/` was open the starting-state spinner neither advanced nor resolved
  — press Enter, then `/`, and a dead spinner frame sat there past its own 20 s cap. Any
  future per-frame duty has to be added to both loops or to neither; they are not one loop.
- **`apply_filter` read six names from a seven-field row.** The record grew `engine` when a
  playlist became a row source (§9.4), and this reader was not widened. `read` gives the last
  name the remainder, so `live` arrived as `is_live<US>yt`, the `is_live` test could never be
  true, and typing `live` in the filter had matched nothing since. What hid it for that long
  is worth recording: the loop re-emits the fields it just split, so pasting that trailing
  variable back produced a **byte-identical row** — every row survived the filter intact and
  only the synthesized haystack was wrong, which is a corruption with no visible corruption.
- **Esc swallowed the key typed after it**, in every view. A lone Esc is only known to be lone
  once the byte behind it has been read, and the reader dropped that byte — so any key inside
  Esc's one-second window vanished (measured both ways: `Esc` then `o` left `sort=relevance`;
  `Esc` then Right left the page on 1). Worse for a key whose first byte is another `\x1b`:
  the introducer was eaten and the REST of the arrow arrived as literal keys, and `[` is the
  seek key — so `Esc` then an arrow did not merely lose the arrow, it seeked. The reader now
  keeps what it read too early, in the two shapes that byte can take: a whole key
  (`PENDING_KEY`, UTF-8-completed at stash time because the continuation bytes are still
  queued) or a position in the parse (`PENDING_ESC`). Found while confirming the fix above —
  Esc was a no-op in the list until it became the way out of a store, so this had never been
  a key anyone pressed there. A one-second window is the price of ESC being both a key and
  every arrow's introducer; what is fixed is losing the NEXT key, not the window. **It had
  been written down for years — as a rig lesson** (§27, "sending the next key too early"):
  the harness was taught to wait around the behaviour instead of the behaviour being read as
  a bug, which is how a defect hides inside a test-writing convention.

## 26. Non-goals / known constraints

- Detached `ascii`/`viz` (no terminal to render into) — rejected at parse time (§9.2);
  `audio` is the norm and `video`/`fast` open their own GUI window.
- Blocking playback (`ut-play -- <handle>` / `-j`) returns only when playback ends; use
  `--detach`+`--status`/`--stop`, or `<engine>-resolve`, for non-blocking agent flows.
- **Scope note (ROADMAP D14/D15): all three listening features have landed**, in the shell
  version, in the order they depended on each other — playlist management (§9.4,
  AS-BUILT-contract.md §1.5), the queue (§9.5, §1.1), the listening log (§9.6, §1.6). Each
  arrived with its agent verb and its `-j` envelope in the same commit as its keybinding,
  which is the constraint they all inherited: a feature with a keybinding and no verb is
  half-built.
  Favourites is deliberately not a feature (a playlist with a fixed name); a downloader and
  channel subscriptions are unscheduled.
- **Queue EDITING — reorder, dequeue, repeat, shuffle — is deliberately not v1.** Those are
  operations on a queue; the first version had to prove a queue ADVANCES, which is the part
  everything else rests on. Adding them is adding verbs to `ut-play` (each with its `-j`
  envelope, D14), not a new command — a queue belongs to the player (§9.5).
- `uting` rows are one jq pass over the cached results per search — fine for small N;
  not intended for thousands of results.
- **URL sniffing in the player** — `ut-play` never guesses which engine a bare URL belongs
  to; the caller says (`--engine`), and `uting` always knows because it did the search.
  Deferred until a third engine makes a pattern registry worth its weight (AS-BUILT-contract.md §1.1).
- **A shared engine library** — deliberately not built; the duplication is the price of an
  engine being a self-contained pair (§23).
- No MCP wrapper (§1). No third-party media-client dependency (§2).
- **Runtime control of a DETACHED player is a set of verbs** (`--set-volume N`,
  `--pause`, `--resume`, `--seek ±N`, `--seek-to N`, each `[--id ID]` —
  §9.2/AS-BUILT-contract.md §1.1/§3): each detached mpv runs with
  `--input-ipc-server=mpv-<id>.sock`, and one command goes over that per-instance socket
  (`ipc_command`, shared by all five). `nc -U` is gated lazily so a bare search never pays
  for it (AS-BUILT-contract.md §4). `--volume N` remains the launch-time STARTING volume.
  The four playback verbs arrived after `--set-volume`, and **the criterion that had blocked
  them — "a verb is added only when a caller genuinely cannot speak to the socket" — is
  retired.** Four things retired it, written down here because a rule that sounds this
  reasonable gets re-proposed:
    1. **`--set-volume` was already a counter-example.** Volume and pause are equally
       reachable over the socket — the criterion applied to both, word for word — and volume
       had been a verb since before the rule was written. A rule that cannot explain the
       surface already shipped is not a rule; the real trade had always been "the TUI needs
       it, so it exists".
    2. **The queue would have overturned it a second time.** `--next [--id ID]` has exactly
       the same shape: a mutation on a running player, over the same socket, ambiguity → 4.
       Once `--next` ships, refusing `--pause` is arbitrary.
    3. **The cost runs the other way.** Opening the frozen surface is a deliberate, documented
       act (ROADMAP D3). All five at once opens it ONCE; two batches open it twice.
    4. **The code already existed, in the wrong file.** `uting`'s `toggle_pause` /
       `seek_relative` had been driving the IPC directly for months, so this moved logic DOWN
       and net-DELETED TUI code — the governing principle rather than an addition to the
       player.
  What belongs here is what the code IS:
    - The two constraints this section wrote down in advance shipped verbatim: `--seek`
      takes a SIGNED value and absolute is a distinct spelling (`--seek-to N`); there is no
      `--toggle-pause`, because mpv's `cycle pause` returns no value and the envelope could
      only guess the resulting state. `uting` decides the target and sends one of the two
      idempotent verbs.
    - Every envelope reports the property **read back off the socket**, never the value
      asked for (`do_playback_verb`) — mpv clamps a seek at the ends of the file, so those
      two numbers differ exactly when a caller most needs the truth.
    - **What did NOT move, and the number that decided it.** `uting`'s per-tick READ
      (`fetch_play_times`, four properties on one connection) stays on the socket: a process
      chain per 1 s tick is a real cost, and that half of the old criterion was always
      right. So do the `9`/`0` volume keys, which get held down — measured on a live player,
      10 presses each: **10 ms a press over the socket against 60 ms through
      `ut-play --set-volume`**, which also resolves the target and patches the state file
      under a lock. That is over the 50 ms line set for this choice, so the keys stayed and
      the exception is recorded with its number rather than left as an unexplained
      inconsistency. Pause and seek are one call per keypress, not one per tick, so they pay
      it happily — and the TUI net-LOST IPC write code, which is the point: playback
      correctness now lives in the player, where every caller inherits it.
  Deliberately still OUT of scope:
    - Live volume for FOREGROUND playback — it has a real TTY, so mpv's own volume keys
      already work; no IPC needed. (`uting` is no longer foreground: it plays detached
      and adjusts volume over the socket, which `--status` then reports live.)
    - Linux `nc -U` portability — macOS-primary tool; BSD `nc -U` is stock, GNU netcat
      variants differ (`ncat -U` works; `netcat-traditional` has no Unix-socket support).
      Accepted as a known gap, noted in a script comment rather than solved now.

## 27. Verification matrix

**Last run — a measurement, filled in from the run, not a constant kept in sync.** Each suite
prints its own count on the last line, which is that number's one home; the entry here records
what a particular run on a particular day cost, and goes stale by design rather than by drift.
*2026-08-25, both suites green*: `contract.sh` **178 ok / 0 failed in 94s** — 177 until the
TUI-leak check below joined it, and 81–109s across five runs that evening, which is the
network — and `playback.sh` **42 ok / 0 failed in 68s** (and 68s / 65s / 67s on three
consecutive runs before it, because the queue's track-end claim rests on a race), with `pgrep
mpv` empty afterwards. `contract.sh` now runs its **offline half first**: measured on that
run, the flag gates are red at 1s, the idle lifecycle at 1s, the death record at 2s, and the
last offline section finishes at 22s before any network call is made — 19 of those 22 being
the playlist store's own deliberate 5s lock spin and eight concurrent writers. The order is
stated as a contract in the file, since part of it is load-bearing (offline first; the
death-record fixtures and then the TUI section last, because the pane's `uting` polls
`--status` and every lifecycle verb reaps). All THREE entry points under `tests/` point
`TMPDIR` at a directory of their own — the two suites and the `drive.sh` driver, which was the
last one still using the user's — so none reaches the state dir of a player the user is
listening to. The suites point `UT_STATE_DIR` at one too: a detached player writes a listening
row per track (§9.6), so without it every run would append a dozen tracks nobody listened to
to the user's real history, which unlike a player is not something `--stop` takes back.
`drive.sh` deliberately leaves `UT_STATE_DIR` alone — a frame captured from it should show the
store a human sees — and passes `UT_HISTORY=0` into the pane instead, which suppresses the
write without emptying the read.

**Functional only, and two files.** The renderer rig (`tui_pane.sh`) and its cell-grid prover
were removed: layout is proved when a frame enters a doc (`.claude/skills/capture-pane`, which
still carries `assert_pane.py`), and the suite asserts *survival* instead — the TUI boots,
holds through two resizes, and leaves on `q` with 0. `playback.sh` lost its banner-tick case
for the same reason and no longer needs tmux at all. What that trade gives up is named
plainly: a CJK title that wraps, a rail that stops being right-flush, or a repaint that clears
the screen will not be caught by a test — only by the next doc capture. **One timing claim goes
with them, and is named here because nothing else names it:** that a detached player flips the
TUI's card from *Starting* to *Playing* on its own 1 s tick, with no keypress. That needed a
pty; `playback.sh` deliberately has no terminal, `contract.sh`'s TUI section deliberately
starts no player, and `drive.sh -k Enter -w Playing` waits for the banner without asserting on
it. So it is proved nowhere today, and the honest entry is that sentence rather than a check
somewhere that half-covers it.

**Two checks were written, watched, and pulled — recorded here because the register is where a
coverage decision belongs, and because a pulled check that leaves no trace gets re-added.**
Both failed the same test: *it could not be made to go red.*

- **The `head -n <count>` pipe close in `live_props` (§9.3).** Against the real peer it cannot
  fail. Swapping the `head` for a `cat` and re-running measures **0.04 s either way**, so a
  timing assertion on it would pass whatever the code does. The 1.11 s the guard once appeared
  to save was a *scripted peer's* idle timer, and that peer is gone with every other stand-in.
  The guard stays in the player as defence, without a green tick pretending the suite proved it.
- **That a stopped queue files no tombstone.** Disabling the child's `stopped` arm outright
  *still* produced an empty `failed[]`, so the check was green against broken code. The claim
  lives where it can fail instead: `contract.sh` drives the tombstone boundaries from fixtures
  (a normal finish writes none, a log with no epitaph writes none), which is where a rule about
  what the REAPER records belongs.

`tests/playback.sh` carries a one-line pointer at each of the two sites, so the next reader
finds the reasoning without the file carrying it twice.

> **Observed flakiness — the shared-state one is CLOSED, and this is the record of it.** On
> 2026-08-23 ten checks failed on the first of three runs and the next two passed 78/78
> unchanged; on 2026-08-24 the same cluster went red twice while an ordinary interactive
> `uting` was open in another window, then passed 3/3 minutes later with nothing changed. The
> mechanism was sharper than "two overlapping runs": the death-record fixtures lived under
> `${TMPDIR}/uting-$(id -u)/players`, keyed by uid and nothing else, and **every lifecycle verb
> reaps** — so one `ut-play --status` from anywhere, a TUI's liveness poll included, deleted a
> tombstone fixture between its creation and the assertion that read it. The durable fix was
> the per-run state dir, and every entry point under `tests/` now builds it: each exports a
> `TMPDIR` of its own, so no other uting on the uid shares the directory. What survives is the
> ordering rule the same mechanism still implies inside a single run — the death-record
> section must precede the TUI section, since the pane's own `--status` poll reaps — and that
> is written at the section itself rather than left to layout.
>
> **A third, observed TWICE and still NOT located — recorded because an unrecorded flake is a
> flake nobody can recognise the second time.** On 2026-08-25, in the first of two
> back-to-back runs, the TUI section's last two checks went red together — *"quits on q with
> 0"* and *"hands the tty back on exit"* — and the second run passed 177/177 unchanged. The
> pair failing TOGETHER is the signal: the FLAGS line the second check reads is printed by
> the same pane command that prints `RC=`, so neither appeared, which means `uting` had not
> left within the 10 s the poll allows. It was not a slow quit: measured afterwards, seven
> runs (three plain, four driving the section's exact boot → 62x20 → 26x24 → `q` sequence),
> **every quit landed in 186–250 ms**, i.e. the budget is fifty times the cost. Two in-app
> mechanisms that could swallow a keypress were looked for and ruled out: the OSC 11
> background query is skipped when `$TMUX` is set (§11), so no terminal reply can be sitting
> in the reader, and `q` is not a UTF-8 lead byte, so `utf8_complete` cannot absorb it. What
> is left is the machine: a second session was working in this checkout that afternoon and
> had run the same suite, and whether the two overlapped was not captured. Filed as
> unlocated, with the measurement, rather than explained.
>
> **It happened again the same evening — same two checks, again the first of two runs, the
> second clean — and this time it left something behind.** Seven minutes after the run,
> `ut-play --engine yt -f audio --` on a URL off the pane's own result list was still
> running, parented to PID 1, its mpv on a socket under that run's own `uting-contract.*` directory.
> Nothing in the section presses Enter, so the pane received input the suite did not send:
> the cause is still unlocated. What the recurrence did settle is that the reading above —
> another session on the machine — is the weaker one, because that evening there was none;
> the day's other work had landed seven hours earlier.
>
> The player explains the CONSEQUENCE, and that half is now fixed. `uting` stops its playback
> from `cleanup_on_exit` (EXIT INT TERM HUP), so a TUI that leaves takes its player with it,
> and a TUI that does **not** leave is a TUI still holding one — the two reds and a live
> player are one event, not two. `contract.sh`'s cleanup was `rm -rf` and nothing else, so
> the state dir went and the player's RECORD went with it: the process outlived
> `--stop --all`'s ability to find it, and nothing short of `kill` could stop the audio — in
> a file whose own docstring says it does not touch your state. Three changes, each proved by
> breaking it (a run that presses Enter and then never presses `q`):
>
> - the cleanup **reaps before it removes**, and reports an orphan mpv scoped to the run's own
>   socket dir — the order `playback.sh`'s cleanup already used;
> - a check, *"the TUI left no player behind"*, so a leak is **visible** and not merely
>   harmless. It is red only in this exact situation, which is what makes it worth a line;
> - the pane is **dumped** when `q` is not honoured. The frame is the only witness to which
>   reader ate the byte and it dies with the session; in the sabotage run the dump carries
>   `▶ Playing:` on its third line, which is precisely the fact the first occurrence had no
>   way to record. The next occurrence will say what this one had to be reconstructed from.
>
> **The fourth is CLOSED too, and it is the one worth reading twice, because a red check
> turned another one off.** On 2026-08-25 `playback.sh` ran 34s/35 ok/1 failed and then
> 41s/36 ok/0 failed, same machine, no code change; the red one was *"no duration on the queued
> player"*. Not shared state — a **live field read exactly once**: after `--next` the poll
> waited for the recorded `url` to flip, which the parent does the moment it advances the
> queue, while `duration` comes off the socket, where the new mpv may not have reported one
> yet. The cost was never the one red. It sat on a `case` whose other arm proves *a track
> ending advances the queue* — the single claim a queue exists for — so a race in the setup
> silently withdrew the check, and the score fell by one while the coverage fell by two. **The
> mirror image of the rule this suite lives by:** not a green nobody has seen fail, but a red
> nobody noticed had switched something off. Fixed by the bounded poll the field always
> needed (`wait_live <id> <field>`, shared with the two `position` waits), and the failure
> message now says *never reported a duration in 40s* rather than *no duration*, because those
> are different findings. Confirmed by sabotage — `wait_live` returning failure at once turns
> all three of its sites red, C4's among them — and then by three consecutive clean runs at
> 42 ok, since a race check run once proves nothing.

**Four things this suite deliberately does not have, recorded so each is refused on purpose
rather than re-proposed.** None is a gap; each is a decision with a reason:

- **No `tests/lib.sh`.** That the two suites are independent and each runs alone is the design,
  not an accident, and CLAUDE.md's "no rig layer" governs it directly. What is duplicated is
  about twenty lines of `report`/`ok`/`bad` bookkeeping, which is acceptable; a duplicated
  *argument* is not, which is why the `TMPDIR` reasoning is stated once and pointed at twice.
- **No `tests/all.sh`.** Two commands, and CLAUDE.md already says when each is run: `contract.sh`
  before every commit, `playback.sh` when the player changed.
- **No "skip the network" environment switch.** Set-once tuning is what an environment variable
  is for, and this would instead create a second meaning for green — *which* green did you get?
  Running the offline half first buys the same fast feedback with zero new concepts.
- **No check that exists to raise the count**, and no timing or rendered-picture assertion. The
  hardening pass this register describes added a net **zero** checks to the two suites: it made
  existing ones honest, deleted three duplications, and fixed one race.

**No *scratch* check is named by path here, on purpose.** The exception is the three files
that earned a permanent home and are committed under `tests/` — the two suites `contract.sh`
and `playback.sh`, and the TUI driver `drive.sh` (which asserts nothing and exists to reap the
detached player a session kill leaves behind) — which
the root README describes by name because a contributor cannot run what nothing points at. (Two pty-based rigs and then a tmux renderer rig preceded today's
shape: a pty starting at 0×0 produced plausible-looking one-row frames — a wrong green — and
tmux fixed that, but asserting on the picture at all is what finally went.) Everything else this suite has been
verified with is a throwaway under a `tmp/` the repo does not track (`.gitignore`:
`**/tmp/`), so citing one of those by path is a promise the checkout cannot keep — it resolves on exactly one machine, until that
machine's scratch directory is cleaned. What is durable is the *shape* of each check, and that
is what the entries below record: what was driven, how it was observed, and the count of
assertions that survived. A check is cheap to rebuild from its description and expensive to trust
when the file it names is gone; §25.1's harness lessons are here for the same reason — they are
the part of a deleted harness worth keeping.

```
   Syntax     : bash -n on every script in shell/ (+ repo-wide shell check), gated by
                .githooks/pre-commit on staged content and pre-push on the worktree
   Engine seam: an unknown --engine is USAGE (1), not a tool failure — an agent must not
                retry a name that will never exist; `--engine ../evil` is rejected too;
                a well-formed id that resolves to nothing is 2+ WITH a reason, which is
                the semantic the split bought by moving the shape check into the engine
   Engine      : the two engines' envelopes are compared KEY SET AGAINST KEY SET — search,
   parity       result records, and resolve — so a field renamed, added or dropped in
                EITHER engine fails, including one added years from now and forgotten on
                the other side. Nothing else in the suite would notice: each engine's own
                checks would still pass and playback would break only for the engine
                nobody happened to run. bili-search additionally: names its engine,
                one line, duration is a NUMBER (the site sends "222:28"), titles carry
                no surviving <em> markup or entities
   Search     : <engine>-search -j → 8-field envelope + count; -J → full; default list;
                flag-after-query ordering; empty-query error; zero-result query →
                count:0; a live entry renders "LIVE"/"n/a views" (never a raw null);
                -m 999999 excludes unknown-duration (live) entries; yt-dlp failure →
                {status:"error",…,reason:"network"} under -j, exit 2 (prose: stderr + die)
   Argv       : `yt-search -- --status` SEARCHES for that text (does not list players) —
                the check lives on the search verb because that is where searching lives
                now; --status --stop → conflicting actions; --status --id X → rejected;
                -d --stop → rejected; -d -f ascii|viz → rejected
   Player     : ut-play (no args) → D3 error; ut-play "a query" and ut-play -- "a query"
                → 1, naming yt-search; invalid --color rejected
   Gating     : one tier, eight self-gating verbs (AS-BUILT-contract.md §2). <engine>-search rejects
                -f/--detach/URL (URL rejection re-applied after `--`); ut-play rejects
                -n/-s/bare-query. Three checks exist specifically to prove the deleted
                wrapper took its gate WITH it rather than dropping it: an unknown long
                flag (`--json-full`) exits 1 instead of reaching getopts as a bare `-`,
                `--get-url` exits 1 as retired, and `--info` exits 1 naming the engine
   Envelopes  : every -j/-J payload is ONE line (AS-BUILT-contract.md §3) — search -j/-J, a zero-result search,
                --info -j/-J, --get-url -j, -d -j, --status with 0 AND with 2 players,
                --stop, an ambiguous --set-volume — measured with `| wc -l`, and each still
                parses with the same fields (jq -e on .query/.count/.results[0], .status)
   Resolve    : <engine>-resolve (prose + -j envelope, no playback); the envelope carries
                stream_urls[] and http_headers{}, and playback.sh proves the headers are
                load-bearing: a detached bili player reaches position 1s, which the bare
                URL cannot do (403 without them)
   Host gate  : a URL from the other site is rejected by each resolver with exit 1 —
                usage, not extraction failure (§10, ROADMAP D12)
   Transcript : yt-resolve --transcript → one line of clean text on stdout, ZERO bytes on
                stderr; -j → single-line {status,id,url,lang,is_auto,text,segments} with
                is_auto:false on a human-captioned video and 60 cues recovered; -J → the
                SAME envelope + segments, asserted a strict superset (del(.segments) is
                byte-equal to -j) — 17,074 vs 52,732 bytes on a 444-cue track;
                --sub-lang on a language
                the video does not carry → {status:"error",reason:"no_subtitles_available"}
                exit 1 under -j and a die() sentence in prose mode — note yt-dlp exits 0
                for an absent language, so the miss is detected by NO FILE WRITTEN, never
                by the exit status; --transcript with a playback flag is rejected by the
                engine's own gate; --transcript --info → conflicting actions; a bad --sub-lang is
                refused in 0.016s (before any network round trip); the temp caption dir
                under the 0700 state dir is gone afterwards on every path
                Parser: driven offline against a saved human track and a saved auto track
                — 60 and 52 cues, zero residual tags, newlines or empty cues in either,
                and the auto track's rollup duplicates absent from the output
   Playback   : ut-play -j -- <bad-id> → {status:error, reason:unavailable, retried:false}
                — the reason is the ENGINE's verdict, replayed (§8.3), not re-derived
   Lifecycle  : -d ×2 → --status lists BOTH players → --set-volume --id (only that
                player changes) → ambiguous --set-volume w/o --id (exit 4) →
                --stop --id one → --stop --all → --status(empty); assert ZERO orphan
                mpv after stop; players/ holds only <id>.json (no bare token leak)
                Detach latency: `out=$(ut-play -d -j -- URL)` returns in ~0.03s (no
                background job may hold the captured pipe) and --status shows the
                title a few seconds later; -d -j envelope carries sock+log
                Two engines at once: a yt player and a bili player run side by side and
                --stop --all clears both — one owner for players/ (§9.2)
                Detached log: mpv-<id>.log stays ~59 bytes with ZERO growth while
                playing, and still records a real ytdl_hook ERROR
                IPC window : --set-volume --id on a JUST-launched player answers
                {status:"error",reason:"ipc_failed"} with exit 4 until mpv is actually
                listening — measured at t=3s vs exit 0 from t=6s on a cold URL. That is the
                taxonomy working (4 = did not take effect), not a defect; a rig that sets a
                property inside the start-up window reads it as a false red
   Store      : the playlist verbs driven under a disposable UT_STATE_DIR (the knob exists
                so the suite cannot write into a user's real playlists). A search envelope
                keeps its engine tag through the store; a bare array keeps its OWN engine,
                so one list holds both sources; duration_fmt is derived on read and null
                when duration is; --show on a missing name is 4 + not_found (never an
                empty list, which would be indistinguishable from an empty playlist);
                --del on a missing name is idempotent 0 with deleted:false; --rename onto
                an occupied name is 4 + exists; an unreadable file is 4 + corrupt on --show
                but merely SKIPPED by --ls (one bad file must not hide the store), and a
                schema newer than this build is 4 + corrupt; a name with `/` is refused;
                --index without --rm is 1 on every verb including --ls; a playback flag and
                a positional after `--` are both 1
                naming the right verb; bad stdin is 1 AND emits the error envelope under
                -j. Concurrency is DRIVEN, not argued: eight concurrent --add calls all
                survive (with lock_playlist stubbed out the same loop leaves ONE item —
                watched, so the check is known to be able to fail), a held lock is 4 with
                reason locked rather than an unlocked write, and a lock older than a
                minute is stolen
   History    : the LOG's own contract in contract.sh, from fixtures and under a disposable
                UT_STATE_DIR (32 checks): an empty log is ok/count 0; a recorded row comes
                back out of --ls; both _fmt fields are derived on read; a key the caller
                carried in (`channel`) never lands on disk; --ls is newest first and one
                line; -n bounds it; the envelope drops straight into ut-playlist --add,
                which is the claim the row shape exists for. The 4096-byte premise is
                driven rather than argued: an 8 KB title is recorded, reports truncated,
                still parses back, and NO line in the shard reaches 4096 bytes — watched
                red with the truncation removed. One hand-broken line and one row from a
                newer schema are both skipped without hiding the rest; --clear --before
                takes the older shard and leaves the current one; --clear on an empty log
                is idempotent 0. The gate: two actions, no action, -n on --clear, --before
                on --ls, a playback flag, a playlist verb, a positional after `--`, and
                --record without `-` are each 1, and bad stdin is 1 with the error
                envelope under -j. Each validated field has its own check — a bad engine
                name, a url with whitespace, a malformed played_at, a reason off the
                playback enum
                The WIRING in playback.sh, where a real track really ends (6 checks): a
                19-second handle is played to its end and the log is POLLED for its row —
                that row exists, carries no reason (the claim that separates a history from
                a death record), and holds the engine's own title and a played length near
                the length of the thing. An interrupted track is in there too, from the
                players every section above stopped, so the log is not a record of what
                went uninterrupted. Every row is a CALL (an engine NAME and a
                whitespace-free handle, asserted as grammar so a third engine passes it
                unedited) and both engines this run drove are present under one shape.
                UT_HISTORY=0 then plays one more real player and writes nothing — counted
                by url, since this file leaves players stopping in the background. Watched
                red with the child's history_record call removed
   Live volume: uting 9/0 on a --volume 0 player → --status reports the
                moved value (not the stale launch value); from 98, three 0 presses stop
                at 100 and never reach mpv's own 130 ceiling
   Queue      : the idle half in contract.sh, where no player exists and no socket is
                opened (17 checks): --next and --enqueue answer not_playing and exit 4, the
                SAME shape the socket verbs use, while a payload this process cannot use is
                1 — driven through --enqueue rather than --queue on purpose, because a
                --queue that got past its gate would LAUNCH a player and that file starts
                none. The 1-vs-4 pairing is the point: bad JSON, none of the three stdin
                shapes, an empty list, a url with whitespace, an empty url and an engine
                name that is not [a-z0-9_-] are all 1; a well-formed payload with nothing
                running is 4. Both --show and search envelopes parse (the engine tag lives
                on the envelope, so only the whole thing can label an item); a shapeless
                object does not. --queue without -d, with a handle on argv, or with an
                action is 1, each naming what to do instead
                The live half in playback.sh, against a real player and a real engine
                (10 checks): --queue - launches and --status carries {pos,len,next} before
                mpv has decoded a frame; --enqueue appends and reports the queue it wrote;
                six CONCURRENT --enqueue calls all land (3+6=9, and fewer with
                lock_queue_state stubbed to fail); --next moves the position and the
                player's own record follows the track; a track reaching its END advances
                the queue on its own (seek to duration-4 rather than waiting out a stream);
                --stop takes the whole queue down and leaves no orphan mpv. A mock engine
                would skip the JIT resolve — the thing most likely to break between two
                tracks — so nothing here stands in for either end
   Playback   : the idle half in contract.sh, where no player exists: all four verbs answer
   verbs        not_playing and exit 4 (the --set-volume shape, reused rather than re-argued),
                `--seek 30` without a sign is 1 while `--seek +30` with nothing playing is 4
                — the pair is what proves "malformed" and "did not take effect" were not
                collapsed into one code — `--seek -15` is a VALUE and not an unknown flag,
                and --id parses on every one of them
                The live half in playback.sh, against real mpv: --pause reads back
                paused:true and --status agrees, --resume the reverse, --seek +30 moves the
                playhead forward and --seek-to 0 brings it back to the START — in that
                ORDER, because a --seek-to that secretly seeks relative passes the reverse
                order (a relative 0 near the start also lands near the start; found by
                breaking it that way). The seeks run while PAUSED so no assertion races the
                decoder, and each is anchored to the position BEFORE it so a verb that does
                nothing cannot ride on wherever mpv happened to be. All six seen red first
   TUI wiring : uting's Space / [ / ] now call the verbs (§26), driven in tmux against a real
                detached player: paused flips true then false in --status, `]` moved 3s→13s
                and `[` came back to 3s. Held-down keys did NOT move — 10 ms a press over
                the socket vs 60 ms through the verb, measured, §26 carries the number
   Live read  : the four properties in ONE round trip (§9.3), driven against REAL mpv over
                its own socket and nothing else — the scripted peer this entry used to cite
                was deleted with the no-stand-in rule, and the shapes only it could produce
                on cue (replies out of order, a property answered null, async events
                interleaved) are coverage this suite now does WITHOUT rather than fake.
                What a real player proves, in playback.sh: position and duration arrive as
                numbers off the socket rather than off the record, a playing player answers
                paused:false and not null, and a really-running player whose socket is
                really removed reports paused/position/duration null with volume falling
                back to the record (proved red by leaving the socket in place). NOT checked,
                and deliberately: the `head -n <count>` pipe close — against real mpv the
                read costs 0.04s with head or with a bare cat, so a timing check on it
                cannot fail (§9.3 carries the correction). Also measured: with `nc` off
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
   uting      : HISTORICAL RECORD, NOT A GUARDED CHECK. Everything under this heading was
                proved by the renderer rig that has since been removed (functional-only
                suite — CLAUDE.md); the suite now asserts only that the TUI boots, survives
                two resizes, never leaves the tty in the getpass pair (sampled from inside
                the boot wait, which IS the fetch — the one stretch with no read running),
                exits 0 on `q` and hands the tty back with echo and ICANON on, both read
                out of a pane that outlives it. These entries are kept because they record
                that the layout WAS correct, measured, at a point in time — but a regression
                in any of them today is caught by the next `capture-pane` proof, not by a
                test. Re-proving one means driving it by hand through that skill.
                (tmux PTY) Enter → background play + banner; Tab → card (live
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
                a launch that fails prints the player's own last stderr line and waits on
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

**Every script in `shell/` must run under bash 3.2** (macOS's frozen system `/bin/bash`, which
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
                            cmd ${arr[@]+"${arr[@]}"}                  (inline, as in uting)
   Arithmetic + set -e:   a bare ((expr)) is a COMMAND, and its exit status is 1 when
                          the expression evaluates to 0. Under set -e that aborts the
                          script. So never write ((x = 1 - x)) or ((n += w)) as a
                          statement — use x=$((1 - x)) / n=$((n + w)). ((x)) as a TEST
                          (in `if`, `&&`, `||`) is fine: there the status is the point.
   read -rsn1 = one BYTE: not one character, on 3.2. A CJK character typed at a prompt
                          arrives as 2-3 separate "keys" (verified: 你 → e4 bd a0), so
                          any reader that accumulates keypresses into text has to
                          reassemble the UTF-8 sequence from its lead byte (uting's
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
                          for the whole session — see the next rule for the flags — and
                          restore it from the same trap that restores the cursor.
   -echo needs -icanon:   echo off with canonical mode still ON is the termios signature of
                          getpass(), and terminals act on the pair, not on the program:
                          Ghostty flips macOS Secure Input on that heuristic
                          (macos-auto-secure-input), iTerm2 draws a padlock at the cursor. A
                          full-screen app is -echo -icanon, which is why vi is never flagged.
                          read -rsn1 clears ICANON for its own duration only, so owning the
                          echo for a session and leaving ICANON alone looks like a password
                          prompt in every gap between keys and for the whole of any blocking
                          call (§25). Take both down together — stty -echo -icanon min 1
                          time 0 — and restore the stty -g state saved on the way in rather
                          than re-asserting defaults over a tty the caller set up itself.
   ${var//pat/} is O(n2): pattern SUBSTITUTION is quadratic-with-a-multibyte-constant on
                          3.2 the moment the string contains ONE match: bash walks every
                          byte position running a glob match, and each attempt costs
                          O(remaining) in a UTF-8 locale. Measured on 3.2.57, one space per
                          five bytes: 1KB 93ms - 2KB 527ms - 4KB 3.4s - 7KB 17.5s. With no
                          match ANYWHERE there is a fast bail (48KB in 5ms), and that is
                          precisely why the idiom reads as free: a hand-written test
                          envelope with terse titles takes the fast path, while every real
                          title contains a space and takes the slow one. Measured before
                          this rule existed: `yt-search -j -n 25 | ut-playlist --add` spent
                          16s in one such expansion, and `ut-play -d --queue -` 16.5s.
                          So a blank-input test is a MATCH, never a substitution:
                            [[ "$s" == *[![:space:]]* ]]   has a non-blank character
                            [[ "$s" != *[![:space:]]* ]]   is blank or empty
                          Both amplifiers are measured too: a character class costs 47x a
                          literal pattern, and en_US.UTF-8 costs 8x LC_ALL=C. There is now
                          no `${var//` anywhere in shell/ — keep it that way, and note that
                          the anchored strips (${v#pat}, ${v%pat}) are NOT affected.
   Verify:                run the empty-argument paths under /bin/bash explicitly —
                          this class is a runtime bash-version behavior, so `bash -n`
                          and shellcheck do NOT catch it; only executing on 3.2 does.
                          Same for the two rules above: both are runtime behaviors.
```

If a future feature genuinely needs bash 4+, the honest move is to assert
`((BASH_VERSINFO[0] >= 4))` at the top with a `brew install bash` hint and let PATH
provide it — never hardcode `/opt/homebrew/bin/bash` (breaks Intel macOS + Linux).
