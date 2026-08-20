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
  D0  Names: yt, yt-search, yt-play, yt-tui — self-descriptive, never yts/ytp.
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
```

## 4. Command topology & file layout

Four commands, one engine. `yt` is the full **non-interactive** core (search + play +
resolve + lifecycle), kept internal to `shell-scripts/` — not a PATH-exposed surface.
`yt-search`/`yt-play` are narrow real wrappers that gate flags and delegate. `yt-tui`
is the interactive human surface — pure orchestration with **zero** search/play logic.

```
                          PATH entries (per OS)
        macos/bin/                               linux/bin/
        ├── yt-search · yts                      ├── yt-search · yts
        ├── yt-play   · ytp                      ├── yt-play   · ytp
        └── yt-tui    · ytt                      └── yt-tui    · ytt
              (symlinks → ../../shell-scripts/…)

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
| **mpv** | playback | general scriptable player; alt = vlc/ffplay | `run_mpv()` (single) |
| jq | JSON shaping | universal JSON tool | pervasive (search/JSON emit, lifecycle, `yt-tui` rows) |

Only **mpv** sits behind a single function (`run_mpv` — all five `play_*_url` modes route
through it), so swapping it (mpv→vlc) is a truly localized edit. **yt-dlp** is invoked at
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
   │      --status/--stop/--get-url/--info/--set-volume → ACTION/flags   │
   │  (b) getopts  ":n:m:M:s:f:S:dljJh"  → NUM_RESULTS, MODE, …         │
   │  (c) VALIDATION  ints, enums (sort, color), -M>-m, ascii VO       │
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
  │     --match-filter "duration > MIN [and duration < MAX]"     │
  │     [--cookies-from-browser <B>] --flat-playlist             │
  │     --dump-single-json -f ba --skip-download --quiet …       │
  │        │  .entries → jq sort_by(duration|view_count)|reverse │
  │        ▼  per entry: + {duration_fmt: convert_seconds(dur)}  │
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
failures still propagate. The filter drops only non-error lines, so the `-j` error taxonomy
is unaffected — the classifier still sees `403`/unavailable/etc., and the JSON status line
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
      id = new_player_id()            # mktemp token; socket path known before launch
      set -m                          # monitor mode: backgrounded job = pgroup leader
      YT_IPC_SOCK=mpv-<id>.sock nohup bash SELF -f MODE URL > mpv-<id>.log 2>&1 &  # pgid == pid ($!)
      set +m ; disown
      players/<id>.json ← {id,pid,url,mode,format,started_at,log,sock,title:null,volume}
      rm PLAYERS_DIR/<id>              # drop bare mktemp token; state lives in <id>.json
      detach_title_updater(id,pid,url) &  # async backfill; returns instantly (see below)

   ┌─ process group  pgid = 57678  (player <id>) ───────────┐
   │  57678  bash yt -f audio URL   (leader)                │
   │    ├─ (probe: yt-dlp + curl, short-lived)               │
   │    └─ 57712  mpv --input-ipc-server=mpv-<id>.sock       │  ← reparents to init
   └──────────────────────────────────────────────────────────┘     but pgid stays

   stop_group(pgid):  kill -INT -pgid ; wait (pgrep -g); escalate kill -KILL -pgid
   group_alive(pgid): pgrep -g pgid has ≥1 member
```

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

Detached is **audio only** — a detached process has no controlling terminal, so
video/ascii/viz have nowhere to render. (Schemas → §14.)

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

**Handle = a monotonic token, not the pid (D9).** `new_player_id` mints the handle via
`basename "$(mktemp "$PLAYERS_DIR/XXXXXX")"` — atomic and collision-free. This solves
two problems at once: (1) the socket must be **named at launch** via `YT_IPC_SOCK`, but
the child's pid isn't known until `$!` *after* launch — the token breaks that
chicken-and-egg; and (2) it is immune to **pid reuse** (a dead `<id>.json` plus an
unrelated process reclaiming that pid can't false-positive liveness, because liveness is
checked against the pid stored *inside* `<id>.json`, and the file is reaped the moment
its group is gone). `mktemp` leaves a **bare** `<id>` file to reserve the id; after
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
grounding signal): `--info` *adds* the grounding an agent reasons over.

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
        │  the ONLY search path — the initial fetch, `s` new-search, and `S` more-results
        │  all use it, then the same build_all_rows → load_rows, so they can never drift
        ▼
   ALL_ROWS  jq: .results[] → [ url, "title · dur · views · channel" ] | @tsv
        │  ` · `-joined cells; a live stream shows "● LIVE" in place of its zero duration.
        │  f1=url (hidden)  f2=display.  NO leading number — the menu numbers rows by
        │  visible position, which stays correct after a filter re-orders them.
        ▼
   load_rows → urls[] / options[] / NUM_ENTRIES / NUM_PAGES
        ▼
    ┌─ SELF-RENDERED MENU LOOP (yt-tui draws every line, reads every key; plain ─────┐
    │  text + ANSI — 3-view switchable cycling: List ↔ Mode A (Card) ↔ Mode B (Mini))│
    │  display_menu:                                                                 │
    │    List View:     title · status · live Now-Playing mini banner · results ·    │
    │                   pagination dots · live filter input                          │
    │    Mode A (Card): full-screen rail-bounded card with metadata, progress bar &  │
    │                   interactive controls                                         │
    │    Mode B (Mini): ultra-minimalist 3-line mini-player with live progress bar   │
    │  read_nav_input: one keypress; decodes ESC-[/O arrow sequences                 │
    │    ↑/↓  move selection (paginate at edges)      ←/→  page / seek               │
    │    Enter → play_selected:   yt-play -d -j -f MODE -- url  (NON-BLOCKING)       │
    │    Tab/p → toggle view:     List View ──► Mode A (Card) ──► Mode B (Mini) ──►  │
    │    Space → toggle pause:    sends IPC cycle pause over UNIX socket             │
    │    s     → stop playback:   yt-play --stop --id ID                             │
    │    9/0   → volume:          adjusts volume via socket IPC                      │
    │    v     → cycle_mode:      PLAY_MODE audio→video→fast (local; next Enter)     │
    │    n     → new_search:      read query → fetch_json → reload (music continues) │
    │    m     → more_results:    re-fetch CURRENT query, RESULT_N += 25 (else keep) │
    │    o     → cycle_sort:      rotate SORT_FIELD, re-fetch (relevance→views→dur)  │
    │    /     → filter_live:     LIVE narrow — type to filter, Esc clears           │
    │    q     → exit 0           reaps background players cleanly on trap EXIT      │
    └────────────────────────────────────────────────────────────────────────────────┘
```

- **PLAY is asynchronous & non-blocking via `yt-play -d -j`.** Playback launches in an
  independent, detached process group so `yt-tui` retains full terminal control. Audio
  streams uninterrupted while users browse results, change pages, or initiate a new search
  (`n`). A single `Enter` on any track cleanly stops the previous player and starts the
  new selection without latency.
- **THREE SWITCHABLE VIEWS cycled with `Tab` (or `p`):**
  - **List View (Search & Browse)**: Interactive multi-row list with a top Now-Playing banner.
  - **Mode A (Now Playing Focus Card)**: Clean distraction-free card with word-wrapped title within
    adaptive divider rails, live `playtime / total time (pct%)`, and dynamic visual progress bar.
  - **Mode B (Minimalist Mini-Player)**: Ultra-clean 3-line player with progress bar for zero visual noise.
  - **Anti-Flicker in-place rendering**: Real-time 1s timer refreshes time and progress bars smoothly
    via `\033[H` (cursor home) without full-screen blanking or flashing.
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
  injection. Only the display field is matched; the hidden url rides along. `n` (new search)
  stays Enter-submit — it hits the network — so the two prompts diverge on purpose (in-page
  filter is live; a remote search submits).
- **Chrome: pagination + cursor.** Pagination dots (`●○○`, current filled) render ONLY when
  there's more than one page — a lone dot conveys nothing — and fall back to numeric `page X/Y`
  in ASCII mode or past a readable dot cap. The terminal cursor is hidden while the menu is
  drawn (so no stray block parks below the footer) and shown only for the bottom filter input,
  typed prompts, and playback; a `trap … EXIT` restores it on quit / error / Ctrl-C.
- **URL plumbing:** jq `@tsv` escapes any tab/newline in a title, so the hidden
  url/display field boundary never breaks; `load_rows` splits back into parallel
  `urls[]`/`options[]`, so a pick is a direct array index — never re-parsing a
  rendered line.
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
- Surface: `yt-tui [-n N] [-m S] [-M S] [-s field] [-f MODE] [--volume N] [-p ROWS]
  [--color auto|always|never] [query]` — search-shaping flags forwarded to `yt-search`;
  `-f`/`--volume` playback settings forwarded to `yt-play` on every play; `-p`
  rows/page; rejects all else. `--volume` is launch-time only (no live cycle key,
  unlike `-f`'s `v` — see §26). Query optional (prompts if
  absent). Requires a TTY on both stdin and stdout, `jq`, and the sibling verbs.
  Keys: arrows nav/page · Enter blocking play · `v` cycle mode (audio→video→fast) ·
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

Playback status (`yt-play -j <url>`):
```json
{ "status":"ok"|"error", "url":"…", "mode":"audio",
  "exit_code":0, "reason":null, "retried":false }
```
`reason` enum: `forbidden | unavailable | format_unavailable | network |
stopped_by_user | unknown | null(ok)`.

Lifecycle / resolve:
```
   --status : {status:"players", players:[{id,pid,url,mode,volume,title,started_at}…]}
              empty array when nothing playing (still exit 0); one entry per live player
              title is null for the first ~3s after a detach, then the async updater fills it
              volume is null unless --volume was passed at that player's launch
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
        (prose), empty-query (D3), yt-tui non-TTY refusal
   2+   propagated yt-dlp / mpv failure (playback, resolve -j)
   4    --set-volume / --stop: did not take effect — no such player, no player,
        ambiguous target, or mpv IPC failure. The -j status/reason says which.
        Distinct from 1 (usage) and 2+ (propagated player failure). --stop treats
        "nothing playing" as idempotent success (exit 0); only ambiguity is exit 4.

   TTY  : yt-tui requires BOTH stdin and stdout (§11); the core never needs a TTY —
          it errors on empty input rather than prompting (D1/D3).
   deps : core needs yt-dlp jq mpv before search/play/geturl; --status/--stop need
          only jq, --set-volume needs jq+nc (nc gated lazily so a bare search never
          demands it), and --info needs only yt-dlp+jq (all checked before the mpv
          gate). yt-tui needs only jq and the verbs. curl is an OPTIONAL soft dep for
          the play-time client probe (§8.2). BSD `nc -U` is stock on macOS; the Linux
          netcat `-U` gap is a known, documented limitation (§26 / script comment).
```

## 16. Configuration surface

Per-request choices are flags; set-once tuning is environment variables — deliberately
kept out of flags to keep each verb's flag surface narrow.

```
   Flags (per call):  -n -m -M -s -f -S -l -j -J -d --color
                      --detach --status --stop --get-url --info --set-volume --id --all --volume
   Env (set once):    YT_COOKIE_BROWSER   (default chrome = login on; "none" = anon-only)
                      YT_AUDIO_FORMAT (ba)  YT_VIDEO_FORMAT (bv*+ba/b)
                      YT_VIDEO_FORMAT_FAST  YT_ASCII_VO (tct)  YT_MPV_INPUT_CONF
                      YT_TUI_ASCII (1 = ASCII glyph fallbacks; auto-on for non-UTF-8 locale)
   (color is the --color flag, NOT an env var — the scripts hardcode COLOR_MODE=auto
    at startup and only --color changes it, so a COLOR_MODE env value is never read.)
```

Cookie handling: `YT_COOKIE_BROWSER` is presence-checked per platform (does the
browser's profile dir exist); if absent, extraction runs without cookies rather than
breaking. Reading a browser's cookie DB while it is running can yield a locked read and
silently degrade to unauthenticated extraction — closing the browser is the workaround.

## 17. Function map & provenance

```
   Core (shell-scripts/yt)
     Setup/util : usage, die, is_non_negative_int, validate_enum,
                  require_cmd/require_deps, mpv_supports_vo, convert_seconds,
                  normalize_playback_mode
     Search     : fetch_results, print_list, emit_search_json
     Playback   : run_mpv, warn_audio_only_mode, play_{audio,video,fast,ascii,viz}_url,
                  play_mode_url, have_probe_tools, probe_media_fetchable,
                  play_url_with_probe, play_url_directly,
                  play_url_json, classify_playback_error, format_for_mode
     Lifecycle  : group_alive, stop_group,
                  player_state/player_sock/player_log/player_lock_dir,
                  lock_player_state/unlock_player_state, new_player_id, detach_play,
                  detach_title_updater, reap_dead_players, resolve_target,
                  do_status, do_stop, do_set_volume
     Resolve    : resolve_stream_url (--get-url), resolve_info (--info)
   Wrappers     : yt-search, yt-play   (parse → gate → exec yt)
   Interactive  : yt-tui   (fetch_json → build_all_rows → load_rows → menu loop:
                  display_menu · read_nav_input · move_selection · play_selected ·
                  new_search [read_query_input, Esc cancels] · filter_live → apply_filter)
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
   pid reuse false-positives a dead player   handle is a monotonic id token, not the pid;
                                             liveness checks the pid stored IN <id>.json,
                                             which is reaped the moment its group is gone
   Concurrent title-backfill + set-volume  per-id mkdir lock (lock_player_state)
   clobber the same <id>.json              serializes the two temp+mv patches (§9.3)
   Stale socket after SIGKILL'd mpv          [[ -S sock ]] test → ipc_failed, never hangs
   nc waits full -w1 (mpv keeps socket open) request_id filter + head -1; ~≤1s/call, not
                                             for tight loops (human-driven adjust is fine)
```

## 26. Non-goals / known constraints

- Detached video/ascii/viz (no terminal to render into) — audio only by design.
- Blocking playback (`yt-play <url>` / `-j`) returns only when playback ends; use
  `--detach`+`--status`/`--stop` or `--get-url` for non-blocking agent flows.
- Per-item jq spawning in `fetch_results`/`print_list` is O(results) processes, and
  `print_list` recomputes `duration_fmt` rather than reading the stored field — both
  run once per search behind a network call, imperceptible; left unoptimized.
- `yt-tui` rows are one jq pass over the cached results per search — fine for small N;
  not intended for thousands of results.
- No MCP wrapper (§1). No third-party YouTube client dependency (§2).
- Runtime volume control on DETACHED players IS supported (`--set-volume N [--id ID]`,
  §9.2/§14): each detached mpv runs with `--input-ipc-server=mpv-<id>.sock`, and
  `do_set_volume` sends one `set_property volume` command over that per-instance socket.
  `nc -U` is gated lazily so a bare search never pays for it (§15). `--volume N` remains
  the launch-time STARTING volume; `--set-volume` adjusts it live thereafter.
  Deliberately still OUT of scope:
    - Live volume for FOREGROUND / `yt-tui` playback — those have a real TTY, so mpv's
      own volume keys already work; no IPC needed.
    - `--pause` / `--seek` / mute and other runtime properties — the same per-instance
      socket would carry them (`set_property`/`cycle`), but the wrapper's contract is
      kept narrow; add only when actually needed.
    - Linux `nc -U` portability — macOS-primary tool; BSD `nc -U` is stock, GNU netcat
      variants differ (`ncat -U` works; `netcat-traditional` has no Unix-socket support).
      Accepted as a known gap, noted in a script comment rather than solved now.

## 27. Verification matrix

```
   Syntax     : bash -n on core + all three wrappers/glue (+ repo-wide shell check)
   Search     : yt-search -j → 8-field envelope + count; -J → full; default list;
                flag-after-query ordering; empty-query error
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
   yt-tui     : (tmux PTY) full chrome draws (title w/ ♫ accent · status · hints · '>'-caret selected row · ●○○ pages · bottom filter input);
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
   Verify:                run the empty-argument paths under /bin/bash explicitly —
                          this class is a runtime bash-version behavior, so `bash -n`
                          and shellcheck do NOT catch it; only executing on 3.2 does.
```

If a future feature genuinely needs bash 4+, the honest move is to assert
`((BASH_VERSINFO[0] >= 4))` at the top with a `brew install bash` hint and let PATH
provide it — never hardcode `/opt/homebrew/bin/bash` (breaks Intel macOS + Linux).
