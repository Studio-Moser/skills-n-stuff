# Storybook → Figma import

**Goal: every production component exists in Figma as a real component** — variant properties a
designer can toggle, states, nested instances, fills bound to tokens — and it stays in sync
with code.

## Route first — and prefer story.to.design

| | **story.to.design (s2d)** — the default | **MCP write path** — the fallback |
|---|---|---|
| Mechanism | Figma plugin. Renders your stories server-side, captures the DOM, generates Figma components with auto-layout | Agent authors `use_figma` Plugin API scripts |
| Use when | You can edit the stories and reach the Storybook | Third-party library, can't edit stories, or output must be composed into new design work now |
| Sync | Flags **Outdated** → one **Update all** click | Re-run the agent; no diffing |
| Cost | Story-authoring discipline; a human clicks import | You must reconstruct geometry — see the warning below |

**The mental model that makes this work: code is the source of truth, and you never hand-build
components in Figma.** A Figma library built by hand — or reconstructed by an agent — is a
second source of truth that will drift.

> **Warning from an actual pilot run.** Taking the MCP path for a single Chakra `Input`
> required driving the Storybook in a headless browser and reading `getComputedStyle` across
> all 15 variant/size combinations, then hand-transcribing heights, paddings, radii and border
> colors into the build script. It produced a correct 15-variant set with 12/15 fully
> variable-bound — but every one of those measurements is a copy that can go stale. s2d does
> this server-side, automatically, and re-syncs on a click. **Only take the MCP path when s2d
> is genuinely unavailable.**

s2d supports Storybook 6.0+, Backlight, and Histoire, and is framework-agnostic
(React/Vue/Svelte/Web Components).

**There is no open-source equivalent.** `divriots/story-to-design` on GitHub is a bug tracker —
"the code is not open-source yet". `bem/storybook-to-figma` was archived 2026-07-20 in early
beta with acknowledged conversion-accuracy problems. Don't plan around either.

---

## Step 1 — Detect

**`index.json` enumerates; it does not describe.** Served at `/index.json`. Entries carry only
`id`, `name`, `title`, `tags?`, `importPath`, `type`, `subtype`, `componentPath?`,
`exportName?`. `argTypes`, `args`, `parameters` and `subcomponents` appear nowhere in the
schema, so **a second pass is mandatory** (Step 3). Measured on a real Storybook 10.2 build:
141 entries, and `componentPath` present on only 93 of them — **don't rely on it** to locate a
component's source.

`stories.json` is the removed predecessor (gone in Storybook 8). Don't target it.

**Accept the index version as a range and warn — never throw.** Storybook 8.1.4, a *patch*,
bumped `v: 4` → `v: 5` with no structural change and hard-broke consumers that pinned it.
Current is `v: 5`.

Read `.storybook/main.*` for:

| Field | Why |
|---|---|
| `framework` | Which docgen produced the metadata |
| `typescript.reactDocgen` | `'react-docgen'` \| `'react-docgen-typescript'` \| `false`. **If `false`, stop** — no prop metadata exists |
| `reactDocgenTypescriptOptions` | A wholesale override drops Storybook's preset defaults |
| `staticDirs`, `viteFinal`/`webpackFinal` aliases | Asset roots; monorepo package resolution |
| `refs` | Composed Storybooks — separate libraries, import separately |

For s2d, the Storybook must be **reachable**: a public deployed URL (simplest), or the
plugin's **local agent** / **Local Mode** pointed at `localhost:6006` for fast iteration.

---

## Step 2 — Tokens FIRST, before any component

Importing tokens first means components arrive **bound to styles** instead of raw hex.

**s2d token phase.** Open the plugin's **Tokens tab** — it parses the Storybook and lists every
CSS custom property it finds (themed component libraries emit these automatically). Click
**Apply as styles**. On a code-side token change, refresh the Tokens tab; no component
re-import needed.

Know the ceiling before you plan around it:

- **Colors only.** Alpha feature; typography and spacing are not handled.
- **It creates Figma _styles_, not Variables** — no modes.
- **Retroactive.** It reapplies to already-imported components, so a component that slipped in
  before the token phase is recoverable.
- **For true Variables with modes**, use Tokens Studio or the Variables/Plugin API, and
  **prefix the tokens with `story.to.design`** so the plugin still recognises and maps them.

**Figma-side ceiling (applies to either pipeline):**

- Variables resolve to four types only — `BOOLEAN | COLOR | FLOAT | STRING`.
- **Shadows are not variables** → `figma.createEffectStyle()`. Gradients are not variables
  (`setBoundVariableForPaint` is SOLID-only) → paint styles.
- The Variables **REST API is Enterprise-only, reads and writes alike** — assume the Plugin
  API / MCP path.

### Verified in a live pilot — carry these into any token script

- **`fontSize` *is* bindable** via `setBoundVariable('fontSize', v)` on a TEXT node. Vendor
  guidance suggesting otherwise did not hold: the binding was set and read back as
  `boundVariables.fontSize` present. Verify `fontWeight`/`lineHeight` yourself before assuming
  either way.
- **Figma rejects `.` in variable names.** `createVariable('spacing/1.5', …)` throws
  `invalid variable name`. Sanitize to `spacing/1-5` while keeping the dot in the CSS name the
  code syntax points at.
- **Convert units.** Chakra/Tailwind emit `rem`; Figma FLOAT variables are absolute px.
  Multiply by the root font size (16 by default). Handle bare `0` and `px` values too.
- **Not every computed value has a token.** A real Chakra `Input` at size `xl` computes
  `padding-inline: 18px`, which is not on the spacing scale — it cannot bind, and the honest
  move is to leave it hardcoded and *report* it, not invent a token.

Stamp the origin on every variable:

```js
v.setVariableCodeSyntax('WEB', `var(--chakra-colors-brand-500)`)
```

**One-way Dev Mode annotation, not a live round-trip** — nothing reads it back into code. Its
value is that Dev Mode shows the real token name instead of one guessed from the Figma name.

---

## Step 3 — Prop surface → variant axes

**Read `options` first, then `type`.** Both patterns occur, often in the same Storybook:

| Source | `argType.type.name` | `argType.options` |
|---|---|---|
| **Hand-authored** in the story (`control: 'select', options: [...]`) | the primitive — `'string'` | **populated** ← the axis |
| **Docgen-inferred** from a TS union/enum | `'enum'`, with `type.value: [...]` | populated |

Measured on one real library: all 8 Chakra primitives were hand-authored and had
**`type.name === 'string'` with zero `type.name === 'enum'`** — reading only `type` would have
found no axes at all. Components whose argTypes came from docgen did show `'enum'`.

So: **`options` is the reliable axis source** (present in both paths). Use `type.name` to
classify the property *kind*, and `type.name === 'enum'` as confirmation, not the primary read.
An explicit `argTypes` block in the story outranks anything inferred.

| Signal | Figma |
|---|---|
| `options: [...]` (or `type.name === 'enum'` → `type.value`) | **VARIANT** axis |
| `type.name === 'boolean'` | **BOOLEAN** property |
| `control: 'text'` | **TEXT** property |
| `node` / element / `ReactNode` | **INSTANCE_SWAP** or slot frame |
| object / array | nested instances, not a property |
| handlers, ids, `href` | skip |

**When `s2d.variantProperties` exists, it is authoritative — do not derive axes from all
available `options`.** It is the human's curated budget. Observed: `Button` exposes four
option axes (theme 2 × variant 6 × size 6 × colorPalette 9 = **648**) but declares only
`theme × variant × size` = 72, deliberately dropping `colorPalette`.

### Docgen reliability

- `react-docgen` (Storybook 8+ default) is a Babel AST matcher with no type-checker. Since
  6.0.x it **does** handle locally declared literal unions — `variant?: 'primary' | 'ghost'`
  usually resolves. Real blind spots: **TS `enum` declarations** and **imported/re-exported
  types across files**.
- `react-docgen-typescript` uses the type-checker but loses re-exported types and is slower.
  Literal extraction needs `shouldExtractLiteralValuesFromEnum`, which is `false` at library
  level — **but Storybook's own preset already sets it `true`.** Verify it survived an
  override; don't tell users to add it.
- Non-React docgen (vue-docgen-api, compodoc, `custom-elements.json`) is **not confirmed** to
  produce the same shape. Verify per framework.

### The variant budget

The matrix is the **product** of the axes. Target **≤ ~30 generated variants**, counting any
State axis — that is what State multiplies into. In practice a base matrix alone may exceed
this deliberately (Button at 72); the rule is: don't add a State axis on top of a large base,
leave those as separate named stories. Never promote every boolean to its own axis.

State the matrix size before building, and say what you dropped.

---

## Step 4 — Import order (this is what makes it a system)

**A component must be imported *after* everything it contains**, or nesting flattens instead of
linking. Nested-component detection requires both:

1. the child was **imported as its own component first**, and
2. the parent **actually renders that child** — the real primitive, not hand-rolled markup.

1. **Design tokens** (Step 2) — before any component.
2. **Atomics** — Icon first (it's inside everything), then Spinner, Badge, Avatar, Checkbox,
   Switch, CloseButton.
3. **Simple interactives** — Button, IconButton, Input, Tag, selection cards.
4. **Composites** — Card, Alert, Dialog, Menu, Combobox, Field, Table, Tabs.
5. **Your reusable sub-components.**
6. **Page-level composites** last.

Use **"Add all"** per tier rather than picking one at a time. **Canary-verify one flagship
component** (variants, bound fills, a nested instance, auto-layout) before running Add all.

A child links only if the parent renders a variant that **exists in the child's imported
matrix**. An off-matrix override — a color palette that isn't an axis — won't link. Decide:
add the axis, or accept it as bespoke.

Story `title` is a path (`'Chakra UI/Button'`) — use it as the Figma page/section structure.
Composed `refs` are separate libraries; don't merge them.

---

## Step 5 — Verify, then hand back

Each story renders standalone at `/iframe.html?id=<storyId>&viewMode=story` — the screenshot
oracle for the verification loop. Drive it with Playwright against a static build
(`storybook build` → `storybook-static/`) for reproducibility.

Audit every variant for unresolved values: each fill, stroke, padding, gap and radius should
resolve to a bound variable, and anything that can't should be **listed**, not silently left.

Then the manual steps — **neither pipeline fully automates**:

- s2d sync is an **in-plugin button. There is no CLI or CI trigger.** Budget a manual click
  per release.
- **Publish the library in the Figma UI** before Code Connect completes. No REST endpoint
  exists for publishing.

---

## The s2d authoring contract

Add an `s2d` parameter and the plugin auto-loads the story pre-configured — no manual variant
clicking:

```js
export const Default = {
  args: { /* the default variant */ },
  parameters: { s2d: { variantProperties: [ /* axes */ ] } },
};
```

**Exactly one `Default` story per component**, carrying the `s2d` param — that is the import
target. One `Default` per `title`, or story ids collide and the build fails.

`variantProperties` entries take three shapes:

**1. String** — pulls values from that arg's `argTypes`:
```js
variantProperties: ['variant', 'size']
```
Only works for controls of type `boolean | select | multi-select | radio | inline-radio |
check | inline-check`. **`text`, `number`, `range`, `color`, `date`, `object` are silently
ignored** — a string-form axis over those produces no visual difference.

**2. `S2dArgVariant`** — rename / remap an arg:
```js
{ fromArg: 'size', name: 'Size', axis: 'x',
  values: [ { name: 'Small', argValue: 'sm', excludedArgs: {} } ] }
```

**3. `S2dComplexVariant`** — build an axis from an arg *combination*; use for numeric- or
text-driven variants the string form can't express:
```js
{ name: 'Progress', axis: 'y',
  values: [ { name: '50%', withArgs: { value: 50 }, excludedArgs: {} } ] }
```
`name` is mandatory. **Every real prop named in `withArgs` must already exist in the story's
base `args`/`argTypes`** or the import errors with `argument '<name>' is missing`. Declare it
as an arg and consume it — don't hardcode the value in `render`. Pseudo-args are exempt.

Both object forms also accept **`axis: 'x' | 'y' | 'split'`** (controls variant grid layout)
and per-value **`excludedArgs`**.

**Pseudo-state axis** — no story rewrite needed:
```js
{ name: 'State', values: [
    { name: 'Default',  withArgs: {} },
    { name: 'Hover',    withArgs: { ':hover': true } },
    { name: 'Focus',    withArgs: { ':focus': true } },
    { name: 'Disabled', withArgs: { disabled: true } },
] }
```
Available: `:hover`, `:focus`, `:active`, `:tap`, `:viewport`, `:appearance` (light/dark). Use
**`:tap`, not `:active`** — `:active` only holds the pointer down; `:tap` captures the result
of a click.

**Special args** (colon-prefixed, usable anywhere an arg is): `:portalSelector` (capture
portaled overlays), `:selector` (target a sub-element), `:width` / `:height` (default
"try to hug"), `:css` (inject a theme stylesheet), `:story` (pull variants from other stories).

### Clean-render rules — whatever the story renders becomes the Figma frame

- **No wrapper pollution.** No `<Box p="16">`, no full-viewport centering decorator, no demo
  label siblings. Render the bare component.
- **No portal escape.** The plugin captures the Storybook root; content portaled to
  `document.body` imports as a bare trigger. Render overlays **inline and open**
  (`defaultOpen`), or set `:portalSelector` to the portaled node.
- **No baked widths** unless width is genuinely part of the design — prefer the `:width` hug
  default. A hardcoded width freezes the Figma component.
- **Story the real themed production components.** Do not build a wrapper library for Figma —
  it is a second source of truth that will drift. Compose real primitives; a re-skinned
  `<div>` flattens to vectors and won't nest-link.
- **Promote reusable sub-components to their own stories** when 2+ parents use them.
- **Runtime-context components** (toasts, provider-dependent UI) won't render statically.
  Render them through their style recipe/class directly for the capture, and keep a separate
  interactive story for humans.
- **Multi-theme?** Expose a Theme axis via `:css` or a theme arg, on the components that
  actually differ by theme.

### Gotchas

| Symptom | Cause | Fix |
|---|---|---|
| Imports as a flat grid / "the whole stage" | Imported the **Overview** all-variants story | Import `Default` (single instance) |
| Overlay imports as a bare trigger | Content **portaled to `document.body`** | Render inline, or set `:portalSelector` |
| Figma component is a page with huge padding | **Layout wrapper** in the story render | Remove wrappers; render the bare component |
| An axis produces no visual difference | Arg is a `color`/`number`/`text` control, ignored by the string form | Use the complex `withArgs` form |
| Build fails: "Duplicate stories with id …" | Two files share a `title` and both export `Default` | Only one `Default` per title |
| Instances won't nest-link | Parent renders raw markup, or an **off-matrix** child variant | Compose the real primitive; add the axis or accept bespoke |
| Won't render statically at all | Needs a runtime provider/context | Render via its style recipe/class |
| Fills are raw hex, not styles | Components imported **before tokens** | Re-open Tokens tab, re-apply (maps retroactively) |
| `argument '<name>' is missing` | `withArgs` names a prop absent from base `args` | Declare it as an arg and consume it |

---

## MCP write-path notes

Only when s2d is unavailable. Follow the main skill's build loop, plus:

- One component at a time, phase-gated. Variables before components.
- `combineAsVariants` does **not** arrange variants — compute grid positions and
  `resizeWithoutConstraints` the set yourself.
- Set `resize()` **before** sizing modes; append to an auto-layout parent **before** setting
  `FILL`/`HUG`; new TEXT nodes need `textAutoResize = 'HEIGHT'` plus an explicit width.
- Font style names are family-dependent — verify with `listAvailableFontsAsync()`. Montserrat
  uses `"SemiBold"`; Inter uses `"Semi Bold"`.
- `/iframe.html?id=…` is the screenshot oracle, not a source of layout truth — reconstruct
  with auto-layout, don't copy pixel positions.
- Storybook's `&args=key:value;key2:value2` URL param drives per-variant measurement.

## Unresolved

Don't assert these without checking:

- Whether Code Connect can be generated at scale from Storybook metadata, or whether each
  component still needs a hand-written `.figma.tsx`.
- Whether `use_figma` has a practical ceiling on variants per component set. (15 built cleanly
  in one pilot; 72+ untested.)
- Whether non-React docgen produces the `SBType` shape Step 3's `type` fallback depends on.
- Whether `fontWeight` / `lineHeight` are bindable via `setBoundVariable` (`fontSize` is).
