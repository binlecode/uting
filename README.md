# uting

**u-ting / 你听** — an agent-first YouTube engine with a terminal face.

Search YouTube, play it through mpv detached from your terminal, and keep controlling it — from a
TUI if you are a human, from a single-line JSON contract if you are a program.

```sh
ytt                              # interactive: search, browse, play, control
yts -j -n 25 -- "lofi hip hop"   # machine: one line of JSON out
ytp -d -j -- "<url>"             # machine: launch detached, get {id, pid, sock}
ytp --status -j                  # machine: what is playing, where, how loud
ytp --stop --id <id> -j          # machine: stop it
```

## Status

**Reference implementation.** This is a working shell suite that its author uses daily, published
together with a design document that is longer than most of the code it describes. It is not
packaged: there is no installer and no Homebrew formula, and none is planned for the shell version
(see [`docs/ROADMAP.md`](docs/ROADMAP.md) for why, and for what a Go rewrite would change).

The document may be the more useful artifact. `docs/DESIGN.md` records things that are usually
learned and then forgotten: East-Asian-width handling in a terminal renderer, DCS frame
synchronisation, correlating mpv IPC replies by `request_id`, and the `set -e` traps that bash 3.2
sets for you.

## What it is

- **`yt`** — the engine. Never interactive, never prompts. Drives yt-dlp and mpv, owns the detached
  player lifecycle (id / pid / socket / lock / state dir / reap), and defines the contract.
- **`yt-search`, `yt-play`** — narrow verb wrappers over the engine, deliberately single-purpose
  with mutually exclusive flags rejected up front, because that is what makes them safe for a small
  model to call.
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
- bash 3.2 — the version macOS ships. The suite is written to that floor on purpose; see
  `docs/DESIGN.md` §28.

Nothing is vendored. Install yt-dlp and mpv however you normally would.

## Try it

```sh
git clone git@github.com:binlecode/uting.git
cd uting
./shell/yt-tui "lofi hip hop"     # or: ./shell/yt-tui  and type a query
```

For daily use, symlink short names onto your PATH:

```sh
ln -s "$PWD/shell/yt-tui"    ~/bin/ytt
ln -s "$PWD/shell/yt-search" ~/bin/yts
ln -s "$PWD/shell/yt-play"   ~/bin/ytp
```

`yt` itself is reached through a path relative to the wrappers and is deliberately **not** put on
PATH — it is internal, and `yt` is far too generic a name to occupy.

## Keys

`↑/↓` select · `←/→` page · `Enter` play · `Tab` focus card · `/` filter · `n` new search ·
`m` more results · `o` sort · `v` playback mode · `Space` pause · `9/0` volume · `s` stop ·
`l` language · `q` quit

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — architecture, every non-obvious decision and why, plus the
  verification matrix.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — positioning and non-goals, the naming survey, the OSS
  readiness assessment, and the conditions under which the core would move to Go.

## License

MIT
