# What the gallery shows

A tour of `gallery.mjs` for answering the owner, and the files it reads from each direction folder.


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
    (`design:present` § Edit a variant). A variant built in a framework has
    no Edit; its preview is its page in the direction's static build
    (`design:present` § Framework builds), or its plates when there is no
    build.

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
