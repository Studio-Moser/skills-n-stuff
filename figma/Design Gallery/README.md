# Design Gallery (Figma plugin)

Shows the live page of a design variant inside Figma. Select a variant on the
canvas and the panel loads its real page: it scrolls and moves as built, at
the panel's size or at laptop, tablet, or phone size.

Figma holds the layout and the comments; the page lives in the project. This
panel is the bridge, so reviewing a variant does not mean leaving the file.

## What it needs

1. **A link on each variant.** The variant's label in Figma carries a link to
   the variant's page ("Open live preview"). That link is the whole contract:
   the plugin loads whatever page it points at.
2. **Something serving that page over `http`.** Any static server rooted at
   the project will do, for example `python3 -m http.server 4600` from the
   project root; so will the design plugin's gallery, or a shared host. A
   plugin panel cannot open a file straight from disk.

Nothing else: no gallery, no data endpoint, no build step.

## Install

It is a development plugin, loaded from this folder:

1. In the Figma desktop app, open any design file.
2. Plugins → Development → Import plugin from manifest…
3. Choose `manifest.json` in this folder.
4. Run it from Plugins → Development → Design Gallery.

Figma reads `code.js` and `ui.html` as they are; after changing either, run
the plugin again.

## Use

1. Run the plugin and select a variant: its label, one of its screens, or its
   whole column.
2. The panel shows that variant's page. The buttons in its bar: fill the
   panel, laptop (1440 × 900), tablet (834 × 1112), phone (360 × 800), reload,
   and the server address. A size larger than the panel is scaled to fit and
   the bar says by how much.
3. Drag the right or bottom edge of the page, or its corner, to try other
   sizes.
4. Drag the grip in the window's bottom-right corner to resize the plugin's
   window; the page refits.

Selecting a layer that is not part of a variant says so and clears the panel.

## How it finds a variant

It walks up from the selection to the nearest layer that contains exactly one
link to a page (links to other Figma files do not count), and loads that link.
A layer containing several variants' links, such as a whole section, is not a
variant. The panel's title is the first text beside the link.

## The server address

By default each link opens as written, so a file whose links point at
`http://127.0.0.1:4600` works on a machine serving the project there. To use
another server without rewriting the links (a shared host, say), set its
address with the gear: it replaces the server part of every link, for every
variant, in any file. It is each person's own setting, kept in Figma's plugin
storage, and changes nothing in the file.

## Limits

- The page is in a floating panel, not on the canvas.
- Each person runs the plugin themselves. To give it to a team without each
  person importing it, publish it privately to the organisation from Figma.
- The manifest allows any address (`networkAccess.allowedDomains: ["*"]`),
  because the server's address is the user's to set.
