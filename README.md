# uting

**u-ting / 你听** — an agent-first YouTube engine with a terminal face.

Search YouTube, play it through mpv detached from your terminal, and keep controlling it — from a
TUI if you are a human, from a single-line JSON contract if you are a program.

```sh
ytt                                    # interactive: search, browse, play, control
yt-search -j -n 25 -- "lofi hip hop"   # machine: one line of JSON out
yt-play -d -j -- "<url>"               # machine: launch detached, get {id, pid, sock}
yt-play --transcript -j -- "<url>"     # machine: captions as clean text + timed segments
yt-play --status -j                    # machine: what is playing, where, how loud
yt-play --stop --id <id> -j            # machine: stop it
```

## Status

**Reference implementation.** This is a working shell suite that its author uses daily, published
together with a design document that is longer than most of the code it describes. It is not
packaged: there is no installer and no Homebrew formula, and none is planned for the shell version
(see [`docs/ROADMAP.md`](docs/ROADMAP.md) for why, and for what a Go rewrite would change).

The document may be the more useful artifact. `docs/SPEC-system.md` records things that are usually
learned and then forgotten: East-Asian-width handling in a terminal renderer, DCS frame
synchronisation, correlating mpv IPC replies by `request_id`, and the `set -e` traps that bash 3.2
sets for you.

## What it is

- **`ut-play`** — the player. Source-agnostic: it drives mpv, owns the detached player lifecycle
  (id / pid / socket / lock / state dir / reap), and defines the contract. It never searches and
  never extracts, so it knows nothing about YouTube.
- **`yt-search` + `yt-resolve`** — the YouTube *engine*, a pair. Search turns a query into results;
  resolve turns a result id (or a URL) into a direct stream URL plus the HTTP headers it must be
  fetched with, and also answers `--info` and `--transcript`. Everything site-specific lives here:
  the yt-dlp calls, the cookie decision, the format-per-mode table. Adding a source is adding a pair.
- **`yt-play`** — a narrow verb wrapper over the player, deliberately single-purpose with mutually
  exclusive flags rejected up front, because that is what makes it safe for a small model to call.
- **`yt-tui`** — the human face. Self-rendered list and focus card, live filter, pagination that
  reflows against the measured chrome, three playback states, en/zh chrome, ASCII fallback, themes.
  No TUI framework, no fzf.

The pieces a program depends on: a **single-line JSON envelope**, an **exit-code taxonomy**
(1 usage / 2+ propagated tool failure / 4 didn't take effect), and a **player lifecycle** that
survives the terminal that started it.

## What it is not

Not a general-purpose terminal music player. That layer is full and well maintained — cmus,
ncmpcpp, rmpc, musikcube, kew, termusic. So there is **no queue, no playlist management, no
listening history, no favourites, no downloader, no channel subscriptions**, and their absence is a
scope decision rather than a gap. The TUI's job ends at: find it, play it, watch it play, control it.

## Requirements

- **macOS first.** Linux is not currently usable: the stock netcat has no `-U`, which the mpv IPC
  path needs.
- `yt-dlp`, `jq`, `mpv`, `nc` (BSD netcat ships with macOS). `curl` is an optional soft dependency.
  They are not all needed by all of it: `yt-dlp` (+ optional `curl`) belongs to the engines, `mpv`
  and `nc` to the player, `jq` to both.
- bash 3.2 — the version macOS ships. The suite is written to that floor on purpose; see
  `docs/SPEC-system.md` §28.

Nothing is vendored. Install yt-dlp and mpv however you normally would.

## Try it

```sh
git clone git@github.com:binlecode/uting.git
cd uting
./shell/yt-tui "lofi hip hop"     # or: ./shell/yt-tui  and type a query
```

For daily use, symlink onto your PATH — the TUI under the short name you type by hand, the
two agent-facing wrappers under their own names:

```sh
ln -s "$PWD/shell/yt-tui"    ~/bin/ytt
ln -s "$PWD/shell/yt-search"  ~/bin/yt-search
ln -s "$PWD/shell/yt-resolve" ~/bin/yt-resolve
ln -s "$PWD/shell/yt-play"    ~/bin/yt-play
```

The older `yts` / `ytp` spellings are **deprecated**. Nothing in the suite reads its own
`argv[0]`, so an existing `~/bin/yts` keeps working — it is simply no longer a documented
name, and one name per command is the point.

`ut-play` itself is reached through a path relative to the wrappers and is deliberately **not** put
on PATH yet — it is still internal while the restructure is in flight. It goes on PATH, and
`yt-play` goes away, at `docs/PLAN-ut-restructure.md` step B-3.

`ytt --version` (or `-V`) answers before any dependency check, so it works on a machine that has
not installed yt-dlp or mpv yet — which is exactly when you want to know what you have. All five
entry points report the same number: it is declared once, in `shell/VERSION`.

## Keys

`↑/↓` select · `←/→` page · `Enter` play · `Tab` focus card · `/` filter · `n` new search ·
`m` more results · `o` sort · `v` playback mode · `Space` pause · `9/0` volume · `s` stop ·
`l` language · `q` quit

## Tests

Verification rigs, not a unit-test suite — what this code gets wrong is renderer and protocol
behaviour, which only a real terminal and a real socket can show. tmux IS that terminal, so
nothing here hand-rolls a pty. Each file's header says what it proves; run any of them
directly.

| Rig | What it is for |
|---|---|
| `tests/assert_pane.py` | Layout invariants on a captured pane: nothing exceeds the pane width (measured in cells), every row's title starts on the same column, the duration rail is right-flush at exactly the pane width, and the boundary rail is full width in both its static and its live form. |
| `tests/mpv_ipc_mock.py` | A fake mpv JSON-IPC peer that can do what the real one will not do on cue: answer out of order (`--reverse`), report a property as null (`--null pause`), start out paused (`--paused`), interleave async events, walk the clock, and never close its side of the socket. Every IPC rule in the read path exists because of one of these shapes. |
| `tests/contract.sh` | The CLI contract, asserted by running it: the search and resolve envelopes, the player's engine seam (an unknown engine is usage, a dead media id is a propagated failure that still carries a reason), every documented rejection, `--transcript` both ways, the lifecycle verbs, the live `--status` read (against the mock, over a real socket), the tombstone record for a player that died unasked, and the exit-code taxonomy. |
| `tests/tui_pane.sh` | The TUI against a real terminal (tmux): layout at four geometries plus the chrome variants, redraw-on-resize with no keypress, the in-place repaint rule (a keypress emits no screen-clear), and the fetch spinner actually turning. Starts no playback. |
| `tests/lifecycle.sh` | The detached-player lifecycle, whose bugs are **processes**: detach returns before mpv is up, two players, an ambiguous mutation → exit 4, a targeted one moves only its target, `Starting` → `Playing` flipping on the tick with no keypress, and zero orphan mpv at the end. Starts real players at `--volume 0`, so it is gated behind `YT_TEST_LIFECYCLE=1`. |

The two `.sh` rigs need `tmux`; `contract.sh` skips its live-read block without `python3` (it
drives the mock). There is no `pip install` step: a suite whose claim is that it depends only
on primitives everyone already has should not need a Python terminal emulator to test itself,
which is why the two pty rigs it used to carry are gone. Nothing here is needed at runtime.

Four things these rigs learned the hard way, every one of which produced a wrong result first:

- **Wait on a ready marker, never on a sleep.** A captured spinner frame is a picture of the
  loading state, not of the layout.
- **Assert on the cell grid, not the byte stream** — for a claim that is about the screen.
  `tmux capture-pane` is that grid; `tmux pipe-pane` is the byte stream, for the claims that
  really are about bytes (a screen-clear, a spinner frame).
- **A piped `while read` loop body runs in a subshell**, so every failure it counted was
  discarded and the run reported green regardless.
- **Match multibyte glyphs without `LC_ALL=C`.** Under the C locale a bracket expression of
  multibyte characters is a set of *bytes*: it matches fragments, reports one glyph where four
  turned, and reads as a spinner that never advanced.

## Documentation

- [`docs/SPEC-system.md`](docs/SPEC-system.md) — architecture, every non-obvious decision and why, plus the
  verification matrix.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — positioning and non-goals, the naming survey, the OSS
  readiness assessment, and the conditions under which the core would move to Go.

## License

MIT
