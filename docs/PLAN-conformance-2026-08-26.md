# PLAN — conformance audit (uting) · 2026-08-26

Status: **round landed · backlog open (2).** R9 landed since (the argv arrays dropped the knob prefix), off-round. The audited round — the engine seam — landed in
`d7b5d34` (canonical modes across the resolve seam), `4eb7a49` (the `--set-volume` lock), and
the `AS-BUILT-contract.md` §5/§6 edits in HEAD; every `done_when` was executed, not read, and
those rows are deleted from this file. What remains is the deferred backlog and the
do-not-re-open list. **Re-anchored against `4508599`** — every `file:line` below resolves there, and in
today's worktree too (the in-flight edits to the eight scripts are in place and shift no
cited line). The two `docs/` rows cite a **section**, not a line: those files are mid-edit,
and a section number is what survives a resync.

Scope: all eight scripts in `shell/`   ·   Functions graphed: 226   ·   Prior report folded: none

**The clean-class sweeps are deliberately NOT carried forward.** They were run before the
configuration surface existed (`config`, `ut_read_config`, the four-layer chain —
`AS-BUILT-contract.md` §5), which added a fourth precedence layer and a new read path in all
eight entry points. Inheriting those rows as "swept, nothing found" would report green on a
surface nothing has swept. The next audit re-sweeps R3 / R7 / R8 / R12 from scratch.

## Deferred backlog (2)

| rule | file:line | what | fix |
|---|---|---|---|
| **R13** | `shell/uting:516,537,544,547` | *Re-filed from R1/R10 — R13 did not exist when this row was written, and it owns the case.* `C_YELLOW`: four write sites, zero read sites (re-confirmed across `shell/`, `tests/`, `docs/`). The prose at `uting:503-507` argues a stale read of it is harmless — but there is **no read to be stale**, which is R13's canonical shape verbatim: prose defending its own retention, re-litigated by every audit. Doc mentions: `RESEARCH-oss-landscape.md` §5.1 (the one tracked SC2034) and `AS-BUILT-tui.md` §11 (the palette block, two paragraphs) — plus a third in `AS-BUILT-verification.md` that HEAD still carries and the in-flight §25/§27 restructure deletes. So the prose cost is three today, two once that lands; the row's original `AS-BUILT-verification.md:216` was off by two lines when written. | delete the four assignments **and** every doc mention still standing when it is done; the per-theme hexes are in git, same as `C_GREEN`'s, which was already deleted outright for this exact reason. R13 closes the "pick one" this row used to leave open: the prose is the finding, so keeping the variable and dropping the prose is not the cheaper half — it is the half that leaves a write-only global with nothing left arguing for it. |
| **R5** | `shell/uting:1331,1348,1355,1587` | Four bare `((var += …))` **statements** under `set -euo pipefail`, which CLAUDE.md forbids absolutely. Traced all four: `iw` ≥ 1 (`1 + DISP_W`), `sep_w` ≥ 2 (`${HINT_SEP:-"  "}`, and every real assignment is `" $GL_SEP "`), `cur_w += w_len + 1` ≥ 1. **Provably non-zero today — latent, not live.** But the safety is an argument about `print_hints`' callers, and every reader re-derives it. | mechanical rewrite to `var=$((var + …))`. No behaviour change; removes the class from the file so the next `HINT_SEP=""` caller cannot resurrect it. Best done when `print_hints` / `wrap_print` are open for another reason. |

## Not findings — recorded so the next audit does not re-open them

- **The 30 `DUP` names in the function graph are the deliberate carve-outs.** Standalone-execution helpers (`die`, `print_usage`, `require_cmd`, `require_deps`, `validate_enum`, `is_non_negative_int`, `ensure_scratch`, `cleanup_scratch`, `fail`, `now_utc`, `set_action`), the engine-half family (`dump_once`, `emit_stream`, `format_for_mode`, `resolve_info`, `resolve_stream`, `resolve_auth`, `resolve_fail`, `url_host`, `is_own_host`, `normalize_target`, `classify_yt_dlp_error`, `fetch_results`, `print_list`, `emit_search_json`, `reject_url`), and the store pair (`do_ls`, `ensure_store`) — separate executables whose alternative is the shared library the split exists to avoid. **`normalize_playback_mode` is gone from the list**: it was the one DUP spanning player and engine, and that is what the round fixed.
- **`ut_read_config` (`ut-play:83`, and byte-identical in all eight entry points) is a sanctioned duplicate, not an R4 row.** Its own header states the reason: eight independent executables share no library, and a verbatim copy is greppable for drift where a sourced file would invert the dependency direction the `VERSION` data file exists to keep straight. Verify it stays byte-identical; do not propose collapsing it.
- **Six `DEAD` candidates, all false positives.** `child_signal` (`ut-play:1003`) is called from the trap strings just below it; `do_show` / `do_add` / `do_rm` / `do_del` / `do_rename` (`ut-playlist:402-503`) are reached through the assembled name at `ut-playlist:697` (`"do_$ACTION"`). Zero real dead functions.
- **`engine_resolve_bin` in `ut-play:361` + `uting:186`** — same name, different questions: the player's resolves one engine's binary for a play, the TUI's probes a candidate while **discovering** which engines are installed. Neither is on the other's hot path. Not merged, and the player must not gain a discovery loop.
- **`lock_player_state` has no stale-lock steal where `lock_playlist` does** (`ut-play:1245` vs `ut-playlist:225-242`) — deliberate and documented at `ut-playlist:208`: the player's writes are best-effort field patches, the store's can drop a track a user just added. The player's stale dirs are cleared by `rm_player_files` at reap and at both `--stop` paths.
- **No path holds both `lock_player_state` and `lock_queue_state`** — re-checked all five call-site regions (`483-498`, `1376-1383`, `1398-1406`, `1419-1431`, `2007-2013`); each holds exactly one lock family. The hard rule at `ut-play:1291` holds.
- **Internals no longer wear knob prefixes — the R9 renames were extended to the sibling-binary paths and the memo flag** (`PLAY_BIN` / `PLAYLIST_BIN` / `HISTORY_BIN`, `HISTORY_LOOKED`), off-round with R9. The rule of record: an internal may carry the settable `UT_`/`YT_`/`BILI_` prefix only when it is on `ut_read_config`'s refuse list or provably assigned regardless of config. The three that remain qualify: `UT_VERSION` (assigned before the loader runs, which then skips it), `UT_DEFAULTS` (on the refuse list, and assigned unconditionally), `BILI_REFERER` (a constant, clobbered after load). §5 owes none of them a mention.
