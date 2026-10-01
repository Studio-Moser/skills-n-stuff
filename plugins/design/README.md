# Design

Design exploration rounds for [Claude Code](https://code.claude.com). One brief
and one copy doc fan out into several independent HTML variants, each built by
a named skill and model; fresh-context critics push each first draft further
into its own premise; the variants land as live frames on a shared Doop canvas
where the owner's pinned comments flow back into the next brief. Nothing here
picks a winner. The owner harvests what moved them into the next
brief, and the briefs turn prescriptive as the exploration converges.

[![skills.sh](https://skills.sh/b/Studio-Moser/skills-n-stuff)](https://skills.sh/Studio-Moser/skills-n-stuff)

## Skills

| Skill | Role | What |
| --- | --- | --- |
| `/design:fan-out` | Round runner | Validates a round sheet (max seven variants, one skill each), prepares the medium (files for `html`, worktrees for `code`), dispatches builders as local subagents or through Harness, gates first drafts, freezes, writes covers, publishes, and writes the round index |
| `/design:variant-brief` | Brief author | Cuts the project's variant build brief from the shared template, keeping the discipline verbatim and filling the project's slots |
| `/design:first-draft-critic` | Critic loop | Explore mode (two lenses, pushes toward the premise, two rounds) inside a fan-out; gauntlet mode (three lenses against a written done bar, five rounds) for convergence and hero pieces |
| `/design:canvas` | Review surface | One self-hosted Doop server for every project; publishes each direction as its own canvas (a cover first, a full-height frame of plates per variant, a live one-screen frame above each `html` variant for Present) and harvests element-pinned comments into the next brief's Carry forward |
| `/design:capture` | Freezes and screenshots | `freeze.mjs` freezes a running page or an HTML file into plates (one settled screen per scroll stop, checked against the live page); `views.mjs` shoots per-viewport stills and motion strips for critics; stitched, banded captures for Figma when that is the destination |

## Templates

- `templates/Direction Brief.md`: premise, type, hard rules, Wins if / Loses
  if, plus **Carry forward** (what the owner harvested last round and why) and
  **Reference pack** (the one move to borrow from each reference).
- `templates/Round Sheet.md`: one row per variant with method, route, dials,
  and borrows; the Results section is the round index.
- `templates/Variant Build Brief.md`: what every builder reads first.

## Two mediums

- **`html`** (exploration, the default): a variant is one self-contained page
  beside the direction brief; the direction's `tokens.css` is the only shared
  surface. No worktrees, servers, or registries. Variants are reviewed on the
  canvas and are probes, not production code.
- **`code`** (convergence): the survivor is rebuilt in the project's real stack
  on a branch, with gauntlet-mode critics and the project's verify gates.

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
5. `canvas` publishes each direction as its own canvas, cover first; the round index records method,
   resolved model, file, frame name, and remaining fails.
6. The owner looks on the canvas and pins comments; `canvas` § Harvest turns
   them into the next briefs' Carry forward. When Carry forward stops gaining
   lines across two rounds, exploration is over.

## Requirements

- Design skills installed on the machine for the methods a round names
  (`impeccable`, `frontend-design`, `design-taste-frontend`, `hallmark`, or
  others); the plugin ships none of them.
- Harness for delegated builders (`/plugin install harness@studio-moser`).
- For `canvas`: Docker plus `preview:serve-preview`'s router on one host, a
  clone of [kgoedecke/doop](https://github.com/kgoedecke/doop), and the `doop`
  MCP registered on each machine (`claude mcp add --transport http --scope user doop <url>/mcp`).
- For `capture`: Playwright with Chromium and `sharp` resolvable from the
  project root.
- Optional personal agents `design-builder-*` and `design-critic-*` in
  `~/.claude/agents`; the skills fall back to general-purpose subagents with
  the bundled prompts.

## Verification

```bash
./tests/run-tests.sh
```
