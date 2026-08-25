# AS-BUILT-contract — the uting CLI contract

The **frozen surface** (ROADMAP D3/D13): the one thing that survives any rewrite, and the
acceptance spec for a port. Everything here is as built — verified against the seven scripts —
and versioned by `shell/VERSION` under ROADMAP D13's semver rule. **Changing anything in
this file is a deliberate, documented act** (CLAUDE.md hard rule 4), never a side effect
of a feature.

Written for two readers, neither of whom should need the source:

- **a test author** — every envelope, exit code and error shape needed to write a JSON
  diff test against any of the seven commands is in §1–§5;
- **a third-engine author** — §1.2/§1.3 (the engine's two command surfaces), §2 (its gate),
  §3 (its envelopes) and §6 (the checklist) are the whole obligation; `bili-search` /
  `bili-resolve` satisfy nothing beyond what is stated here.

Rationale lives in `ARCHITECTURE.md` (pointed at throughout); process in
`AS-BUILT-workflow.md`. One fact, one place: the schemas here are stated nowhere else.

## 1. Command specifications

Seven peers, four shapes: the player, an engine's two halves, the UI, and the playlist
store. Every one of them parses its own argv and holds its own gate (ARCHITECTURE.md §4) —
there is no core to delegate to.

### 1.1 `ut-play` — the player (source-agnostic, non-interactive)

- **Owns:** playback, the detached lifecycle, the playback envelope, the exit-code taxonomy,
  `players/`. **Owns no site knowledge:** no yt-dlp call, no cookie decision, no format
  string, no id shape.
- **Flags:** `-f -S -d -j -l -h -V` + long `--engine --volume --detach --json --list
  --status --stop --set-volume --pause --resume --seek --seek-to --queue --enqueue --next
  --id --all --color --help --version`. Color is `--color`
  only (no `-c`); `-S` is the format-sort override (no `-F`) and is forwarded to the engine
  verbatim. `--` ends option parsing: everything after it is the handle (ARCHITECTURE.md §6). At most one
  action per call; `--id` belongs to every verb that ADDRESSES one running player (`--stop`,
  `--set-volume`, `--pause`, `--resume`, `--seek`, `--seek-to`, `--enqueue`, `--next`) and
  `--all` only to `--stop`; `-d` combines with neither an action nor `-f ascii|viz`.
  `--queue` is not an action but a LAUNCH modifier: it requires `-d`, refuses a handle on
  argv, and takes its items from stdin (`-` is its only legal value, as for `--enqueue`).
- **Behavior:**
  ```
   ut-play -- <handle>          play (prose)      ut-play -j -- <handle>   playback JSON
   ut-play -d -- <handle>       detach; concurrent players OK
   ut-play --status             list players      ut-play --set-volume N [--id ID]
   ut-play --stop [--id ID | --all]               stop one/all (--id from --status)
   ut-play --pause | --resume [--id ID]           two idempotent verbs, never a toggle
   ut-play --seek ±N [--id ID]                    RELATIVE; the sign is required
   ut-play --seek-to N [--id ID]                  absolute, seconds
   ut-play -d --queue - < items.json              launch on a QUEUE; the first item plays
   ut-play --enqueue - [--id ID] < items.json     append to a running player's queue
   ut-play --next [--id ID]                       drop this track, start the next (4: none)
   ut-play                      → usage error naming yt-search / uting (D3)
   ut-play -- "some query"      → usage error naming yt-search (whitespace ⇒ not a handle)
  ```
- **Engine selection:** `--engine NAME`, defaulting to `UT_DEFAULT_ENGINE` (default `yt`).
  The name is the command prefix; an unknown one exits 1 naming it (ARCHITECTURE.md §4). **v1 does no URL
  sniffing** — `uting` always knows the engine because it did the search, and an agent
  playing a bare URL says which engine it is. Sniffing (engines declaring URL patterns) is
  deferred until a third engine makes it worth a registry.
- **Gate arms that name the right verb** (what the deleted wrapper's rejections became):
  `-n`/`-m`/`-M`/`-s` → "that is a search flag — use yt-search"; `-J` → "that is an engine
  flag — try `yt-resolve --info -J`"; `--info`/`--transcript`/`--sub-lang` → "that is an
  engine verb"; `--get-url` → the `yt-resolve -j` call that replaced it; any other unknown
  long flag → the list of play flags.

### 1.2 `<engine>-search` — an engine's half one

- **Owns:** one site's query path, its own transport, its own cookie decision, its own
  result shaping and duration formatter, its own gate. **Zero playback or lifecycle logic.**
- **Flags:** `-n -m -M -s -l -j -J --color -h -V`. Positional: a QUERY. A URL is
  rejected, pointing at `ut-play` — including after `--`, which is where the check has to be
  re-applied because `--` stops flag parsing, not argument validation.
- **Envelope:** `{status, engine, query, count, results[]}`, one line (§3).
- **Today:** `yt-search` (yt-dlp) and `bili-search` (curl + jq). Same envelope, different
  transport — the seam is the envelope, not the tool (ROADMAP D11).

### 1.3 `<engine>-resolve` — an engine's half two

- **Owns:** the handle grammar and host allowlist, the mode→format table, the cookie
  decision, the site's read-only verbs, the yt-dlp error vocabulary.
- **Flags:** `-f -S -j -J --color -h -V` + the verbs it has: `--info` (both engines),
  `--transcript --sub-lang` (`yt-resolve` only, D13).
- **Behavior:** ARCHITECTURE.md §10. Non-own-site host → usage error (1).
- **Capability by presence (D13):** what an engine cannot do, it does not have a verb for.

### 1.4 `uting` — interactive terminal UI

- Surface: `uting [--engine NAME] [-n N] [-m S] [-M S] [-s field] [-f audio|video|fast]
  [--volume N] [-p ROWS] [--color auto|always|never] [query]` — search-shaping flags
  forwarded to `<engine>-search`; `-f`/`--volume` playback settings forwarded to `ut-play`
  on every play; `-p` rows/page; rejects all else. `--volume` is launch-time only (no live
  cycle key, unlike `-f`'s `v` — see ARCHITECTURE.md §26). Query optional (prompts if absent). Requires a
  TTY on both stdin and stdout, `jq`, and the sibling verbs.
  `-f` is validated against `audio|video|fast`: playback is detached, and `ascii`/`viz`
  need a terminal (ARCHITECTURE.md §9.2).
  Keys: arrows nav/page · Enter non-blocking play · `Tab`/`p` toggle the two views ·
  `Esc` back to list · `Space` pause · `[`/`]` seek ∓10s · `9`/`0` volume · `s` stop ·
  `v` cycle mode (audio→video→fast) · `e` switch source (hidden with one engine) ·
  `l` switch chrome language (en↔zh, any view) · `t` cycle palette family (any view) ·
  `n` new search · `m` more results · `o` sort · `/` filter · `q` quit ·
  `a` add the focused row to a playlist · `b` open a stored playlist as the row source.
  `a`/`b` appear only when `ut-playlist` is installed (§1.5), the same rule that hides `e`
  on a single-engine install. With a playlist on screen the three keys that RE-FETCH a
  query — `m` `o` `e` — say so and do nothing; everything that works on the rows
  themselves is unchanged. Rows carry their own `engine`, so a list mixing sources plays
  each row under the engine that produced it.

### 1.5 `ut-playlist` — the playlist store (durable, user-level, engine-agnostic)

- **Owns:** the user-level state directory, the playlist file layout, the lock and the
  atomic write, the item record (§3), and the state-error enum. **Owns nothing else:** no
  site knowledge, no playback, no `players/`, no queue.
- **Verbs (exactly one per call):** `--ls` · `--show NAME` · `--add NAME` · `--rm NAME
  --index N` · `--del NAME` · `--rename NAME NEWNAME`. Shared: `-l -j --color -h -V`.
  There is no `--new`: `--add` creates on demand. `--index` is 0-based, as `--show` prints
  it, and belongs to `--rm` alone (a selector with another verb is exit 1, as `--id` is on
  the player).
- **Positional: none.** Every name is attached to its verb, so anything after `--` is a
  caller who meant `ut-play`, and the gate says so.
- **Input — ONE shape, on stdin (`--add`):** JSON, in any of three forms: a **search
  envelope** (`<engine>-search -j` verbatim), this command's own **`--show` envelope** (so
  one list copies into another), or a bare **array of items**. The search-envelope form is
  the point: a search RESULT carries no `engine` field, the envelope does, so only the
  whole package tags items with the engine that produced them.
  Unknown fields are dropped; `engine` and `url` are required per item.
- **Storage:** `$UT_STATE_DIR/playlists/<name>.json`, one file per playlist, `mkdir` lock
  (`.lock-<name>`), temp+mv. The name IS the filename — no slug, because a slug makes the
  name on screen and the name on disk two facts. Names reject `/`, control characters and
  a leading `.`, and cap at 64 characters. **On a case-insensitive filesystem (macOS
  default) two names differing only in case are the same playlist** — accepted and
  documented rather than normalised.
- **Not the player's state.** `players/` is in `$TMPDIR` and dies with the reboot; this
  does not. The queue (a playlist being consumed) stays with the player — a queue that
  survives a reboot IS a playlist (ARCHITECTURE.md §9.4).

## 2. Gating model — one tier, seven self-gating verbs

There is **no wrapper tier**. Each verb accepts only its own surface and points the caller at
the correct tool on a cross-flag; that is what keeps the contracts non-overlapping now that
nothing sits between a caller and an implementation.

```
   <engine>-search                            ut-play
   ─────────────────────────────────         ─────────────────────────────────
   allow: -n -m -M -s -l -j -J              allow: -f -S -d -j -l --engine --volume
          --color -h -V                             --status --stop --set-volume
                                                    --id --all --color -h -V
   reject (→ "use ut-play"):                  reject (→ "use yt-search"):
          -f -d --detach --status                   -n -m -M -s
          --stop --set-volume --id --all      reject (→ "use <engine>-resolve"):
   reject (→ "use <engine>-resolve"):                --info --transcript --sub-lang
          --info --transcript -S                    --get-url  -J
          (-S sorts stream formats; a
           search resolves none)
   positional: a QUERY (reject URLs)         positional: a HANDLE (reject whitespace)
   default: inject -l if no -l/-j/-J         handle required unless
                                             --status/--stop/--set-volume
   both: `--` ends flags; the positional check is RE-APPLIED after it

   ut-playlist
   ─────────────────────────────────
   allow: --ls --show --add --rm --del --rename --index -l -j --color -h -V
   reject (→ "use ut-play"):        -f -d --detach --status --stop --set-volume --all
                                    --engine, and ANY positional (incl. after --)
   reject (→ "use <engine>-*"):     -n -m -M -s --info --transcript
   input: stdin JSON for --add; no positional at all
```

**`--` stops FLAG parsing, not argument validation.** Each verb re-applies its positional
check inside its own `--` drain loop, because that check is the verb's whole point. The
lesson is paid for: `yt-play -- "some query"` once walked past the "not a URL" rejection
that `yt-play "some query"` gave, reached the core, and ran a SEARCH — printing a prose list
or, under `-j`, a full search envelope from the verb whose contract said it plays URLs. A
gate that only guards the spelling without `--` is not a gate. The rule survived the wrapper
that taught it: `ut-play` applies the whitespace test to whatever follows `--`, and
`<engine>-search` applies `reject_url` to every token after it.

**Why the gate stopped being a layer (D7, retired).** The old model was one core plus two
wrappers, and the gate was the wrapper's reason to exist: the core implemented a wide
polymorphic surface (`yt "query"` searched, `yt <url>` played) and the wrapper's job was to
guarantee which half a caller reached. Once search moved to `<engine>-search` and extraction
to `<engine>-resolve`, the player had exactly one verb left — there is no other operation
for a bypass to reach, so there is nothing left for a layer to defend. What the wrapper
contributed that was worth keeping is its ERROR TEXT, and that is what its arms became
(§1.1).

**Why `uting` composes the verbs, never their internals (D8).** `fetch_json` parses the
search envelope, and `<engine>-search`'s URL rejection is what makes "`-j` = search
envelope" unconditional — a URL pasted into the TUI's `n` (new search) prompt must not
become anything but a rejected search. The TUI also passes `--engine` **explicitly, taken
from the envelope's own `engine` field**, never letting `ut-play`'s default decide: with two
engines installed, that default would send the second engine's URL to the first engine's
resolver, which since ROADMAP D12 is a hard usage error instead of the silent mislabel it
used to be. The one sanctioned exception to D8 is the mpv socket (ARCHITECTURE.md §9.3), whose path the
player publishes in the `-d -j` envelope precisely so a client may use it.

## 3. Data contracts (JSON schemas)

Search envelope (`<engine>-search -j`):
```json
{ "status":"ok", "engine":"yt", "query": "lofi", "count": 25,
  "results": [ { "id":"…", "title":"…", "url":"https://www.youtube.com/watch?v=…",
    "channel":"…", "duration":213, "duration_fmt":"00h:03m:33s",
    "view_count":12345, "live_status":"not_live" } ] }
```
`-j` = the 8 result fields above (high-signal, ~4× smaller than the raw ~23-field yt-dlp
entry). `-J`/`--json-full` = same envelope, `results` holds every raw field.
`duration` and `duration_fmt` are **`null` together** when the duration is unknown (a live
stream); `view_count` can be `null` too. On failure the envelope is instead
`{status:"error", engine, query, count:0, results:[], reason}` with the same `reason` enum as
playback, and the exit code is 2+ (ARCHITECTURE.md §7 / §4 here).

- **`engine` is a REQUIRED key of every engine envelope** — search, resolve, `--info`,
  `--transcript`, and each of their error shapes. It is the token that is also the command
  prefix, so a caller holding a result reaches the matching resolver by concatenation
  (`yt` → `yt-resolve`) and `uting` can pass `ut-play --engine <that value>` without a
  mapping table. **This is the field the host allowlist protects** (ARCHITECTURE.md §10, ROADMAP D12): a
  resolver that accepted another site's URL would emit its own name here and the routing
  claim would be false. Every engine emits its own name from one constant (`ENGINE_NAME`)
  rather than deriving it, so the envelope and the filename cannot disagree.
- **`status` is a REQUIRED key too**, `"ok"` or `"error"` — so a caller can branch on one
  field before it looks at anything else, in every envelope the suite writes.
- **Both keys are engine-level, not YouTube-level:** `bili-search` emits the identical
  envelope with `engine:"bili"`. A third engine that omitted either would be
  indistinguishable from a truncated read.

Resolve envelope (`<engine>-resolve -j -f MODE -- <handle>`):
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
  `ytdl_hook` used to do for free (ARCHITECTURE.md §8.1).
- **`http_headers` is a REQUIRED key**, possibly `{}`. This closes the hole the old
  `--get-url` left open: a bare stream URL is not enough to fetch on a host that checks
  `Referer` or pins a `User-Agent`, and the player has no way to invent them. An engine
  must NOT return a credential header here — the player puts these on mpv's argv, where
  `ps` can read them.
- **`format`** is the format string the engine actually used. The player records it in the
  player state file verbatim and never reads it: `bv*+ba/b` is a yt-dlp expression and the
  player does not know that language.
- **`retried`** = the engine fell back to an anonymous client (ARCHITECTURE.md §8.2). The player relays it
  into the playback envelope's `retried`; it no longer observes it.
- **`engine`** = the token that is also the command prefix, so a caller holding a search
  result can reach the matching resolver by concatenation (`yt` → `yt-resolve`).
- Failure → `{status:"error", engine, url, mode, reason}` with the same `reason` enum as
  playback and **exit 2+** — floored to 2, because yt-dlp exits 1 for an unavailable video
  and 1 is reserved for usage errors.

Playback status (`ut-play -j -- <handle>`) — the player's envelope, and the only one with no
`engine` key: the player is source-agnostic and the handle it echoes back is whatever it was
given (ARCHITECTURE.md §4).
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

Playlist store (`ut-playlist`) — the ITEM is the durable record, and it is a subset of a
search result with the envelope's `engine` folded in:
```json
{"engine":"yt","id":"a1","url":"https://…","title":"…","duration":213,"added_at":"…"}
```
`engine` + `url` are exactly the two arguments of `ut-play --engine E -- URL`, so **a stored
record IS a call** — no mapping table anywhere. `channel`, `view_count` and `live_status`
are deliberately NOT stored: playback does not need them and they expire into wrong answers.
`duration` may be null (a live stream), as in the search envelope.

On disk, one file per playlist:
```json
{"schema":1,"name":"chill","created_at":"…","updated_at":"…","count":2,"items":[…]}
```
`schema` is stamped from the first version: this is a file on a user's disk for years, and a
format change with no version field can only be migrated by guessing.

Envelopes (`-j`, one line each):
```
   --ls     : {status:"ok", count, playlists:[{name, count, updated_at}…]}
   --show   : {status:"ok", name, count, items:[item + {duration_fmt}…]}
   --add    : {status:"ok", name, added, count}
   --rm     : {status:"ok", name, removed, count}
   --del    : {status:"ok", name, deleted:true|false}     false = it was already gone
   --rename : {status:"ok", name, from}
   error    : {status:"error", name:NAME|null, reason}
```
`duration_fmt` is **derived on read, never stored** — a stored copy would be a second truth
about the same number. It is emitted so an item is field-for-field row-compatible with a
search result, which is what lets `uting` render a playlist through the same loader.

**The state-error enum is its own, and deliberately not the playback one:**
`not_found | exists | invalid_name | invalid_input | locked | corrupt`. Nothing in a file
store can be `format_unavailable`, and widening a taxonomy that three other readers branch
on would be the wrong kind of sharing. `corrupt` covers both shapes of "this build cannot
read that file": unparseable JSON, and a `schema` newer than the one this build understands
(the field is written by every add and CHECKED on every read — a version nobody reads buys
nothing). Prose goes to stderr in both output modes; the envelope goes to
stdout under `-j` only, exactly as an engine reports an extraction failure.

Lifecycle / resolve:
```
   -d       : {status:"started", id, pid, url, mode, started_at, title:null, sock, log}
              sock/log are handed over so a client never rebuilds the state-dir layout
   --status : {status:"players",
               players:[{id,pid,url,mode,volume,paused,position,duration,title,started_at,
                         queue:{pos,len,next}}…],
               failed:[{id,url,mode,started_at,ended_at,exit_code,reason}…]}
              empty arrays when nothing playing / nothing failed (still exit 0)
              title is null for the first second or two after a detach: the detached CHILD
              resolves (the parent must return in milliseconds) and patches `title` and
              `format` into its own record from the resolve envelope the moment it has one
              volume, paused, position and duration are read LIVE off the player's socket in
              ONE round trip (ARCHITECTURE.md §9.3). volume falls back to the recorded launch/--set-volume
              value; the other three are null when the socket could not be asked or the
              player answered null — null is "could not ask", NOT false/0. position and
              duration are integer seconds and are null until mpv starts decoding (~8s on a
              cold start); duration stays null for a live stream.
              queue is NEVER null on a live player: every detached launch writes one, and a
              lone handle is a queue of length 1 (ARCHITECTURE.md §9.5). It is read off the player's own
              queue file, not off the socket — mpv is handed one URL at a time and never
              learns there is a list. `next` is the item AFTER pos, `null` on the last track.
              url and title follow the TRACK: the child patches its own record each time it
              resolves, so a --status taken ten minutes in describes what is playing now.
              failed[] is the tombstone list — players that DIED on their own, newest first,
              at most 8, nothing older than an hour (ARCHITECTURE.md §9.2). reason is the shared playback
              enum. A player that finished normally or was --stopped is never in it, so the
              array is an error record, NOT the listening history feature (ROADMAP D14/P4),
              which gets its own durable store — this one lives in $TMPDIR and is bounded.
   --set-volume : {status:"ok", id, volume}          (live-adjusted via mpv IPC socket)
                | {status:"not_playing"}             (no target; exit 4)
                | {status:"ambiguous", reason:"multiple_players", players:[{id,pid,title,url}…]}  (exit 4)
                | {status:"error", reason:"ipc_failed"}   (dead/missing socket; exit 4)
   --pause  : {status:"ok", id, paused:true}    --resume : {status:"ok", id, paused:false}
   --seek   : {status:"ok", id, position:<int seconds>}      --seek-to : same shape
              All four take the THREE not_playing / ambiguous / ipc_failed shapes above,
              verbatim and for the same reasons — one target resolution, one exit taxonomy.
              `paused` and `position` are READ BACK off the socket after the command
              succeeded, never computed from what was asked for: mpv clamps a seek at the
              ends of the file, so the number asked for and the number arrived at differ
              exactly when a caller most needs the truth. Both are null if that read-back
              alone failed — the verb still took effect, so it is not an error.
              Seeking past the end is NOT an error: mpv clamps, the envelope reports where
              it landed, exit 0. A live stream has no seekable timeline and mpv refuses;
              that refusal surfaces as ipc_failed (exit 4) rather than as a prediction the
              player made from a null duration — that would be site knowledge it does not hold.
   --enqueue: {status:"ok", id, added:<n>, queue:{pos,len,next}}
   --next   : {status:"ok", id, queue:{pos,len,next}}
              Both take the not_playing / ambiguous shapes above — same target resolution,
              same exit taxonomy — but never ipc_failed: a queue is the player's state on
              disk and no socket is opened. Their two own failures are
                {status:"error", reason:"queue_empty"}   --next with nothing after this track
                {status:"error", reason:"queue_failed"}  the queue file could not be written
              both exit 4, both well-formed calls that did not take effect. `queue` is READ
              BACK off the file after the write, never predicted — the same rule --seek
              follows for `position`: --next moves the position in the PARENT and only then
              signals the child, so the envelope reports a queue that is already on disk.
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
              summarise-this case the verb exists for (ARCHITECTURE.md §22, token efficiency). `chars`
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
              error → {status:"error", engine, url, reason} with exit 1, mirroring --info
              (engine, like everywhere else, is required). reason
              is the shared enum plus `no_subtitles_available`, which also covers a track
              that parses to zero usable cues (an empty transcript is a miss, not an
              empty success — a caller handed {"text":""} would summarise silence).
```

**The queue's input is stdin, in three shapes** — the same three `ut-playlist --add` takes,
for the same reason: a search result does not carry `engine` (that field is on the
ENVELOPE), so only taking the whole envelope can label an item with the source it came from.
`--queue -` and `--enqueue -` accept a bare item array, a `ut-playlist --show -j` envelope
(`.items`), or a search envelope (`.results`); an item is
`{engine, url, title?, duration?}` and `--engine` is only the fallback for an item without
one, so ONE queue may mix sources. Everything else about the payload is a usage error (**1**)
raised in the caller's own shell before any player is addressed: unparseable JSON, none of the
three shapes, zero items, a url with whitespace in it, an engine name that is not
`[a-z0-9][a-z0-9_-]*`. The url is checked no further than a handle on argv is — which ids are
good is engine knowledge — but the engine NAME is validated here because it becomes a command
name inside a detached child, where a `die` would only reach a log.

**A queue is resolved JUST IN TIME, one track at a time.** A stream URL expires in hours, so
a queue resolved at enqueue time would 403 halfway down; the price is a gap between tracks
(the engine round trip) and the design decision is ARCHITECTURE.md §9.5. One consequence is
contractual: a queued item that fails to resolve does NOT kill the player. The queue advances
and the track gets its own tombstone in `failed[]`, keyed `<id>-q<pos>` — a track that did
not play, in the same shape as a player that did not play, so a caller reading `failed[]`
sees a named gap rather than a silent one.

On disk (runtime state, dies with the player — it is not a playlist):
```json
{"schema":1,"pos":0,"items":[{"engine":"yt","url":"https://…","title":null,"duration":null}]}
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

**Wrong-engine handles are a USAGE error, not an envelope.** `<engine>-resolve` given a URL
whose host is not its own site's exits **1** with a message on stderr and writes no envelope
at all — nothing was attempted and nothing is retryable, so it is the same class as
`--engine nope` and must not be confused with an extraction failure (2+) that a caller might
retry. This is a contract on every engine, present and future: the host allowlist is an
explicit list per engine (ARCHITECTURE.md §10), never a substring match. The bare-id path is the same rule
in the other direction — an id that does not match this engine's shape is also 1.

**One envelope, one line.** Every `-j` / `-J` payload the suite writes to stdout is a single
line of JSON — search, resolve, `--info`, `--transcript`, `-d`, `--status`, `--stop`,
`--set-volume`, and every error shape above. That is what makes the output usable as NDJSON:
a caller can read one line, parse it, and be done, without a streaming parser or a brace
counter. It also makes `-J` a *strict superset of `-j`* in shape as well as in fields.

The rule was violated for a long time by the two oldest read verbs. Search emitted 26 lines
for `-j -n 3` and 76 for `-J`, `--info -j` emitted 16, the resolve verb (then spelled
`--get-url`) was pretty too, and
`--status` was compact only while the player list was **empty** — it pretty-printed as soon
as a player existed, i.e. exactly when something is polling it. Every one of those was a bare
`jq` where the lifecycle verbs had always used `jq -nc`; the fix was `-c` at five sites
(`emit_search_json` ×2, `resolve_info`, `emit_stream`, the `--status` `jq -s`). The
state files under `players/` are *not* covered by this rule and stay pretty — they are an
on-disk record read by jq, not an envelope.

## 4. Exit codes, TTY, dependencies

```
   0    success; also --status/--stop (always); 130 normalized (SIGINT; clean q already exits 0)
   1    usage/validation error (die), a verb's flag-gating rejection, uting's non-TTY
        refusal, conflicting actions, no handle (D3), a handle with whitespace in it,
        --id/--all outside a lifecycle verb, -d with an action or with -f ascii|viz,
        a `--seek` value without a sign (`--seek 30`) or a negative `--seek-to`,
        a queue payload this process could not use (`--queue`/`--enqueue`: bad JSON, none
        of the three stdin shapes, no items, a url with whitespace, a bad engine name) —
        refused in the PARENT, so a malformed queue never reaches a player,
        `--queue` without `-d`, with an action, or with a handle on argv,
        an unknown --engine, a URL whose host is not this engine's (ARCHITECTURE.md §10 / §3 here),
        --info / --transcript fetch failure (incl. no_subtitles_available)
   2+   propagated yt-dlp / mpv / HTTP failure (playback, resolve -j, SEARCH failure —
        search reports 2 even when yt-dlp exits 1, so a tool failure is never confused
        with 1). A handle the engine cannot resolve lands HERE, not in 1: the player
        cannot judge an id's shape, so "bad id" is an extraction outcome (ARCHITECTURE.md §6).
   4    --set-volume / --pause / --resume / --seek / --seek-to / --enqueue / --next /
        --stop: did not take effect — no such player, no player, ambiguous target, or mpv
        IPC failure; for the two queue verbs also `queue_empty` (--next with nothing after
        the current track) and `queue_failed` (the queue file could not be written), which
        are the only two that never involve a socket. The -j status/reason says which. The split is the point: a MALFORMED call is 1 and never
        reaches a player (`--seek 30`), a well-formed one mpv would not do is 4
        (`--seek +30` with nothing playing).
        Distinct from 1 (usage) and 2+ (propagated player failure). --stop treats
        "nothing playing" as idempotent success (exit 0); only ambiguity is exit 4.
        ALSO ut-playlist, for the same meaning — the call was well formed and the
        store could not answer: `locked` (held by another writer; it fails rather
        than writing unlocked, because this store is durable and an unlocked write
        can drop what the user just added), `not_found` (a verb naming a playlist
        that is not there), `exists` (--rename onto a name already taken), and
        `corrupt` (a file this build cannot read). 1 is left to mean what it means
        everywhere else in the suite: the CALL was malformed — `invalid_name`,
        `invalid_input` (bad stdin, an out-of-range --index). --del on a missing
        playlist is idempotent success (0, `deleted:false`), the same rule as --stop
        with nothing playing.

   TTY  : uting requires BOTH stdin and stdout (ARCHITECTURE.md §11). No other verb ever needs one —
          each errors on empty input rather than prompting (D1/D3).
   deps : they are per-FILE now, which is the point of the split —
          ut-play      : jq + mpv to play; --status/--stop need only jq (--status uses
                         nc opportunistically for the live read and degrades to the
                         recorded volume plus three nulls without it); every socket verb
                         (--set-volume, --pause, --resume, --seek, --seek-to)
                         needs jq+nc (nc gated lazily so a plain play never demands it).
                         The queue verbs (--queue, --enqueue, --next) need only jq: a
                         queue is a file, and --next reaches the player with a SIGNAL.
                         It needs NO yt-dlp and no curl.
          yt-search / yt-resolve / bili-resolve : yt-dlp + jq. curl is an OPTIONAL soft
                         dep of yt-resolve, for the client probe (ARCHITECTURE.md §8.2).
          bili-search  : curl + jq — curl is REQUIRED here; it is the transport.
          uting        : jq, plus the verbs it composes. ut-playlist is OPTIONAL —
                         absent, the two playlist keys say so and nothing else changes.
          ut-playlist  : jq only. No network, no yt-dlp, no mpv.
          BSD `nc -U` is stock on macOS; the Linux netcat `-U` gap is a known,
          documented limitation (ARCHITECTURE.md §26 / script comment).
   -V   : every entry point answers it BEFORE any dependency gate, reading shell/VERSION
          and printing its own name — needing yt-dlp installed to learn your version is
          backwards, and seven executables must not be able to disagree (ARCHITECTURE.md §4).
          Asserted over every file in shell/ that has a shebang, not over a list of names.
```

## 5. Configuration surface

Per-request choices are flags; set-once tuning is environment variables — deliberately
kept out of flags to keep each verb's flag surface narrow.

```
   Flags (per call):  -n -m -M -s -f -S -l -j -J -d -h -V --color --theme --engine
                      --detach --status --stop --info --transcript --sub-lang
                      --set-volume --pause --resume --seek --seek-to --queue --enqueue
                      --next --id --all --volume
   Env (set once):    UT_STATE_DIR  (default ${XDG_STATE_HOME:-~/.local/state}/uting) =
                        the USER-LEVEL, durable state root — today `playlists/`. Distinct
                        from the player's runtime state in ${TMPDIR}/uting-$(id -u), which
                        is erased on reboot; nothing a user built by hand may live there.
                        XDG rather than ~/Library/Application Support because the user
                        surface is a terminal and a Linux port needs no second layout.
                        Not a convenience knob: tests/contract.sh sets it, and without it
                        the suite would write into the user's real playlists.
                      UT_DEFAULT_ENGINE   (default yt) = which engine --engine defaults
                        to. Read by BOTH ut-play and uting, deliberately the same
                        variable: a user who picks a default source once should not
                        have to pick it again per surface. uting falls back to the
                        first installed engine when the name is not present.
                      YT_COOKIE_BROWSER   (default chrome = login on; "none" = anon-only)
                        — read by each ENGINE, never by the player.
                      YT_AUDIO_FORMAT (ba)  YT_VIDEO_FORMAT (bv*+ba/b)
                      YT_VIDEO_FORMAT_FAST  — the mode→format table's values; they live
                        with the table, i.e. in each <engine>-resolve.
                      YT_ASCII_VO (tct)  YT_MPV_INPUT_CONF  — player-side, mpv knobs.
                      YT_ASCII (1 = ASCII glyph fallbacks; auto-on for a non-UTF-8 locale;
                        read by the player and uting — legacy alias YT_TUI_ASCII).
                        Covers the WHOLE glyph set: ♫ ● ○ ❯ · ▶ ❚❚ • … → — ↑/↓ ←/→ ↵ ▘▝▗▖
                        and the bar/rail runs. Verified by asserting a rendered pane
                        holds no non-ASCII beyond the label text.
                      YT_LANG (en|zh) = language of uting's menu chrome; default zh
                        under a zh* locale, English otherwise. Help output, errors and
                        the card's field labels stay English in both.
                      YT_THEME (minimal|mono|catppuccin|tokyonight|nord|gruvbox|
                        onedark) = uting palette family (ARCHITECTURE.md §11: one accent + one status
                        hue; community themes are 24-bit only under COLORTERM=truecolor).
                        --theme beats env; the t key cycles it live at runtime.
                      YT_BG (auto|light|dark) = background mode; auto chain:
                        $COLORFGBG → OSC 11 query → dark. Light = the theme's own light
                        variant (minimal swaps cyan for blue).
                      YT_SYNC (0|1|auto) = synchronized redraws (DCS 1q/2q; auto: on,
                        off under tmux).
                      YT_BRAND (=1: header wordmark in math sans-serif bold, ARCHITECTURE.md §11 glyph
                        section; opt-in, ASCII mode wins).
                      NO_COLOR (=1: --color auto renders plain; explicit --color wins).
   Internal (set by the player for its own detached child, not a user knob):
                      YT_IPC_SOCK (per-player mpv IPC socket)  YT_DETACHED (=1: no
                      terminal, so quiet mpv + no stderr filter)  YT_PLAYER_ID (which
                      record the child backfills title/format into, ARCHITECTURE.md §9.1)
   Test-only:         YT_TEST_LIFECYCLE (=1 arms tests/lifecycle.sh, which starts real
                      players; unset it and the suite skips rather than making noise)
   (color MODE is the --color flag, NOT an env var — the scripts hardcode
    COLOR_MODE=auto at startup and only --color changes it, so a COLOR_MODE env
    value is never read. Theme and background ARE env-read: YT_THEME / YT_BG.)
```

**The `YT_` prefix is historical and deliberately not churned.** The suite is `uting` and
the new engine knob is `UT_DEFAULT_ENGINE`, but renaming a dozen working variables would
break every user's shell profile to buy consistency in a doc. New knobs use `UT_`; existing
ones keep `YT_`.

Cookie handling: `YT_COOKIE_BROWSER` is presence-checked per platform (does the
browser's profile dir exist); if absent, extraction runs without cookies rather than
breaking. Reading a browser's cookie DB while it is running can yield a locked read and
silently degrade to unauthenticated extraction — closing the browser is the workaround.
**Only engines read it**, so the player has no cookie code path to leak one.

## 6. Adding an engine — the checklist

Pointers only; every obligation is stated once above. A new source `foo` ships exactly two
executables and changes nothing else (ROADMAP D9):

1. **`foo-search`** — the surface of §1.2: flags `-n -m -M -s -l -j -J --color -h -V`,
   a QUERY positional (URLs rejected, re-checked after `--`), the §3 search envelope with
   `engine:"foo"`, errors per §3 with exit 2+ (§4).
2. **`foo-resolve`** — the surface of §1.3: flags `-f -S -j -J --color -h -V` plus only the
   verbs the site supports (§1.3: capability by presence); the §3 resolve envelope
   (`stream_urls[]` video-first, `http_headers{}` required and credential-free, `format`
   opaque, `retried`); an explicit own-host allowlist — a non-own URL or malformed id is a
   usage error, exit 1 (§3).
3. **Both halves**: `ENGINE_NAME` emitted from one constant; `status` and `engine` in every
   envelope including errors; one line per envelope (§3); `-V` answers before any
   dependency gate (§4); the gate points cross-flags at the right verb (§2).
4. **Nothing else**: no playback, no lifecycle, no `players/` writes — the player finds
   `foo-resolve` by name (§1.1) and `uting` discovers the pair by scanning for
   `foo-search` + `foo-resolve` on PATH and beside itself (ARCHITECTURE.md §11).

The engine picks its own transport per verb (curl or yt-dlp or anything else) — the seam
is the envelope, not the tool behind it (ROADMAP D11).
