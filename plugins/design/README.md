# Design

Design exploration rounds for [Claude Code](https://code.claude.com). One brief
and one copy doc fan out into several independent HTML variants, each built by
a named skill and model; fresh-context critics push each first draft further
into its own premise; a local gallery shows every direction with its brief,
references, design system, and variants, and the owner edits a variant in the
page with impeccable live. Nothing here picks a winner. The owner harvests
what moved them into the next brief, and the briefs turn prescriptive as the
exploration converges.

[![skills.sh](https://skills.sh/b/Studio-Moser/skills-n-stuff)](https://skills.sh/Studio-Moser/skills-n-stuff)

## Skills

| Skill | Role | What |
| --- | --- | --- |
| `/design:direction-brief` | Direction interview | Guides the owner from a hunch and a pile of references to a direction brief and a copy direction: asks only what the project's documents do not answer, captures every URL as view stills and saves every image into the direction's `References/` folder, drafts each section for correction, then runs a readiness check and drafts the round sheet |
| `/design:present` | Presenting a round | A dependency-free local server over the directions folder: a grid of directions, and per direction its variants as whole-scroll pictures, its full brief, saved references, and design system. A variant opens in a resizable preview with device sizes, shows its notes, or opens for in-page editing with impeccable live. `frames.mjs` pictures each variant a screen at a time at desktop (1440 × 900) and mobile (360 × 800), for the gallery's grids and for a Figma file whose labels link back to the live preview; editing is offered only on the machine running the gallery; `import-build.mjs` brings a framework build's static export into a direction so its real pages play from the repository |
| `/design:fan-out` | Round runner | Validates a round sheet (max seven variants, one skill each), prepares the medium (files for `html`, worktrees for `code`), dispatches builders as local subagents or through Harness, gates first drafts, and writes the round index; `html` variants appear in the gallery as written |
| `/design:variant-brief` | Brief author | Cuts the project's variant build brief from the shared template, keeping the discipline verbatim and filling the project's slots |
| `/design:first-draft-critic` | Critic loop | Explore mode (two lenses, pushes toward the premise, two rounds) inside a fan-out; gauntlet mode (three lenses against a written done bar, five rounds) for convergence and hero pieces |
| `/design:capture` | Freezes and screenshots | `views.mjs` shoots per-viewport stills and motion strips for critics and for saved references; `freeze.mjs` freezes a viewport-driven framework page into plates (one settled screen per scroll stop, checked against the live page); stitched, banded captures for Figma when that is the destination |

## Templates

- `templates/Direction Brief.md`: premise, type, hard rules, Wins if / Loses
  if, plus **Carry forward** (what the owner harvested last round and why) and
  **Reference pack** (the one move to borrow from each reference).
- `templates/Copy Direction.md`: the bet, the page line by line (used
  verbatim), the rules for lines a builder writes, and the source of every fact.
- `templates/Frozen Brief.md`: the project-level brief every direction sits
  under, for a project that has none yet.
- `templates/Round Sheet.md`: one row per variant with method, route, dials,
  and borrows; the Results section is the round index.
- `templates/Variant Build Brief.md`: what every builder reads first.

## Two mediums

- **`html`** (exploration, the default): a variant is one self-contained page
  beside the direction brief; the direction's `tokens.css` is the only shared
  surface. No worktrees, servers, or registries. Variants are reviewed in the
  gallery and are probes, not production code.
- **`code`** (convergence): the survivor is rebuilt in the project's real stack
  on a branch, with gauntlet-mode critics and the project's verify gates.

## How a round works

1. `direction-brief` interviews the owner, saves the references, and writes
   the direction brief (Reference pack, Carry forward) and copy direction.
2. The round sheet lists up to seven variants. Diversity comes from direction,
   reference pack, and dials before model; two rows differing only in model are
   an ablation and say so.
3. `fan-out` dispatches. Claude builders run as local subagents; the plugin's
   `design:design-builder-<skill>` agent is used, so one skill is preloaded and
   no other. Other rows go through `harness:delegate` with a
   semantic route; Harness resolves the model.
4. `first-draft-critic` in explore mode gives each variant one fix pass against
   its own Wins if / Loses if and the craft gates. No system lens, no taste
   opinions.
5. `gallery` shows the round as soon as the files exist; the round index records method,
   resolved model, file, frame name, and remaining fails.
6. The owner looks in the gallery, edits variants in the page with impeccable
   live, and says what to carry forward; `direction-brief` writes it into the
   next briefs' Carry forward. When Carry forward stops gaining
   lines across two rounds, exploration is over.

## Requirements

- Design skills installed on the machine for the methods a round names
  (`impeccable`, `frontend-design`, `design-taste-frontend`, `hallmark`, or
  others); the plugin ships none of them.
- Harness for delegated builders (`/plugin install harness@studio-moser`).
- For `gallery`: Node only. Editing a variant needs impeccable installed and
  a `PRODUCT.md` at the project root.
- For `capture`, and `design:present`'s `frames.mjs` and `import-build.mjs`:
  Playwright with Chromium and `sharp` resolvable from the project root.
- The builder agents (`design:design-builder-*`) each preload one design skill
  (`impeccable`, `hallmark`, `frontend-design`, `design-taste-frontend`), which
  must be installed separately; without it the skills fall back to
  general-purpose subagents with the bundled prompts.

## Verification

```bash
./tests/run-tests.sh
```
