---
name: capture
description: >-
  Use to screenshot every variant in a design round at one fixed width, ready
  for side-by-side review in Figma or a local gallery. Stitches viewport frames
  instead of trusting full-page capture, cuts each shot into bands Figma's
  editor will actually draw, and fails loudly on overflow, broken images, or a
  blank render. Triggers: "capture the round", "shoot the variants", "update
  the Figma shots".
---

# Capture

Screenshots are how the owner sees a round. Two things paint blank without an
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
