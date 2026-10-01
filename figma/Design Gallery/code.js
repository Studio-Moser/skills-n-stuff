// Design Gallery: shows the live page of the design variant selected on the
// canvas.
//
// A variant on the canvas is recognised by its link. Its label carries a link
// to the variant's page ("Open live preview"), and that page is what the panel
// loads. Selecting anything in the variant's column (the label, a screen, the
// column itself) finds the link. Nothing else is needed: any server that
// serves the page will do.

figma.showUI(__html__, { width: 1080, height: 780, themeColors: true })

// Links to pages, not to other Figma files.
const isPage = (url) => /^https?:\/\//i.test(url) && !/^https?:\/\/([^/]*\.)?figma\.com\//i.test(url)

// Every distinct page link on or inside a node, with the text it sits on.
function linksIn(node) {
  const texts = node.type === 'TEXT' ? [node] : 'findAllWithCriteria' in node ? node.findAllWithCriteria({ types: ['TEXT'] }) : []
  const found = new Map()
  let label = ''
  for (const text of texts) {
    let linked = false
    for (const segment of text.getStyledTextSegments(['hyperlink'])) {
      const url = segment.hyperlink && segment.hyperlink.type === 'URL' ? segment.hyperlink.value : ''
      if (!isPage(url)) continue
      found.set(url, url)
      linked = true
    }
    // The variant's name is the first text beside the link that is not it.
    if (!linked && !label) label = text.characters.split('\n')[0].slice(0, 80)
  }
  return { urls: [...found.values()], label }
}

// The variant a node belongs to: the nearest ancestor that holds exactly one
// page link. An ancestor holding several (a whole section) is not a variant.
function variantFor(node) {
  for (let n = node; n && n.type !== 'PAGE' && n.type !== 'DOCUMENT'; n = n.parent) {
    const { urls, label } = linksIn(n)
    if (urls.length === 1) return { url: urls[0], label }
    if (urls.length > 1) return null
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
}
