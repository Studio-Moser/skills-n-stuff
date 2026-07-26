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
| CSS custom property (`--token`) | Figma **Variable** (`figma.variables.createVariable` in a collection) | Bind via `setBoundVariable` / `setBoundVariableForPaint`. Always `setVariableCodeSyntax('WEB', 'var(--token)')` using the **real codebase name** — omit it and Dev Mode guesses, so code and Figma drift. |
| `clamp()` / `vh` / `vw` / `%` sizing | **no equivalent** | Figma FLOAT variables are absolute. Resolve to a fixed px per breakpoint mode, or skip — and say which. |
| `linear-gradient` / `radial-gradient` | **paint style**, not a variable | `setBoundVariableForPaint` is SOLID-only. |
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
   `FILL`/`HUG`. Set `FILL`/`HUG` only **after** `appendChild` — a freshly-created node has no
   parent, so setting them immediately after `createFrame()` always throws. (FIXED works
   anywhere.) Two more silent collapses: a **HUG parent shrinks its FILL children** to minimum
   size; and a new TEXT node defaults to `textAutoResize='WIDTH_AND_HEIGHT'`, which ignores
   FILL and turns the node into a thousands-of-pixels-tall "text thread" — set
   `textAutoResize='HEIGHT'` plus an explicit `resize()`.
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
   nothing, so small calls keep errors recoverable. (The ceiling is relaxed in Slides files:
   3–5 slides per call is safe.)
9. **Keep mutations sequential.** `figma-generate-library` states it outright: never
   parallelize `use_figma` — Figma state mutations must be strictly sequential. Multi-page
   work is one `setCurrentPageAsync` per call, run **one after another**; never loop pages
   inside one script either.
10. **Page switching is async:** `await figma.setCurrentPageAsync(page)`. The sync setter
    throws "Setting figma.currentPage is not supported".
11. **Unsupported in `use_figma`:** `figma.notify()` throws; `getPluginData`/`setPluginData`
    (use the Shared variants); `loadAllPagesAsync`. `figma.createPage()` is Design-files-only.
12. **Sections don't auto-resize** to fit their children.

## Limits of write-to-canvas (beta)

- **Write tools are remote-server only.** The local/desktop Figma MCP server cannot write.
  Most "write to canvas is not working" reports are local-server config.
- **No external image-URL fetch.** The Plugin API can only set an image fill by copying an
  `imageHash` from a node already in the file. For web sources, run `generate_figma_design`
  against the same `fileKey` in parallel to capture a reference, transfer the hashes, then
  delete the capture. For local image files, `upload_assets` (PNG/JPG/GIF/WebP/SVG, 10MB).
- **Beta-level quality** — output needs manual review, and **components must be published
  manually in the Figma UI** before Code Connect completes (no REST endpoint for publishing).
- Probable but not firmly confirmed: a Full Figma seat + edit permission on the target file.
  Earlier versions of this file also asserted a ~20kb per-call output cap and a custom-font
  limitation; neither survived verification against current docs — check before relying on
  them. The documented cap that does exist is on **input**: `code` max 50 000 chars.

## The mental model

**CSS flexbox tree = Figma auto-layout tree.** Author the same hierarchy you'd author in
HTML. Absolute positioning is the rare exception in good CSS — same here. When you copy
pixel coordinates literally you get `position:absolute; top:247px` everywhere: pixel-perfect
until someone resizes, at which point it reads as AI slop. Think in auto-layout, compose from
components, bind variables — then the screenshot-and-fix loop catches the rest.
