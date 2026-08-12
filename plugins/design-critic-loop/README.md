# design-critic-loop

A Claude Code plugin that raises any design to a high bar with the **Gauntlet
Loop** — independent, fresh-context critics instead of letting the generator
grade its own homework.

A model that just built a design is the worst judge of it: it decides "looks
done" and inherits its own blind spots. This skill spins up separate critic
subagents — **brief** (did it do what was asked?), **system** (does it obey the
tokens/checklist?), and **craft** (does it hit the taste bar?) — that judge
against an explicit definition of done, then loops build → critique → fix until
the critics stop finding real faults.

## What's inside

- **`design-critic-loop`** skill:
  - **Phase 0 defines "done" first** — and if the bar is unclear (vague
    aesthetic, no reference, thin brief), it asks the user for goals and reference
    examples *before* burning tokens, then restates the rubric for a yes.
  - Three independent fresh-context critics with a model-routing rule (taste →
    Claude; mechanical → cheap models — because weak judges falsely reject good
    work).
  - Converges naturally, logs a round-by-round critique trail, and flags cost.
  - Reusable by other design skills (`mac-design`, `figma-design`, a project
    `DESIGN.md`) — they pass their own checklist as the rubric.

## Install

```
/plugin marketplace add Studio-Moser/skills-n-stuff
/plugin install design-critic-loop@studio-moser
```

Invoke on any design ("run the gauntlet on this", "critique this design"), or let
another design skill call it after building. **Reserve it for high-value /
reusable artifacts** — the loop is token-expensive.
