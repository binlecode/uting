# PLAN — doc taxonomy rename + P0 contract extraction

**Status: Phase A landed (commit pending); Phase B not started.**
**Authorizes:** ROADMAP P0 (契约抽取), plus the taxonomy decisions settled 2026-08-24.
**Tracks its own progress; deleted on landing (B7).**

## 0. Decisions settled (this conversation, recorded here until they land in CLAUDE.md)

1. **`SPEC-` retires.** The word reads as "specification" — a normative promise the code
   chases — while these docs are the opposite: descriptions that chase the code. The
   taxonomy closes over two terms and only two: **`PLAN-` tracks the life of a feature
   delivery; `AS-BUILT-` records what is built.** No further doc class is introduced.
   The two are one lifecycle: a plan's content is split into the as-built docs as it
   lands, and when it is done the plan is gone — deleted, not archived.
2. **Renames:** `docs/SPEC-system.md` → `docs/ARCHITECTURE.md` (the system doc IS the
   umbrella — revised mid-flight from an earlier AS-BUILT-system + thin-index split);
   `docs/SPEC-workflow.md` → `docs/AS-BUILT-workflow.md`. If ARCHITECTURE.md grows heavy,
   modular `AS-BUILT-<scope>.md` docs spin off (the contract in Phase B is the first).
3. **P0's deliverable is `docs/AS-BUILT-contract.md`** — the CLI contract as built. Its
   *frozen* status is governance (ROADMAP D3/D13 say changing it is a deliberate,
   documented act), not a naming class.
4. ~~Thin umbrella index~~ **Superseded**: `ARCHITECTURE.md` is the renamed system doc
   itself (decision 2); no separate index file exists. A4 below is dropped.
5. **The workflow pipeline diagram is wrong and gets fixed** (`SPEC-workflow.md` §1): it
   placed the code-synced doc between plan and build and ordered the stages against its own
   bindings. Correct order: research → interrogate → plan → pre-mortem → build →
   verify → land, with the **as-built resync at land** (B7), never before build.
6. **Global skills (`~/.claude/skills/`) update too** — same vocabulary, and the one real
   defect: `grilling` lists `SPEC-` as a landing place for settled decisions (a decision
   not yet built must not enter an as-built doc; it lands in PLAN-/ROADMAP).
7. **No `DESIGN-` doc class.** Four stages: RESEARCH- → ROADMAP → PLAN- → as-built.
   Design is an activity inside authoring the PLAN-, not a doc stage; what settles is
   written into the plan directly. Applied to CLAUDE.md's stage table, the workflow
   pipeline, the global skills, and user-level AGENTS.md.

## Phase A — taxonomy & flow (docs and comments only; zero behavior change)

- [x] **A1. Rename the two docs** with `git mv` (history preserved):
      `SPEC-system.md` → `ARCHITECTURE.md`, `SPEC-workflow.md` → `AS-BUILT-workflow.md`.
      `done_when`: both old paths gone, `git log --follow` shows continuity.
- [x] **A2. Citation sweep** — every `SPEC-system` / `SPEC-workflow` reference retargeted.
      Measured surface (~112 sites): shell/ 56 (ut-play 18, yt-resolve 9, bili-resolve 9,
      bili-search 8, yt-search 8, uting 4) · docs/ROADMAP.md 18 · CLAUDE.md 12 ·
      tests/ 5 · README.md 3 · .claude/skills/ 8 · .githooks/pre-commit 2 · self-refs 7.
      Section numbers (§14 etc.) are unchanged in this phase, so each edit is a filename
      substitution only.
      `done_when`: `grep -rn "SPEC-" --exclude-dir=.git .` returns **zero** lines.
- [x] **A3. Fix the pipeline diagram** in (now) `AS-BUILT-workflow.md` §1 per decision 5,
      and reword its scope header ("code-synced spec" → "as-built doc"). The land column
      names the resync explicitly.
      `done_when`: diagram stage order matches B1–B7 bindings and §3's walkthrough; the
      words "as-built" appear in the land column.
- [-] **A4. Dropped** (decision 4 superseded): no separate thin index; ARCHITECTURE.md
      is the umbrella itself.
- [x] **A5. CLAUDE.md stage table + naming rules**: `SPEC-<scope>.md` row becomes
      `AS-BUILT-<scope>.md` ("synced at land, after the code stops moving"); the live-files
      list gains ARCHITECTURE.md and AS-BUILT-contract.md; the "one fact, one place" rule
      and the SDLC prose lose the word "spec" for these docs.
      `done_when`: CLAUDE.md grep for `SPEC-` is empty; stage table names both terms'
      semantics (PLAN- tracks delivery life; AS-BUILT- records what is built).
- [x] **A6. Global skills sweep** (`~/.claude/skills/`, outside this repo):
      - `grilling/SKILL.md:30` — remove `SPEC-` from the decision-landing list (decisions
        land in PLAN-/ROADMAP; as-built docs are only ever resynced at land).
      - `research`, `land`, `handoff`, `diagnosing-bugs`, `codebase-design` (+
        `DESIGN-IT-TWICE.md`), `README.md` — lifecycle vocabulary becomes
        RESEARCH-/ROADMAP/PLAN-/AS-BUILT-; "code-synced spec" phrasing becomes
        "as-built doc"; generic fallbacks (`docs/SPEC-*.md` examples) become
        `docs/AS-BUILT-*.md`.
      - Log the refinement in the skills README per its own convention.
      - User-level `~/.claude/CLAUDE.md` (→ `~/env-config/macos/AGENTS.md`) gains the
        four-stage Doc Lifecycle section (done; commit of env-config is the user's).
      `done_when`: `grep -rn "SPEC-" ~/.claude/skills/` is empty. **Met.**
- [x] **A7. Verify + commit Phase A**: `bash -n` all six scripts (comment-only edits, but
      the hook demands it) and `tests/contract.sh`. One commit for the repo rename+sweep,
      one for CLAUDE.md if cleaner as its own change; skills live outside the repo.
      `done_when`: contract.sh 89/89 green; working tree clean.

## Phase B — P0: extract `docs/AS-BUILT-contract.md`

**Prerequisite (ROADMAP P0):** the source must be code-synced. ARCHITECTURE.md Part III was
read against the emitters this session (`emit_search_json` ×2, `emit_stream` ×2,
`emit_play_json`, `do_status`/`do_stop`/`do_set_volume`, `resolve_info` ×2,
`normalize_target` ×2, `record_player_death`) — no drift found. Holds.

- [ ] **B1. Move Part III (§12–§16) into `AS-BUILT-contract.md`**, reorganized for its two
      readers (a JSON-diff test author; a third-engine author):
      1. *Shared ground*: exit-code table (0/1/2+/4), the one-envelope-one-line rule,
         `status` + `engine` required keys, the `reason` enum (closed list, no member added
         without this doc changing), `-J` ⊇ `-j` strict-superset rule, `-V`-before-gates.
      2. *Player contract* (`ut-play`): argv/flag surface + gate arms, playback envelope,
         `-d` envelope (sock/log handover), `--status` shape (players[] live-read null
         semantics, failed[] tombstone bounds: failures only / ≤8 / ≤1h / $TMPDIR),
         `--stop` + `--set-volume` shapes and the exit-4 taxonomy, idempotent stop,
         ambiguity → 4, the player record schema (`players/<id>.json`), engine selection
         (`--engine`, `UT_DEFAULT_ENGINE`, name = command prefix), the no-credential-header
         rule (headers land on argv).
      3. *Engine contract* (what a third engine must implement): the `<name>-search` +
         `<name>-resolve` pair discovery rule; search envelope (8 fields, null pairing of
         duration/duration_fmt, error shape, exit 2+ floor); resolve envelope
         (`stream_urls[]` video-first, `http_headers{}` required and credential-free,
         `format` opaque, `retried`, error → 2+ floored); `--info` shape; capability by
         verb presence (D13 — no `--transcript` means the verb does not exist);
         host allowlist — own-site hosts only, non-own URL/id = **usage error 1**, explicit
         list never substring; `ENGINE_NAME` emitted from one constant; `--` re-applies
         positional validation; the engine-read env vars (`YT_COOKIE_BROWSER`, format
         table vars).
      4. *Config surface*: the flag-vs-env rule and the D13 "in/out of the public API"
         table, by move from §16 + pointer to ROADMAP D13 for the semver rule itself.
      `--transcript`'s full envelope moves too (it is `yt-resolve` surface, engine-specific
      but still contract).
      `done_when`: every field name, enum member, exit code and error shape in §12–§16
      appears in the contract doc; ARCHITECTURE.md contains none of them (see B2).
- [ ] **B2. ARCHITECTURE.md keeps its numbering, loses the facts**: §12–§16 bodies become
      one-line pointers into the contract doc ("§14 → AS-BUILT-contract §C2/§C3"). No
      renumbering — §17/§25/§27/§28 are cited from shell comments and CLAUDE.md and must
      stay stable. Parts I–II and IV–V keep their rationale prose; where they restated a
      contract fact they now point.
      `done_when`: no JSON schema, exit-code table or reason enum remains in
      ARCHITECTURE.md; all §12–§16 stubs point at a real contract section.
- [ ] **B3. Retarget code comments that cite §12–§16** (≈20 of the §14/§15 refs in shell/
      and tests/) to the contract doc's section ids. Comments citing §9.x/§25/§27 stay.
      `done_when`: `grep -rn "ARCHITECTURE.md §1[2-6]" shell tests` is empty.
- [ ] **B4. Acceptance, executed not read** (ROADMAP P0's two clauses):
      - *"Write a JSON-diff test from this doc alone"*: walk the contract doc's envelope
        inventory against `tests/contract.sh` — every envelope/exit-code claim in the doc
        is either driven by an existing check or listed in the doc's own verification
        appendix as driven-by-which-check. Any claim with no check gets the existing check
        hardened (CLAUDE.md: harden before extend).
      - *"Write a third engine pair from this doc alone"*: audit the engine-contract
        section against `bili-search`/`bili-resolve` as the reference reader — every
        obligation those two files satisfy must be stated (the second engine is the proof
        that the list is complete; anything it does that the doc omits is a doc gap).
      `done_when`: both walks recorded in this PLAN with zero unstated obligations left.
- [ ] **B5. ROADMAP + README resync**: P0 marked done (状态 line), D3's "P0 抽契约文档时"
      wording updated to name `AS-BUILT-contract.md`, README's doc list gains the contract
      and ARCHITECTURE entries.
      `done_when`: ROADMAP P0 status flipped; README doc table lists all live docs.
- [ ] **B6. Verify**: `bash -n` ×6, `tests/contract.sh`. No `shell/VERSION` bump — D13's
      table puts `docs/` outside the public API and no envelope byte changed.
      `done_when`: contract.sh green on the 3.2 floor.
- [ ] **B7. Land per B7-binding**: this PLAN's items all checked or explicitly deferred,
      then **this file is deleted** in the landing commit.

## Pre-mortem (self-applied; a cold read can still be requested before build)

| Failure imagined | Preventive fix (accepted into the plan) |
|---|---|
| Renumbering ARCHITECTURE.md breaks ~30 shell-comment §-cites silently | B2: no renumbering, ever — moved sections become pointer stubs |
| Sweep misses a spelling (`SPEC-system.md`, `docs/SPEC-system.md §14`, bare `SPEC-workflow`) | A2/A6 gates are greps for the bare token `SPEC-`, not for full paths |
| Contract doc restates rationale and starts drifting from ARCHITECTURE.md | B1 moves *normative surface* only; rationale stays in system doc; each fact exists once |
| The two-reader acceptance is read, not run | B4 is an executed walk with the second engine as the completeness oracle |
| Global skills become uting-specific | A6 keeps them generic — the lifecycle is named as a convention with AS-BUILT- as its vocabulary, repos without it unaffected |
| `.githooks/pre-commit` still greps old doc name and warns forever | A2 surface list includes .githooks explicitly |

## Out of scope (stated, not silently dropped)

- P4 (queue/playlists/history) — next unit of work; unblocked by this one.
- Any envelope/exit-code *change* — this extracts and documents; it changes nothing.
- MEMORY/global CLAUDE.md additions — user-level CLAUDE.md carries no doc-lifecycle rule
  today and gains none; the skills carry it.
