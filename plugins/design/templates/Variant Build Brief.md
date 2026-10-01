# Variant build brief

Template: design plugin 0.1.0. Text outside `{slots}` is shared discipline; copy
it as written. Fill slots from the project's own documents and point at them.

You are building one variant for one direction of the {project} identity
exploration. A direction is a design premise; a variant is one execution of
it. A direction may have many variants, and they exist to be compared, so yours
has to make a different argument rather than a different skin.

Your task names the direction, the copy direction, the design skill to use,
and your output: in the `html` medium, the file path and letter; in the `code`
medium, the worktree, the route, and the running dev server. If any of those is
missing, ask before building.

## Medium

**`html` (exploration).** Your variant is one file,
`{directions dir}/{NN Name}/Homepage <X> - <Title>.html`, complete on its own:
inline `<style>`, fonts by `@font-face` with a self-hosted or data URL, images
inline or from the project's imagery folder, no framework, no build step, no
build step. The
direction's shared type and tokens live in `{NN Name}/tokens.css`; the first
variant writes it, later variants paste it into their `<style>` unchanged (a
frame on the canvas cannot fetch a relative file). It is a normal page: it
scrolls, it may size sections to the viewport, and it may carry a small inline
script for motion CSS cannot do, as long as it needs no network, storage, or
same-origin access (a canvas frame is sandboxed). Verify by opening the file in
a browser at 1440 and 390. The round freezes it into plates for the canvas;
you do not write those. Nothing here touches the project's application code.

**`code` (convergence).** Your variant is a route in the project's real stack,
on the direction's branch, in its worktree, against its running dev server.
The sections below on the system, off-limits files, the registry, and traps
apply in full.

## Read first

- `{frozen brief}`: the identity or brand brief and the intent behind everything below.
  Read {the sections a builder needs, by number}. The pass/fail rubric is not
  there; it is § Done gates in this file.
- `{copy rules}`: follow them exactly.
- `{directions readme}`: how a direction branch is laid out and run.
- **Your direction's brief.** It is the design decision, already made. Execute
  that premise; do not substitute a new one. If you believe the premise is
  wrong, say so in your report and build it anyway. Its **Carry forward**
  section tells you what the owner harvested from the last round and why;
  extend those ideas, do not copy them. Its **Reference pack** names the one
  move to borrow from each reference and the thing that would make it a copy.
- **Your copy direction.** Its lines are the copy, verbatim. Its brief states
  the rules that bind any line you have to write yourself. Design and copy are
  separate axes: the same copy is used by variants in several directions, so
  the words are not yours to re-argue.
- **Every variant that already exists for this direction**, listed in
  `{registry}`. You cannot make a different argument from the others without
  knowing what they argue.
- `{facts files}`: the real facts when your copy direction does not supply
  one. Real names, years, nouns, and numbers only. Invent nothing. Where copy
  and facts disagree, copy wins for words and facts win for facts; if the
  conflict is a fact, report it rather than picking a side.

## Two situations

**The direction has no variants yet.** You are establishing its design system:
type, tokens beyond the frozen palette, recipes, components (`html`: the
direction's `tokens.css`). Build them as a system rather than as one page's
styling, because every later variant reuses them.

**The direction already has variants.** Its design system exists. Reuse it. Do
not modify it, do not modify another variant's route, and do not restyle the
system to suit your layout. If a component genuinely does not fit, write a new
one inside your own route folder and say why in your report. A parallel set of
near-identical components is the wrong answer.

Either way, everything you write lives in your own route folder.

## What "a different argument" means

Not a reskin and not a reshuffle. Change what the page claims and the shape it
claims it in. Things worth moving: what the first screen leads with, the order
the proof arrives in, how much of the page is imagery versus words, the scale
contrast, the density, where colour lands, and what the page does as you
scroll. Keep the premise, the fixed items, and the direction's type.

Commit fully. In an exploration round a safe average of the siblings is the one
result with no value. If you conclude an existing variant is already the right
answer, say so in your report rather than producing a near-copy.

## Fixed, not yours to change

{fixed items: palette hex values, marks, blend rules, grain, with the file each
lives in}

## Off limits

{off limits: shared layout, globals, chrome, config, package exports, every
other variant's route folder; on a direction that already has variants, also
its tokens, fonts, recipes, and components}

One exception: register yourself in `{registry}` when you are done. It is the
direction's index of its own variants and the only shared file you may append
to. Entry shape: {entry shape}.

## Where variants live

{route convention}. Letters carry no meaning on their own; the registry
carries all of it: the title, what the variant argues, which design skill
built it, and the date.

## Traps

{traps: one short paragraph each, with the symptom, the cause, and the fix
already in the codebase. Framework rules that fail silently, scroll containers
that eat sticky and scroll-driven motion, captures that paint blank.}

## Imagery

{imagery rule: generated stand-ins for exploration only, never shipped, each
with a full placeholder spec and a provenance log entry. No AI-generated page
mockups: they invent the studio and its clients, drop whichever rule makes a
direction distinct, and cannot be checked for contrast. Build in real code.}

## Design skills

Your task names the design skill to invoke, and you follow it exactly,
including when it says to invoke none. Variants are compared partly on how
they were made, so reaching for a skill you were not given, or skipping one
you were, destroys the comparison. Invoke exactly one unless told otherwise;
stacking two makes the result unattributable. Say which one you used in your
report.

{skills installed: one line each, what it does and how it differs}

## Self-review while you build

After the hero and after each major section, take a screenshot at 1440px and
judge it against your direction brief's Wins if / Loses if. Fix what fails.
Count the pass. Report how many passes you ran and what each one changed.

## Done gates

Pass/fail lines. A variant clears every one before it is captured.

**Brief**

- [ ] A critic cannot name the template lane this belongs to.
- [ ] Every fixed item is unchanged.
- [ ] No decorative label pattern repeats above every section; a label earns
      its place by adding information.
- [ ] {persona and funnel lines from the frozen brief}

**System**

- [ ] Identity changes live in tokens, fonts, recipes, and components; no new
      hex, radius, or spacing outside tokens. Page files change only for
      composition and copy.
- [ ] {shared export or token contract is byte-identical}

**Craft**

- [ ] WCAG AA contrast for every piece of text, including text over colour, at
      every breakpoint.
- [ ] Layout holds at 390px: no horizontal scroll, no overlapped or hidden copy.
- [ ] Under `prefers-reduced-motion` the page is a normal long-scroll document:
      no fixed or sticky stage, every scene's ground, imagery and type present
      in flow in its final lockup, nothing that exists only in a scroll state,
      and no idle motion. Stopping the animations is not enough; a stage frozen
      on its first scene hides every other scene from the people who asked for
      less motion. (`freeze.mjs --flow` tests this.)
- [ ] Visible focus ring on every interactive element, on every ground.
- [ ] No font-swap layout shift beyond the current baseline.
- [ ] {copy rules that are checkable: punctuation, casing}

## Banned outright

{banned: the frozen brief's lane list, plus house design law such as gradient
text, side-stripe accent borders, decorative glassmorphism, the big-number
hero-metric template, identical repeating card grids, nested cards}

## Verify before you report done

At 1440 and 390 wide: no horizontal overflow
(`document.documentElement.scrollWidth <= clientWidth`), every visible image
has `naturalWidth > 0`, no console or page errors after a full scroll, motion
still under `prefers-reduced-motion: reduce`. Then screenshot both widths.

Then run {verify: the project's typecheck, lint, test, format commands}.

## Report

Return paths and screenshots, not code. Fields, in this order:

- **Variant:** direction, letter, route, title.
- **Argues:** one line.
- **Method:** the one skill invoked, or `none`; for the taste method, the three
  dial values.
- **System:** established or reused; any new component inside your route and why.
- **Self-review:** number of passes and what each changed.
- **Gates:** each done gate as pass or fail; every fail with the reason.
- **Screenshots:** paths at 1440 and 390.
- **Flags:** anything you disagree with in the brief, any fact conflict, any
  trap you hit that is not written down yet.
