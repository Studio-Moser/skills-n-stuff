# Storybook → Figma import

A Storybook is a strong import source: it already enumerates every component, renders each
one in isolation at a stable URL, and (usually) carries a machine-readable prop surface that
maps onto Figma component properties. What it does **not** do is hand you that prop surface
from one file — see Step 1.

## Route first: which pipeline?

Two genuinely different paths. Pick before planning.

| | **story.to.design (s2d)** | **MCP write path** |
|---|---|---|
| How | A Figma plugin, driven by hand, reading `s2d` parameters you add to stories | Agent-authored `use_figma` scripts |
| Use when | The Storybook is yours and you can edit stories | You can't edit the Storybook, or you want agent-composed output |
| Gives you | Pixel-true capture; one-click "Update all" re-sync | Native structure you fully control; no plugin dependency |
| Costs you | Story authoring discipline; a human runs the import | You reconstruct layout; capture fidelity is on you |

**Default to s2d when you own the Storybook** — re-sync on one click is worth the authoring
rules, and captures are pixel-true in a way reconstruction is not. Use the MCP path for
third-party libraries, or when the components must be composed into new design work
immediately. They are not exclusive: s2d for the library, MCP for the screens built from it.

The rest of this file is the shared extraction contract, then a section per pipeline.

---

## Step 1 — Detect

**`index.json` enumerates; it does not describe.** Served at `/index.json` on a running or
static Storybook. An entry carries only `id`, `name`, `title`, `tags?`, `importPath`, `type`,
`subtype`, `componentPath?`, `exportName?`. The strings `argTypes`, `args`, `parameters` and
`subcomponents` appear nowhere in the index schema. `componentPath` points at the component
file, not its API, and autodocs computes argTypes at runtime in the preview iframe. **So a
second extraction pass is mandatory** — Step 3.

`stories.json` is the removed predecessor (gone in Storybook 8). Don't target it.

**Accept an index version range and warn — never throw.** Storybook 8.1.4, a *patch* release,
bumped the index from `v: 4` to `v: 5` with no structural change; downstream consumers that
hardcoded a version hard-failed (`@storybook/test-runner` threw `Unsupported version 5`).
Upstream's own fix was tolerant parsing. Current is `v: 5`.

Then read `.storybook/main.*` for:

| Field | Why it matters |
|---|---|
| `framework` | Decides which docgen produced the metadata, and whether Step 3's shape holds |
| `typescript.reactDocgen` | `'react-docgen'` (default) \| `'react-docgen-typescript'` \| `false`. **If `false`, stop** and tell the user there is no prop metadata to read. |
| `typescript.reactDocgenTypescriptOptions` | See Step 3 — a wholesale override silently drops Storybook's preset defaults |
| `staticDirs` | Where assets resolve from |
| `viteFinal` / `webpackFinal` aliases | Monorepo package resolution; tells you the real component source roots |
| `refs` | Composed Storybooks — separate libraries, import them separately |

A static build (`storybook build` → `storybook-static/`) gives you `index.json` plus
`iframe.html` offline, which is the most reproducible thing to point a capture at.

## Step 2 — Tokens → Figma variables

Find the token source. In rough order of preference: a DTCG/Style Dictionary `tokens.json`,
CSS custom properties, a theme module (`theme.ts`, Chakra/MUI/Tamagui recipes), a Tailwind
theme. `@storybook/addon-themes` and `globalTypes` tell you which **modes** exist (light/dark,
brand themes) — those become variable modes, one per toolbar value.

The Figma-side ceiling is hard and worth internalising:

- **Variables resolve to four types only** — `BOOLEAN | COLOR | FLOAT | STRING`. There is no
  composite type.
- **Shadows are not variables** → `figma.createEffectStyle()`. Gradients are not variables
  (`setBoundVariableForPaint` is SOLID-only) → paint styles.
- **`fontSize` / `fontWeight` / `lineHeight` are not bindable** via `setBoundVariable` — set
  them directly on text nodes. Type composites → text styles.
- **The Variables REST API is Enterprise-only, reads and writes alike.** Assume you are on
  the Plugin API / remote MCP write path. (If you *are* on Enterprise, the REST shape worth
  mirroring anyway is one bulk POST applying `variableCollections` → `variableModes` →
  `variables` → `variableModeValues` in that order, with `tempId`s linking them. Note only
  the first three support DELETE; `variableModeValues` is set-only.)

Stamp the origin name on every variable:

```js
v.setVariableCodeSyntax('WEB', `var(--color-bg-default)`)
```

**This is a one-way Dev Mode annotation, not a live round-trip.** Nothing reads it back into
your codebase. Its value is that Dev Mode shows the *real* token name instead of one guessed
from the Figma variable name — which is what keeps the two sides from drifting under human
maintenance. Use the actual name from the codebase. ANDROID/iOS take no wrapper.

## Step 3 — Prop surface → Figma component properties

**Read `argType.type`, not `argType.options`.** `options` is derived from the type, not the
other way around: Storybook's `inferControls` destructures `{ type, options }` and for
`type.name === 'enum'` returns `{ control: value.length <= 5 ? 'radio' : 'select', options: value }`.

| `argType.type.name` | Figma |
|---|---|
| `enum` → `type.value: (string\|number)[]` | **VARIANT** axis, one value per member |
| `union` → walk `type.value[]` for literals | **VARIANT** axis (no special case in `inferControls`; it falls through to `object` control, so the control is a bad signal here) |
| `boolean` | **BOOLEAN** property |
| `string` (rendered as text) | **TEXT** property |
| `node` / element | **INSTANCE_SWAP** or a slot frame |
| `object` / `array` | nested instances, not a property |
| Handlers, ids, non-visual props | skip |

An explicit `argTypes` block hand-written in the story **outranks anything inferred** — treat
inferred metadata as a hint and confirm against explicit declarations where they exist.

### Docgen reliability

- `react-docgen` (Storybook 8+ default) is a Babel AST matcher with no type-checker. It
  **does** handle locally declared literal unions since 6.0.x — `variant?: 'primary' | 'ghost'`,
  the common case, usually resolves. Its real blind spots are **TS `enum` declarations** and
  **imported / re-exported types across files**.
- `react-docgen-typescript` uses the type-checker but loses re-exported types and is slower.
  Literal extraction depends on `shouldExtractLiteralValuesFromEnum`, which is `false` at
  library level — **but Storybook's own preset already sets it `true`**. So the job is to
  verify it survived a `reactDocgenTypescriptOptions` override (a spread override drops the
  preset defaults wholesale), not to tell the user to add it.
- Non-React frameworks (vue-docgen-api, compodoc, `custom-elements.json`) are **not confirmed**
  to produce the same `SBType` shape. Verify per framework before trusting this table.

### The variant budget — enforce it

The matrix is the **product** of every axis, so it explodes fast. A component with
`theme(2) × variant(6) × size(6)` is 72 variants before you add anything.

**Target ≤ ~30 variants per component.** Add a pseudo-state axis only when the base matrix is
small enough that `× State` still lands under that. For large base matrices, leave interactive
states as separate named stories instead. Never promote every boolean to its own axis — make
the primary axis a VARIANT and the rest BOOLEAN/TEXT properties.

State the matrix size before you build, and say what you dropped.

## Step 4 — Structure

Story `title` is a path (`'Primitives/Button'`) — use it directly as the Figma page/section
structure rather than inventing one. Composed `refs` are separate libraries; don't merge them.

## Step 5 — Verify, then hand back

Each story renders standalone at:

```
/iframe.html?id=<storyId>&viewMode=story
```

That URL is the screenshot oracle for the verification loop — compare your built Figma
component against it. Drive it with Playwright against a static build for reproducibility.

Then the manual step: **publish the library in the Figma UI** before Code Connect completes.
No REST endpoint exists for publishing.

---

## Pipeline A — story.to.design conventions

Field-tested authoring rules. These are conventions observed to work in production, not
vendor documentation — re-verify against the plugin's current docs if something misbehaves.

**One `Default` story per component, carrying the `s2d` parameter, is the import target.**
It becomes one Figma component with variants as toggleable properties. An all-variants
`Overview` grid imports as a single flat frame — keep it for browsing, never import it.

```ts
export const Default: Story = {
  args: { /* the default variant */ },
  parameters: { s2d: { variantProperties: [ /* axes */ ] } },
};
```

Declaring axes in `s2d.variantProperties`:

- **String form** — `['variant', 'size']` — pulls values from that arg's `argTypes`. Works
  only for controls of type `boolean | select | multi-select | radio | inline-radio | check |
  inline-check`. **`text` / `number` / `range` / `color` / `date` / `object` are ignored** —
  never put them in string form.
- **Rename/remap** — `{ fromArg, name, values: [{ name, argValue }] }`.
- **Combination / numeric** — `{ name, values: [{ name, withArgs: { value: 50 } }] }` for
  variants the string form can't express. **Every real prop named in `withArgs` must already
  exist in the story's base `args` or `argTypes`** or the import errors with
  `argument '<name>' is missing`. Declare it as an arg and consume it — don't hardcode the
  value in `render`. Pseudo-args are exempt.
- **Pseudo-state axis** — `:hover :focus :active :tap :viewport :appearance`. Use `:tap`, not
  `:active`, to capture post-click state.

### Clean-render rules — whatever the story renders becomes the Figma frame

- **No wrapper pollution.** No padding boxes, full-viewport centering decorators, or demo
  label siblings. Render the bare component.
- **No portal escape.** The plugin captures the story root element; content portaled to
  `document.body` imports as a bare trigger. Render overlays inline and open. If the portal
  is inside the component, point the plugin at the portaled node via its selector option.
- **No baked widths** unless width is genuinely part of the design — let the hug default size it.
- **Runtime-context components** (toasts, provider-dependent UI) won't render statically.
  Render them through their slot recipe/class directly for the capture, and keep a separate
  interactive story.
- **Compose real primitives.** A re-skinned `<div>` flattens to vectors in Figma. Promote a
  sub-component to its own story when 2+ parents use it, so it imports and nests as an instance.
- **Nesting links only** when the parent renders a variant that exists in the child's imported
  matrix. Off-matrix overrides won't link.

Naming: one `Default` per `title`, or story ids collide and the build fails. Verify with a
full `storybook build` — it compiles and indexes everything and catches id collisions that
`tsc` alone misses.

## Pipeline B — MCP write path

Follow the main skill's Step 5–8 loop, with these Storybook-specific notes:

- Build one component at a time, phase-gated. Variables before components.
- Use Step 3's `argType.type` mapping to author the variant set; `combineAsVariants` does not
  arrange variants — compute the grid positions yourself.
- The `/iframe.html?id=…` render is the screenshot oracle, not a source of layout truth —
  reconstruct with auto-layout rather than copying pixel positions.
- For imagery the Plugin API cannot fetch, capture with `generate_figma_design` against the
  same `fileKey` and transfer `imageHash` values, or `upload_assets` for local files.

## Unresolved

Do not assert these in a build without checking first:

- **Whether Code Connect can be generated at scale from Storybook metadata.** Each component
  may still need a hand-written `.figma.tsx`. This is the hinge between "components exist in
  Figma" and "components round-trip".
- **Whether `use_figma` has a practical ceiling on variants per component set**, and whether
  agent-authored structure survives a manual publish unchanged.
- **Whether non-React docgen output matches the `SBType` shape** Step 3 depends on.
