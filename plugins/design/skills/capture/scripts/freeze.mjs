// Freeze a running page into one long, self-contained HTML file of stacked
// "plates": one screen per scroll stop, each captured in its settled state
// with the page's scripts and motion running.
//
// Why plates. A page built around a viewport (a fixed stage whose scenes change
// as you scroll, vh-sized sections, scroll-driven animation) has no single
// static rendering: what you see depends on where you are. Stripping its
// scripts freezes it in the first scene; putting it in a tall frame makes its
// "viewport" nine thousand pixels high. So the page is loaded at a real
// viewport, stopped at every screen, allowed to settle, and each screen's DOM
// is captured with every running animation committed to its current value.
// The output stacks those screens. Text stays text; nothing needs to scroll,
// which is what a canvas whose frames do not scroll needs.
//
// How a plate holds together in one document:
//   - one shared stylesheet, selectors on html/body/:root rewritten onto the
//     plate's own wrappers, viewport units pinned to the capture viewport;
//   - each plate is a transformed, clipped box, which makes it the containing
//     block for position:fixed descendants (a stage fills its plate) while
//     in-flow content is shifted up by the plate's scroll offset;
//   - images and fonts are inlined once and referenced from every plate.
//
// Every plate is then rendered from the file and compared with a screenshot of
// the live page at that stop; the difference per plate goes in the manifest
// and the run exits 1 when any plate is more than 1% away.
//
// Usage: node freeze.mjs <targets.json> --dir <directions dir> [--only <direction key>] [--variant <id>] [--flow]
//
// --flow is for a page whose reduced-motion layout is a normal long-scroll
// document: it is loaded under prefers-reduced-motion, refused if a fixed or
// sticky layer still covers the viewport, and captured as one document.
//
// targets.json is the capture.mjs shape (directions[].variants[] with id, url,
// optional label); url is an http(s) address or a path to a self-contained
// HTML file. Output is "Homepage <X> - <Title>.plates.html". Each direction needs a `folder` (name under --dir) or a key
// whose first segment matches a folder's leading token ("03-drawn" ->
// "03 Drawn"). A variant's title comes from a spec beside it named
// "Homepage <X> - <Title>.md" when one exists, else from its label.
//
// Needs each variant's page running, and @playwright/test (or playwright) with
// Chromium plus sharp resolvable from the current working directory.
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { basename, relative, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const args = process.argv.slice(2)
const flag = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const targetsPath = args.find((a) => !a.startsWith('--') && a.endsWith('.json'))
const dirArg = flag('--dir')
if (!targetsPath || !dirArg) {
  console.error('usage: freeze.mjs <targets.json> --dir <directions dir> [--only <direction key>] [--variant <id>]')
  process.exit(2)
}
const only = flag('--only')
const onlyVariant = flag('--variant')
// --flow: the page has a real reduced-motion layout (a normal long-scroll
// document, no fixed stage), so capture that once instead of stacking plates.
const flowMode = args.includes('--flow')
const cfg = JSON.parse(readFileSync(targetsPath, 'utf8'))
const DIRECTIONS = resolve(dirArg)
const WIDTH = cfg.captureWidth ?? 1440
const HEIGHT = cfg.captureHeight ?? 900
const SETTLE_MS = Number(flag('--settle') ?? 1600)
const HIDE = (cfg.hideSelectors ?? ['nextjs-portal']).concat('[data-preview-chrome]').join(',')

const cwd = process.cwd()
const projectRequire = createRequire(resolve(cwd, 'package.json'))
function requireFirst(names) {
  for (const n of names) {
    try {
      return projectRequire(n)
    } catch {}
  }
  // pnpm keeps transitive deps out of the root node_modules; look in the store.
  const store = resolve(cwd, 'node_modules/.pnpm')
  if (existsSync(store)) {
    for (const n of names) {
      const d = readdirSync(store).find((x) => x.startsWith(`${n}@`))
      if (d) return createRequire(resolve(store, d, `node_modules/${n}/package.json`))(n)
    }
  }
  throw new Error(`cannot resolve ${names.join(' or ')} from ${cwd}; install it in the project`)
}
const { chromium } = requireFirst(['@playwright/test', 'playwright'])
const sharp = requireFirst(['sharp'])

// How far a rendered plate is from its live screen, 0 to 1: both are shrunk
// (grain and antialiasing wash out), cut into a grid of tiles, and the worst
// tile's mean difference is the score. A whole-screen mean lets a moved
// heading on a sparse page hide below any sensible threshold; a tile does not.
async function difference(a, b) {
  const W = 360
  const H = 225
  const T = 45
  const raw = (buf) => sharp(buf).resize(W, H, { fit: 'fill' }).removeAlpha().raw().toBuffer()
  const [x, y] = await Promise.all([raw(a), raw(b)])
  let worst = 0
  for (let ty = 0; ty < H; ty += T) {
    for (let tx = 0; tx < W; tx += T) {
      let sum = 0
      for (let py = ty; py < ty + T; py++) {
        for (let px = tx; px < tx + T; px++) {
          const i = (py * W + px) * 3
          sum += Math.abs(x[i] - y[i]) + Math.abs(x[i + 1] - y[i + 1]) + Math.abs(x[i + 2] - y[i + 2])
        }
      }
      worst = Math.max(worst, sum / (T * T * 3) / 255)
    }
  }
  return worst
}

function folderFor(d) {
  if (d.folder) {
    const p = resolve(DIRECTIONS, d.folder)
    mkdirSync(p, { recursive: true })
    return p
  }
  const token = d.key.split('-')[0]
  const found = readdirSync(DIRECTIONS).find((f) => f.split(' ')[0] === token)
  if (found) return resolve(DIRECTIONS, found)
  throw new Error(`no folder for ${d.key} under ${DIRECTIONS}; set "folder" on the direction`)
}

function titleFor(dir, id, label) {
  const letter = id.length === 1 ? id.toUpperCase() : null
  if (letter) {
    const spec = readdirSync(dir).find((f) => f.startsWith(`Homepage ${letter} - `) && f.endsWith('.md'))
    if (spec) return spec.slice(`Homepage ${letter} - `.length, -3)
  }
  return (label ?? id)
    .replace(/^[A-Za-z],\s*/, '')
    .replace(/[^A-Za-z0-9 ().-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (c) => c.toUpperCase())
}
// The plates file sits beside the variant's live page (when there is one) and
// its spec, so the suffix says which is which.
const fileNameFor = (id, title) => `Homepage ${id.length === 1 ? id.toUpperCase() : id} - ${title}.plates.html`
// A variant's url is an http(s) address or a path to a self-contained HTML file.
const isRemote = (u) => /^https?:\/\//.test(u)
const toUrl = (u) => (isRemote(u) || u.startsWith('file:') ? u : pathToFileURL(resolve(u)).href)

// ---- in-page helpers (serialised into the page) ---------------------------

// The whole stylesheet as text, with selectors that address the document
// (html, body, :root) moved onto the plate wrappers, so per-plate state on
// those elements keeps working and inherited base styles reach every plate.
function collectCss() {
  const mapSelector = (sel) =>
    sel
      .replace(/(^|[\s,>+~(])html(?=$|[\s,.:#[>+~)])/g, '$1.plate-root')
      .replace(/(^|[\s,>+~(])body(?=$|[\s,.:#[>+~)])/g, '$1.plate-body')
      .replace(/:root/g, '.plate-root')
  const walk = (rules) => {
    let out = ''
    for (const r of rules) {
      if (r instanceof CSSStyleRule) {
        const nested = r.cssRules && r.cssRules.length ? walk(r.cssRules) : ''
        out += `${mapSelector(r.selectorText)}{${r.style.cssText}${nested}}\n`
      } else if (r instanceof CSSMediaRule || r instanceof CSSSupportsRule || (window.CSSContainerRule && r instanceof CSSContainerRule)) {
        out += `${r.cssText.slice(0, r.cssText.indexOf('{'))}{\n${walk(r.cssRules)}}\n`
      } else if (window.CSSLayerBlockRule && r instanceof CSSLayerBlockRule) {
        out += `@layer ${r.name}{\n${walk(r.cssRules)}}\n`
      } else {
        out += r.cssText + '\n' // @font-face, @keyframes, @property, @layer statements
      }
    }
    return out
  }
  let css = ''
  for (const sheet of document.styleSheets) {
    try {
      css += walk(sheet.cssRules)
    } catch {} // cross-origin sheet; nothing here uses one
  }
  return css
}

// Freeze the current moment into the DOM and return it. Every animation
// (CSS, scroll-driven, Web Animations) is committed to inline style so the
// plate can drop the animation and keep the look.
// Bring the screen to rest. A transition or one-shot animation still running
// when the plate is taken would be frozen mid-flight (a window caught at
// opacity 0.1 reads as empty), so anything on the document timeline with a
// finite end is finished first; a scene that waits for its image before it
// fades in gets its images decoded before that.
async function settlePlate() {
  await Promise.all(
    [...document.images].filter((i) => i.currentSrc || i.src).map((i) => i.decode().catch(() => {}))
  )
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
  for (let pass = 0; pass < 3; pass++) {
    for (const a of document.getAnimations()) {
      const end = a.effect?.getComputedTiming().endTime
      const onDocumentTimeline = !a.timeline || a.timeline instanceof DocumentTimeline
      if (onDocumentTimeline && Number.isFinite(end)) {
        try {
          a.finish()
        } catch {}
      }
    }
    // finishing one transition can start the next (a chained reveal)
    await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))
  }
}

function capturePlate(hide) {
  // What is still animating now is scroll-driven or endless; pin it where it is.
  for (const a of document.getAnimations()) {
    try {
      a.commitStyles()
    } catch {}
  }
  const attrs = (el) => [...el.attributes].map((a) => [a.name, a.value])
  const body = document.body.cloneNode(true)
  body.querySelectorAll('script, noscript, link[rel=preload]').forEach((n) => n.remove())
  if (hide) body.querySelectorAll(hide).forEach((n) => n.remove())
  // Resolve what each image is actually showing; srcset/sizes are meaningless
  // once the file is static.
  const live = [...document.body.querySelectorAll('img')]
  const cloned = [...body.querySelectorAll('img')]
  cloned.forEach((img, i) => {
    const src = live[i]?.currentSrc || live[i]?.src || ''
    img.setAttribute('data-plate-src', src)
    img.removeAttribute('srcset')
    img.removeAttribute('sizes')
    img.removeAttribute('loading')
  })
  return {
    scrollY: Math.round(window.scrollY),
    html: attrs(document.documentElement),
    body: attrs(document.body),
    inner: body.innerHTML,
  }
}

// ---- node side -------------------------------------------------------------

const VH = /(-?\d*\.?\d+)(?:s|d|l)?vh\b/g
// Never inside url(...): a base64 font or image can contain "3vh" by chance,
// and rewriting it corrupts the file (a display face silently falling back to
// Times is how that shows up).
const pinViewportUnits = (css) =>
  css
    .split(/(url\([^)]*\))/)
    .map((part, i) => (i % 2 ? part : part.replace(VH, (_, n) => `${(Number(n) * HEIGHT) / 100}px`)))
    .join('')
// The same, limited to style attributes, for a plate's markup.
const pinInlineStyles = (html) => html.replace(/\sstyle="[^"]*"/g, (m) => pinViewportUnits(m))

async function inlineUrl(page, url, cache) {
  if (cache.has(url)) return cache.get(url)
  let value = null
  try {
    const res = await page.request.get(url, { timeout: 60000 })
    if (res.ok()) {
      const type = (res.headers()['content-type'] || 'application/octet-stream').split(';')[0]
      value = `data:${type};base64,${(await res.body()).toString('base64')}`
    }
  } catch {}
  cache.set(url, value)
  return value
}

// url(...) inside CSS text -> data URIs, resolved against the page.
async function inlineCssUrls(page, css, base, cache) {
  const urls = [...new Set([...css.matchAll(/url\(\s*(['"]?)([^'")]+)\1\s*\)/g)].map((m) => m[2]))].filter(
    (u) => !u.startsWith('data:') && !u.startsWith('#')
  )
  for (const u of urls) {
    const abs = new URL(u, base).href
    const data = await inlineUrl(page, abs, cache)
    if (data) css = css.split(`url(${u})`).join(`url(${data})`).split(`url("${u}")`).join(`url(${data})`).split(`url('${u}')`).join(`url(${data})`)
  }
  return css
}

const attrString = (pairs, skip = []) =>
  pairs
    .filter(([k]) => !skip.includes(k))
    .map(([k, v]) => `${k}="${String(v).replace(/&/g, '&amp;').replace(/"/g, '&quot;')}"`)
    .join(' ')

async function buildPlates(page, url, flow = false) {
  await page.goto(url, { waitUntil: 'networkidle', timeout: 180000 })
  await page.addStyleTag({ content: `${HIDE}{display:none !important}` })
  await page.waitForTimeout(2500)
  // Walk once so lazy images load and anything revealed on first sight has been seen.
  const total = await page.evaluate(() => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight))
  const stops = Math.max(1, Math.ceil(total / HEIGHT - 0.05))
  for (let i = 0; i < stops; i++) {
    await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), i * HEIGHT)
    await page.waitForTimeout(250)
  }
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }))
  await page.waitForTimeout(1500)

  const cache = new Map()
  let css = await page.evaluate(collectCss)
  css = await inlineCssUrls(page, pinViewportUnits(css), url, cache)

  // A page that keeps a viewport-sized fixed or sticky layer under reduced
  // motion is still a stage, not a long-scroll document.
  const stage = flow
    ? await page.evaluate(() => {
        const vw = innerWidth
        const vh = innerHeight
        for (const el of document.body.querySelectorAll('*')) {
          const cs = getComputedStyle(el)
          if (cs.position !== 'fixed' && cs.position !== 'sticky') continue
          const r = el.getBoundingClientRect()
          if (r.width * r.height > vw * vh * 0.5 && cs.visibility !== 'hidden' && cs.display !== 'none')
            return `${el.tagName.toLowerCase()}.${String(el.className).split(' ')[0]} (${cs.position}, ${Math.round(r.width)}x${Math.round(r.height)})`
        }
        return null
      })
    : null
  if (stage) throw new Error(`not a long-scroll layout under reduced motion: ${stage} covers the viewport`)

  const plates = []
  const shots = []
  for (let i = 0; i < stops; i++) {
    await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), i * HEIGHT)
    await page.waitForTimeout(SETTLE_MS)
    await page.evaluate(settlePlate)
    await page.waitForTimeout(150)
    // The live screen is the reference each plate is checked against. In flow
    // mode the document is captured once, so a fixed header would show in
    // every live screen but only once in the file: hide fixed layers below
    // the first screen for the reference shots.
    if (flow && i > 0) {
      await page.evaluate(() => {
        for (const el of document.body.querySelectorAll('*')) {
          if (getComputedStyle(el).position === 'fixed') {
            el.dataset.flowHidden = '1'
            el.style.visibility = 'hidden'
          }
        }
      })
    }
    shots.push(await page.screenshot())
    if (!flow) plates.push(await page.evaluate(capturePlate, HIDE))
  }
  if (flow) {
    await page.evaluate(() => {
      document.querySelectorAll('[data-flow-hidden]').forEach((el) => {
        el.style.visibility = ''
        delete el.dataset.flowHidden
      })
      window.scrollTo({ top: 0, behavior: 'instant' })
    })
    await page.waitForTimeout(400)
    await page.evaluate(settlePlate)
    plates.push(await page.evaluate(capturePlate, HIDE))
  }

  // Images: one custom property per distinct source, referenced from every plate.
  const imgVar = new Map()
  let vars = ''
  for (const p of plates) {
    for (const m of p.inner.matchAll(/data-plate-src="([^"]*)"/g)) {
      const src = m[1].replace(/&amp;/g, '&')
      if (!src || imgVar.has(src)) continue
      const data = src.startsWith('data:') ? src : await inlineUrl(page, new URL(src, url).href, cache)
      const name = `--plate-img-${imgVar.size}`
      imgVar.set(src, data ? name : null)
      if (data) vars += `${name}:url(${data});`
    }
  }
  const BLANK = 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw=='
  const renderInner = (inner) =>
    pinInlineStyles(
      inner.replace(/<img\b([^>]*?)data-plate-src="([^"]*)"([^>]*)>/g, (_, a, src, b) => {
        const name = imgVar.get(src.replace(/&amp;/g, '&'))
        const rest = (a + b).replace(/\ssrc="[^"]*"/, '')
        const styled = /\sstyle="/.test(rest)
          ? rest.replace(/\sstyle="/, ` style="content:var(${name});`)
          : `${rest} style="content:var(${name})"`
        return name ? `<img src="${BLANK}"${styled}>` : `<img${rest}>`
      })
    )

  const plateCss = `
html,body{margin:0;padding:0;background:#fff}
.plate-doc{${vars}}
.plate{display:block;position:relative;width:${WIDTH}px;height:${HEIGHT}px;overflow:hidden;transform:translateZ(0);contain:paint}
.plate-root{position:relative;display:block;width:${WIDTH}px;min-height:${HEIGHT}px}
.plate-body{display:block;min-height:${HEIGHT}px}
.plate *,.plate *::before,.plate *::after{animation:none !important;transition:none !important;scroll-snap-align:none !important}
`
  const last = plates[plates.length - 1].scrollY
  const body = plates
    .map((p, i) => {
      // The final stop cannot scroll a full screen, so its plate starts where
      // the page actually stopped; note it so the overlap is not a surprise.
      const htmlAttrs = attrString(p.html, ['class', 'style'])
      const bodyAttrs = attrString(p.body, ['class', 'style'])
      const cls = (pairs) => (pairs.find(([k]) => k === 'class') || [, ''])[1]
      const sty = (pairs) => pinViewportUnits((pairs.find(([k]) => k === 'style') || [, ''])[1])
      // Custom elements, so a page rule on `section` or `div` cannot style the
      // wrappers (a page's own `section { padding }` once doubled every inset).
      return `<x-plate class="plate"${flow ? ` style="height:${Math.max(total, HEIGHT)}px"` : ''} data-plate="${i + 1}" data-scroll-y="${p.scrollY}">
<x-plate-root class="plate-root ${cls(p.html)}" ${htmlAttrs} style="margin-top:-${p.scrollY}px;${sty(p.html)}">
<x-plate-body class="plate-body ${cls(p.body)}" ${bodyAttrs} style="${sty(p.body)}">${renderInner(p.inner)}</x-plate-body></x-plate-root></x-plate>`
    })
    .join('\n')

  const doc = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=${WIDTH}">
<title>${(await page.title()).replace(/</g, '&lt;')}</title>
<style>${css}</style><style>${plateCss}</style></head>
<body class="plate-doc">
${body}
</body></html>
`
  return { doc, plates: plates.length, screens: shots.length, pageHeight: total, lastScrollY: last, shots }
}

async function measure(browser, file, shots, expectedHeight) {
  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT } })
  const errors = []
  page.on('pageerror', (e) => errors.push(String(e)))
  await page.goto(pathToFileURL(file).href, { waitUntil: 'load' })
  await page.waitForTimeout(500)
  const stats = await page.evaluate(() => ({
    height: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    imgs: document.images.length,
  }))
  // Each plate, rendered from the file, against the live screen it was taken from.
  const diffs = []
  for (let i = 0; i < shots.length; i++) {
    // the last live screen stops where the page ends, not on a multiple of the height
    const y = Math.min(i * HEIGHT, Math.max(0, expectedHeight - HEIGHT))
    const got = await page.screenshot({ clip: { x: 0, y, width: WIDTH, height: HEIGHT }, fullPage: true })
    diffs.push(Number((await difference(got, shots[i])).toFixed(4)))
  }
  await page.close()
  return {
    ...stats,
    expectedHeight,
    errors: errors.length,
    plateDiff: diffs,
    worstDiff: Math.max(...diffs),
  }
}

const browser = await chromium.launch()
const results = []
for (const d of cfg.directions) {
  if (only && d.key !== only) continue
  const dir = folderFor(d)
  const manifestPath = resolve(dir, 'Snapshots.json')
  const manifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : { variants: [] }
  for (const v of d.variants) {
    if (onlyVariant && v.id !== onlyVariant) continue
    // A local file already carries its title: "Homepage C - The Shelf.html".
    const own = !isRemote(v.url) && /^Homepage \S+ - (.+)\.html$/.exec(basename(v.url))
    const title = own ? own[1] : titleFor(dir, v.id, v.label)
    const file = resolve(dir, fileNameFor(v.id, title))
    const entry = {
      id: v.id,
      title,
      file: fileNameFor(v.id, title),
      label: v.label ?? null,
      source: v.url,
      // The live page, for a second, viewport-sized frame that can be presented.
      ...(isRemote(v.url) ? {} : { live: relative(dir, resolve(v.url)) }),
      round: d.key,
      mode: flowMode ? 'flow' : 'plates',
      capturedAt: new Date().toISOString(),
    }
    const page = await browser.newPage({
      viewport: { width: WIDTH, height: HEIGHT },
      deviceScaleFactor: 1,
      ...(flowMode ? { reducedMotion: 'reduce' } : {}),
    })
    const consoleErrors = []
    page.on('pageerror', (e) => consoleErrors.push(String(e)))
    try {
      const built = await buildPlates(page, toUrl(v.url), flowMode)
      writeFileSync(file, built.doc)
      const expected = flowMode ? Math.max(built.pageHeight, HEIGHT) : built.plates * HEIGHT
      Object.assign(entry, await measure(browser, file, built.shots, expected), {
        plates: built.plates,
        pageHeight: built.pageHeight,
        bytes: statSync(file).size,
        sourceErrors: consoleErrors.length,
        ok: true,
      })
    } catch (e) {
      Object.assign(entry, { ok: false, err: String(e).slice(0, 300) })
    }
    await page.close()
    manifest.variants = manifest.variants.filter((m) => m.id !== v.id).concat(entry)
    results.push(entry)
    console.log(JSON.stringify(entry))
  }
  manifest.variants.sort((a, b) => a.id.localeCompare(b.id))
  manifest.width = WIDTH
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n')
}
await browser.close()

// A faithful plate's worst tile is within about half a percent of its live
// screen; 2% on any tile means something visible differs there.
const bad = results.filter((r) => !r.ok || r.overflow > 0 || r.height !== r.expectedHeight || r.worstDiff > 0.02)
if (bad.length) {
  console.error(`\n${bad.length} plate file(s) need attention`)
  process.exitCode = 1
}
