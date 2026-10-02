---
name: fan-out
description: >-
  Runs one design exploration round: fans a brief and copy out into independent variants, each built by a named skill and model, and captures them for side-by-side review. Use when asked to run a round, fan out, or spawn N variants. Not for choosing a winner or polishing one design.
---

# Fan-out

One exploration round. The owner is diverging, not selecting: the round's job
is to produce a handful of variants that each commit hard to a distinct
premise, so the owner can harvest what moves them into the next brief. Nothing
here ranks, votes, or merges.

Read `../../templates/Round Sheet.md` for the input shape.

## Inputs

A round needs four documents, all owned by the project, none invented here.
`design:direction-brief` produces the second and third with the owner, saves
the references they point at, and drafts the round sheet:

1. **The frozen brief** (identity brief, brand brief, whatever the project
   calls it). What is fixed, what is banned, character words, personas.
2. **One direction brief per direction in the round**, in the shape of
   `templates/Direction Brief.md`: premise, type, hard rules, Wins if /
   Loses if, and a **Reference pack**.
3. **One copy direction**, verbatim lines plus the rules for lines the builder
   has to write.
4. **The project's variant build brief**, produced with `design:variant-brief`.
   It owns the done gates, the off-limits files, the report format, and the
   project's own traps.

Plus **the round sheet**: its `medium` (`html`, the default: one
self-contained page per variant beside the direction brief; or `code`: a
route in the project's real stack on a direction branch), and one row per
variant with `id`, `direction`, `copy`, `method` (exactly one design skill, or
`none`), `route` (a Harness semantic route, or a Claude model alias for a local
subagent), optional `dials`, and the reference entries this variant borrows
from. If any input is missing, ask once,
batching every question, then run to the end state: a round index handed back.

## Rules that make the round worth its cost

- **Cap the round at seven variants.** Review attention, not generation, is the
  ceiling; past five to seven the owner stops seeing them.
- **One method per variant.** A builder invokes exactly the skill its row names
  and no other. Two skills on one variant make the result unattributable.
- **Diversity comes from the sheet, not from luck.** Vary direction, reference
  pack, and dials across rows before varying model. Two rows that differ only
  in model are an ablation, and the sheet should say so.
- **Builders are independent.** A builder reads the sibling variants that
  already exist (the build brief requires it) but never another builder's
  in-progress work or conversation.
- **Builders return paths and screenshots, not code.** Their report follows the
  build brief's format; the round index collects those reports.
- **Exploration is `html`; convergence is `code`.** In the `html` medium a
  variant is one file, the direction's shared `tokens.css` is the only shared
  surface, and there are no worktrees, servers, or registries to prepare. The
  `code` medium is for rebuilding the survivor in the project's stack once
  Carry forward stops growing; its variants live on a direction branch and
  never touch `main`.

## Procedure

1. **Validate the sheet.** Every row resolves: its direction passes
   `design:direction-brief`'s `check-brief.mjs`, copy direction exists, method is installed (or `none`), route is one the Harness
   rubric knows or a Claude alias. Reject a sheet over seven rows.
2. **Prepare the medium.** `html`: confirm the direction folder exists with
   its brief and, after the first variant, its `tokens.css`; pick the next free
   letter from `Snapshots.json`. `code`: one worktree per direction branch,
   dev server or preview running and reachable before dispatch (a builder must
   not start a second one), following the project's preview convention.
3. **Assemble each builder's packet:** the variant build brief, the direction
   brief, the copy direction, and the output (`html`: the file path and letter;
   `code`: the worktree, the route, and the running server). The build brief
   says a builder asks if one is missing.
4. **Dispatch in parallel.**
   - A row whose `route` is a Claude alias runs as a local subagent. If a
     personal agent named `design-builder-<method>` exists, use it with the
     row's model; otherwise spawn a general-purpose subagent, tell it to invoke
     exactly that skill, and pass the packet.
   - A row whose `route` is a Harness semantic route (`taste`, `default`,
     `bulk`) goes through `harness:delegate` with `operation: execute`, the
     packet as context, the project root (`html`) or the worktree (`code`) as
     `authority.working_directory`, allowed paths limited to the variant's own
     output (`html`: its file, plus `tokens.css` for a direction's first
     variant; `code`: its route folder plus the registry file), and the build
     brief's verify checklist as the acceptance check. Harness
     resolves the model; the round index records what it resolved.
   - In `html`, builders on the same direction write different files and may
     run at once; only the first variant of a direction writes `tokens.css`. In
     `code`, never dispatch two rows to one worktree unless the build brief's
     off-limits rules make their write sets disjoint.
5. **Gate first drafts.** When the sheet sets `critic: explore` (the default
   for a fan-out), run `design:first-draft-critic` in explore mode on each
   finished variant and give the builder one fix pass. Skip when the sheet says
   `critic: none`.
6. **Show the round.** Picture the variants, then put them where the owner
   reviews.
   - **Pictures.** `html`: the variants are files; run `design:present`'s
     `frames.mjs` and look at the pictures (an incomplete one means the variant
     fails the reduced-motion gate). `code`: freeze the running routes with
     `design:capture`'s `freeze.mjs` and read its per-plate diffs, export the
     build as a static site and bring it in with `design:present`'s
     `import-build.mjs`, then run `frames.mjs`.
   - **Figma**, when the round sheet names a file: follow `design:present`
     § Review in Figma. For every variant, create its column, place its
     screens, and store its page address on the column frame
     (`setSharedPluginData('design_gallery', 'page', …)`), which is what makes
     the variant open its live page in the Figma plugin. Read each address
     back after writing it, and check one of them answers from the server the
     round sheet names. A variant placed without its address is not finished.
   - **Gallery**, otherwise: make sure it is running and give the owner the
     direction's address.
7. **Write the round index** into the round sheet's Results section: for each
   variant, the method, the resolved model and effort, the file or route, its
   page address and Figma frame when placed, the builder's self-review pass
   count, and the critic's
   remaining fails if any. Then stop. Do not rank, do not recommend a winner.

## After the round

The owner looks at the round in the Figma file or the gallery, opens a
variant's live page (in Figma, by selecting it with the Design Gallery plugin
running), and edits a variant in the page when they want to push it
(`design:present` § Edit a variant).
What they say they want more of goes into the next direction brief's **Carry
forward** block through `design:direction-brief` (element, which variant it
came from, the owner's words as the why). That section is the round's only
lasting record; the variants are probes. When Carry
forward stops gaining new lines across two rounds, exploration is over and the
briefs can turn prescriptive; hand the survivor to `design:first-draft-critic`
in gauntlet mode.
