# yt CLI Suite — Design & Implementation

`yt` · `yt-search` · `yt-play` · `yt-tui` — a YouTube search + terminal-playback CLI
suite, designed as much for **LLM/agent callers** as for humans. This is the single
systematic reference: architecture, functional structure, module contract, supported
workflows, and the rationale behind them. Each fact lives in ONE section; everything
else points at it.

- Core engine: `shell-scripts/yt` (single source of truth, non-interactive)
- Narrow headless verbs: `shell-scripts/yt-search`, `shell-scripts/yt-play`
- Interactive UI: `shell-scripts/yt-tui` (owned glue over the verbs; no extra deps)
- Caller-facing surface: each verb's own `-h`/`--help` · Contributor notes: `shell-scripts/README.md`
- Runtime deps: `yt-dlp`, `jq` (search); `mpv` (playback); `curl` optional (§8.2).
  No fzf / TUI framework — only foundational primitives.

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
   Human surface     ──►  yt-tui             (interactive: self-rendered menu + blocking play)
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
  D0  Names: yt, yt-search, yt-play, yt-tui — self-descriptive, and still the
      canonical name every doc, help text and error message uses. On PATH, though,
      bin/ carries ONLY the short forms yts/ytp/ytt: three symlinks for three
      scripts, where six meant two names for every command. The long names remain
      the identity of the scripts, not entries in bin/.  (§4)
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
```

## 4. Command topology & file layout

Four commands, one engine. `yt` is the full **non-interactive** core (search + play +
resolve + lifecycle), kept internal to `shell-scripts/` — not a PATH-exposed surface.
`yt-search`/`yt-play` are narrow real wrappers that gate flags and delegate. `yt-tui`
is the interactive human surface — pure orchestration with **zero** search/play logic.

```
                          PATH entries (per OS)
        macos/bin/                               linux/bin/
        ├── yts  → yt-search                     ├── yts  → yt-search
        ├── ytp  → yt-play                       ├── ytp  → yt-play
        └── ytt  → yt-tui                        └── ytt  → yt-tui
              (symlinks → ../../shell-scripts/…)
              ONE name per command: the long names are NOT in bin/

        shell-scripts/
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

**Why symlinks, not copies:** `macos/bin` and `linux/bin` hold only symlinks with zero
OS-specific logic (OS branching lives in the core via `uname -s`). One physical copy,
so platforms can't drift.

**Why only the SHORT names are on PATH:** `bin/` used to carry both spellings of all
three commands — six symlinks onto three scripts — so every command answered to two
names and each doc, allowlist and habit had to pick one. The short forms won because
they are what actually gets typed; the long names stay the canonical *identity* of the
scripts (help text, errors, this doc) without also being PATH entries. Consequence:
`yt-tui` can no longer find its verbs as siblings in `bin/`, so it falls back to the
same `../../shell-scripts/` hop the wrappers use to reach the core — invoked as
`bin/ytt`, `bin/../../shell-scripts/yt-search` resolves because the kernel walks `..`
through the `bin` symlink into env-config. Anything that called `yt-search`/`yt-play`
by name through PATH (agent tool definitions, Claude Code Bash allowlist entries) must
use `yts`/`ytp`, or an absolute path into `shell-scripts/`.

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
`shell-scripts/`. `yt` keeps its full standalone argument parsing (D2/D3) for
direct debugging from `shell-scripts/`, it's just no longer advertised as a surface.

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
| **yt-dlp** | extraction / search | de-facto standard; every client uses it | `fetch_results`, `resolve_stream_url`, `resolve_info`, `probe_media_fetchable`, `detach_title_updater` (~5 sites) |
| **mpv** | playback | general scriptable player; alt = vlc/ffplay | `run_mpv()` (single play seam) + `mpv_supports_vo()` capability probe |
| jq | JSON shaping | universal JSON tool | pervasive (search/JSON emit, lifecycle, `yt-tui` rows) |

Only **mpv** sits behind a single function (`run_mpv` — all five `play_*_url` modes route
through it), so swapping it (mpv→vlc) is a nearly localized edit; two mpv-specific details
sit outside it by necessity — `mpv_supports_vo()` asks mpv what terminal VOs it has, and
`play_viz_url` passes mpv's `--lavfi-complex` showwaves filter through `run_mpv`. **yt-dlp** is invoked at
the ~5 sites above rather than one seam — but it is the extraction standard every client
depends on, so replacing it isn't a realistic goal; the value is that each site is a
plain `yt-dlp …` array, not buried in a third-party client. **jq** is pervasive. The
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

```
   detach_play():
      ensure_state_dir()              # 0700 STATE_DIR + players/ (socket = a control channel)
      id = new_player_id()            # mktemp token; socket path known before launch
      set -m                          # monitor mode: backgrounded job = pgroup leader
      YT_IPC_SOCK=mpv-<id>.sock YT_DETACHED=1 \
        nohup bash SELF -f MODE [--volume N] [-S SORT] -- URL > mpv-<id>.log 2>&1 &  # pgid == pid ($!)
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
   • state: ${TMPDIR:-/tmp}/yt-cli-$(id -u)/players/<id>.json (+ mpv-<id>.sock, mpv-<id>.log)
```

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
**live** volume, read off the socket by `live_volume()` (one round trip, ~10ms measured —
`head` closes the pipe so `nc` never reaches its `-w1` timeout), falling back to the
recorded value. It is soft-gated on `nc`, keeping `--status`'s jq-only dependency (§15).
Verified: two `0` presses in `yt-tui` moved a player launched at `--volume 0` to `10`, and
`--status` reported `10` (it used to report `0` forever).

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
        │  no query on argv → prompt "❯ Search YouTube: " (empty/Ctrl-D cancels, exit 0)
        ▼
   SEARCH  fetch_json:  json = yt-search -j -n "$RESULT_N" "${SEARCH_ARGS[@]}" -- "lofi"
        │  the ONLY search path — the initial fetch, `n` new-search, and `m` more-results
        │  all use it, then the same build_all_rows → load_rows, so they can never drift
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
    │  text + ANSI — 3-view switchable cycling: List ↔ Mode A (Card) ↔ Mode B (Mini))│
    │  display_menu:                                                                 │
    │    List View:     title · status · live Now-Playing mini banner · result rows  │
    │                   (title + right-rail duration) · pagination dots · details    │
    │                   section for the SELECTED row · live filter input. A dim rail  │
    │                   sits under the Navigation block (chrome | content boundary,   │
    │                   drawn with the block or not at all).                          │
    │    Mode A (Card): full-screen rail-bounded card with metadata, progress bar &  │
    │                   interactive controls                                         │
    │    Mode B (Mini): ultra-minimalist 3-line mini-player with live progress bar   │
    │  read_nav_input: one keypress; decodes ESC-[/O arrow sequences                 │
    │    ↑/↓  move selection (paginate at edges)      ←/→  page (list) / seek 5s (card)│
    │    [ / ] seek ∓10s from ANY view                ↑/↓  volume (card/mini)         │
    │    Enter → play_selected:   yt-play -d -j -f MODE -- url  (NON-BLOCKING)       │
    │    Tab/p → toggle view:     List View ──► Mode A (Card) ──► Mode B (Mini) ──►  │
    │    Space → toggle pause:    sends IPC cycle pause over UNIX socket             │
    │    s     → stop playback:   yt-play --stop --id ID                             │
    │    9/0   → volume:          adjusts volume via socket IPC                      │
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
- **THREE SWITCHABLE VIEWS cycled with `Tab` (or `p`):**
  - **List View (Search & Browse)**: Interactive multi-row list with a top Now-Playing banner.
  - **Mode A (Now Playing Focus Card)**: Clean distraction-free card with word-wrapped title within
    adaptive divider rails, live `playtime / total time (pct%)`, and dynamic visual progress bar.
    The rails open the card (top) and close it (bottom) only — nothing separates the
    progress bar from the controls, so the readout labels the bar above it and the
    controls flow straight after it (the redundant rail between bar and Controls was
    removed in the theme pass).
  - **Mode B (Minimalist Mini-Player)**: Ultra-clean 3-line player with progress bar for zero visual noise.
  - **Anti-Flicker in-place rendering**: Real-time 1s timer refreshes time and progress bars smoothly
    via `\033[H` (cursor home) without full-screen blanking or flashing. Because nothing is
    blanked, **every row a frame emits must carry `\033[K`** — blank spacer rows included.
    The card grows by two rows the moment the progress bar appears (mpv has no `time-pos`
    for the first second or so), and an uncleared spacer kept displaying the divider rail
    the previous, shorter frame had drawn on that line.
  - **The progress bar is sized to the layout, not hardcoded.** `render_prog_bar pct total`
    takes the FULL cell width it may occupy (brackets included): the card passes
    `cols - 4`, so the bar keeps the body indent and ends flush with the divider rails,
    and the mini player passes whatever its time readout leaves on the line, ending at the
    same right edge as the wrapped title. The rendered string is *always* exactly that
    many cells — the head glyph is part of the track and `filled` is capped at `width-1`,
    where the old fixed-42 bar measured 46 cells at 0%, 44 at 50% and 47 at 100%, making
    the line jitter on every refresh. `repeat_glyph` builds the runs because
    `printf 'x%.0s' $(seq 1 0)` still prints one cell (printf always walks its format once).
  - **A live stream has no position, so it gets no position readout.** mpv reports
    `time-pos` on the *broadcast's* timeline with `duration` = the live edge, so
    `percent-pos` is ~99.98% from the first second and a progress bar is pinned full —
    measured on a 24/7 radio: `time-pos=77390 duration=77403 percent-pos=99.98` (a VOD at
    the same age reads 0.03%). The card and mini player therefore key off the row's own
    `live_status` (carried raw in `R_LIVE`; `play_selected` is what turns it into the
    `GL_LIVE` badge on `CURRENT_PLAY_DURATION`), show
    `Tuned: MM:SS · ● LIVE` — wall-clock since *this* listener attached, which mpv cannot
    provide — and draw no bar. `CURRENT_PLAY_IS_LIVE`/`CURRENT_PLAY_STARTED` carry it;
    both reset on stop.
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
    filter: hierarchy by gray levels (dim → normal → bold), hue is ONE accent
    (`C_CYAN`: headers, selection marker) plus ONE status hue (`C_GREEN`:
    playing); the rest of a community palette (its yellow/red/purple/…) is
    dropped on purpose. `C_YELLOW` is retired but stays defined as `""` — the five
    sites that still read it render default foreground, because the theme is a
    table of VALUES (`set_theme`) and the rendering sites are untouched; deleting
    the variable would be eight site edits for zero behavior change. `C_MARK` is
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

    **One deliberate exception: the brand wordmark (`YT_BRAND=1`).** The three view
    headers render `𝗬 𝗧  𝗧 𝗨 𝗜` (mathematical sans-serif bold, U+1D5D4 block) when
    opted in. It lives OUTSIDE the closed inventory on purpose: the UCD class is Neutral
    (one cell "in principle"), but real terminal fonts render this block via fallback
    fonts at whatever width they like — so it is NOT measured and NOT in the table, and
    `char_w`'s conservative 2-cell default applies to it (over-count packs the query
    elision a cell or two early; it can never overflow). It is opt-in precisely because
    a font without the block shows tofu and only the user's eyes can judge that.
    `YT_ASCII=1` wins over `YT_BRAND` — a font that cannot draw ♫ cannot draw these.

    **Neutral EAW — one cell in every terminal, unconditionally (4)**

    | glyph | cp | declared as | name |
    |---|---|---|---|
    | `↵` | U+21B5 | `GL_ENTER` | Downwards Arrow With Corner Leftwards |
    | `♫` | U+266B | `GL_NOTE` | Beamed Eighth Notes |
    | `❚` | U+275A | `GL_PAUSE` (drawn `❚❚`) | Heavy Vertical Bar |
    | `❯` | U+276F | `GL_CARET` | Heavy Right-Pointing Angle Quotation Mark Ornament |

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
    The Neutral 4 are one cell by definition of their class, so no setting reaches them.
    `♫` U+266B belongs there and not with the arrows — it is Neutral, so it stays one cell
    even under `YT_AMBIG_WIDE`.

    Everything the TUI draws is therefore in one of four buckets: ASCII (1 cell), these 17
    (tabled), CJK label text (2, exact), or untabled and conservatively over-counted.
    `YT_ASCII=1` (auto-on for a non-UTF-8 locale) replaces all 17 with ASCII equivalents, so
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
    than the inline test it replaced (300 measurements of the mini-player hint row: 94 ms
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
    with a first/continuation prefix; `truncate_disp` elides a variable-length value that
    shares a one-line budget with fixed chrome. Applied to the navigation row, the card's
    `Controls` block, the mini player's hint row, the empty-state copy, and the list's
    status row (whose `min=`/`max=` now appear only when set — at their `0s` default they
    were pure width). The card's `Time / Mode / Status` row measures its three segments and
    splits onto two lines when they do not fit, and the Now-Playing banner gives the title
    whatever the fixed parts leave, dropping its inline hint block before it would squeeze
    the title below 12 cells. Result: every chrome line fits at 46 columns, where the old
    fixed strings wrapped mid-item from ~72 down.
  - **EVERY row in the list view is one physical line, result rows included.** They were the
    last rows printed unmeasured, and the ones that mattered most: at 62 columns a
    `title · duration · views · channel` row takes two or three lines, so ten entries filled
    21 lines and scrolled the header, the status row, the Now-Playing banner and the entire
    navigation block off the top — every hint the layout had just packed, spent on rows that
    then scrolled away. Each row's TITLE is elided to what its `> 10. ` / `  10. ` prefix,
    a two-cell gap and the duration rail leave (`cols - 4 - <digits> - 2 - rail`). The title
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
    fetch behind `PT_CUR` / `PT_TOTAL` / `PT_PCT`, including the live special case: both
    player views had inlined the same three `nc | jq` pipelines and had already drifted, and
    the live path used to fetch three round-trips per second only to discard them. The card's
    divider rail is built by `repeat_glyph` and cached on `(width, glyph mode)` instead of
    `printf '─%.0s' $(seq 1 "$cols")` — a fork, plus precisely the idiom `repeat_glyph` exists
    to replace, run twice so the Unicode rail could be thrown away in ASCII mode.
    `repeat_glyph` and `render_prog_bar` now return through globals (`GLYPH_RUN`, `PROG_BAR`)
    like the rest of the width layer, so a redraw costs no subshell for them.
  - Pressing `Tab` cycles views; pressing `Esc` in Card/Mini view instantly returns to List View.
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
  --status --stop --get-url --info --set-volume --id --all --color --volume` (color is
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
  Keys: arrows nav/page · Enter non-blocking play · `Tab`/`p` cycle the three views ·
  `Esc` back to list · `Space` pause · `[`/`]` seek ∓10s · `9`/`0` volume · `s` stop ·
  `v` cycle mode (audio→video→fast) · `l` switch chrome language (en↔zh, any view) ·
  `n` new search · `m` more results · `o` sort · `/` filter · `q` quit.

## 13. Wrapper gating model

Each wrapper accepts only its own surface and points the caller at the correct tool on
a cross-flag — this is what makes the two contracts non-overlapping.

```
   yt-search                                  yt-play
   ─────────────────────────────────         ─────────────────────────────────
   allow: -n -m -M -s -S -l -j -J            allow: -f -d -j -J --detach --get-url
          --color -h                                --info --status --stop --set-volume
                                                    --id --all --color -h --volume
   reject (→ "use yt-play"):                  reject (→ "use yt-search"):
          -f -d --detach --status                   -n -m -M -s -S -l --list
          --stop --get-url --info
          --set-volume --id --all
   positional: a QUERY (reject URLs)         positional: a URL
   default: inject -l if no -l/-j/-J         URL required unless
                                             --status/--stop/--set-volume
   both: emit `<flags> -- <positional>`  (the `--` is FORWARDED, not just consumed)
```

The core implements the *full* set; the wrapper only restricts which subset each verb
exposes. **Unified `-j` semantics** work because the wrapper guarantees the operation
type: `yt-search` guarantees non-URL → core `-j` = SEARCH envelope; `yt-play`
guarantees URL → core `-j` = PLAYBACK status.

**Why yt-tui composes the verbs, never the core (D8).** The same guarantee is what the
TUI relies on. `fetch_json` parses the search envelope, and only `yt-search`'s URL
rejection makes "core `-j` = search envelope" unconditional — a URL pasted into the
TUI's `s` prompt would otherwise route to `play_url_json`: a *blocking playback* while
the TUI waits for search JSON. Calling the core directly would force that URL guard up
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

Playback status (`yt-play -j <url>`):
```json
{ "status":"ok"|"error", "url":"…", "mode":"audio",
  "exit_code":0, "reason":null, "retried":false }
```
`reason` enum: `forbidden | unavailable | format_unavailable | network |
stopped_by_user | unknown | null(ok)`.

Lifecycle / resolve:
```
   -d       : {status:"started", id, pid, url, mode, started_at, title:null, sock, log}
              sock/log are handed over so a client never rebuilds the state-dir layout
   --status : {status:"players", players:[{id,pid,url,mode,volume,title,started_at}…]}
              empty array when nothing playing (still exit 0); one entry per live player
              title is null for the first ~3s after a detach, then the async updater fills it
              volume is read LIVE off the player's socket (§9.3), falling back to the
              recorded launch/--set-volume value; null only if neither is available
   --set-volume : {status:"ok", id, volume}          (live-adjusted via mpv IPC socket)
                | {status:"not_playing"}             (no target; exit 4)
                | {status:"ambiguous", reason:"multiple_players", players:[{id,pid,title,url}…]}  (exit 4)
                | {status:"error", reason:"ipc_failed"}   (dead/missing socket; exit 4)
   --stop   : {status:"stopped", id, stopped:bool}   (single target)
            | {status:"stopped", scope:"all", stopped:bool}   (--all)
            | {status:"ambiguous", …}                (2+ players, no --id; exit 4)
   --get-url: {status,url,mode,format,stream_urls:[…]}
   --info   : {status,id,title,url,channel,uploader,upload_date,duration,duration_fmt,
              view_count,like_count,live_status,description,chapters} ; -J = raw record
              chapters = [{start_time,end_time,title}] | null ; error → {status,url,reason}
```

## 15. Exit codes, TTY, dependencies

```
   0    success; also --status/--stop (always); 130 normalized (SIGINT; clean q already exits 0)
   1    usage/validation error (die), wrapper flag-gating rejection, resolve failure
        (prose), empty-query (D3), yt-tui non-TTY refusal, conflicting actions,
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
          only jq (--status uses nc opportunistically for live volume and degrades to
          the recorded value without it), --set-volume needs jq+nc (nc gated lazily so a
          bare search never demands it), and --info needs only yt-dlp+jq (all checked
          before the mpv gate). yt-tui needs only jq and the verbs. curl is an OPTIONAL soft dep for
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
                        Covers the WHOLE glyph set: ♫ ● ○ ❯ · ▶ ❚❚ • … → — ↑/↓ ←/→ ↵
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
   Core (shell-scripts/yt)
     Setup/util : usage, die, is_non_negative_int, validate_enum,
                  require_cmd/require_deps, mpv_supports_vo, normalize_playback_mode,
                  set_action, JQ_PRELUDE (jq p2/fmt_dur — the one duration formatter)
     Search     : fetch_results, print_list, emit_search_json
     Playback   : run_mpv, play_{audio,video,fast,ascii,viz}_url,
                  play_mode_url, have_probe_tools, probe_media_fetchable,
                  play_url_with_probe, play_url_directly,
                  play_url_json, classify_playback_error, format_for_mode
     Lifecycle  : group_alive, stop_group, ensure_state_dir, live_volume,
                  player_state/player_sock/player_log/player_lock_dir,
                  lock_player_state/unlock_player_state, new_player_id, detach_play,
                  detach_title_updater, reap_dead_players, resolve_target,
                  do_status, do_stop, do_set_volume
     Resolve    : resolve_stream_url (--get-url), resolve_info (--info)
   Wrappers     : yt-search, yt-play   (parse → gate → exec yt)
   Interactive  : yt-tui   (fetch_json → build_all_rows → load_rows → menu loop:
                  display_menu · read_nav_input · move_selection · play_selected ·
                  new_search [read_query_input, Esc cancels] · filter_live → apply_filter)
     Width layer: char_w/disp_w/truncate_disp/cluster_back, cw_range/init_cell_tables
     Chrome     : layout_cols, print_hints (HINT_MEASURE), wrap_print/wrap_emit
                  (WRAP_MEASURE), print_details (DETAIL_MEASURE), card_divider,
                  repeat_glyph, render_prog_bar
     Formatters : fmt_sec (clock), short_dur (duration_fmt → 6:10:58), commas
```

**Provenance.** The suite descends from an all-in-one `yt-search-n-play.sh`: its
non-interactive core moved into `yt` behind the verbs, and its self-rendered TUI
(menu chrome, `display_menu`, `read_nav_input`, `read_query_input`, arrow-key paging,
blocking-play semantics) was re-homed in `yt-tui` — same menu, now delegating to the
verbs. Where yt-tui behavior looks arbitrary (no `clear` before play, no stdin flush,
rows printed untruncated and left to wrap), it is deliberate parity with that original;
the `/` filter is the one net-new addition.

---

# Part IV — Supported workflows

## 18. Human — interactive browse & play

```
   $ yt-tui "lofi hip hop" -n 40 [-f video] [-p 15]
     → self-rendered menu (§11): ↑/↓ nav · ←/→ page · Enter blocking play
       (mpv progress bar; q returns to the menu) · v cycle mode (audio→video→fast) ·
       n new search · m more results · o sort · / filter · q quit
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
| Token efficiency | high-signal beats complete | ✅ 8-field `-j` (~4× smaller); `-J` opt-in |
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
   nc waits full -w1 (mpv keeps socket open) request_id filter + head -1; ~≤1s/call, not
                                             for tight loops (human-driven adjust is fine).
                                             yt-tui's redraw path IS a tight loop and has no
                                             head -1 — it pays the second (§25.1 F19)
```

### 25.1 Open defect register — `yt-tui` hardening pass

Audited against `shell-scripts/yt-tui`. **Batch 1 (the one-line edits) and batch A (the cheap
correctness/UX edits) are fixed; the rest is not** — this is a register of known defects, not a description of the code. It is kept here rather than as a loose `TODO-` file
because the findings are statements about *this* design's seams, and each one is only
actionable next to the section it sits in. The open rows below have since been re-audited
against the code and re-measured on the machine's own bash 3.2.57. **Six of them asserted
something false** — F2's reason source, F5's round-trip cost, F10's byte-ordering trick,
F11's padding unit, F13's positional reply read, and the whole of F15 — so the corrections
are recorded inline rather than quietly swapped: each of those was a premise a fix would
have been built on.

**Reproduced, not inferred:**

- Space → pause → unpause exits the script with status 1 (`set -e` kills it on the second
  toggle).
- `play_selected` returning 1 from a case arm exits the script with status 1 — no output,
  no cleanup message.
- `read -rsn1` on bash 3.2 delivers one **byte**: 你 arrives as `e4 bd a0`, three keys.
- `${q%?}` under a UTF-8 locale strips a whole **character** on 3.2 (你好 → `e4 bd a0`), so
  the F10 backspace needs no byte-repair fallback.
- One `nc -U -w1` round trip against a peer that keeps the socket open costs **~1.02 s**,
  not the ~10 ms the core measures with `head -1` (F19).
- `printf '%-8s'` pads to eight **bytes**, not eight characters (F11).

**The `set -e` family — fixed.** All three were the same trap (§28): a non-zero status
reaching `set -e` from a place that reads like an expression, not a command. See the closed
list at the end of this section. What remains of F2 is the *reporting* half — `play_selected`
still returns 1 silently, so a failed Enter is now a survivable no-op with no message. The
message should be shown in the same "press any key" style as the `n`/`m`/`o` failures, which
is why it is batched with F7. **Correction:** it cannot come from the envelope's `reason`.
The §14 taxonomy belongs to the *blocking* play path; for a synchronous `-d` failure the core
`die`s with prose on **stderr** and emits nothing on stdout (verified: `yt-play -d -j -f ascii
-- <url>` → rc 1, empty stdout). yt-tui must capture that stderr, the way `fetch_json`
already does for search.

Audited clear in the same pass: every other case-arm function returns 0 on all paths
(`move_selection`, `cycle_mode`, `cycle_sort`, `new_search`, `more_results`, `filter_live`,
`stop_current_playback`, `apply_filter`); `mpv_get_prop` ends in `|| true` and is only ever
used in command substitution.

**Call-stack boundary — yt-tui reaching past a seam it already has.**

| ID | Sev | Finding |
|----|-----|---------|
| F3 | high | **A dead player leaves a stale banner forever.** `send_mpv_ipc` swallows every failure, `mpv_get_prop` returns empty on a dead socket, and nothing re-checks the player: a track that ends (or an mpv crash) leaves the list banner showing the old title, the card showing `--:--` against a stale title, and Space flipping a local paused flag with no IPC peer. The core already defines liveness as "process group alive" (§9.3 `reap_dead_players`), and the `-d` envelope's `.pid` is the **wrapper's** pid, which blocks on mpv — so wrapper alive ⇔ still playing, and `kill -0` on it is the same truth for one builtin and no fork. Two call sites, not one: the main loop *and* `filter_live`'s own key loop, which never returns to the main loop while `/` is open. An **empty** pid must mean "unknown, assume alive" — `play_selected` requires only id and sock, so clearing on an absent pid would blank a healthy player's chrome. |
| F5 | high | **Volume over the raw socket escapes the 0–100 contract.** `9`/`0` send `add volume ±5` straight to mpv, bypassing the core's `--set-volume` validation; mpv's own ceiling is 130, so holding `0` reaches a value the rest of the suite's vocabulary says cannot exist (§9.3). Read-modify-set with a clamp costs one extra round trip per keypress — which is **~1 s at today's `nc` shape**, not the ~10 ms first recorded here (that figure is the core's, and it only holds because `live_volume` pipes through `head -1`; see F19). F5 therefore lands *after* F19, never before it. |
| F9 | med | **The filter's `?)` catch-all cannot match a multibyte character** — the Tab half is fixed (its own no-op arm); widening `?)` to `*)` belongs with F10, which is what makes the widening safe. Swallowing `q`/`s`/`9`/`0`/`l` mid-filter stays: deliberate modality ("type to narrow, Esc clears"). |
| F10 | med | **CJK typed into the filter or the new-search prompt arrives byte-split** — see §28. Both readers need one shared UTF-8 assembly helper off the lead byte, with the continuation reads on a timeout so a lone lead byte cannot stall the once-a-second card/mini tick. Backspace is confirmed to strip a whole character on 3.2, so no repair path is needed — but its `\b \b` erase is one cell and a CJK glyph occupies two. **Classify the lead byte by table membership, the way `char_w` does:** `LC_ALL=C [[ … ]]` is not valid bash (an assignment prefix needs a simple command; `[[` is a reserved word), so it silently answers under the wrong collation, and a `( LC_ALL=C … )` subshell would fork per keypress. |

**Shape — duplication and unfinished rules.**

| ID | Sev | Finding |
|----|-----|---------|
| F7 | med | The "no results / error / press any key" block is copy-pasted in `new_search`, `more_results` and `cycle_sort`, **and has already drifted in wording** — the standard signal that it wants to be one function. Each caller restores its own mutated variable before calling, as today. |
| F8 | low | `read_query_input` returns 2 on Esc and 1 on EOF; its only caller treats both as cancel. The distinction is dead — collapse to 0/1 as part of the F10 rewrite. |
| F11 | low | **The one-language-per-run rule stops at the list hints.** `Playing`/`Paused`, `NOW PLAYING FOCUS`, `MINI PLAYER`, and the card's `Title:`/`Channel:`/`Time:`/`Tuned:`/`Mode:`/`Status:` are hardcoded English inside a bilingual chrome (§11 — help text and errors stay English *by design*; these are chrome). They want `S_*` entries in both branches of `set_ui_lang`. **This cannot be a pure string swap**, for two reasons, and the first was recorded backwards here: bash 3.2's `%-8s` pads to eight **bytes**, not eight characters, so "时间:" (7 bytes) renders **6** cells where the fit estimate assumes 8 — an *over*-estimate, and a `${#label}` correction would err the other way. Drop `%-8s` for a translated label and emit a `disp_w`-measured pad, so the printed width and the estimate are the same number by construction. Second, the card's `wrap_print` calls hardcode a 15-space continuation to sit under a 15-cell first prefix; a shorter CJK label drifts it. Derive both prefixes from the label. English values must reproduce today's numbers exactly. |

**Found in the re-audit — the latency defect.**

| ID | Sev | Finding |
|----|-----|---------|
| F19 | high | **Every `nc -U -w1` in yt-tui waits the full second.** BSD `nc` never shuts down its write half at stdin EOF, and mpv keeps the connection open, so `nc` blocks in `read()` until the timeout. The core escapes this only because `live_volume` pipes through `head -1` — the "~10 ms measured" note there is about *that* shape. yt-tui has no `head` on either path, so `mpv_get_prop` and `send_mpv_ipc` each cost **~1.02 s** (measured against a socket peer that behaves like mpv). `fetch_play_times` makes three, so a card/mini redraw costs **~3 s** on a view whose tick claims to be one second, and every pause/seek/volume keypress blocks the UI for ~1 s. **Subsumes F13**, which filed the same code as "3 forks per tick, invisible perf". Fix: batch the three `get_property` calls onto one connection *and* read them through a process substitution, breaking on the last reply so the shell never waits for `nc` (measured ~0.01 s; the abandoned `nc` expires on its own). **Correlate on `request_id`**, not on line order — mpv multiplexes async events to every client (the lesson `do_set_volume` already carries); F13's `map(.data)[]` sketch would seat an event where a property belongs. `nc -N` is not available on macOS and `-w0` returns before any reply. |

**Withdrawn — F15 was not a defect.** It read the mini player's `${#total_time}` bar sizing as
an ambiguous-width bug on the grounds that `total_time` can be `● LIVE`. It cannot: the live
branch of `fetch_play_times` returns early with `PT_PCT=""`, and `bar_total` is only computed
inside `if [[ -n "$PT_PCT" ]]`, where every part of the prefix is ASCII (`fmt_sec` /
`SHORT_DUR`). The `·` separator on that line is likewise live-only, i.e. bar-free. What is
wrong there is only the comment, which states the conclusion ("all the prefix cells are
ASCII") without the early-return that makes it true.

**Accepted, not defects** (recorded so they are not re-litigated): the filter swallowing
`q`/`s`/`9`/`0`/`l` is intentional modality; a failed play in filter mode consuming one
keystroke on "press any key" matches the `n`/`m`/`o` failure behavior. Pid reuse can
false-positive F3's `kill -0`, exactly as §25 records for the core's own `group_alive` —
narrowed by the monotonic id, not closed, and not worth a second mechanism in the client.

**Order — by ROI, not by severity.** The batching below is deliberate: the largest edit in the
pass (F11) is the only purely cosmetic one. The re-audit moved the IPC work from last to
second: F13 was ranked as invisible perf on a borrowed ~10 ms figure, and at ~1 s a round trip
(F19) it is the defect the user actually feels.

1. **The IPC layer** — F19 (subsuming F13), then F5 on top of it. F5 adds a round trip, so it
   is unaffordable until F19 makes one cheap.
2. **F3** — the liveness poll; the most visible defect that is not a crash.
3. **F2's other half + F7** — one shared "message, then press any key" path for a failed play
   and for the three re-fetch failures, with the play reason read off the core's **stderr**.
4. **The input layer** — F10 + F8 + F9's `?)`→`*)` widening, one shared UTF-8 helper across
   four sites. Highest effort, and it touches every keypress, so it does not sit in front of
   the cheap batches.
5. **F11** — the cosmetic i18n pass, with its byte-padding layout fix.

(The cheap correctness/UX batch that stood in front of these — F18, F14, F16 — has shipped;
see the closed list below.)

Each step ends `bash -n` clean, re-runs the two `set -e` repros, and the interactive smoke
pass in §27. Patch bodies and the three open questions live in the working sketch pad
`macos/docs/TODO-yt-tui-fixes.md`, which is deleted when this register empties.

**Closed by the batch-1 pass** (one edit, `bash -n` clean, both `set -e` repros green):

- **F1** — `toggle_pause` now assigns (`CURRENT_PLAY_PAUSED=$((1 - …))`) instead of running a
  bare `((x = 0))`, whose status-1 result killed the script on every *un*pause.
- **F17** — `send_mpv_ipc` returns 0, not 1, when the socket file is gone: it is the last
  command of `toggle_pause`/`seek_relative`/`adjust_volume`, and fire-and-forget was already
  its contract (the `nc` failure below it was always swallowed).
- **F2, crash half** — both Enter arms are now `play_selected || true`. A failed play is a
  survivable no-op; the message is still owed (see F2/F7 above).

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

**Closed by the list-view rail/details work:** the original audit also carried F4 — play
metadata re-derived by re-splitting the *display* string, which only parsed correctly
because `clean` collapses whitespace, and which threw away the `views` field it parsed
(proof the split was never a contract). `play_selected` now reads the row's own fields
(§11), and the tab-collapse hazard the fix had to dodge is why the record separator is US
rather than tab. The same audit noted this document's §11 diagram naming `s`/`S` for
new-search/more-results instead of `n`/`m`; also corrected.

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
    - Linux `nc -U` portability — macOS-primary tool; BSD `nc -U` is stock, GNU netcat
      variants differ (`ncat -U` works; `netcat-traditional` has no Unix-socket support).
      Accepted as a known gap, noted in a script comment rather than solved now.

## 27. Verification matrix

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
   Gating     : yt-search rejects -f/--detach/URL; yt-play rejects -n/-s/bare-query
   Resolve    : yt-play --get-url (prose + -j envelope, no playback)
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
                Live volume: yt-tui 9/0 on a --volume 0 player → --status reports the
                moved value (not the stale launch value)
   yt-tui     : (tmux PTY) Enter → background play + banner; Tab → card (live
                time/progress via the envelope's sock) → Tab → mini → Esc → list;
                Widths (measured in display cells, CJK-aware): at 100/72/60 cols the
                card's rails and progress bar are equal and flush (80/72/60), the bar
                holds that exact width at 0/1/50/99/100%, the spacer row above it is
                blank (not a stale rail), and the mini player's bar ends at the same
                right edge as its wrapped title; YT_ASCII=1 renders [#---] at the same
                width
                Live stream: card/mini show "Tuned: MM:SS · ● LIVE" with the counter
                ticking and NO bar (never mpv's ~99.98% percent-pos); a VOD in the same
                build still shows "00:05 / 02:03:54 (0%)" + a rail-flush bar
                Narrow terminals: at 100/72/60/46 columns EVERY chrome line fits the
                width in all three views (max measured = the rails/bar themselves) —
                nav + controls + mini hints + empty-state repack, the card's
                Time/Mode/Status row splits, the banner elides its title
                YT_ASCII=1: a rendered pane contains no non-ASCII beyond the label text
                (>, ||, *, Up/Dn, Lt/Rt, Enter, -, ..., ->, [#---], |)
                Language: LANG=zh_CN starts Chinese, LANG=en_US starts English, YT_LANG
                overrides both, YT_LANG=fr dies; the `l` key flips the chrome in the
                list AND card/mini views with playback uninterrupted
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
                -c never → no ANSI; Enter → blocking play, q → menu redraws
                (rc 130 → 0; other rc → "press any key"); no stdin flush after
                playback (§11); non-TTY (piped stdin or stdout) → dies cleanly
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
                          reassemble the UTF-8 sequence from its lead byte. Byte-range
                          comparisons for that need LC_ALL=C: [[ ]] in a UTF-8 locale
                          collates by codepoint, which misorders raw bytes.
   Verify:                run the empty-argument paths under /bin/bash explicitly —
                          this class is a runtime bash-version behavior, so `bash -n`
                          and shellcheck do NOT catch it; only executing on 3.2 does.
                          Same for the two rules above: both are runtime behaviors.
```

If a future feature genuinely needs bash 4+, the honest move is to assert
`((BASH_VERSINFO[0] >= 4))` at the top with a `brew install bash` hint and let PATH
provide it — never hardcode `/opt/homebrew/bin/bash` (breaks Intel macOS + Linux).
