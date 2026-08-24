# SPEC-workflow — how a unit of work moves through this repo

**Scope separation:** `docs/SPEC-system.md` is the spec of the *application* — what the code
is and why. This file is the spec of the *process* — how work on that code is conducted. The
two do not mix: nothing about the suite's behavior lives here, and nothing about workflow
lives there. The doc-lifecycle stages, the testing hard rules, and the commit guidelines are
defined once in `CLAUDE.md`; this file owns the two facts stated nowhere else — which
**discipline** each stage of work is bound to, and the end-to-end walkthrough of a feature
moving through them.

The disciplines are normative for the work itself. The agent skills that automate them (the
maintainer's user-level set, and this repo's own two in `.claude/skills/`) are conveniences:
nothing in the checkout depends on their presence, which is why the disciplines are written
out here rather than left inside the skills.

## 1. The pipeline

```
 (research) ──► interrogate ──► pre-mortem ──► design ──► build ──► verify ──► land
      │              │              │             │          │         │          │
  RESEARCH-       DESIGN-         PLAN-      (SPEC-system  (§24 A-E   (the two  (checklist;
  cited, then    distilled      hardened      §5 seams)   if struct.)  suites)  PLAN- deleted)
  distilled + deleted

  ...and between units of work, on its own cadence: the whole-tree conformance audit.
```

## 2. The bindings (normative)

B1. **An idea is interrogated before it is designed.** A feature or decision enters as an
    adversarial interview, not a monologue: questions asked in dependency order, each with a
    recommended answer; facts are looked up (or run — a contract claim is executed, never
    read), only decisions are asked. What settles is distilled into a `DESIGN-` or `PLAN-`
    doc **before the conversation ends** — a decision that lives only in a conversation does
    not exist.

B2. **A plan is pre-mortemed before it is built.** The plan text — alone, without its
    authoring context — is handed to a cold reader who writes its failure retrospective: the
    wrong assumption, the constraint that bit, the underestimated dependency, the ignored
    early signal. Each preventive fix is accepted into the `PLAN-` doc or explicitly
    rejected. The cold read matters: a critique from the session that wrote the plan
    inherits the plan's assumptions.

B3. **Design speaks the seam vocabulary, and this repo's doctrine outranks generic
    instinct.** Interfaces here are envelopes, seams are `SPEC-system.md` §5's swap points,
    and depth is judged by what a caller gets per fact they must learn. Explore alternatives
    (2–4 deliberately different shapes) before committing to one. Where generic design
    advice points at a shared library or a mock, `CLAUDE.md`'s carve-outs win: six
    standalone executables duplicate on purpose, and every check invokes a real entry
    point rather than a seam built to be tested.

B4. **A build is incremental, or it is staged.** Small edits in place for ordinary work; the
    A→E order (`SPEC-system.md` §24) the moment the change is structural — moves logic
    between files, retires a path, adds a surface.

B5. **A bug gets a red loop before it gets a theory.** No hypothesis until one command
    exists that goes red on the exact symptom — fast, deterministic, agent-runnable.
    Harnesses live in `tmp/`; the regression check lands in whichever suite owns the surface
    (`CLAUDE.md`'s testing rules — and the default move on a gap is to harden an existing
    check, not to add a file); the hypothesis that proved out is stated in the commit
    message.

B6. **Research is cited or it is opinion.** Outside-world questions (a yt-dlp mechanism, a
    dependency's roadmap) are answered against primary sources and land as
    `docs/RESEARCH-<topic>.md` with each claim cited — then distilled into a `ROADMAP.md`
    entry or a `DESIGN-` and deleted, per the lifecycle.

B7. **A landing is a checklist, not a feeling.** The unit of work closes against the
    document that authorized it, atomically: every plan item landed or explicitly deferred,
    every `done_when` executed rather than read, accepted pre-mortem fixes verified in,
    review findings resolved, the spec resynced, the `PLAN-` doc deleted, the version judged
    (its own commit if bumped). Skipping the housekeeping half means the work has not
    landed — the code is merely present. Landing closes the unit of work, not the code's
    liability: that stays with `SPEC-system.md` §25 and B9.

B8. **A session ends by sorting its residue.** Durable state — settled decisions,
    work-in-progress position — is written into the in-flight `PLAN-` doc before the
    session closes; only conversation-shaped remainder (untested hunches, the next command
    to run) goes to a `tmp/` handoff note. The dividing line: if it still has value after
    the next session consumes it, it is not handoff content.

B9. **Accretion is audited, not watched for.** Diff review catches what a change
    introduces; the whole-tree sweep (`/audit-conformance`, this repo's own skill) catches
    what accumulates between changes. Its cadence and rules are its own file's.

## 3. Worked walkthrough — a play queue (ROADMAP D14)

How one in-scope feature would move through the bindings, stage by stage.

**Research (as needed, B6).** Should the queue ride mpv's own playlist machinery? A
background pass over the mpv manual and source answers it with citations in
`docs/RESEARCH-mpv-playlist.md`; the verdict is distilled into the design and the doc
deleted.

**Interrogate (B1).** The idea enters an interview: where does queue state live — the
player's state dir or a new home? What is the agent-facing verb and its `-j` envelope
(a TUI-only feature is half a feature here)? Who owns the queue when the detached player
exits? Each question arrives with a recommended answer; the answers settle into
`docs/DESIGN-queue.md`.

**Design (B3).** The queue verb's interface is designed in seam vocabulary: the envelope is
the interface, alternatives are sketched 2–4 deliberately different ways (smallest surface /
most flexible / easiest common call) and compared on depth and seam placement before one is
chosen. The choice lands in `ROADMAP.md`; the `DESIGN-` doc is distilled into
`docs/PLAN-queue.md` — field names, flags, verification matrix, a `done_when` per item — and
deleted.

**Pre-mortem (B2).** `PLAN-queue.md` alone goes to a cold reader: "six months later the
queue shipped and failed — why?" The accepted preventive fixes are written back into the
plan; the rejected ones are recorded as rejected. Only now does building start.

**Build (B4, B5).** Ordinary edits go straight in (syntax check before every commit, one
logical change per commit). Anything structural — a new verb touching the player's
lifecycle — runs A→E with the destructive step last and smallest. A bug found on the way
gets its red loop before any theory; the loop's harness sits in `tmp/`, the regression
check graduates into the owning suite.

**Verify.** The suites named in `CLAUDE.md` for whatever surfaces changed: `tests/contract.sh`
for envelope or exit-code changes (and for any change at all), the gated
`tests/lifecycle.sh` for detached-player changes. A renderer change has no suite by design —
layout is proved when a frame enters a doc, and that lives in the `capture-pane` skill,
deliberately outside the suite; `tests/drive.sh` is the driver when a TUI change has to be
driven rather than reasoned about. Doc frames that went stale are re-captured from real
panes, proven, and spliced — never hand-drawn.

**Land (B7).** The closing checklist runs against `PLAN-queue.md`: every item landed or
explicitly deferred; every `done_when` executed with its output shown; the pre-mortem's
accepted fixes confirmed in; a diff review run and its findings resolved; `SPEC-system.md`
resynced (the new envelope in §14, exit codes in §15, functions in §17, checks in §27);
`PLAN-queue.md` deleted; `shell/VERSION` judged — a bump is its own commit. Then, and only
then, the feature has landed.

**Between features (B9).** On its own cadence, the whole-tree conformance audit sweeps for
what the per-change gates cannot see: slow accretion. Its findings become the next
`PLAN-conformance-*.md`.

## 4. Tooling note

Each binding is automated by an agent skill in the maintainer's environment — the interview,
the cold-read pre-mortem, the seam vocabulary, the red-loop discipline, the cited research,
the residue sort, and the landing checklist at user level; the conformance audit and the
frame capture in this repo's `.claude/skills/`. The skills make the bindings cheap; this
file is what makes them binding. A contributor without the skills follows the disciplines
by hand and loses nothing but convenience.
