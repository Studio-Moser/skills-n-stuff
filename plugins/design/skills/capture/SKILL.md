---
name: capture
description: >-
  Freezes a design round's variants into reviewable artifacts: full-page plates, per-viewport stills, motion strips, and banded screenshots for Figma or the local gallery, failing loudly on overflow, broken images, or a blank render. Use when asked to freeze, capture, or shoot a round's variants, make plates, or update the Figma shots.
---

# Capture

Views are what critics and builders see (§ Views for critique); plates hold
every screen of a viewport-driven page in one long document (§ Freeze a page
into plates), which `design:present` pictures. The stitched capture below is
for Figma. Two things paint blank without an
error and have each cost a day: Chromium's full-page capture past 16384 device
pixels, and Figma's editor when handed a tall image. The bundled script routes
around both. Do not replace it with `page.screenshot({ fullPage: true })`.

## Run it

From the project root, where Playwright and sharp resolve:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/capture/scripts/capture.mjs" <targets.json> [--out <dir>] [--only <direction key>]
```

Requirements: `@playwright/test` (or `playwright`) with Chromium installed, and
`sharp`, both resolvable from the project's `package.json`. In a pnpm monorepo
the script also searches `node_modules/.pnpm` for sharp. Every target's preview
must be running; the script does not start servers.

From the project root, check both before the first run:

```sh
node -e "try{require.resolve('@playwright/test')}catch{require.resolve('playwright')}" 2>/dev/null || echo "missing: playwright"
node -e "require.resolve('sharp')" 2>/dev/null || echo "missing: sharp (in a pnpm monorepo the script also searches node_modules/.pnpm)"
```

If one is missing, add it with the project's package manager (for example
`npm i -D @playwright/test sharp`) and run `npx playwright install chromium`.

Output, under `--out` (default `design-shots`, add it to `.gitignore`):

- `<slug>.png`: the stitched page at the configured width and scale, archive copy.
- `bands/<slug>/NN.jpg`: the shot cut into bands of at most 2048 CSS px. **These
  are the files that go into Figma.**
- `figma/<slug>.jpg`: the whole page as one JPEG for anything that is not
  Figma's editor.
- `manifest.json`: every shot with `display` size, band list with heights, and
  the stats below. A filtered run merges into the existing manifest by slug.

Exit code 1 when any target failed to load, has a broken image, scrolls
horizontally, rendered at zero height, or exceeds Figma's asset limit. Read the
JSON lines it prints; each is one target.

## `targets.json`

```json
{
  "captureWidth": 1440,
  "captureScale": 2,
  "background": "#ffffff",
  "directions": [
    {
      "key": "03-ledger",
      "name": "03 Ledger",
      "premise": "one line",
      "variants": [
        { "id": "a", "label": "A, impeccable", "url": "https://preview-…/v/a", "live": "https://…" },
        { "id": "b", "label": "B, taste", "url": "http://localhost:3000/v/b", "capture": "fullPage" }
      ]
    }
  ]
}
```

Optional keys: top-level `hideSelectors` (CSS selectors for dev overlays to
hide in every frame; `nextjs-portal` is the default) and per-variant
`"reducedMotion": true` for a page whose type or stage animates into place as
each view lands, which the stitch wait would otherwise catch mid-reveal.

`capture` defaults to `stitch`. Set `fullPage` only for a static page and look
at the result. A page whose layout depends on the viewport (a fixed layer, `vh`
units, `animation-timeline: view()`) must stitch: full-page capture grows the
viewport to the page height, nothing ever scrolls, and the page renders in its
initial state with the fixed layer missing.

## What the script does per target

1. Opens the URL at `captureWidth` × 900 and `captureScale`, waits for network
   idle, walks the page so lazy images load and scroll-driven sections settle,
   and waits for a real page height (a cold container can report 0 before first
   paint).
2. Measures overflow (`scrollWidth - clientWidth`), visible images and how
   many are broken, and console or page errors.
3. Stitches one real viewport at a time. A `position: fixed` `<header>` is
   hidden after the first frame so it is not stamped down the page; anything
   tagged `data-preview-chrome` (a variant switcher, a review bar) is hidden in
   every frame. A fixed layer that is the design (a stage, a background) is
   left alone; widen the header selector in the script rather than turning off
   stitching if a project has non-`<header>` chrome.
4. Cuts the PNG into bands and writes the JPEG, stepping quality down until the
   file fits Figma's 10 MB asset limit and resizing when the long edge exceeds
   16384 px (`cappedEdge: true` in the manifest; bands are never resized).

## Views for critique

Stitched pages are for side-by-side review; critics and builders need what a
reader sees, one viewport at a time, and how the page moves between views.

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/capture/scripts/views.mjs" <url> <outDir> [--widths 1440,390] [--hide "sel"]
```

For each width it scrolls to every screen-height stop, waits for the page to
settle, and shoots the viewport (`1440-01.png`, `390-03.png`). At desktop
widths it also records motion: from each rest position it sends one wheel
gesture and shoots six frames from mid-gesture to settled, tiled into one strip
per transition (`motion-1440-02-to-03.png`), since stills cannot show a reveal
that never resolves. `report.json` lists stops, overflow, broken images, and
console errors per width; exit code 1 when any width is unhealthy.

Hand a builder its own views after each section for self-review, and hand a
critic the views plus the report; a critic that cannot open the preview from
its sandbox works from these files.

## Freeze a page into plates

A page built around a viewport (a fixed stage whose scenes change as you
scroll, `vh`-sized sections, scroll-driven animation) has no single static
rendering. `freeze.mjs` therefore captures
**plates**: it loads the page at a real viewport with scripts and motion
running, stops at every screen, lets it settle, and captures that screen's DOM.
The output stacks those screens in one long, self-contained file whose height
is `plates × viewport height`.

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/capture/scripts/freeze.mjs" <targets.json> --dir "docs/Design Directions" [--only <direction key>] [--variant <id>] [--flow]
```

Same `targets.json` as above; a variant's `url` is an http(s) address (a
running framework route) or a path to a self-contained HTML file (an
`html`-medium variant). Each direction maps to a folder under `--dir` by its
leading token (`03-drawn` → `03 Drawn`) or an explicit `"folder"`. Output:
`Homepage <X> - <Title>.plates.html` and the entry in `Snapshots.json` (id,
title, file, plates, height, per-plate diff, and `live` when the source was a
local file).

What settling means: images decoded; every animation and transition with a
finite end on the document timeline finished (a window caught mid-fade reads as
empty); whatever is still animating, scroll-driven or endless, committed to
inline style where it is. Then animations are switched off inside plates.

How a plate holds together: one shared stylesheet with `html`/`body`/`:root`
selectors rewritten onto the plate's wrappers; viewport units pinned to the
capture height, never inside `url(...)` (a base64 font can contain `3vh` by
chance, and rewriting it makes a display face fall back silently); each plate
a transformed, clipped box, so `position: fixed` layers pin to their plate
while in-flow content shifts up by the plate's scroll offset; fonts and images
inlined once and referenced from every plate. Text stays text, so comments can
still be pinned to elements.

**`--flow`, for a page with a real reduced-motion layout.** Under
`prefers-reduced-motion` a well-built page is a normal long-scroll document:
no fixed stage, every scene present in flow in its final lockup. `--flow`
loads the page that way, refuses it if a fixed or sticky layer still covers
the viewport ("not a long-scroll layout under reduced motion", which is also an
accessibility finding about the page), and captures it once as a single
document instead of stacked plates: one copy of the DOM, no repeated header.

**The check.** Each plate is rendered from the file and compared with a
screenshot of the live page at that stop. `plateDiff` records the difference
per plate; 0.0005 is typical, and the run exits 1 above 1%. Read the flagged
plate numbers before trusting a file: the diff is what catches a plate frozen
mid-fade or a display face that silently fell back.

Needs Playwright with Chromium and `sharp` resolvable from the project root,
and each page running (the script starts no servers; run dev previews one at a
time when several would not fit in memory together).

## Placing shots in Figma

One row per direction, variants side by side. Upload runs through the Figma
MCP:

1. For each shot create a frame at its `display` size from the manifest,
   labelled with the variant. Make it a vertical auto-layout with no spacing
   or padding, and give it one fixed child frame per band, sized
   `captureWidth` × that band's height.
2. `upload_assets` with the band frame IDs in order, then POST each
   `bands/<slug>/NN.jpg` to its returned URL.

Never upload the whole-page JPEG to a frame. Figma's server renders it, its
API screenshots it, and the editor shows an empty frame, with no error at any
point. Re-uploading to existing frames replaces fills in place, so the layout
survives a re-capture.

## Local gallery instead of Figma

For a quick look, open the PNGs side by side in any viewer, or point the
project's own gallery at `manifest.json`. The manifest's order follows
`targets.json`, so a gallery renders rows per direction without extra
configuration.
