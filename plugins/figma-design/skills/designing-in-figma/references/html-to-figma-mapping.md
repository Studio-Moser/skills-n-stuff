# HTML/CSS → Figma mapping (for `use_figma` authoring)

`use_figma` runs JavaScript against the Figma Plugin API (the `figma` global). Authoring
into Figma is **writing the DOM/CSS as a node tree** — the same hierarchy you'd write in
HTML, expressed as frames + auto-layout instead of markup + flexbox.

**This file is a quick map, not a replacement for `figma-use`.** `figma-use` is the
definitive rule set with WRONG/CORRECT examples for every pitfall. Always load it first.

## Mapping table

| HTML / CSS | Figma Plugin API | Notes / gotchas |
|---|---|---|
| `<div>` block container | `figma.createFrame()` | Plain frame = `layoutMode:'NONE'` (absolute). Children can't FILL/HUG. |
| `display:flex` container | `figma.createAutoLayout(direction?, props?)` | Prefer over `createFrame()` + manual `layoutMode`. Both axes hug by default. |
| `flex-direction: row / column` | `layoutMode = 'HORIZONTAL' \| 'VERTICAL'` | `'GRID'` and `'NONE'` (absolute) also exist. |
| `justify-content` | `primaryAxisAlignItems` = `MIN/CENTER/MAX/SPACE_BETWEEN` | Main-axis alignment. |
| `align-items` | `counterAxisAlignItems` = `MIN/CENTER/MAX/BASELINE` | **No `STRETCH`** — use `MIN` + child `FILL` on the cross axis to stretch. |
| `align-content` (wrapped) | `counterAxisAlignContent` | Only with wrap on. |
| `gap` | `itemSpacing` (main), `counterAxisSpacing` (cross, when wrapping) | Numeric px. |
| `padding` | `paddingTop/Right/Bottom/Left` | Numeric px. |
| `flex-wrap` | `layoutWrap` | |
| `width/height: auto` (shrink to fit) | `layoutSizingHorizontal/Vertical = 'HUG'` | HUG only on an auto-layout frame OR a TEXT child. |
| `flex: 1` / fill remaining | child `layoutSizingHorizontal/Vertical = 'FILL'` | Only on a child of an auto-layout frame; **set AFTER `appendChild`**. |
| fixed `width/height` | `node.resize(w,h)` | `width`/`height` are read-only; **`resize()` resets sizing to FIXED** — call it first, then set FILL/HUG. |
| `flex-grow` | `layoutGrow` | Compresses content if parent hugs — use with FIXED/extra-space parent. |
| `align-self` | `layoutAlign` | |
| `position: absolute` | `layoutPositioning = 'ABSOLUTE'` + explicit `x/y` | The rare exception. Such children can't FILL. |
| CSS custom property (`--token`) | Figma **Variable** (`figma.variables.createVariable` in a collection) | Bind via `setBoundVariable` / `setBoundVariableForPaint`. |
| `:root` theming / dark mode | Variable **collection + modes** (Light/Dark, Desktop/Mobile) | New collection's mode is named `Mode 1` — **rename it**. Mode count is plan-limited (Free 1, Pro 4). |
| `var(--x)` (spacing/radius) | `setBoundVariable("paddingLeft", spacingVar)` | |
| `var(--x)` (color) | `setBoundVariableForPaint(paint, 'color', colorVar)` | **Returns a NEW paint** — capture and reassign it to `fills`. |
| `background-color` / `color` | `node.fills = [{type:'SOLID', color:{r,g,b}}]` | Colors are **0–1**, not 0–255. No `a` in color — opacity at paint level. |
| `border` | `node.strokes` + `strokeWeight` | Arrays are read-only — clone, modify, reassign. |
| `border-radius` | `cornerRadius` (or per-corner) | |
| `box-shadow` | `DROP_SHADOW` effect, or an **effect style** (`effectStyleId`) | |
| type scale / text styles | **Text styles** (`textStyleId`); `fontName`, `fontSize`, `lineHeight {value,unit}`, `letterSpacing {value,unit}` | `lineHeight`/`letterSpacing` are objects, not bare numbers. |
| `@font-face` / Google Fonts | `await figma.loadFontAsync({family, style})` **before** any text mutation | Style names are file-dependent — verify via `listAvailableFontsAsync()`. **`"Semi Bold"` ≠ `"SemiBold"`**; Inter uses `"Semi Bold"`, `"Extra Bold"`. |
| `<Button/>` instance | component instance (`mainComponent.createInstance()`; import via `importComponentSetByKeyAsync`) | Stays linked to the library and updates. |
| component props | `instance.setProperties({ "Label#2:0": "..." })` | Use property keys from the component; more reliable than setting `characters`. |
| reusable component def | `figma.createComponent()` / `combineAsVariants([...])` | `combineAsVariants` needs COMPONENTs (not frames) and does NOT auto-layout the set. |
| the page / route | a top-level wrapper Frame (e.g. 1440px) in clear canvas space | New top-level nodes default to (0,0) — scan `currentPage.children` and offset. |

## The load-bearing gotchas

These cause most silent failures. (Full set + examples: `figma-use`.)

1. **Font load recipe:** `loadFontAsync` → `await` → mutate text → return IDs. Skipping it
   throws "Cannot write to node with unloaded font" — and the distinctive non-Inter fonts the
   aesthetic wants are exactly the ones that trip this.
2. **Sizing order:** `resize()` resets modes to FIXED. Call `resize()` first, then set
   `FILL`/`HUG`. Set `FILL` only **after** `appendChild`.
3. **Build in place, not then-reparent:** create the wrapper in one call (return its ID),
   build sections *inside* it in later calls. `appendChild` across calls can silently orphan.
4. **`return` is the only output channel.** `console.log` is invisible. Return every created
   or mutated node ID so later calls can reference them.
5. **Variable hygiene:** set explicit **scopes** (`["TEXT_FILL"]`, `["FRAME_FILL"]`, `["GAP"]`,
   …) — never leave `ALL_SCOPES`. **Rename modes** — never ship `Mode 1`.
6. **`setBoundVariableForPaint` returns a new paint** — reassign it; mutating in place no-ops.
7. **Batch async:** `Promise.all` the `import*ByKeyAsync` calls; don't await them serially at
   the top of every section.
8. **≤10 logical ops per `use_figma` call.** Calls are atomic — a failed script changes
   nothing, so small calls keep errors recoverable.
9. **Multi-page:** emit N parallel `use_figma` calls in one message (one
   `setCurrentPageAsync` per call) — never loop pages inside one script.

## Limits of write-to-canvas (beta)

- ~20kb output per call; no external image-URL fetch yet. For web sources needing pixel
  fidelity, run `generate_figma_design` in parallel to capture a reference + image hashes,
  transfer them, then delete it.
- Custom-font limits; beta-level quality requiring manual review. Requires a Full Figma seat.

## The mental model

**CSS flexbox tree = Figma auto-layout tree.** Author the same hierarchy you'd author in
HTML. Absolute positioning is the rare exception in good CSS — same here. When you copy
pixel coordinates literally you get `position:absolute; top:247px` everywhere: pixel-perfect
until someone resizes, at which point it reads as AI slop. Think in auto-layout, compose from
components, bind variables — then the screenshot-and-fix loop catches the rest.
