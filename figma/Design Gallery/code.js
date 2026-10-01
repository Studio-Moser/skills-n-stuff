// Design Gallery: shows the live page of the design variant selected on the
// canvas.
//
// A variant on the canvas is recognised by its link. Its label carries a link
// to the variant's page ("Open live preview"), and that page is what the panel
// loads. Selecting anything in the variant (the label, a screen, the whole
// column) finds the link; selecting anything else clears the panel. Nothing
// else is needed: any server that serves the page will do.

figma.showUI(__html__, { width: 1080, height: 780, themeColors: true })

// Links to pages, not to other Figma files.
const isPage = (url) => /^https?:\/\//i.test(url) && !/^https?:\/\/([^/]*\.)?figma\.com\//i.test(url)

const pageLink = (text) => {
  for (const segment of text.getStyledTextSegments(['hyperlink'])) {
    const url = segment.hyperlink && segment.hyperlink.type === 'URL' ? segment.hyperlink.value : ''
    if (isPage(url)) return url
  }
  return ''
}
const hasPicture = (node) => 'fills' in node && Array.isArray(node.fills) && node.fills.some((f) => f.type === 'IMAGE')
const isWithin = (node, root) => {
  for (let n = node; n; n = n.parent) if (n === root) return true
  return false
}

// A variant is the smallest layer that holds both its link and its pictures:
// walking up from the linked text, the first ancestor with a picture in it.
// A row of variants in which only one has a link is therefore not that variant.
function variantRoot(linkText) {
  for (let n = linkText.parent; n && n.type !== 'PAGE' && n.type !== 'DOCUMENT'; n = n.parent) {
    if (hasPicture(n) || ('findOne' in n && n.findOne(hasPicture))) return n
  }
  return null
}

// The variant a node belongs to: a link, at or above the node, whose variant
// contains the node.
function variantFor(node) {
  if (node.type === 'TEXT' && pageLink(node)) return describe(node, variantRoot(node))
  for (let n = node; n && n.type !== 'PAGE' && n.type !== 'DOCUMENT'; n = n.parent) {
    if (!('findAllWithCriteria' in n)) continue
    for (const text of n.findAllWithCriteria({ types: ['TEXT'] })) {
      if (!pageLink(text)) continue
      const root = variantRoot(text)
      if (root && isWithin(node, root)) return describe(text, root)
    }
  }
  return null
}

// The link and the variant's name: the first text in it that is not the link.
function describe(linkText, root) {
  const within = root || linkText.parent
  const named = within && 'findAllWithCriteria' in within ? within.findAllWithCriteria({ types: ['TEXT'] }).find((t) => !pageLink(t)) : null
  return { url: pageLink(linkText), label: named ? named.characters.split('\n')[0].slice(0, 80) : '' }
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
}
