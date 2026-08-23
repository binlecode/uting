---
name: run-yt-tui
description: Launch and drive the yt-tui terminal UI through tmux send-keys/capture-pane. Covers the TTY requirement (yt-tui refuses a non-TTY and cannot be run with the Bash tool directly), the pty-size trap, the fetch/ready markers, the full keymap, the YT_* environment knobs, and the detached-player cleanup that a session kill does NOT do for you. Use whenever a change has to be seen rather than reasoned about.
---

# run-yt-tui

`yt-tui` takes over the terminal and **requires a real TTY on both stdin and stdout** — it
refuses a pipe and exits 1 (`yt-tui: needs a terminal`). Calling it with the Bash tool
therefore proves nothing. Drive it inside tmux.

Everything it calls (`yt-search`, `ut-play`) is the opposite: never interactive, never needs a
TTY. Verify engine behavior with a plain Bash call — see the **verify-suite** skill.

## 1. Launch

```bash
S=ytt
tmux kill-session -t $S 2>/dev/null
tmux new-session -d -s $S -x 100 -y 30 "cd $PWD && YT_LANG=en shell/yt-tui 'lofi hip hop'"
```

**The size must be set at session creation** (`-x` / `-y`). `LINES`/`COLUMNS` in the
environment do **not** work: the TUI reads the real ioctl via `stty size </dev/tty`
(`shell/yt-tui:555`), which is exactly why a rig that forgets `TIOCSWINSZ` gets a 0×0
terminal and a one-row list whose frames still look plausible. Pass a query on argv to skip
the startup prompt; omit it to exercise the prompt and its own UTF-8 reader.

## 2. Wait for a real frame — do not sleep blindly

Two distinct markers, both verified:

```bash
# fetching: the line reads   searching "lofi hip hop"… ▖   (spinner animates ~8/s)
# ready:    the header line carries  query=…  results=N  sort=…  mode=…
timeout 30 bash -c "until tmux capture-pane -t $S -p | grep -q 'results='; do sleep 0.5; done"
tmux capture-pane -t $S -p
```

A cold `yt-dlp` search takes ~10 s. Capturing before `results=` appears grabs the spinner
frame; capturing right after a keypress that triggers a re-fetch (`n`, `m`, `o`) grabs the
old page. Wait for the marker, not for a duration.

## 3. Drive it

```bash
tmux send-keys -t $S Tab          # → focus card ("(nothing playing)" with no player)
tmux send-keys -t $S Down Down    # move the selection (4 screen rows change: 2 rows + 2 detail lines)
tmux send-keys -t $S Right        # next page
tmux send-keys -t $S '/'; sleep 0.5
tmux send-keys -t $S -l 'radio'   # -l = literal; the filter narrows per keystroke, AND across terms
tmux send-keys -t $S Escape       # clear the filter and leave filter mode
tmux send-keys -t $S 'v'          # cycle playback mode (local, no re-fetch)
tmux send-keys -t $S 'l'          # flip chrome language live (en ⇄ zh)
tmux send-keys -t $S 'q'          # quit — reaps only ITS OWN player
```

| Key | Action | Key | Action |
|---|---|---|---|
| `↑`/`↓` | select | `Enter` | play (detached, non-blocking) |
| `←`/`→` | page | `Tab` | focus card ⇄ list |
| `/` | live filter | `n` | new search |
| `m` | more results | `o` | cycle sort |
| `v` | playback mode | `Space` | pause / resume |
| `9`/`0` | volume down / up | `[` `]` | seek |
| `s` | stop | `l` | language |
| `q` | quit | | |

## 4. Playback starts a REAL detached player — clean it up

This is where `yt-tui` differs from an ordinary TUI, and the one thing this skill exists to
stop you getting wrong: `Enter` launches mpv in **its own process group, detached from the
terminal**. Killing the tmux session does **not** stop it. Audio keeps playing.

```bash
tmux send-keys -t $S Enter        # audible playback starts (~9 s cold start)
timeout 20 bash -c "until tmux capture-pane -t $S -p | grep -q 'Playing'; do sleep 0.5; done"

# ALWAYS, at the end of any session that pressed Enter:
tmux send-keys -t $S 'q'; sleep 1
tmux kill-session -t $S 2>/dev/null
shell/ut-play --stop --all -j     # {"status":"stopped","scope":"all","stopped":…}
pgrep -fl 'mpv .*--input-ipc-server' || echo "no orphan mpv"   # MUST be empty
```

Launch with `--volume 0`-equivalent care if you are on speakers: the TUI has no launch
volume flag, so press `9` a few times, or drive `shell/ut-play -d --volume 0` from the
engine side instead when you only need a player to exist.

The banner walks `Starting` → `Playing` **with no keypress** (a poll, not a redraw trigger),
so a capture taken during the ~9 s start-up window legitimately reads `Starting`.

## 5. Environment knobs worth driving

| Var | Values | What it exercises |
|---|---|---|
| `YT_LANG` | `en` \| `zh` | chrome language (default `zh` under a `zh*` locale). Help/errors stay English in both |
| `YT_ASCII` | `1` | full ASCII glyph fallback — a rendered pane must then hold no non-ASCII beyond the title text |
| `YT_THEME` | `minimal` \| `mono` \| `catppuccin` \| `tokyonight` \| `nord` \| `gruvbox` \| `onedark` | palette; community themes need `COLORTERM=truecolor` |
| `YT_BG` | `auto` \| `light` \| `dark` | background mode (auto: `$COLORFGBG` → OSC 11 → dark) |
| `YT_SYNC` | `0` \| `1` \| `auto` | DCS synchronized redraws (auto = off under tmux) |
| `YT_BRAND` | `1` | header wordmark in math-sans bold (the glyph class that renders narrower than it measures) |
| `NO_COLOR` | `1` | plain render under `--color auto` |
| `YT_COOKIE_BROWSER` | `chrome` \| `none` \| … | login vs anonymous extraction |

Under tmux, set `YT_SYNC=0` (or leave `auto`) — tmux and DCS frame sync do not mix.

## 6. What "working" looks like

- Header on **line 1** at every geometry, and no drawn line wider than the pane (measured in
  cells, not characters — a CJK title is two cells).
- The list shows N numbered rows whose titles all start on the **same column** across 1-, 2-
  and 3-digit indexes, with the duration rail right-flush at exactly the pane width.
- A live entry renders `LIVE` and `n/a views` — never a raw `null`.
- `Tab` with no player shows `(nothing playing)`; with a player it shows a ticking
  `elapsed / total (pct)` meta row and a rail-flush progress bar (a live stream shows the
  counter and **no** bar).
- Pause repaints exactly one row and **no frame blanks the screen** (zero ED sequences).
- On `q`: exit 0, and only this instance's player is reaped.

Prove the width and alignment claims rather than eyeballing them:

```bash
tmux capture-pane -t $S -p > tmp/pane.txt
python3 tests/assert_pane.py tmp/pane.txt 100 list    # PASS + the measured rail/index columns
```

## Gotchas

- **Non-TTY = exit 1.** Bash-tool invocation, a pipe on either side, or a here-doc stdin all
  refuse. That refusal is a feature (D1) — don't "fix" it to get a capture.
- **The detached player outlives everything.** Always `--stop --all` + `pgrep` at the end.
- **`send-keys` needs `-l` for literal text**, or a filter string like `n` is read as the
  new-search key.
- Scratch captures go in `tmp/` (repo convention), never the root or `tests/`.
