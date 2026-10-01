---
name: variant-brief
description: >-
  Use when a project needs the document handed to every agent that builds one
  design variant: the variant build brief. Creates or revises it from the
  plugin template, keeping the project-agnostic discipline verbatim and filling
  the project's own slots (fixed items, off-limits files, traps, verify
  commands). Triggers: "write the variant brief", "set up a build brief for
  variants", "what do builders get handed".
---

# Variant brief

The variant build brief is the one document every builder reads first. It
carries the discipline that makes variants comparable (one method per variant,
a different argument rather than a different skin, the first variant sets the
system, self-review by screenshot, a fixed report format) and the project's own
facts (what is frozen, what is off limits, which traps have already cost an
afternoon). Keep the two apart: the discipline is shared across projects and
lives in the template; the facts are the project's and live in its slots.

## Produce it

1. Read `../../templates/Variant Build Brief.md`. Everything outside a
   `{slot}` is the shared discipline; copy it as written. Rewording it is how
   two projects end up with briefs that disagree.
2. Read the project's frozen brief, its directions README (or equivalent),
   and its existing verify commands. Fill each slot from those sources and
   point at them; do not restate a rule that already lives in one of them.
   One fact, one owner.
3. Write the brief to the project's docs folder under the project's naming
   convention (`docs/Variant Build Brief.md` when there is no convention).
4. Record in the brief's header which template version it was cut from, so a
   later template change can be diffed in.

## Revise it

A brief earns a revision when a builder hits something that cost real time and
was not written down: a framework rule that fails silently, a capture that
paints blank, a file that must be appended to rather than edited. Add it to the
**Traps** slot as a short paragraph with the symptom, the cause, and the fix
already in the codebase. Do not add taste; taste belongs to the direction brief.

## Slots

| Slot | Source | Notes |
| --- | --- | --- |
| `{frozen brief}` | the identity or brand brief | sections a builder must read, by number |
| `{copy rules}` | voice or copy rules doc | followed exactly |
| `{directions readme}` | how a direction folder (`html`) or branch (`code`) is laid out and run | |
| `{facts files}` | typed content, case studies, settings | real names and numbers only; invent nothing |
| `{fixed items}` | frozen brief | palette hex values, marks, textures, brand rules |
| `{off limits}` | project layout | shared layout, globals, chrome, package exports, other variants' routes |
| `{registry}` | the one shared file a variant appends to | with the entry shape |
| `{route convention}` | where variants live | e.g. `routes/<letter>/` or `variants/<letter>/` |
| `{traps}` | past afternoons | symptom, cause, fix in the codebase |
| `{imagery rule}` | frozen brief | generated stand-ins, provenance log, never ship |
| `{done gates}` | project's craft floor | pass/fail lines only |
| `{banned}` | frozen brief lane list plus house design law | |
| `{skills installed}` | the machine | one line each; the task names which one to invoke |
| `{verify}` | scripts and checks | the commands and the browser checks at two widths |
| `{report}` | | the fields the round index needs |
