# Design Gallery (Figma plugin)

Shows the live page of a design variant inside Figma. Select a variant on the
canvas and the panel loads its real page: it scrolls and moves as built, at
the panel's size or at laptop, tablet, or phone size.

Figma holds the layout and the comments; the page lives in the project. This
panel is the bridge, so reviewing a variant does not mean leaving the file.

## What it needs

1. **A frame that knows its page.** The address of a variant's page is stored
   on its frame in Figma, as shared plugin data (namespace `design_gallery`,
   key `page`). Nothing is drawn on the canvas for it. Set it in the panel, or
   from any tool that can write shared plugin data:
   `frame.setSharedPluginData('design_gallery', 'page', '<address>')`.
2. **Something serving that page over `http`.** The project's own dev server,
   any static server rooted at the project (`python3 -m http.server 4600`),
   or a shared host. A plugin panel cannot open a file straight from disk.

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

1. Run the plugin and select a variant's frame, or anything inside it. The
   panel shows its page.
2. The buttons in the bar: fill the panel, laptop (1440 × 900), tablet
   (834 × 1112), phone (360 × 800), this frame's page, reload, and the server
   address. A size larger than the panel is scaled to fit and the bar says by
   how much.
3. Drag the right or bottom edge of the page, or its corner, to try other
   sizes.
4. Drag the grip in the window's bottom-right corner to resize the plugin's
   window; the page refits.

Selecting a layer with no page says so and clears the panel.

## Giving a frame a page

Select the variant's whole frame (its column), press the link button, enter
the page's address, and save. Remove takes it away again. The address lives on
the frame in the file, so it is there for everyone who uses the plugin, and it
stays with the frame when it is moved, renamed, or duplicated. The row also
lists every frame on the current canvas page that has one; pressing a name
selects that frame.

## How it finds a variant

It walks up from the selection to the nearest layer that has a page stored on
it. The panel's title is the first text in that frame, or the frame's name.

A frame with none falls back to a link: a text layer that links to a page
("Open live preview"). That variant is the smallest layer holding both the
link and the variant's pictures, so a neighbour without a link shows no
preview. The link also works for people without the plugin, since clicking it
opens the page in a browser. Links to other Figma files do not count.

## The server address

By default each page opens at the address stored for it, so a file whose
addresses point at `http://localhost:3000` works on a machine serving the
project there. To use another server without changing them (a shared host,
say), set its address with the gear: it replaces the server part of every
address, for every variant, in any file. It is each person's own setting, kept in Figma's plugin
storage, and changes nothing in the file.

## Limits

- The page is in a floating panel, not on the canvas.
- Each person runs the plugin themselves. To give it to a team without each
  person importing it, publish it privately to the organisation from Figma.
- The manifest allows any address (`networkAccess.allowedDomains: ["*"]`),
  because the server's address is the user's to set.
