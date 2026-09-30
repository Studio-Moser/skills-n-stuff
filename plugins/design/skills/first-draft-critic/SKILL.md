---
name: first-draft-critic
description: >-
  Use to get a better first draft or a finished design out of an agent by
  sending its output to independent fresh-context critics instead of letting
  the generator grade its own work. Two modes: explore (default inside a
  fan-out round; two lenses, pushes each variant further into its own premise,
  two rounds max) and gauntlet (three lenses against an explicit done bar,
  loops to five rounds; for hero pieces and the convergence phase). Triggers:
  "critique this variant", "run the critics", "gauntlet", "is this done",
  "raise the bar".
---

# First-draft critic

A generator cannot reliably grade its own work: it decides "looks done" and
inherits its own blind spots. This skill replaces self-review with independent
critics that see only the artifact, a rubric, and a reference, never the build
conversation. Fan the critics out in parallel, collect fails, fix, re-judge.

Pick the mode first. The wrong mode does damage: a gauntlet during exploration
pulls every variant toward a safe middle, and an explore pass during
convergence lets craft faults through.

## Explore mode (fan-out rounds)

The owner is diverging. The critic's job is to make each variant commit harder
to its own premise and to catch what is broken, and nothing else.

Two lenses, run in parallel as fresh-context subagents:

- **Commitment** (taste model). Receives the direction brief's Premise and its
  Wins if / Loses if lines, the reference pack, and the variant's screenshots.
  Returns PASS or FAIL per Wins if line, CLEAR or TRIPPED per Loses if line. A
  variant that hedges toward the mean fails commitment even when nothing is
  wrong with it. No taste comments, no "more like the sibling", no
  conventional-wisdom fixes.
- **Broken** (cheap model, may run tools). Receives the running URL and the
  build brief's craft gates. Runs `design:capture`'s `views.mjs` for the
  per-width report and view stills, then measures each gate: overflow at 390
  and 1440, console and page errors, `naturalWidth` of images, reduced-motion
  collapse, focus rings, contrast where the gate names a threshold. Returns
  PASS or FAIL with the measured value and the element.

Give the commitment critic the view stills and motion strips from `views.mjs`
rather than only a stitched page; a reveal that never resolves is invisible in
a still. A critic that cannot open the preview from its sandbox (a delegated
Codex worker) works from these files.

No system or token lens: during exploration the direction's system is still
being invented, and auditing it freezes it early.

Round cap: **2**. One critique, one fix pass by the builder, one re-check of
what changed. Then stop and report the remaining fails into the round index;
the owner decides whether they matter.

If personal agents named `design-critic-craft` and `design-critic-mechanical`
exist, use them; otherwise spawn general-purpose subagents with the prompts in
`references/critic-prompts.md` § Explore.

## Gauntlet mode (convergence and hero pieces)

The owner has chosen a direction, or the artifact is a reusable hero piece,
and "done" can be written down. Do not run the gauntlet against a bar you
made up.

### Phase 0: define done

Assemble a **Done rubric** from, in order: the brief's explicit requirements;
the system (tokens, brand contract, a project `DESIGN.md`, a calling skill's
checklist); at least one concrete reference. If you cannot write it down, stop
and ask the owner for goals and a reference before spending tokens. Restate
the rubric and get a yes.

### Phase 1: three lenses

- **Brief**: each requirement as a yes/no line.
- **System**: each token, brand, or checklist rule as a testable line, quoted
  verbatim from its source.
- **Craft**: hierarchy, type scale, spacing rhythm, alignment, contrast and
  legibility, restraint (one accent, one primary action), state coverage,
  motion discipline. Derive concrete criteria from the reference ("headline
  should dominate like the reference's ~64px"), not adjectives.

### Phase 2 to 4: build, judge, fix, loop

One fresh-context critic per lens, in parallel, each receiving only the
artifact, its lens's rubric, and the reference. Per item: PASS or FAIL, and for
every FAIL an anchored fix (element, current value, target). Vague verdicts go
back. Craft critic on a taste model; brief and system critics on a cheap
model, since weak judges falsely reject faithful work on taste but are safe on
mechanical checks.

Collect fails, apply fixes, re-run the critics on what changed. Stop at zero
actionable fails, at the round cap (**5**, raise for a hero piece), or when the
owner stops it. Log each round in one line: `Round 3 — 2 fails: no focus ring
on dark; headline under-scaled.`

### Phase 5: report

The artifact, the round-by-round trail, and an approximate token cost. State
the rough cost before a long run; the gauntlet is expensive and is for
high-value artifacts, one per loop.

Prompts for all five critic roles are in `references/critic-prompts.md`.

## For skill authors

Any design skill can hand its output here after building. Pass your skill's
checklist as the System rubric (and, where it encodes taste, the Craft rubric),
and say which mode fits the phase the owner is in.
