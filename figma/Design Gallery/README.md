# Design Gallery (Figma plugin)

Shows the live page of a design variant inside Figma. Select a variant on the
canvas and the panel loads its real page from the design plugin's gallery
(`plugins/design`, skill `gallery`): it scrolls and moves as built, at the
panel's size or at laptop, tablet, or phone size.

Figma holds the layout and the comments; the gallery holds the page. This
panel is the bridge, so reviewing a variant does not mean leaving the file.

## Install

It is a development plugin, loaded from this folder:

1. In the Figma desktop app, open any design file.
2. Plugins → Development → Import plugin from manifest…
3. Choose `manifest.json` in this folder.
4. Run it from Plugins → Development → Design Gallery.

There is no build step. Figma reads `code.js` and `ui.html` as they are; after
changing either, run the plugin again.

## Use

1. Start the gallery for the project (`node …/gallery.mjs`, or the project's
   own command). It answers at `http://127.0.0.1:4600` by default.
2. Run the plugin and select a variant: its label, one of its screens, or its
   whole column.
3. The panel shows that variant's page. The buttons in its bar:
   - fill the panel, laptop (1440 × 900), tablet (834 × 1112), phone (360 × 800);
     a size larger than the panel is scaled to fit and the bar says by how much
   - edit with impeccable live, in the browser, when the gallery offers it
     (a source-page variant, on the machine running the gallery)
   - reload
   - the gallery's address
4. Drag the right or bottom edge of the page, or its corner, to try other
   sizes.
5. Drag the grip in the window's bottom-right corner to resize the plugin's
   window; the page refits.

Selecting a layer that is not part of a variant says so and clears the panel.

## How it finds a variant

By its link. When the gallery's pictures are placed in a file, each variant's
label links to `<gallery address>/direction/<folder>?preview=<letter>`
(`plugins/design/skills/gallery/SKILL.md` § Review in Figma). The plugin walks
up from the selection to the nearest layer that contains exactly one such
link, then asks the gallery (`/api/directions.json`) for that variant's page.
A layer containing several variants' links, such as a whole section, is not a
variant.

## The gallery's address

By default the panel uses the address in the variant's own link, so a file
whose links point at `http://127.0.0.1:4600` works on the machine running the
gallery. To use a hosted gallery without rewriting the links, set its address
with the gear. That one address is then used for every variant, in any file;
it is each person's own setting, kept in Figma's plugin storage, and changes
nothing in the file. Empty it to go back to each link's own address.

## Limits

- The page is in a floating panel, not on the canvas.
- Each person runs the plugin themselves. To give it to a team without each
  person importing it, publish it privately to the organisation from Figma.
- The manifest allows any address (`networkAccess.allowedDomains: ["*"]`),
  because the gallery's address is the user's to set.
