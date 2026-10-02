---
name: present
description: >-
  Puts a design round in front of the owner: per-screen pictures, a Figma file with each variant linked to its live page, static build imports, live editing with impeccable, and an optional local gallery. Also sets a project up for the workflow. Use when asked to present a round, put it in Figma, take the pictures, tweak a variant, import a build, or open the gallery.
---

# Present

A project's exploration lives in files: briefs, references, tokens, and one
self-contained page per variant. Presenting a round means turning those files
into something the owner can look at and act on:

- **Pictures** of every variant, a screen at a time (§ Pictures of the variants).
- **A Figma file** with the pictures laid out and each variant's frame hooked
  to its live page, shown inside Figma by the Design Gallery plugin
  (§ Review in Figma). This is the usual review surface.
- **The page itself**, served over `http` by the project's own dev server or
  any static server rooted at the project, and edited in place with impeccable
  live (§ Edit a variant).
- **A local gallery**, optional: a small server that shows every direction
  with its brief, references, design system, and variants (§ The local gallery). It changes nothing on disk except when the owner presses Edit.

## The local gallery (optional)

From the project root:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/present/scripts/gallery.mjs" [--dir "docs/Design Directions"] [--port 4600] [--project "<Name>"]
```

It needs Node and nothing else, and prints its address
(`http://127.0.0.1:4600`). Leave it running in the background for the session;
pages reflect the files at the moment they load. Anyone with the repository
runs it the same way on their own machine; nothing it shows depends on another
host.

It binds to this machine only. To look at it from another device, put the
whole server on a private network instead of pointing parts of it elsewhere:
`tailscale serve --bg 4600` publishes it to the tailnet, or pass `--host` with
a private interface's address. Every link in the gallery is relative, so it
works under either address.

Editing is local by design. The pencil and the route behind it are offered
only to a browser on the machine running the gallery (an address of
`localhost` or `127.0.0.1`), because impeccable's helper listens on that
machine alone. Reached through any other host name, such as a tailnet address
or a dev server, the same gallery is for looking: no pencil, and the route
refuses. `--view-only` turns editing off everywhere. Do not put the gallery on
a public address.

## What the gallery shows

**`/`: every direction.** A tile per direction folder: its number, name, and
phase, the premise at reading size, pictures of its first four variants laid
out like prints on a desk, and counts of variants and references.

**`/direction/<NN Name>`: one direction**, in four tabs. Variants opens first;
the tab is part of the address, so a link lands on the same one.

- **Variants.** Every variant as a picture of its whole scroll, side by side,
  with a small title above it. Hovering a variant shows three
  tools beside the title:
  - **Notes** opens the variant's details and its notes file
    (`Homepage <X> - <Title>.md`) in a scrolling dialog over the page.
  - **Preview** (or a click on the frame) opens the live page in a dialog at
    90% of the window. Drag its right or bottom edge to resize it, or pick a
    size from the bar underneath: fill the window, laptop (1440 × 900), tablet
    (834 × 1112), or phone (390 × 844). A size larger than the window is
    scaled to fit and the bar says by how much. An open preview is part of
    the address (`/direction/<NN Name>?preview=t`), so a link from anywhere
    opens one variant straight into it.
  - **Edit** starts live editing for the variant and opens it in a new tab
    (below). A variant built in a framework has no Edit; its preview is its
    page in the direction's static build (below), or its plates when there is
    no build.

  Every picture and preview is served from the files in the directions folder,
  never from another host, so the gallery works the same on any machine that
  has the repository. A build hosted elsewhere is linked from a variant's notes
  only when the direction has no build of its own.

- **Brief.** The whole `Brief.md`, rendered. Links to other project documents
  (the frozen brief, copy directions, variant notes) open rendered too.
- **References.** `References/References.md`, then a card per saved reference:
  an image, or a captured site whose card opens every view still and motion
  strip `design:direction-brief` saved for it.
- **Design system.** The direction's `tokens.css` as colour swatches, typeface
  names, and a table of the remaining tokens, and its `DESIGN.md` when it has
  one.

What it reads, per direction folder:

```
{directions dir}/{NN Name}/
  Brief.md                      the direction brief
  References/                   References.md, images, captured sites
  tokens.css                    shared type and tokens, written by the first variant
  DESIGN.md                     the direction's design context, for live editing
  Homepage <X> - <Title>.html   a variant's source page
  Homepage <X> - <Title>.md     optional notes on a variant
  Homepage <X> - <Title>.plates.html   frozen plates, for framework builds
  Snapshots.json                labels, and each variant's page in Build/
  Frames/                       a picture of each variant's whole scroll
  Build/                        the static export of a framework build
```

## Pictures of the variants

The grids show pictures, not live pages. Twenty live pages are more than a
browser tab will hold; the live page is one click away in the preview. Take or
refresh the pictures whenever variants are built or edited, from the project
root:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/present/scripts/frames.mjs" --dir "docs/Design Directions" [--only <NN>] [--force]
```

`frames.mjs` and `import-build.mjs` need Playwright with Chromium and `sharp`
resolvable from the project root; run the dependency check under Requirements in
`design:capture` first if this project has not captured before.

It pictures each variant one screen at a time, at two sizes, so every image
is one full screen of the page: usable alone as a thumbnail, and stacked as
the whole scroll.

- `Frames/<variant>/desktop/01.webp …`: 1440 × 900 each.
- `Frames/<variant>/mobile/01.webp …`: 360 × 800 each.
- `Frames/<variant>.webp`: the whole desktop scroll at 640px wide, which the
  gallery's grids show.
- `Frames/Frames.json`: the sizes, the screens, and what each was taken from.

It skips a variant whose pictures are newer than its page. A source page is pictured as a
reader who asked for reduced motion gets it, with viewport heights pinned to a
900px screen: the build brief requires that layout to be a normal long-scroll
page with every scene present, so a variant that fails that gate shows up here
as an incomplete picture. A variant with plates at least as new as its source
is pictured from the plates. Mobile needs a page that responds to width,
which plates do not: a source page is pictured as above, and a variant that
is a page in the direction's `Build/` is opened from there with its motion
running and pictured as it is scrolled a screen at a time. A variant with
neither has no mobile pictures. The gallery marks a picture whose page has
changed since with an amber dot, and shows a short live thumbnail for a variant
that has no picture yet. Needs Playwright with Chromium and `sharp` resolvable
from the project.

## Review in Figma

A Figma file is a second place to lay the same pictures out, with free
arrangement and pinned comments. It needs no gallery: the pictures are files,
and each variant links to its own page, which any static server rooted at the
project serves (`python3 -m http.server 4600` from the project root, the
gallery, or a shared host). The Figma plugin in this repository's
`figma/Design Gallery` folder shows the page of whichever variant is selected,
inside Figma, from the address stored on the variant's frame.

Place a round through the Figma MCP:

1. One section per direction (or round), one column per variant. Store the
   variant's page address on the column frame, which is what the plugin reads:
   `column.setSharedPluginData('design_gallery', 'page', '<address>')`. For
   people without the plugin, the header row may also carry a text link,
   **Open live preview**, to the same address. The address is the variant's
   page at its path in the project:
   `<server address>/<directions dir>/<NN Name>/Homepage <X> - <Title>.html`
   for a source page, or `<server address>/<directions dir>/<NN Name>/Build/<build>`
   for a framework build. Beneath the header row with the variant's label, a
   vertical auto-layout with no spacing or
   padding holding one frame per screen, each `1440 × <screen height>` from
   `Frames.json` (900, the last one shorter). A mobile column beside it is the
   same with `360 × <height>` frames from the `mobile` list.
2. Upload the screens with `upload_assets`, passing the frames' ids in order,
   then send each `Frames/<variant>/desktop/NN.webp` (or `mobile/NN.webp`) to
   its returned address. Re-uploading to the same frames replaces the pictures
   and keeps the layout.
3. Read each column's address back
   (`getSharedPluginData('design_gallery', 'page')`) and request one of them
   from the server, so a variant never lands in the file without a working
   page. When a variant's file is renamed or re-lettered, update the address
   on its column.
4. Never place the whole scroll as one image. Figma shrinks an image past
   4096px on a side, and its editor has painted very tall images blank with no
   error.

While working, the server address is `http://127.0.0.1:4600`, which opens only
on that machine. For a team, serve the same folder from a shared host; the
paths do not change, and each person sets that host once in the plugin, so the
links need no rewriting.

## Framework builds

A variant built in the project's real stack is not a file the gallery can
open. Export the build as a static site and bring it into the direction:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/present/scripts/import-build.mjs" --from <export dir> --dir "docs/Design Directions" --direction "<NN Name>" [--routes /v/a/,/v/b/]
```

It serves the export at a temporary local address, opens each variant's page
at a desktop and a phone width, scrolls it through, and copies into `Build/`
only the files those visits loaded, plus the build's code whole. Each variant
in `Snapshots.json` gets `"build": "v/a/"`.

An export's pages name their own files by root-absolute paths, which only work
at a site's root. The copy is rebased: each such path gets the `Build/`
folder's own address as a prefix (recorded in `Build/Build.json`), so the pages
are plain static files that any server rooted at the project serves, the
gallery included. Run it from the project root so the prefix matches.
`import-build.mjs --rebase --dir … --direction …` applies or changes the prefix
of a build already in place. Importing needs Playwright with Chromium
resolvable from the project; `--rebase` needs nothing.

## Edit a variant

Editing is impeccable's live mode running on the variant's own file: the owner
picks an element in the page, describes a change or annotates it, compares the
variants the agent writes in place, and accepts one, which is written into the
file. Follow impeccable's `reference/live.md` exactly; it is the contract. What
this workflow adds:

1. **Source pages only.** Edit `Homepage <X> - <Title>.html`, never a
   `.plates.html`. Live mode locates the picked element by line, so a page
   whose body is one long line cannot be edited; builders write formatted
   source for this reason.
2. **Keep the original when it matters.** To branch from a variant instead of
   changing it, copy the file to the next free letter first and edit the copy.
3. **Give the direction its design context.** Live mode varies an element
   within an identity, and reads that identity from `DESIGN.md`. A direction
   has its own: write `{NN Name}/DESIGN.md` from the brief's Type, colour, and
   Hard rules and from `tokens.css`, in the format impeccable's
   `reference/document.md` describes. With it, live mode treats the direction
   folder as its project and still inherits the root `PRODUCT.md`.
4. **The owner presses Edit.** The gallery writes the direction's live config
   when there is none, runs `impeccable live --target` on the variant, and
   opens the page with the editing bar in it. The config it writes, at
   `{NN Name}/.impeccable/live/config.json`:

   ```json
   { "files": ["*.html"], "exclude": ["*.plates.html", "Cover*.html"], "insertBefore": "</body>", "commentSyntax": "html", "cspChecked": true }
   ```

   It finds impeccable under `.agents` or `.claude` in the project or the home
   folder; pass `--impeccable <path>` otherwise. When the direction has no
   `DESIGN.md`, or live mode fails to start, the new tab says why and gives the
   sentence to hand the agent.
5. **Run the poll loop** from the direction folder as soon as the owner says
   they are editing, and keep it running until they stop. The gallery starts
   the helper, but only an agent answers the owner's requests; the bar's mark
   dims with an amber dot while nothing is polling. An agent can also start
   live mode itself with the same command. The page must be opened from the
   gallery's address: live mode needs a local server, and maps the gallery's
   URL, which mirrors the file's path, back to the file.
6. **Finish every accept.** After an accept, fold the accepted variant's rules
   into the page's own `<style>`, remove the wrapper and markers, and run
   `impeccable live-complete`. An `html`-medium variant is one file, so its
   stylesheet is that `<style>` block. Then refresh the variant's picture with
   `frames.mjs`.
7. **Stop** with `impeccable live-server stop` when the owner is done; it
   removes the script it injected into the pages.

Live mode refines a direction that already has an identity. To explore a
different premise, write a new direction and run a round.

## What the gallery does not do

It has no comments and no accounts. The owner says what they want carried
forward, and `design:direction-brief` writes it into the next brief. Someone
without the repository looks at the gallery over a private network (§ The local gallery).
