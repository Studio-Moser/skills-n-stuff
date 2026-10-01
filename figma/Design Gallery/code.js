// Design Gallery: shows the live page of the design variant selected on the
// canvas.
//
// A variant is a frame that knows its page. The address is stored on the frame
// itself, as shared plugin data (namespace "design_gallery", key "page"), so
// nothing has to be drawn on the canvas, and any tool that can write shared
// plugin data can hook a frame up. Selecting the frame, or anything inside it,
// shows the page. The panel sets, changes, and removes a frame's page.
//
// A frame without one falls back to a link: a text in it that links to a page
// ("Open live preview"), which also works for people without the plugin.
// Any server that serves the page will do.

figma.showUI(__html__, { width: 1080, height: 780, themeColors: true })

const NAMESPACE = 'design_gallery'
const KEY = 'page'
const pageOf = (node) => ('getSharedPluginData' in node ? node.getSharedPluginData(NAMESPACE, KEY) : '')

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

// A variant's name: the first text in it that is not a link, else the layer's.
const titleOf = (node) => {
  const text = 'findAllWithCriteria' in node ? node.findAllWithCriteria({ types: ['TEXT'] }).find((t) => !pageLink(t)) : null
  return text ? text.characters.split('\n')[0].slice(0, 80) : node.name
}

// The variant a node belongs to: the nearest frame, at or above the node, that
// has a page; failing that, a link at or above the node whose variant contains
// the node.
function variantFor(node) {
  for (let n = node; n && n.type !== 'PAGE' && n.type !== 'DOCUMENT'; n = n.parent) {
    const url = pageOf(n)
    if (url) return { url, label: titleOf(n), via: 'frame', ownerId: n.id, ownerName: n.name }
  }
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
  return { url: pageLink(linkText), label: named ? named.characters.split('\n')[0].slice(0, 80) : '', via: 'link' }
}

function sendSelection() {
  const node = figma.currentPage.selection[0]
  figma.ui.postMessage({
    type: 'selection',
    selected: node ? { id: node.id, name: node.name } : null,
    variant: node ? variantFor(node) : null,
  })
}

// Every frame on this canvas page that has a page of its own.
function sendList() {
  const frames = figma.currentPage.findAllWithCriteria({ sharedPluginData: { namespace: NAMESPACE, keys: [KEY] } })
  figma.ui.postMessage({ type: 'list', frames: frames.map((n) => ({ id: n.id, name: n.name, url: pageOf(n) })) })
}

figma.on('selectionchange', sendSelection)
figma.on('currentpagechange', () => { sendSelection(); sendList() })

figma.ui.onmessage = async (message) => {
  if (message.type === 'ready') {
    figma.ui.postMessage({ type: 'settings', address: (await figma.clientStorage.getAsync('galleryAddress')) || '' })
    sendSelection()
    sendList()
  }
  if (message.type === 'address') {
    await figma.clientStorage.setAsync('galleryAddress', message.value)
    sendSelection()
  }
  if (message.type === 'setPage') {
    const node = await figma.getNodeByIdAsync(message.id)
    if (node && 'setSharedPluginData' in node) node.setSharedPluginData(NAMESPACE, KEY, message.value)
    sendSelection()
    sendList()
  }
  if (message.type === 'select') {
    const node = await figma.getNodeByIdAsync(message.id)
    if (node && node.type !== 'PAGE' && node.type !== 'DOCUMENT') {
      figma.currentPage.selection = [node]
      figma.viewport.scrollAndZoomIntoView([node])
    }
  }
  if (message.type === 'list') sendList()
  if (message.type === 'resize') figma.ui.resize(Math.round(message.width), Math.round(message.height))
}
