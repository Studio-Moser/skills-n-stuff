# Figma Design

Author high-quality designs **directly into Figma** via the Figma Dev Mode MCP — and have
them match the quality you get when Claude designs in HTML/CSS.

## Why

There's a known quality falloff between Claude designing a website in HTML/CSS (excellent)
and Claude authoring the same design into Figma via the MCP write path (often generic). The
gap isn't Figma — it's that the workflow that makes Claude's HTML great gets skipped.

Claude's `frontend-design` workflow is strong because it **forces a committed aesthetic
direction and drives each design dimension as a named decision before generating.** Those
decisions are medium-independent. When authoring into Figma, Claude tends to skip straight to
drawing nodes — pixel-pushing instead of thinking in auto-layout, drawing primitives instead
of composing from a system, with no render→critique loop.

This plugin is the **conductor** that fixes that:

```
quality = committed aesthetic direction   (frontend-design engine)
        + a DESIGN.md token contract       (→ Figma variables)
        + auto-layout + components         (figma-use discipline)
        + render → critique → fix loop     (screenshot self-correction)
```

It branches across five starting points:

- **Claude Design project** — import it. The richest source available: CSS-custom-property
  tokens, a per-component `.d.ts` API that maps straight onto Figma variant sets, a group
  taxonomy, and standalone renders. Read via the `DesignSync` tool, not the `.zip`.
- **Storybook** — prefer the story.to.design plugin so code stays the single source of truth
  and re-syncs on one click. Encodes the `s2d` authoring contract, the tokens-first phase,
  atomics → composites import order and the nesting rules, with the MCP write path as the
  fallback for Storybooks you can't edit.
- **Existing Figma design system** — discover and compose from real components/variables.
- **Design system in code only** — mirror code tokens → a `DESIGN.md` → Figma variables → build.
- **Greenfield** — decide the system first (aesthetic engine → `DESIGN.md` → variables +
  component kit), *then* build screens. (This ordering avoids the "match-conventions → generic"
  trap when there are no conventions yet.)

It also encodes the things agents get wrong by default: searching the design system *before*
creating anything (reuse is never automatic), stamping `setVariableCodeSyntax` so Dev Mode
shows real token names instead of guessed ones, phase-gating library builds instead of
one-shotting them, budgeting variant matrices before they explode, and ending with an explicit
human publish step.

## Installation

```bash
/plugin install figma-design@studio-moser
```

Requires:
- The **remote** Figma MCP server connected (provides `use_figma`, `get_screenshot`,
  `get_variable_defs`, `search_design_system`, `get_libraries`, etc.). Every write tool is
  remote-only — the local/desktop server cannot write to canvas.
- The official **`figma-use`** skill (shipped with the Figma MCP) — loaded automatically as a
  required sub-skill. The skill routes to the rest of Figma's 12-skill catalog by task
  (`figma-generate-library`, `figma-generate-design`, `figma-code-connect`, …) rather than
  restating them, since they are beta and served live.
- For the Claude Design branch: the **`DesignSync`** tool and a Claude Design design-system
  project.
- For the Storybook branch: a Storybook (dev server or `storybook-static/`) with docgen
  enabled — `typescript.reactDocgen` must not be `false`. Optionally the story.to.design
  Figma plugin, if you take that route.
- The **`frontend-design`** skill (Claude plugins official) — the aesthetic engine.
- Optional: `@google/design.md` CLI (`npx @google/design.md …`) for linting/exporting `DESIGN.md`.

## Skill

### `/figma-design:designing-in-figma`

Triggers when you ask Claude to create/build/generate a design, screen, UI, mockup, or
component **into Figma** (code-to-design). Also kicks in when Figma output has been reading as
more generic than Claude's HTML work.

It does **not** handle design-to-code (pulling existing Figma into code) — that's the Figma
MCP's `get_design_context`.

```
# From a Claude Design project — it reads the token index and .d.ts component APIs,
# then builds real Figma variables and variant sets
move the Moby design system into Figma

# From a Storybook — enumerates stories, maps argTypes to variant axes
import our Storybook components into Figma

# Greenfield — it commits an aesthetic direction, writes a DESIGN.md, lays down
# variables + a component kit, then builds the screen
design a bold editorial pricing page in Figma

# From a code system — it mirrors your tokens into Figma variables first
build the settings screen in Figma using our shared-ui design tokens

# Into an existing Figma file — it composes from the file's components/variables
@https://figma.com/design/ABC123/App  add a dashboard screen using our components
```

## What's inside

- `skills/designing-in-figma/SKILL.md` — the conductor: core insight, five-way branch,
  ordered workflow, red-flag table.
- `references/claude-design-import.md` — Claude Design project shapes, the `_ds_manifest.json`
  token index, `.d.ts` → Figma component-property mapping, and the `DesignSync` round trip.
- `references/storybook-import.md` — the story.to.design authoring contract, the tokens-first
  phase and its colors-only/styles-not-Variables ceiling, atomics → composites import order,
  nesting rules, `index.json` limits, `options`-first axis extraction, the variant budget, and
  the MCP fallback.
- `references/design-md-template.md` — Figma-optimized `DESIGN.md` template (Google's real
  spec + Figma-targeting affordances) and how to feed it to the model.
- `references/html-to-figma-mapping.md` — flexbox→auto-layout, CSS-vars→variables,
  component→instance mapping for `use_figma`, with the load-bearing gotchas.

## Background

- `DESIGN.md` is Google Labs' open token-contract spec —
  [google-labs-code/design.md](https://github.com/google-labs-code/design.md).
- The aesthetic principles come from Anthropic's
  [frontend-design](https://claude.com/plugins/frontend-design) skill and the
  [frontend-aesthetics cookbook](https://platform.claude.com/cookbook/coding-prompting-for-frontend-aesthetics).
- Figma write-to-canvas:
  [Figma Developer Docs](https://developers.figma.com/docs/figma-mcp-server/write-to-canvas/).
- Figma's official skill catalog:
  [figma/mcp-server-guide](https://github.com/figma/mcp-server-guide/tree/main/skills).

Write-to-canvas and the Figma skill catalog are **beta** — free during the beta period, with
usage-based pricing planned, and the skill text changes. This plugin delegates to those skills
rather than copying them so it degrades gracefully as they move.

## License

MIT
