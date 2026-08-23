---
name: capture-pane
description: Refresh the terminal frames in README.md / docs/SPEC-system.md from REAL yt-tui panes instead of hand-drawing them. Covers picking the geometry per view, waiting for the ready marker so the frame is not a spinner, cleaning the capture with clean_capture.py, proving it with tests/assert_pane.py BEFORE it enters a doc, and splicing it in with a Python replace rather than hand-transcribing box glyphs. Use when a layout change has made a doc frame stale.
---

# capture-pane

Every terminal frame in this repo's docs must come from a real pane. A hand-drawn mockup
drifts from the code (invented labels, a rail that doesn't line up, a version that no longer
exists) and cannot reproduce the alignment that *is* the claim being made — the right-flush
duration rail, the shared title column, the CJK title that occupies two cells per character.

For session setup, keys, ready markers, and player cleanup, see the **run-yt-tui** skill.
This one is capture → clean → **prove** → splice.

## 1. Pick the view and geometry

One capture = one tmux session at one declared size. Layout in this TUI is *width-conditional*
(the reflow pays for the details block out of the row budget, and the nav block drops entirely
when it doesn't fit), so a frame without its geometry stated is not a claim anyone can check.

| View | How | Geometry | Why this size |
|---|---|---|---|
| list (canonical) | default | `-x 100 -y 30` | wide enough for a full nav block and a 10-row page |
| list (narrow / degraded) | default | `-x 62 -y 12` | the reflow floor — the details block DROPS rather than overflowing |
| focus card | `Tab` | `-x 100 -y 30` | rails render at 80 cells; the meta row keeps all its fields |
| card (dropping fields) | `Tab` | `-x 40 -y 20` | the meta row drops `· mode` instead of wrapping |
| filter open | `/` then text | `-x 100 -y 30` | caret + narrowed page + bottom input row |
| ASCII fallback | `YT_ASCII=1` | any | the whole glyph set in its ASCII form |
| zh chrome | `YT_LANG=zh` | any | translated chrome at the same measured width |

Keep every capture destined for one doc section at the **same width** so the blocks line up
visually, and put that width in the surrounding prose.

## 2. Capture — after the ready marker, never after a sleep

```bash
S=cap
tmux kill-session -t $S 2>/dev/null
tmux new-session -d -s $S -x 100 -y 30 "cd $PWD && YT_LANG=en shell/yt-tui 'lofi hip hop'"
timeout 30 bash -c "until tmux capture-pane -t $S -p | grep -q 'results='; do sleep 0.5; done"
tmux capture-pane -t $S -p > tmp/raw-list.txt
```

For a keypress-driven frame, send the key and wait for the state to settle before capturing —
a re-fetch (`n`, `m`, `o`) needs the `results=` marker again, and a view switch needs ~1 s:

```bash
tmux send-keys -t $S Tab; sleep 1.2
tmux capture-pane -t $S -p > tmp/raw-card.txt
tmux send-keys -t $S '/'; sleep 0.5; tmux send-keys -t $S -l 'radio'; sleep 1
tmux capture-pane -t $S -p > tmp/raw-filter.txt
tmux kill-session -t $S 2>/dev/null
```

If the frame will show playback, read the cleanup section of **run-yt-tui** first — the player
survives the session kill.

## 3. Clean

```bash
python3 .claude/skills/capture-pane/clean_capture.py tmp/raw-list.txt > tmp/list.txt
```

It right-trims tmux's row padding, drops the empty bottom of the pane, drops a leading
`searching "…"…` line, and **exits 2 on a frame that still looks mid-fetch** — that guard is
the whole point, because a spinner frame is a picture of the loading state that reads as a
picture of the layout.

It never removes an interior row. Every row in a list frame is mutually aligned with the
others, so a "compressed" frame is a torn frame — paste frames verbatim.

## 4. Prove the capture BEFORE it enters a doc

A capture is evidence only once it has been measured. This is the step that separates this
skill from screenshotting:

```bash
python3 tests/assert_pane.py tmp/list.txt 100 list   # PASS + rail/index columns reported
python3 tests/assert_pane.py tmp/card.txt 100 card
```

If `assert_pane.py` fails, **you found a layout bug — do not paste the frame.** Fix the
renderer, re-capture. Width measurement lives only in that rig; do not reimplement cell
counting in this skill's script or in a doc-splicing snippet.

## 5. Splice — Python replace between stable markers, never by hand

Box glyphs, the right-flush rail, and CJK column alignment make manual transcription
lossy in a way that is invisible in review.

```bash
python3 - <<'PY'
import pathlib
DOC = pathlib.Path("README.md")
frame = pathlib.Path("tmp/list.txt").read_text().rstrip("\n")
t = DOC.read_text()
start = t.index("<!-- pane:list-100 -->")          # stable markers, added once
end = t.index("<!-- /pane:list-100 -->")
block = f"<!-- pane:list-100 -->\n\n```\n{frame}\n```\n\n"
DOC.write_text(t[:start] + block + t[end:])
PY

grep -c '^```' README.md          # must be EVEN
grep -n '^## ' README.md          # headings intact
```

Prefer HTML-comment markers over "the heading after it" indices: a heading rename silently
relocates an index-based splice, and the diff looks like a doc rewrite.

## Gotchas

- **A spinner frame is the #1 mistake.** Wait for `results=`; the cleaner blocks it, but only
  if you run the cleaner.
- **State the geometry in the prose.** A 100-col frame under a claim about 62 cols is worse
  than no frame.
- **`send-keys -l`** for literal filter text, or `n` becomes the new-search key.
- **Version in a captured frame** comes from `YT_VERSION` in `shell/ut-play` — after a bump,
  re-capture anything showing it rather than editing the number in the fence.
- Scratch stays in `tmp/`. A cleaned frame is scratch too — the doc is where it lands.
