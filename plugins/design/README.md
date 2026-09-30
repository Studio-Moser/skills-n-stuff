# Design

Design exploration rounds for [Claude Code](https://code.claude.com). One brief
and one copy doc fan out into several independent variants, each built by a
named skill and model; fresh-context critics push each first draft further into
its own premise; stitched captures land side by side for the owner to look at.
Nothing here picks a winner. The owner harvests what moved them into the next
brief, and the briefs turn prescriptive as the exploration converges.

[![skills.sh](https://skills.sh/b/Studio-Moser/skills-n-stuff)](https://skills.sh/Studio-Moser/skills-n-stuff)

## Skills

| Skill | Role | What |
| --- | --- | --- |
| `/design:fan-out` | Round runner | Validates a round sheet (max seven variants, one skill each), prepares worktrees, dispatches builders as local subagents or through Harness, gates first drafts, captures, and writes the round index |
| `/design:variant-brief` | Brief author | Cuts the project's variant build brief from the shared template, keeping the discipline verbatim and filling the project's slots |
| `/design:first-draft-critic` | Critic loop | Explore mode (two lenses, pushes toward the premise, two rounds) inside a fan-out; gauntlet mode (three lenses against a written done bar, five rounds) for convergence and hero pieces |
| `/design:capture` | Screenshots | Stitched captures at one width, cut into bands Figma's editor will draw, with a manifest for the upload; fails loudly on overflow, broken images, or blank renders |

## Templates

- `templates/Direction Brief.md`: premise, type, hard rules, Wins if / Loses
  if, plus **Carry forward** (what the owner harvested last round and why) and
  **Reference pack** (the one move to borrow from each reference).
- `templates/Round Sheet.md`: one row per variant with method, route, dials,
  and borrows; the Results section is the round index.
- `templates/Variant Build Brief.md`: what every builder reads first.

## How a round works

1. Direction briefs carry a Reference pack and a Carry forward section.
2. The round sheet lists up to seven variants. Diversity comes from direction,
   reference pack, and dials before model; two rows differing only in model are
   an ablation and say so.
3. `fan-out` dispatches. Claude builders run as local subagents; when a
   personal agent named `design-builder-<skill>` exists it is used, so one skill
   is preloaded and no other. Other rows go through `harness:delegate` with a
   semantic route; Harness resolves the model.
4. `first-draft-critic` in explore mode gives each variant one fix pass against
   its own Wins if / Loses if and the craft gates. No system lens, no taste
   opinions.
5. `capture` shoots the round; the round index records method, resolved model,
   URL, captures, and remaining fails.
6. The owner looks and writes Carry forward into the next briefs. When Carry
   forward stops gaining lines across two rounds, exploration is over.

## Requirements

- Design skills installed on the machine for the methods a round names
  (`impeccable`, `frontend-design`, `design-taste-frontend`, `hallmark`, or
  others); the plugin ships none of them.
- Harness for delegated builders (`/plugin install harness@studio-moser`).
- For `capture`: Playwright with Chromium and `sharp` resolvable from the
  project root.
- Optional personal agents `design-builder-*` and `design-critic-*` in
  `~/.claude/agents`; the skills fall back to general-purpose subagents with
  the bundled prompts.

## Verification

```bash
./tests/run-tests.sh
```
