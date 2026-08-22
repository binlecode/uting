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
ln -s "$PWD/shell/yt-search" ~/bin/yt-search
ln -s "$PWD/shell/yt-play"   ~/bin/yt-play
```

The older `yts` / `ytp` spellings are **deprecated**. Nothing in the suite reads its own
`argv[0]`, so an existing `~/bin/yts` keeps working — it is simply no longer a documented
name, and one name per command is the point.

`yt` itself is reached through a path relative to the wrappers and is deliberately **not** put on
PATH — it is internal, and `yt` is far too generic a name to occupy.

`ytt --version` (or `-V`) answers before any dependency check, so it works on a machine that has
not installed yt-dlp or mpv yet — which is exactly when you want to know what you have. All four
entry points report the same number: it is declared once, in the core.

## Keys

`↑/↓` select · `←/→` page · `Enter` play · `Tab` focus card · `/` filter · `n` new search ·
`m` more results · `o` sort · `v` playback mode · `Space` pause · `9/0` volume · `s` stop ·
`l` language · `q` quit

## Tests

Verification rigs, not a unit-test suite — what this code gets wrong is renderer and protocol
behaviour, which only a real pty and a real socket can show. Each file's docstring says what it
proves; run any of them directly.

| Rig | What it is for |
|---|---|
| `tests/tui_screen.py` | Drives the TUI in a pty and asserts on the **screen** — a pyte cell grid, after `\033[K` / `\033[J` / CHA have been applied. This is what claims like "pause repaints exactly one row, and no frame blanks the screen" are counted from (`changed_rows`, `ed_count`). |
| `tests/pty_drive.py` | Asserts on the **stream and its timing** — spinner frames actually arriving, `Starting` → `Playing` flipping with no keypress, the 1 s tick stopping when it should, exit codes on the cancel paths. |
| `tests/assert_pane.py` | Layout invariants on a captured pane: nothing exceeds the pane width (measured in cells), every row's title starts on the same column, the duration rail is right-flush at exactly the pane width, and the boundary rail is full width in both its static and its live form. |
| `tests/mpv_ipc_mock.py` | A fake mpv JSON-IPC peer that can do what the real one will not do on cue: answer out of order (`--reverse`), report a property as null, interleave async events, walk the clock, and never close its side of the socket. Every IPC rule in the read path exists because of one of these shapes. |

`tui_screen.py` needs `pyte` (`pip install pyte`); nothing else here has dependencies beyond the
suite's own, and none of it is needed at runtime.

Two things these rigs learned the hard way, both of which cost a wrong green result first:

- **A pty starts at 0×0, and `LINES`/`COLUMNS` do not fix it.** The TUI reads `stty size` through
  `/dev/tty` on purpose, so without `TIOCSWINSZ` the reflow has no rows to spend and draws a
  one-row list — whose frames look plausible enough to trust.
- **Assert on the screen model, not the byte stream.** "Changed exactly one row" is a statement
  about cells; the byte stream of a correct in-place frame looks nothing like the picture it
  produces.

## Documentation

- [`docs/SPEC-system.md`](docs/SPEC-system.md) — architecture, every non-obvious decision and why, plus the
  verification matrix.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — positioning and non-goals, the naming survey, the OSS
  readiness assessment, and the conditions under which the core would move to Go.

## License

MIT
