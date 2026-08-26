# AS-BUILT-engine — what an engine is: `<name>-search` + `<name>-resolve`

The implementation of the two halves that know a **site**: `yt-search` / `yt-resolve` and
`bili-search` / `bili-resolve`. Query shaping and the search error contract, the Bilibili
HTTP transport, the login / PO-token probe, handle grammar and the host allowlist, the
resolve envelope, `--info` and `--transcript`. **Every site-specific fact in this suite is
described here or it is a layering violation** — the player is source-agnostic, the TUI is
pure orchestration.

**This is the document a third engine's author reads**, next to the checklist in
`AS-BUILT-contract.md` §6.

**The division of labour.** `ARCHITECTURE.md` keeps the diagrams, the topology, the seams
and the decisions; the contract surface (argv, envelopes, exit codes) is
`AS-BUILT-contract.md`; how an engine actually lands — which rule was forced by a
measurement, and which holes were dug and filled — is here. The playback subsystem and the
detached lifecycle are `AS-BUILT-player.md`'s.

**Section numbers are inherited** from `ARCHITECTURE.md`'s original numbering (§7, §8.2,
§10 and its subsections), so an existing `§10.1` citation only changes filename, never
number. That is why §8.2 appears here without a §8: §8 is the playback subsystem and stays
with the player — 8.2 was always engine knowledge filed under a player heading, and the
split is what makes that visible.

**The code is the only authority.** Function names here are soft references (file +
function); pseudo-code is a shape, not a copy of the source.

**One thing this document deliberately does not own**: what a `-f MODE` *means* as a format
string is engine knowledge (`format_for_mode()` lives in each `<engine>-resolve`), but the
mode→format→mpv table is stated once, beside the player's mpv option set, in `AS-BUILT-player.md` §8.1.

---

## 7. Search subsystem — a verb of the ENGINE

Search is half of an engine (`ARCHITECTURE.md` §4), so this section describes `yt-search`;
`bili-search` is the same envelope over a different transport (§7.1) and its argv is
specified in AS-BUILT-contract.md §1. Everything below —
the single jq program, the internal `FILTERED_JSON` shape, the duration rules, the error
contract — is what BOTH halves implement, and the two files each carry their own copy on
purpose: an engine that shared a library with another engine would be a library the player
would eventually have to know about (`ARCHITECTURE.md` §4).

```
  QUERY, NUM_RESULTS, MIN/MAX_DURATION, SORT_FIELD, cookies
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
        "♫ N. title / dur /       {status,engine,query,count,results:[ project ]}
         views / url"             json: 8 lean fields; json_full: raw
```

`engine` is in the envelope because a caller holding a result must be able to route it back
to the resolver that understands it — `ut-play --engine <that value>` (AS-BUILT-contract.md §3, D12). It is the
field the host allowlist (ROADMAP D12) exists to keep honest.

`print_list()` reads the **`FILTERED_JSON` variable**, not the emitted `-j` stream.
Projection happens only at the emit point, so the JSON contract can change without
touching that consumer. (Schemas → AS-BUILT-contract.md §3.)

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
and `uting` shows `● LIVE`.

**Duration bounds (`-m`/`-M`) are enforced CLIENT-SIDE, in that same jq pass.**
`--match-filter` is only a cheap server-side pre-filter, and is sent **only when a bound was
actually requested** (the old always-on `duration > 0` filtered nothing). Reason: with
`--flat-playlist` yt-dlp marks entries "incomplete", so a filter on a field a flat entry
does not carry — a live stream has no duration — cannot decide and KEEPS the entry. Verified:
`-m 999999` used to still return a live result; now `-m`/`-M` exclude unknown-duration
entries as the flag implies.

**Search has an error contract like every other surface.** A yt-dlp failure used to abort on
`set -e` with raw stderr even under `-j`, handing an agent a jq parse error. `fetch_results`
captures stderr, classifies it with the engine's own `classify_yt_dlp_error` (the enum is
shared, the classifier is not — AS-BUILT-contract.md §3), and emits
`{status:"error", engine, query, count:0, results:[], reason}` for `-j`/`-J` (prose: the captured
stderr plus a `die`). Exit is 2+ — never 1, which AS-BUILT-contract.md §4 reserves for usage/validation.

### 7.1 The Bilibili transport — the same envelope over a hand-built request (D11)

`bili-search` implements everything above over `curl` + `jq` instead of yt-dlp. The split
is not a preference, it is the only combination that works (measured, ROADMAP D11):
yt-dlp's `--flat-playlist` answers in 0.9s with **zero metadata** (`BiliBiliSearchIE` yields
`url_result(arcurl, aid)` and drops the title/author/duration/play sitting in the response
it just parsed), and a full extraction recurses into every part of every collection —
this site's music results are overwhelmingly multi-part — so `bilisearch10:` did not finish
in 120s. One hand-built request answers in 0.71s with every field the envelope needs.

`fetch_page_once` is **the only place in the suite that builds an HTTP request by hand**
(`ARCHITECTURE.md` §5). Arguments reach curl as an ARRAY and the query values through `--data-urlencode`, so
a query containing `&`, a space or a quote is a value and never a second parameter:

```
   GET <search/type>  search_type=video · keyword=<QUERY> · page=<N>
       -H "User-Agent: $BILI_UA"          # a browser UA; must not contain `curl`/`python`
       -H "Referer:    https://www.bilibili.com/"
       [-H "Cookie: buvid3=<uuidgen>infoc"]
       --compressed --max-time 15 --retry 0        # the retry decision is the caller's
   ok ⇔ curl rc 0 AND http 200 AND the body's own `.code == 0`
```

Three request facts, each forced by a measurement rather than chosen:

- **The `Referer` is required and is the only thing that is.** With it the endpoint answers
  `code:0`, without it 412 (measured 2026-08-23). It is a public constant, not an
  authentication mechanism — every Bilibili extractor in yt-dlp sends the same one.
- **The `buvid3` is a DEVICE identifier, not a credential**: no account, no token, nothing
  read from a browser profile — the engine generates a random one (`uuidgen` + `infoc`, the
  shape yt-dlp itself uses) and throws it away when the process exits. It is
  **correctness, not optimisation**: six consecutive searches scored 200 200 412 412 412 200
  anonymously and 200 six times with a stable buvid3 (measured 2026-08-23).
- **`BILI_UA` is overridable** because the site is known to start refusing a UA that has
  gone stale (yt-dlp carries a commit for exactly that), and a suite that cannot be nudged
  without an edit would need a release to survive it.

**The hand-written HTTP path never touches a credential**, and that is the line through the
middle of this engine: login state reaches only yt-dlp, in the resolve half, through
`--cookies-from-browser`. It is what keeps the D11 answer to "why not a full client"
("that whole block belongs to yt-dlp") true of the search half as well.

**Retry is classified, not blanket.** `classify_http_error` maps rc/http/`.code` onto the
suite's reason enum, and only the `network` class earns a second attempt after
`RETRY_PAUSE`; a `forbidden` or `unavailable` answer will say the same thing a second later,
and asking again is another request against a host that counts them. Everything else fails
straight to `search_fail` — exit **2**, never 1 (AS-BUILT-contract.md §4).

**Paging stops on either condition.** Pages are requested only while the caller still wants
rows *and* the site is still sending them (`MAX_PAGES` caps the rest), so a short tail does
not cost `MAX_PAGES` round trips. An exhausted or empty search omits `data.result` entirely
rather than sending `[]`, which is why the read is `.data.result // []`.

**The shaping is the same one jq program** — with one extra job, because this transport
returns a *search API's* record rather than an extractor's. The normalised fields are merged
**over** the raw record, so `-J` keeps every field the site sent while `-j` projects the same
eight fields `yt-search` projects, and `title`/`duration` are the cleaned, correctly-typed
values in BOTH — no surface can be handed the HTML or the `"MM:SS"` string. Two normalisations
worth naming: `url` is built from the `bvid` rather than taken from `arcurl` (the `av`
spelling, served over `http://`), because the canonical BV URL is what a caller hands back to
`bili-resolve`; and `live_status` is **`null`, not the raw `0`** — under `search_type=video`
that field is not the suite's is_live/was_live notion at all, and carrying the 0 over would
let a renderer draw a liveness state the site never claimed. A field an engine cannot know is
null, and the key is still present (AS-BUILT-contract.md §3).

## 8.2 Login, PO tokens, and the probe-then-play client pick — **inside `yt-resolve`**

This whole subsection is YouTube-engine knowledge and lives in `shell/yt-resolve`. It is
specified here because it is the reason the resolve envelope carries `retried`, and because
"probe **then** play" is now literally true: the probe happens one process before mpv starts,
in the engine, and the player only relays the verdict. `bili-resolve` has no probe — the site
has no PO-token equivalent — which is the model for what a second engine may simply not have.

**Login is ON by default (`YT_COOKIE_BROWSER=chrome`)** — a setting each ENGINE reads for
itself — so login-gated / members /
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
`probe_raw` takes the first media URL out of the record already resolved — it makes no
second extraction — and issues an
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
scoping) so the chosen resolve drops cookies without touching the real setting; the verdict
surfaces as `retried` in the RESOLVE envelope, and `ut-play` relays it into the playback
envelope's `retried` rather than observing it (AS-BUILT-contract.md §3). Cost: one extra
resolve + 1-byte GET per play (two on a cookie-403 video). `curl` is a soft dependency —
without it the probe is skipped and the old play-fail-replay retry runs (the error-dump
regression reappears only there). `YT_COOKIE_BROWSER=none` forces anonymous-only (no
keychain read, no probe); a configured browser with no local profile auto-degrades to
anonymous rather than erroring.

## 10. Resolve — the engine's half two

`<engine>-resolve` turns a **handle** into everything needed to play it, and carries the
site's read-only verbs. It never plays: no mpv, no lifecycle, no `players/`.

```
   <engine>-resolve [-f MODE] [-S SORT] [-j|-J] -- <handle>   stream URLs + headers
   <engine>-resolve --info [-j|-J] -- <handle>                metadata only
   yt-resolve --transcript [--sub-lang L] [-j|-J] -- <handle> captions as clean text
```

**The handle grammar is per-engine, and so is the host allowlist (ROADMAP D12).**
`normalize_target` accepts a URL on one of THIS engine's hosts, or this engine's own media
id shape:

| Engine | Hosts accepted | Bare id shape |
|---|---|---|
| `yt-resolve` | `youtube.com`, `youtu.be`, `youtube-nocookie.com` + their subdomains | exactly 11 chars of `[A-Za-z0-9_-]` |
| `bili-resolve` | `bilibili.com`, `b23.tv` + their subdomains | `BV…` / `av…` |

An **explicit list, not a substring test**: `*.youtube.com` matches `music.youtube.com` and
refuses `evilyoutube.com`, which a bare `*youtube.com*` would wave through.

**A URL from another site is a usage error (1), not an extraction failure (2+).** Nothing
was attempted and nothing is retryable — the caller named the wrong engine, which is the
same mistake as `--engine nope` and scores the same. This closes a hole that *worked*, which
is why it survived so long: both resolvers used to hand any http(s) URL to yt-dlp (1700+
supported sites), so a Bilibili URL resolved fine through `yt-resolve` and came back labelled
`engine:"yt"` — a lie in the one field whose entire job is routing a result back to the
resolver that understands it. The cost is recorded honestly: URL-only sources (Bandcamp,
Apple Podcasts) that used to play by accident no longer do, and the fix for those is a pair
of their own, never a looser host check.

```
   resolve_stream(handle):                      # the bare verb — what ut-play calls
      yt-dlp --dump-single-json --no-playlist -f <format_for_mode(MODE)>
             [--format-sort SORT] [--cookies-from-browser B]
      → probe (yt only, §8.2) may re-resolve anonymously and set retried
      prose: print the stream URL(s)
      -j:    {status,engine,id,url,title,duration,mode,format,stream_urls[],http_headers{},retried}
      -J:    the full raw yt-dlp record
      error: {status:"error",engine,url,mode,reason}, exit 2+
```

`stream_urls` is **video first**: element 0 is what a player opens, element 1 — present only
when the chosen format merged two streams — is its separate audio track. `http_headers` is
**required, possibly `{}`**. Full schema and the reasoning for both: AS-BUILT-contract.md §3.

### 10.1 Metadata-only (`--info`)

Read-only, non-blocking, side-effect-free; needs yt-dlp+jq but never mpv. **Both engines have
it.** Reason it exists: without it an agent that wants to know *what* a video is (description,
chapters, uploader, date, like count) has to leave the ecosystem and drop to raw
`yt-dlp --dump-json` — the same escape-hatch failure the JSON search surface removed.
LLM-first, not human ergonomics (contrast the rejected `--url-only`, which strips grounding
signal): `--info` *adds* the grounding an agent reasons over. `duration_fmt` comes from the
engine's own `JQ_PRELUDE` `fmt_dur` (§7), so within an engine `--info` and search cannot
drift on the format — and it is `null`, not `"00h:00m:00s"`, when the duration is unknown.

```
   resolve_info(handle):
      yt-dlp --dump-single-json --skip-download
             [--cookies-from-browser B]   # only when login opted in
             --no-warnings --quiet
      prose: readable block (title/channel/date/duration/views/likes/live/url,
             then Chapters M:SS, then Description)          (die on failure)
      -j:    lean, high-signal projection mirroring search -j field discipline:
             {status,engine,id,title,url,channel,uploader,upload_date,duration,duration_fmt,
              view_count,like_count,live_status,description,chapters}
             chapters = [{start_time,end_time,title}] | null
      -J:    full raw yt-dlp record (fidelity escape hatch, same role as search -J)
      error: -j/-J → {status:"error",engine,url,reason} exit 1 ; prose → die
```

`bili-resolve --info` fills `channel` from `.channel // .uploader` because that extractor
populates one or the other by record — **the envelope's shape must not depend on which**.
That is the general rule for an engine: normalise to the contract, never publish the
extractor's variance.

### 10.2 Captions (`--transcript`) — a verb `bili-resolve` does not have (D13)

`yt-resolve --transcript` fetches a caption track and cleans it into text that can be dropped
straight into a prompt. Envelope, the `-j`/`-J` split, and the one-yt-dlp-call constraint:
AS-BUILT-contract.md §3, which is also where the `no_subtitles_available` reason is specified.

**Bilibili serves no captions, so `bili-resolve` has no `--transcript` at all** — the flag is
not accepted and the help does not list it. This is the capability rule in the small: an
engine says what it cannot do by *not having the verb*, rather than by publishing one that
always answers "none", which a caller cannot tell apart from a bad day or a rate limit.
