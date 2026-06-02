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

It branches across three starting points:

- **Existing Figma design system** — discover and compose from real components/variables.
- **Design system in code only** — mirror code tokens → a `DESIGN.md` → Figma variables → build.
- **Greenfield** — decide the system first (aesthetic engine → `DESIGN.md` → variables +
  component kit), *then* build screens. (This ordering avoids the "match-conventions → generic"
  trap when there are no conventions yet.)

## Installation

```bash
/plugin install figma-design@studio-moser
```

Requires:
- The **Figma Dev Mode MCP** server connected (provides `use_figma`, `get_screenshot`,
  `get_variable_defs`, `search_design_system`, `get_libraries`, etc.) and a Full Figma seat
  for write-to-canvas.
- The official **`figma-use`** skill (shipped with the Figma MCP) — loaded automatically as a
  required sub-skill.
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
# Greenfield — it commits an aesthetic direction, writes a DESIGN.md, lays down
# variables + a component kit, then builds the screen
design a bold editorial pricing page in Figma

# From a code system — it mirrors your tokens into Figma variables first
build the settings screen in Figma using our shared-ui design tokens

# Into an existing Figma file — it composes from the file's components/variables
@https://figma.com/design/ABC123/App  add a dashboard screen using our components
```

## What's inside

- `skills/designing-in-figma/SKILL.md` — the conductor: core insight, three-way branch,
  ordered workflow, red-flag table.
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

## License

MIT
