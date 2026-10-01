---
name: gallery
description: >-
  Use for the local review surface of a design exploration: one small server at
  the top of a project's design directions that shows every direction in a
  grid, and for each direction its full brief, saved references, design system,
  and all its variants, each one click from opening full-size or being edited
  in the page with impeccable live. Also sets a project up for the workflow.
  Triggers: "open the gallery", "show me the directions", "set up the design
  gallery", "set up design exploration here", "edit this variant", "let me
  tweak variant C".
---

# Gallery

A project's exploration lives in files: briefs, references, tokens, and one
self-contained page per variant. The gallery is a view of those
files, rendered on request, so there is nothing to publish and nothing to keep
in sync. It changes nothing on disk except when the owner presses Edit. Editing happens in the variant itself, through impeccable's live mode,
and lands in the same file.

## Run it

From the project root:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/gallery/scripts/gallery.mjs" [--dir "docs/Design Directions"] [--port 4600] [--project "<Name>"]
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
works under either address. Live editing stays on the machine running the
gallery, because impeccable's helper listens on that machine alone. Do not put
the gallery on a public address.

## What it shows

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
    scaled to fit and the bar says by how much.
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
node "${CLAUDE_PLUGIN_ROOT}/skills/gallery/scripts/frames.mjs" --dir "docs/Design Directions" [--only <NN>] [--force]
```

It writes `Frames/<variant>.webp` (640px wide) and `Frames/Frames.json`, and
skips a picture that is newer than its page. A source page is pictured as a
reader who asked for reduced motion gets it, with viewport heights pinned to a
900px screen: the build brief requires that layout to be a normal long-scroll
page with every scene present, so a variant that fails that gate shows up here
as an incomplete picture. A variant with plates at least as new as its source
is pictured from the plates. The gallery marks a picture whose page has
changed since with an amber dot, and shows a short live thumbnail for a variant
that has no picture yet. Needs Playwright with Chromium and `sharp` resolvable
from the project.

## Framework builds

A variant built in the project's real stack is not a file the gallery can
open. Export the build as a static site and bring it into the direction:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/gallery/scripts/import-build.mjs" --from <export dir> --dir "docs/Design Directions" --direction "<NN Name>" [--routes /v/a/,/v/b/]
```

It serves the export at a temporary local address, opens each variant's page
at a desktop and a phone width, scrolls it through, and copies into `Build/`
only the files those visits loaded, plus the build's code whole. Each variant
in `Snapshots.json` gets `"build": "v/a/"`, and the gallery previews that page
with its motion. The export's pages use root-absolute paths, so the gallery
mounts the build at `/build/<NN Name>/` and prefixes those paths as it serves
each file. Needs Playwright with Chromium resolvable from the project.

## Set a project up

A new project needs four things before its first round:

1. A directions folder (`docs/Design Directions` unless the project has a
   convention). The gallery starts on an empty one and says what to do next.
2. The frozen brief, copy rules, and facts files: `design:direction-brief`
   stage 0 finds them and writes a frozen brief when there is none.
3. The variant build brief, from `design:variant-brief`.
4. For editing: impeccable installed, and its product context
   (`PRODUCT.md` at the project root, written by impeccable's `init`). One
   product context serves every direction.

Then `design:direction-brief` creates each direction, `design:fan-out` builds
its variants, and they appear here as the files are written.

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
without the repository looks at the gallery over a private network (§ Run it).
