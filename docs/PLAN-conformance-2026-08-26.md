# PLAN — conformance audit (uting) · 2026-08-26

Status: **CLOSED — every row landed.** The round (the engine seam) landed in `1558db7`,
`397e82c` and the `AS-BUILT-contract.md` §5/§6 edits; the R9 backlog row in `024cda6` +
`610a8e9`; and the last two — R13 `C_YELLOW` and R5's five bare `((var += …))` — in the
working tree now. Every `done_when` was executed, not read. Nothing is deferred.

Scope: all eight scripts in `shell/`   ·   Functions graphed: 226   ·   Prior report folded: none

**The clean-class sweeps were NOT carried forward, and the next audit must re-run them.** They
were swept before the configuration surface existed (`d9625f9`: `config`, `ut_read_config`, the
four-layer chain — `AS-BUILT-contract.md` §5), which added a precedence layer and a new read
path in all eight entry points. That surface has never been audited. R3 / R7 / R8 / R12 start
from scratch.

**Baseline moved with the last two rows:** `shellcheck --severity=warning` is now **22**
(`--format=json1`; SC2034 is zero for the first time) — `RESEARCH-oss-landscape.md` §5.1
carries the itemization and the measurement history.

## Not findings — recorded so the next audit does not re-open them

- **The 30 `DUP` names in the function graph are the deliberate carve-outs.** Standalone-execution helpers (`die`, `print_usage`, `require_cmd`, `require_deps`, `validate_enum`, `is_non_negative_int`, `ensure_scratch`, `cleanup_scratch`, `fail`, `now_utc`, `set_action`), the engine-half family (`dump_once`, `emit_stream`, `format_for_mode`, `resolve_info`, `resolve_stream`, `resolve_auth`, `resolve_fail`, `url_host`, `is_own_host`, `normalize_target`, `classify_yt_dlp_error`, `fetch_results`, `print_list`, `emit_search_json`, `reject_url`), and the store pair (`do_ls`, `ensure_store`) — separate executables whose alternative is the shared library the split exists to avoid. **`normalize_playback_mode` is gone from the list**: it was the one DUP spanning player and engine, and that is what the round fixed.
- **`ut_read_config` (`ut-play:83`, and byte-identical in all eight entry points) is a sanctioned duplicate, not an R4 row.** Its own header states the reason: eight independent executables share no library, and a verbatim copy is greppable for drift where a sourced file would invert the dependency direction the `VERSION` data file exists to keep straight. Verify it stays byte-identical; do not propose collapsing it.
- **Six `DEAD` candidates, all false positives.** `child_signal` (`ut-play:1003`) is called from the trap strings at `1026-1027`; `do_show` / `do_add` / `do_rm` / `do_del` / `do_rename` (`ut-playlist:402-503`) are reached through the assembled name at `ut-playlist:697` (`"do_$ACTION"`). Zero real dead functions.
- **`engine_resolve_bin` in `ut-play:361` + `uting:187`** — same name, different questions: the player's resolves one engine's binary for a play, the TUI's probes a candidate while **discovering** which engines are installed. Neither is on the other's hot path. Not merged, and the player must not gain a discovery loop.
- **`lock_player_state` has no stale-lock steal where `lock_playlist` does** (`ut-play:1245` vs `ut-playlist:225`) — deliberate and documented at `ut-playlist:206-209`: the player's writes are best-effort field patches, the store's can drop a track a user just added. The player's stale dirs are cleared by `rm_player_files` at reap and at both `--stop` paths.
- **No path holds both `lock_player_state` and `lock_queue_state`** — re-checked all five call-site regions (`483-498`, `1376-1383`, `1398-1406`, `1419-1431`, `2007-2013`); each holds exactly one lock family. The hard rule at `ut-play:1291` holds.
- **Three plain internal globals still wear a knob prefix, and that is not drift**: `UT_VERSION` (the version string each entry point reads), `UT_DEFAULTS` (`ut-play:82` — the shipped-defaults path) and `BILI_REFERER` (`bili-search:110`, a constant). None is an env read; §5 owes them nothing, and `ut_read_config`'s refuse list (`ut-play:96-98`) already blocks `UT_DEFAULTS` from a config file. The rest of this class is gone: the argv arrays, the sibling-binary paths (`PLAY_BIN` / `PLAYLIST_BIN` / `HISTORY_BIN`) and the memo flag (`HISTORY_LOOKED`) all dropped the prefix in `024cda6` / `610a8e9`.
