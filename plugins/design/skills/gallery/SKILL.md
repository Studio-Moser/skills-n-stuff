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
self-contained page per variant. The gallery is a read-only view of those
files, rendered on request, so there is nothing to publish and nothing to keep
in sync. Editing happens in the variant itself, through impeccable's live mode,
and lands in the same file.

## Run it

From the project root:

```sh
node "${CLAUDE_PLUGIN_ROOT}/skills/gallery/scripts/gallery.mjs" [--dir "docs/Design Directions"] [--port 4600] [--project "<Name>"]
```

It needs Node and nothing else, and prints its address
(`http://127.0.0.1:4600`). Leave it running in the background for the session;
pages reflect the files at the moment they load. It binds to this machine only.
To reach it from another machine on a private network, pass `--host` with that
interface's address; it serves the directions folder and the project's
markdown, read-only, so do not put it on a public address.

## What it shows

**`/`: every direction.** A card per direction folder: its number and name,
phase, the premise, a live thumbnail of its first variant, and counts of
variants and references.

**`/direction/<NN Name>`: one direction**, in four sections:

- **Brief.** The whole `Brief.md`, rendered. Links to other project documents
  (the frozen brief, copy directions, variant notes) open rendered too.
- **References.** `References/References.md`, then a card per saved reference:
  an image, or a captured site whose card opens every view still and motion
  strip `design:direction-brief` saved for it.
- **Design system.** The direction's `tokens.css` as colour swatches, typeface
  names, and a table of the remaining tokens, and its `DESIGN.md` when it has
  one.
- **Variants.** A card per variant with a live thumbnail and the label from
  `Snapshots.json` when there is one. **Open** shows the page full-size in a
  new tab, where it scrolls and moves as built. **Phone** shows it at 390px.
  **Edit** opens it for live editing (below). A variant that exists only as
  frozen plates of a framework build is marked Frozen, links to its live build
  when the manifest names one, and cannot be edited here.

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
  Snapshots.json                labels and live-build addresses, when frozen
```

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
4. **Give the direction a live config**, once, at
   `{NN Name}/.impeccable/live/config.json`:

   ```json
   { "files": ["*.html"], "exclude": ["*.plates.html", "Cover*.html"], "insertBefore": "</body>", "commentSyntax": "html", "cspChecked": true }
   ```

5. **Start it** from the project root:
   `impeccable live --target "{directions dir}/{NN Name}/Homepage <X> - <Title>.html"`,
   then run the poll loop from the `projectRoot` it returns (the direction
   folder). The gallery now marks the direction's variants Live, and **Edit**
   opens the page with the editing bar in it. The page must be opened from the
   gallery's address: live mode needs a local server, and maps the gallery's
   URL, which mirrors the file's path, back to the file.
6. **Finish every accept.** After an accept, fold the accepted variant's rules
   into the page's own `<style>`, remove the wrapper and markers, and run
   `impeccable live-complete`. An `html`-medium variant is one file, so its
   stylesheet is that `<style>` block.
7. **Stop** with `impeccable live-server stop` when the owner is done; it
   removes the script it injected into the pages.

Live mode refines a direction that already has an identity. To explore a
different premise, write a new direction and run a round.

When **Edit** is pressed and live mode is not running, the gallery shows the
sentence to give the agent instead of opening a page that cannot be edited.

## What the gallery does not do

It has no comments and no accounts. The owner says what they want carried
forward, and `design:direction-brief` writes it into the next brief. When
people without a checkout need to review and comment, publish to a hosted
canvas with `design:canvas` as well.
