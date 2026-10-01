// Design Gallery: shows the live page of the design variant selected on the
// canvas, served by the design plugin's gallery (plugins/design, skill
// "gallery").
//
// A variant on the canvas is recognised by its link. When the gallery's
// pictures are placed in a file, each variant's label links to
// "<gallery address>/direction/<folder>?preview=<letter>". Selecting anything
// in that variant's column (the label, a screen, the column itself) finds the
// link, and the panel loads that variant from the gallery.

figma.showUI(__html__, { width: 1080, height: 780, themeColors: true })

const LINK = /^(https?:\/\/[^/]+)\/direction\/([^?#]+)\?(?:[^#]*&)?preview=([^&#]+)/

// Every distinct variant link on or inside a node.
function linksIn(node) {
  const texts = node.type === 'TEXT' ? [node] : 'findAllWithCriteria' in node ? node.findAllWithCriteria({ types: ['TEXT'] }) : []
  const found = new Map()
  for (const text of texts) {
    for (const segment of text.getStyledTextSegments(['hyperlink'])) {
      const url = segment.hyperlink && segment.hyperlink.type === 'URL' ? segment.hyperlink.value : ''
      const m = url.match(LINK)
      if (!m) continue
      const variant = { origin: m[1], folder: decodeURIComponent(m[2]), letter: decodeURIComponent(m[3]).toLowerCase() }
      found.set(variant.folder + '/' + variant.letter, variant)
    }
  }
  return [...found.values()]
}

// The variant a node belongs to: the nearest ancestor that holds exactly one
// variant link. An ancestor holding several (a whole section) is not a variant.
function variantFor(node) {
  for (let n = node; n && n.type !== 'PAGE' && n.type !== 'DOCUMENT'; n = n.parent) {
    const links = linksIn(n)
    if (links.length === 1) return links[0]
    if (links.length > 1) return null
  }
  return null
}

function sendSelection() {
  const node = figma.currentPage.selection[0]
  figma.ui.postMessage({ type: 'selection', variant: node ? variantFor(node) : null, selected: Boolean(node) })
}

figma.on('selectionchange', sendSelection)

figma.ui.onmessage = async (message) => {
  if (message.type === 'ready') {
    figma.ui.postMessage({ type: 'settings', address: (await figma.clientStorage.getAsync('galleryAddress')) || '' })
    sendSelection()
  }
  if (message.type === 'address') {
    await figma.clientStorage.setAsync('galleryAddress', message.value)
    sendSelection()
  }
  if (message.type === 'resize') figma.ui.resize(Math.round(message.width), Math.round(message.height))
  if (message.type === 'open') figma.openExternal(message.url)
}
