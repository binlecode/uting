# AS-BUILT-workflow — how a unit of work moves through this repo

**Scope:** `docs/ARCHITECTURE.md` is the as-built doc of the *application* — what the code is
and why. This is the as-built doc of the *process*, and the two do not mix. The doc-lifecycle
stages, the testing hard rules and the commit guidelines are defined once in `CLAUDE.md`; this
file owns the one fact stated nowhere else — which **discipline** each stage of work is bound
to. The disciplines are normative for the work itself; the agent skills that automate them are
conveniences, which is why they are written out here rather than left inside the skills.

## 1. The pipeline

```
 (roadmap) ──► plan ──────────► pre-mortem ──► build ──► verify ──► land
     │          │                   │             │          │          │
 ROADMAP.md   PLAN- authored:     PLAN-       (§24 A-E   (the two   (checklist;
 entry:       interrogated (B1),  hardened    if struct.)  suites)  as-built docs
 decided,     designed (B3)                                         resynced,
 sequenced                                                          PLAN- deleted)

  ...and between units of work, on their own cadence: research feeding the roadmap (B6),
  and the whole-tree conformance audit (B9).
```

Interrogation (B1) and design (B3) are activities inside authoring the `PLAN-`, not stages of
their own; the as-built docs are touched only at land.

## 2. The bindings (normative)

B1. **An idea is interrogated before it is designed.** An adversarial interview, not a
    monologue: questions in dependency order, each with a recommended answer; facts are looked
    up — a contract claim is executed, never read — and only decisions are asked. What settles
    is distilled into the `PLAN-` **before the conversation ends**: a decision that lives only
    in a conversation does not exist.

B2. **A plan is pre-mortemed before it is built.** The plan text *alone*, without its authoring
    context, goes to a cold reader who writes its failure retrospective. Each preventive fix is
    accepted into the `PLAN-` or explicitly rejected. The cold read is the point — a critique
    from the session that wrote the plan inherits the plan's assumptions.

B3. **Design speaks the seam vocabulary, and this repo's doctrine outranks generic instinct.**
    Interfaces here are envelopes, seams are `ARCHITECTURE.md` §5's swap points, and depth is
    judged by what a caller gets per fact they must learn. Explore 2–4 deliberately different
    shapes before committing. Where generic advice points at a shared library or a mock,
    `CLAUDE.md`'s carve-outs win.

B4. **A build is incremental, or it is staged.** Small edits in place for ordinary work; the
    A→E order (`ARCHITECTURE.md` §24) the moment the change is structural — moves logic between
    files, retires a path, adds a surface.

B5. **A bug gets a red loop before it gets a theory.** No hypothesis until one command exists
    that goes red on the exact symptom — fast, deterministic, agent-runnable. The harness lives
    in `tmp/`; the regression check lands in whichever suite owns the surface; the hypothesis
    that proved out is stated in the commit message.

B6. **An initiative descends from the roadmap; research is its input, not a stage.**
    Outside-world questions are answered against primary sources and land as
    `docs/RESEARCH-<topic>.md` with each claim cited — that work runs on its own cadence, off
    this pipeline. What survives the filter of relevance and business need (`ROADMAP.md` §0's
    positioning and non-goals) becomes a roadmap entry carrying its reopen condition; the
    **decision** moves, the **survey stays** where it was measured, dated, with the roadmap
    linking to it — a roadmap that carries data ages into a doc nobody trusts. The `PLAN-`
    names the roadmap entry it implements, never the research doc.

B7. **A landing is a checklist, not a feeling.** The unit of work closes against the document
    that authorized it, atomically: every plan item landed or explicitly deferred, every
    `done_when` executed rather than read, accepted pre-mortem fixes verified in, review
    findings resolved, the as-built docs resynced, the `PLAN-` deleted, the version judged.
    Skipping the housekeeping half means the work has not landed — the code is merely present.
    Landing closes the unit of work, not the code's liability: that stays with
    `ARCHITECTURE.md` §25 and B9.

B8. **A session ends by sorting its residue.** Durable state — settled decisions,
    work-in-progress position — goes into the in-flight `PLAN-` before the session closes; only
    conversation-shaped remainder goes to a `tmp/` handoff note. The dividing line: if it still
    has value after the next session consumes it, it is not handoff content.

B9. **Accretion is audited, not watched for.** Diff review catches what a change introduces;
    the whole-tree sweep (`/audit-conformance`) catches what accumulates between changes. Its
    cadence and rules are its own file's.
