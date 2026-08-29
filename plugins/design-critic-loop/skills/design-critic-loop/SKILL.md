---
name: design-critic-loop
description: >-
  Use to raise a design to a high bar — a website, screen, UI, presentation,
  graphic, mockup, HTML/CSS or SwiftUI/AppKit output — via the Gauntlet Loop:
  independent fresh-context critics that judge against an explicit "done" bar and
  iterate until they pass, instead of the generator grading its own homework.
  Triggers: "critique this design", "run the gauntlet", "design loop", "polish
  this", "make it better", "raise the bar", "is this good enough". Also invoke it
  from another design skill after building, to verify the output against that
  skill's checklist. If "done" is unclear, it asks the user for goals and
  reference examples first. Reserve for high-value / reusable artifacts — the loop
  is token-expensive. NOT for routine one-off tweaks.
---

# Design Critic Loop — the Gauntlet

A generator can't reliably grade its own homework: it decides "looks done" and
inherits its own blind spots. This skill replaces self-review with **independent,
fresh-context critics** that judge the design against an explicit definition of
done, then loops build → critique → fix until the critics stop finding real
faults. Popularized as the "Gauntlet Loop" / "Design Loop" (Matt Shumer).

Run the phases in order. **Do not skip Phase 0.**

## Phase 0 — Define "done" (the gate)

The loop is only as good as its target. Before spending tokens, produce a
concrete, restate-able **Done Rubric**. Assemble it from, in order:

1. **The brief** — the explicit requirements the user gave.
2. **The system** — a design system, brand contract, tokens, or a calling skill's
   checklist (e.g. `mac-app-design` Mac App Done Rubric, `figma-design` token contract).
3. **A reference** — at least one concrete example (URL, screenshot, "like X") or
   an unambiguous aesthetic direction to judge craft against.

**Elicitation gate — if you cannot yet write down what "done" looks like** (the
aesthetic is vague, there's no reference, the brief is thin, or you'd have to
*invent* the bar), STOP and engage the user before building. Ask focused
questions and request examples:

- "What should 'great' look like here — any site, app, or image you'd point to?"
- "Who is it for, and what's the one thing it absolutely must nail?"
- "Any brand, tokens, or existing screens I should match?"
- "Can you drop a reference image or URL?"

Use `AskUserQuestion` for choices; ask for reference links/images in chat. Keep
going until you can **restate the Done Rubric back to the user and get a yes.**
Never run the gauntlet against a bar you quietly made up — a confident loop
toward the wrong target wastes the most tokens of all.

Output: a written **Done Rubric**, grouped by the three lenses below.

## Phase 1 — Pre-flight rubric

Turn the Done Rubric into explicit, checkable items across three lenses:

- **Brief** — each requirement as a yes/no line ("covers all 7 tools"; "has a
  clear primary CTA"; "fits a 1080×1080 frame").
- **System** — token / brand / checklist adherence. Pull the calling skill's
  rubric **verbatim** (`mac-app-design` Mac App Done Rubric, `figma-design` token
  contract, the project `DESIGN.md`). Each rule is one checkable line.
- **Craft** — the taste bar: visual hierarchy, type scale, spacing rhythm,
  alignment, contrast/legibility, restraint (one accent, one primary action),
  state coverage, motion discipline. Derive concrete criteria from the reference
  ("headline should dominate like the ref's ~64px", not "good hierarchy").

## Phase 2 — Build

Produce the design — or take the artifact the calling skill already built.

## Phase 3 — The Gauntlet (independent critics)

Spawn **one fresh-context subagent per lens** (the `Agent` tool). Each critic
receives ONLY: the artifact + its lens's rubric + the reference. **Not** the build
conversation — independence is the entire point; a critic that shares your context
inherits your rationalizations.

Each critic returns, per rubric item: **pass / fail**, and for every fail a
**specific, actionable** fix anchored to an element or line — "logo is ~40px, ref
reads ~64px, bump it"; "three competing accent colors, cut to one"; "body 16px,
Mac wants 13px". Reject vague verdicts ("make it pop"); send them back.

Run the critics in parallel.

**No subagents available (e.g. Claude.ai)?** The *independence* is what matters,
not the mechanism. Run each critic as a separate clean pass that sees only the
artifact + its rubric + the reference — a fresh section, or a separate chat —
without letting it read your build reasoning. A sequential loop of honest critics
still beats self-review; don't skip the loop just because you can't fan out.

**Model routing** (our subagent rubric + the pge-evaluator finding that weak
judges *falsely reject* faithful work):

- **Craft / taste critic → Claude** (fable for a review-grade pass). Do **not**
  cheap out here — taste judging is where a weak model does the most damage.
- **Brief-coverage & System/token critics → codex / a cheap model** — these are
  mechanical, checkable, and safe to delegate.

## Phase 4 — Fix & re-judge (the loop)

Collect all fails, apply the fixes, then re-run the critics on what changed.
Repeat.

- **Stop when** a round returns zero actionable fails, OR the round cap is hit
  (default **5**, raise it for a hero piece), OR the user stops it.
- **Log each round** — "Round 3 — 3 fails: no logo, broke monochrome, headline
  under-scaled." The round-by-round trail is the proof of quality; keep it.
- Let it converge naturally. Once critics stop finding real faults, stop — don't
  grind extra rounds for cosmetics.

## Phase 5 — Report

Deliver: the final artifact + the round-by-round critique trail + an approximate
token cost.

## Cost & when to use

The loop is expensive — millions of tokens across rounds × critics. **Reserve it
for high-value, reusable artifacts** (templates, hero pieces, carousels, key
screens), not routine tweaks. State the rough cost before a long run. Keep the
taste generator on Claude — that's where design judgment lives — and push the
mechanical critics to cheaper models. One artifact per loop.

## For skill authors — wiring this in

Any design skill can delegate verification here. After building, invoke
`design-critic-loop` and pass your skill's checklist as the **System** (and, where
it encodes taste, **Craft**) rubric:

- `mac-app-design` → passes the Mac App Done Rubric from `Mac Interface Contract.md`.
- `figma-design` → passes its token contract + craft bar.
- A project workflow → passes its `DESIGN.md`.

Copy-paste critic subagent prompts: `references/critic-prompts.md`.
