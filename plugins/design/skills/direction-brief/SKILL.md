---
name: direction-brief
description: >-
  Use to start or revise a design direction: a guided interview that turns the
  owner's hunch and references into a direction brief and a copy direction, and
  saves every reference (URLs captured as screenshots, images, files) into the
  direction's folder for builders to look at. Ends with a readiness check and a
  drafted round sheet, so nothing a round needs is missing. Triggers: "new
  design direction", "start a direction", "let's write a design brief", "brief
  this direction", "write the copy brief", "here are some references".
---

# Direction brief

A direction is a design premise the owner arrives at by mashing references
together. This skill gets that out of the owner's head and into the documents
a round needs, in the order the owner thinks: references first, premise second,
rules last. It ends when `check-brief.mjs` passes and a round sheet is drafted;
`design:fan-out` takes it from there.

What it produces, all owned by the project:

```
{directions dir}/{NN Name}/
  Brief.md                 from templates/Direction Brief.md
  References/
    References.md          one entry per reference: source, date, the owner's words, files
    01 {Source}/           a captured URL: view stills, motion strips, report.json
    02 {Name}.png          an image or file the owner supplied
  DESIGN.md                the direction's design context, once it is being refined
{copy dir}/{NN Name}/{Page}.md   from templates/Copy Direction.md (when the copy is new)
```

The brief is named `Brief.md`; `design:present` reads it, the references, and
`DESIGN.md` from this folder and shows them on the direction's page.

## How to run the interview

- **Read before asking.** Never ask what a project document already answers.
  Stage 0 is silent reading; its output is one short message of what was found
  and what is missing.
- **Ask in stages, a few questions at a time.** At most four per turn. Use
  choices where the answer is one of a known few; ask open questions in plain
  text where the owner's wording is the content.
- **Draft, then ask for correction.** From stage 3 on, write the section and
  ask what is wrong with it. An owner corrects a draft faster and more honestly
  than they fill a blank.
- **Keep the owner's words.** Why a reference moves them is recorded verbatim
  in `References.md` and in Carry forward. Do not tidy it into design language.
- **Look forward.** Do not ask the owner to rank, score, or revisit earlier
  variants. What carries forward is what they already said they want more of.
- **Invent nothing.** A typeface's licence, a fact in the copy, a client name:
  verified from a source and dated, or marked open for the owner.

The question bank, with when to ask and when to skip each one, is in
`references/Interview.md`.

## Stage 0: read the project

Find, without asking: the directions folder and the next free number; the
frozen brief (identity or brand brief: what is fixed, what is banned, character
words, personas); the copy or voice rules; the copy directions folder; the
facts files; the variant build brief; the project's inspiration archive, if it
has one; every existing direction's `Brief.md` (read each Premise, for
Siblings). If the direction already has a round, ask the owner what they want
carried forward from it, in their words; that is this brief's Carry forward.

Then tell the owner what exists and what is missing. A missing frozen brief is
written first, from `../../templates/Frozen Brief.md`, using the project
questions in the interview file. A missing variant build brief is written after
this one, with `design:variant-brief`.

## Stage 1: the seed

The working name, the hunch in the owner's own words, the pages in scope, and
the **phase**, which sets how much this brief decides and how much it leaves to
builders:

- **wide**: early exploration. Premise, references, and a few hard rules; type
  shortlisted rather than chosen; page structure left open.
- **tightening**: the owner has harvested at least one round. Carry forward is
  filled; type is chosen; structure is sketched.
- **prescriptive**: converging. Every section is decided and builders vary
  execution only.

## Stage 2: references

Ask for everything that is in the owner's head for this direction: URLs,
screenshots, photographs, files, entries in the project's inspiration archive,
even a sentence describing something they cannot find again. For each one:

1. **Save it** under `References/` with a number and a Title Case name.
   - **A URL**: capture it with `design:capture`'s `views.mjs`, from the
     project root:
     `node "${CLAUDE_PLUGIN_ROOT}/skills/capture/scripts/views.mjs" <url> "<direction folder>/References/NN <Source>" --widths 1440,390`.
     It writes one still per screen, a motion strip per transition, and
     `report.json`. Exit code 1 here usually means the third-party page logged
     console errors, which does not matter; open `1440-01.png` and check the
     page actually rendered. A cookie wall, a login, or a bot check renders
     instead of the page: hide the banner with `--hide "<selector>"`, or ask
     the owner for a screenshot.
   - **An image or screenshot attached in the conversation**: copy the file
     from the path the conversation gives. If it is visible only inline, ask
     for the file.
   - **A file on disk, a PDF, a design-tool link**: copy the file, or export
     the frame or page as an image with the tool available for it.
   - **An entry in the project's inspiration archive**: do not copy it; point
     at it.
   - **A description with no artifact**: record the words; it is still a
     reference.
2. **Look at it.** Open the saved images before saying anything about them.
3. **Ask what moves the owner in it**, and write the answer down verbatim.
4. **Propose the one move to borrow and the thing that would make it a copy.**
   Screenshots carry surface; they do not carry structure, so name the
   structural choice (what leads, how the page is paced, where the type breaks
   the grid) and get a yes or a correction.

Add an entry to `References/References.md` for each (source, capture date, the
owner's words, the files worth opening first). The brief's **Reference pack**
table carries the binding part: path, borrow this, not this. Aim for two to
four references in the pack. With more than five, ask which lead; the rest stay
in the folder as background.

Search for references only when the owner asks for more; a direction built on
references the agent picked is the agent's direction.

## Stage 3: the premise

Draft, from the references and the hunch: the **Premise** (the single argument,
and the one thing this direction does that no sibling can do without becoming
it), **Why this is not** the closest thing the owner has already rejected, and
the **Siblings** line. Ask what is wrong with it. Repeat until the owner would
say it that way themselves.

## Stage 4: the system

Draft each section from the references, the frozen brief, and the phase, and
ask only about gaps: **Type** (faces, roles, licence and axes verified with the
date, delivery; a shortlist in the wide phase), **Hard rules** (each stops one
named failure), **Motion** (load, scroll, pointer, and the reduced-motion page,
which must still be recognisably this direction), **Page structure** (to the
depth the phase calls for), **Scope and checks**.

## Stage 5: wins and loses

Draft **Wins if** and **Loses if** as lines a critic with no context could
check from screenshots, each Loses if mapped to the hard rule that was not
held. These lines are what `design:first-draft-critic` judges every variant
against, so a vague line here becomes a vague critique later.

## Stage 6: the copy direction

Design and copy are separate axes: one copy direction is used by variants in
several design directions. Ask whether this direction uses an existing copy
direction or needs a new one. For a new one, work from
`../../templates/Copy Direction.md`: the bet, the posture, then the page
section by section. Lines the owner already has go in verbatim; the rest are
drafted from the facts files and approved by the owner line by line, because
builders use them verbatim. Finish with the rules for the few lines a builder
has to write (labels, alt text, captions).

## Stage 7: check, then hand over

Run the readiness check from the project root:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/direction-brief/scripts/check-brief.mjs" "<direction folder>" [--copy "<copy direction file>"]
```

It fails on a missing section, an unfilled `{slot}`, a Reference pack with
fewer than two entries or a path that does not exist, fewer than two Wins if or
Loses if lines, a Motion section that never says what happens under reduced
motion, or a missing copy file. Fix what it lists; do not hand over a failing
brief.

Then draft the round sheet from `../../templates/Round Sheet.md`: up to seven
rows, varying the reference entries and dials before the model, each naming
one method and one route. Show the owner the brief's Premise, the Reference
pack, and the sheet's rows in one message, and ask for the go-ahead to run
`design:fan-out`.

## Revising a direction for the next round

Same skill, shorter path: ask what carries forward (stage 0), rewrite **Carry
forward** in the owner's words, add any new references (stage 2), move the
phase forward when the owner says so, tighten whatever that settled, and re-run
the check. When the phase reaches tightening, write the direction's
`DESIGN.md` from the brief's Type, colour, and Hard rules and its `tokens.css`:
it is what live editing reads to stay inside this direction.
Do not rewrite the Premise unless the owner changes it; a direction whose
premise changes is a new direction with a new number.
