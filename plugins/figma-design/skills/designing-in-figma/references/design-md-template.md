# DESIGN.md — the token contract (Figma-optimized)

**Contents:** What DESIGN.md is · How it drives Figma output · Template · Spec details
worth knowing · Branch B: generating DESIGN.md from existing code tokens.

`DESIGN.md` is an open spec from Google Labs (born out of Stitch, Apache-2.0:
[google-labs-code/design.md](https://github.com/google-labs-code/design.md)). It is the
*design* sibling of `CLAUDE.md`/`AGENTS.md`: a portable contract that grounds AI design
generation so the model uses **your** colors/fonts/spacing instead of inventing generic
defaults. Constrained generation is more consistent than unconstrained generation — that
is the whole mechanism.

Two layers:
1. **YAML front matter = normative tokens** (the actual values). Inspired by the W3C DTCG
   token spec; uses `{path.to.token}` references; converts cleanly to `tokens.json`,
   **Figma variables**, and Tailwind theme config.
2. **Markdown body = rationale** (`##` sections explaining how to apply the tokens).

Place it at the **project root**. Reference it from `CLAUDE.md`/`AGENTS.md` under a
"UI & Design System" heading, and re-mention it in generation prompts to keep the model
anchored ("Use only colors, fonts, and spacing defined in DESIGN.md. Do not invent values").

## How this drives Figma output

1. `npx @google/design.md lint DESIGN.md` — fix broken refs + WCAG contrast warnings first.
2. `npx @google/design.md export --format dtcg DESIGN.md > tokens.json` — produces a DTCG
   token file you can import into **Figma Variables** (e.g. via Tokens Studio), so the
   contract's tokens become real Figma variables/modes.
3. **Name tokens to mirror your Figma variable names exactly** — so binding is 1:1 and the
   agent never has to guess a mapping.
4. The `## Layout` section carries a **Figma Output Contract** telling the agent to emit
   auto-layout frames named after the component keys, so they map cleanly to Figma components.

## Template

```markdown
---
version: alpha
name: <Design System Name>
description: <one line: product + brand feeling>

# --- TOKENS (normative; map 1:1 to Figma Variable collections) ---
colors:
  # name these to mirror your Figma variable names exactly
  primary: "#1A73E8"
  on-primary: "#FFFFFF"
  secondary: "#5F6368"
  surface: "#FFFFFF"
  on-surface: "#202124"
  surface-container: "#F8F9FA"
  outline: "#DADCE0"
  success: "#1E8E3E"
  warning: "#F9AB00"
  error: "#D93025"

typography:
  display-lg:  { fontFamily: Fraunces, fontSize: 48px, fontWeight: 800, lineHeight: 1.1, letterSpacing: -0.02em }
  headline-md: { fontFamily: Fraunces, fontSize: 24px, fontWeight: 600, lineHeight: 1.25 }
  body-md:     { fontFamily: Inter,    fontSize: 16px, fontWeight: 400, lineHeight: 1.5 }
  label-sm:    { fontFamily: Inter,    fontSize: 12px, fontWeight: 500, lineHeight: 1.0, letterSpacing: 0.05em }

spacing:        # 8px base scale -> Figma number variables / auto-layout gaps & padding
  base: 8px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 40px

rounded:        # -> Figma corner-radius variables
  sm: 4px
  md: 8px
  lg: 16px
  full: 9999px

components:     # -> Figma component variants; reference tokens, never literals
  button-primary:       { backgroundColor: "{colors.primary}", textColor: "{colors.on-primary}", typography: "{typography.label-sm}", rounded: "{rounded.md}", padding: 12px, height: 40px }
  button-primary-hover: { backgroundColor: "{colors.secondary}" }
  card:                 { backgroundColor: "{colors.surface-container}", rounded: "{rounded.lg}", padding: "{spacing.lg}" }
  input-field:          { backgroundColor: "{colors.surface}", textColor: "{colors.on-surface}", rounded: "{rounded.md}", padding: 12px, height: 40px }
---

## Overview
<Brand personality, target audience, emotional response. Dense vs. spacious,
playful vs. professional, the ONE thing that makes it memorable. This is the fallback
the agent reasons from when no token directly applies.>

## Colors
<Each role with hex + intended use, so a CTA color never lands on decoration.>
- **Primary:** the single most-important action per screen.
- **Surface / on-surface:** page + text base; maintain 4.5:1 contrast.
- **Semantic (success/warning/error):** status only, never branding.

## Typography
<Families, the type scale, usage per level. Max weights per screen. Casing rules.>

## Layout
<Grid model (e.g. 12-col desktop max 1200px, fluid mobile). The 8px spacing rhythm.
Containment rules (related items grouped in cards, 24px internal padding).>
**Figma Output Contract:** Emit every container as an auto-layout frame. Map `spacing.*`
to item spacing / padding. Name frames after the component keys above so they map cleanly
to Figma components.

## Elevation & Depth
<Shadow tokens OR, for flat designs, how hierarchy is conveyed without them
(borders via `outline`, tonal surface steps). Give exact shadow values if used.>

## Shapes
<Corner-radius language and when each `rounded.*` applies. Stroke / icon style.>

## Components
<Per-atom guidance for buttons, inputs, cards, chips, lists, tooltips, checkboxes,
radios — including all interaction states (hover / active / disabled / focus). Reference
the component tokens; describe behavior the tokens can't.>

## Do's and Don'ts
- Do use `primary` for only one action per screen.
- Do keep WCAG AA contrast (4.5:1 body, 3:1 large text / UI).
- Do reference tokens, never hardcode hex / px in generated output.
- Don't mix sharp and rounded corners in one view.
- Don't exceed two font weights per screen.
- Don't introduce colors / spacing not defined above.
```

## Spec details worth knowing

- **Dimension units:** `px`, `em`, `rem`. Colors are `#`+sRGB hex (no alpha in the token;
  opacity lives at the paint level in Figma).
- **Typography fields:** `fontFamily`, `fontSize`, `fontWeight`, `lineHeight` (Dimension or
  unitless multiplier), `letterSpacing`, `fontFeature`, `fontVariation`.
- **Component property tokens:** `backgroundColor`, `textColor`, `typography`, `rounded`,
  `padding`, `size`, `height`, `width`. Variants are separate keyed entries
  (`button-primary`, `button-primary-hover`, …).
- **Section order is normative** when present (Overview → Colors → Typography → Layout →
  Elevation → Shapes → Components → Do's/Don'ts), but any section may be omitted.
  **Duplicate headings reject the file.** Unknown sections/tokens degrade gracefully.
- **CLI:** `lint` (incl. `contrast-ratio`, `broken-ref`, `missing-primary`, `section-order`),
  `diff` (regression detection between versions), `export` (`dtcg`, `json-tailwind`,
  `css-tailwind`), `spec` (emits the spec text for injection into a prompt).
- Status is **alpha** — expect changes. There is no official DESIGN.md→Figma importer yet;
  the route is DESIGN.md → DTCG `tokens.json` → Figma Variables plugin, or materialize the
  variables directly via `use_figma` (Step 4 of the skill).

## Branch B: generating DESIGN.md from existing code tokens

When the system lives in code (Tailwind theme, CSS variables, a tokens file, a component
library), reverse it into `DESIGN.md`:
1. Read the source of truth (e.g. `tailwind.config`, `:root` custom properties, a tokens
   module, the shared-ui theme).
2. Map: CSS custom properties / Tailwind theme keys → `colors`/`spacing`/`rounded`;
   font stacks + type scale → `typography`; documented component styles → `components`.
3. Write `DESIGN.md`, `lint` it, then materialize to Figma variables (skill Step 4).
This keeps Figma and code reading from the same contract instead of drifting.
