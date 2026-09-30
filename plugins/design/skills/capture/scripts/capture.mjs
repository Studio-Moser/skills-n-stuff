// Screenshot every variant in a targets.json at one fixed width and scale,
// ready to be placed side by side in Figma or a local gallery.
//
// Each shot produces three things: a stitched PNG for the archive, a set of
// horizontal BANDS which is what actually goes into Figma, and a manifest
// describing both so the frames can be built before the upload.
//
// Usage: node capture.mjs <targets.json> [--out <dir>] [--only <direction key>]
//
// Requires @playwright/test (or playwright) and sharp, resolvable from the
// current working directory's package.json. Run it from the project root.
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync, rmSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { createRequire } from 'node:module'

const args = process.argv.slice(2)
const targetsPath = args.find((a) => !a.startsWith('--'))
if (!targetsPath) {
  console.error('usage: capture.mjs <targets.json> [--out <dir>] [--only <direction key>]')
  process.exit(2)
}
const flag = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const cwd = process.cwd()
const projectRequire = createRequire(resolve(cwd, 'package.json'))

function requireFirst(names) {
  for (const n of names) {
    try {
      return projectRequire(n)
    } catch {}
  }
  // pnpm keeps transitive deps out of the root node_modules, so look in the
  // store before giving up.
  const store = resolve(cwd, 'node_modules/.pnpm')
  if (existsSync(store)) {
    for (const n of names) {
      const dir = readdirSync(store).find((d) => d.startsWith(`${n}@`))
      if (dir) return createRequire(resolve(store, dir, `node_modules/${n}/package.json`))(n)
    }
  }
  throw new Error(`cannot resolve ${names.join(' or ')} from ${cwd}; install it in the project`)
}

const { chromium } = requireFirst(['@playwright/test', 'playwright'])
const sharp = requireFirst(['sharp'])

const cfg = JSON.parse(readFileSync(targetsPath, 'utf8'))
const OUT = resolve(cwd, flag('--out') ?? 'Generations/shots')
const UPLOAD = resolve(OUT, 'figma')
const BANDS = resolve(OUT, 'bands')
const only = flag('--only')
const WIDTH = cfg.captureWidth ?? 1440
const SCALE = cfg.captureScale ?? 2
const BACKGROUND = cfg.background ?? '#ffffff'

// Figma's EDITOR refuses to draw a tall image while its server-side renderer
// draws it happily: an oversized fill uploads, inspects as a normal IMAGE, and
// screenshots correctly through the API, yet shows as an empty frame on the
// designer's screen. So every shot is cut into bands of at most this many CSS
// pixels and stacked in a vertical auto-layout frame.
const MAX_BAND = 2048
// Anything over 10MB per asset is rejected; anything whose long edge exceeds
// 16384px is accepted and renders as nothing.
const FIGMA_MAX_EDGE = 16384
const FIGMA_MAX_BYTES = 9_500_000

for (const d of [OUT, UPLOAD, BANDS]) mkdirSync(d, { recursive: true })

function hexToRgb(hex) {
  const h = hex.replace('#', '')
  const n = parseInt(h.length === 3 ? h.replace(/./g, (c) => c + c) : h, 16)
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
}

// A fixed <header> paints in every viewport frame, so stitching would stamp it
// down the page; hide it after the first frame where it belongs. Scoped to
// <header> on purpose: a direction may fix a full-viewport layer that is the
// design, not chrome. Review chrome tagged data-preview-chrome is hidden in
// every frame including the first.
const HIDE_HEADER = `[...document.querySelectorAll('header')]
  .filter((e) => getComputedStyle(e).position === 'fixed')
  .forEach((e) => { e.dataset.shotHidden = '1'; e.style.visibility = 'hidden' })`
const HIDE_PREVIEW_CHROME = `[...document.querySelectorAll('[data-preview-chrome]')]
  .forEach((e) => { e.dataset.shotHidden = '1'; e.style.visibility = 'hidden' })`
const SHOW_ALL = `[...document.querySelectorAll('[data-shot-hidden]')]
  .forEach((e) => { e.style.visibility = ''; delete e.dataset.shotHidden })`

async function stitch(page, outPath, pageHeight) {
  if (!(pageHeight > 0)) {
    throw new Error(
      `measured page height ${pageHeight}; nothing to stitch. The route rendered empty, ` +
        `or its root is a fixed stage that leaves scrollHeight at 0.`
    )
  }
  const vh = page.viewportSize().height
  const frames = []
  for (let y = 0; y < pageHeight; y += vh) {
    await page.evaluate((top) => window.scrollTo(0, top), y)
    await page.evaluate(HIDE_PREVIEW_CHROME)
    if (y > 0) await page.evaluate(HIDE_HEADER)
    await page.waitForTimeout(450)
    frames.push({ buf: await page.screenshot(), top: y })
  }
  await page.evaluate(SHOW_ALL)
  // The final scroll stops short of a full viewport, so trim its overlap.
  frames[frames.length - 1].top = await page.evaluate(() => window.scrollY)
  const settled = frames[frames.length - 1].top
  await sharp({
    create: {
      width: WIDTH * SCALE,
      height: Math.round((settled + vh) * SCALE),
      channels: 3,
      background: hexToRgb(BACKGROUND),
    },
  })
    .composite(frames.map((f) => ({ input: f.buf, top: Math.round(f.top * SCALE), left: 0 })))
    .png()
    .toFile(outPath)
}

async function toFigmaJpeg(png, out, pxHeight) {
  const cappedEdge = pxHeight > FIGMA_MAX_EDGE
  for (const quality of [80, 70, 62, 52, 44]) {
    let img = sharp(png)
    if (cappedEdge) img = img.resize({ height: FIGMA_MAX_EDGE })
    const info = await img.jpeg({ quality }).toFile(out)
    if (info.size < FIGMA_MAX_BYTES) return { quality, cappedEdge }
  }
  return { quality: null, cappedEdge }
}

async function sliceIntoBands(png, slug) {
  const dir = resolve(BANDS, slug)
  rmSync(dir, { recursive: true, force: true })
  mkdirSync(dir, { recursive: true })
  const { width, height } = await sharp(png).metadata()
  const bandDevice = MAX_BAND * SCALE
  const out = []
  for (let top = 0, i = 1; top < height; top += bandDevice, i++) {
    const h = Math.min(bandDevice, height - top)
    const file = resolve(dir, `${String(i).padStart(2, '0')}.jpg`)
    await sharp(png).extract({ left: 0, top, width, height: h }).jpeg({ quality: 82 }).toFile(file)
    out.push({ file, w: width / SCALE, h: h / SCALE })
  }
  return out
}

const browser = await chromium.launch()
const results = []

for (const d of cfg.directions) {
  if (only && d.key !== only) continue
  for (const v of d.variants) {
    const slug = `${d.key}--${v.id}`
    const page = await browser.newPage({
      viewport: { width: WIDTH, height: 900 },
      deviceScaleFactor: SCALE,
    })
    const errors = []
    page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))
    page.on('pageerror', (e) => errors.push(String(e)))
    try {
      await page.goto(v.url, { waitUntil: 'networkidle', timeout: 180000 })
      // Walk the page so lazy images load and scroll-driven sections settle.
      await page.evaluate(
        () =>
          new Promise((r) => {
            let y = 0
            const t = setInterval(() => {
              y += 700
              window.scrollTo(0, y)
              if (y > document.body.scrollHeight) {
                clearInterval(t)
                window.scrollTo(0, 0)
                r()
              }
            }, 70)
          })
      )
      await page.waitForTimeout(2000)
      // A root that is a fixed stage can leave body.scrollHeight at 0, and a
      // cold container can report 0 before first paint; wait for a real height.
      await page
        .waitForFunction(
          () => Math.max(document.body.scrollHeight, document.documentElement.scrollHeight) > 0,
          { timeout: 30000 }
        )
        .catch(() => {})
      const stats = await page.evaluate(() => {
        const imgs = [...document.querySelectorAll('img')].filter((i) => i.offsetParent !== null)
        return {
          height: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
          imgs: imgs.length,
          broken: imgs.filter((i) => !i.complete || i.naturalWidth === 0).length,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        }
      })
      const png = resolve(OUT, `${slug}.png`)
      if (v.capture === 'fullPage') {
        // Opt in only for a static page you have looked at. Chromium stops
        // painting past 16384 device pixels and drops content below that too,
        // blank rather than erroring.
        await page.screenshot({ path: png, fullPage: true })
      } else {
        await stitch(page, png, stats.height)
      }
      const jpeg = resolve(UPLOAD, `${slug}.jpg`)
      const { quality, cappedEdge } = await toFigmaJpeg(png, jpeg, stats.height * SCALE)
      const bands = await sliceIntoBands(png, slug)
      results.push({
        slug,
        ok: true,
        errors: errors.length,
        ...stats,
        display: { w: WIDTH, h: stats.height },
        bands,
        jpeg,
        quality,
        cappedEdge,
        oversize: quality === null,
      })
    } catch (e) {
      results.push({ slug, ok: false, err: String(e).slice(0, 200) })
    }
    await page.close()
  }
}
await browser.close()

// A filtered run must not wipe the shots it did not touch, so merge by slug.
const manifestPath = resolve(OUT, 'manifest.json')
const previous = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')).shots : []
const bySlug = new Map(previous.map((s) => [s.slug, s]))
for (const r of results) bySlug.set(r.slug, r)
const order = cfg.directions.flatMap((d) => d.variants.map((v) => `${d.key}--${v.id}`))
writeFileSync(
  manifestPath,
  JSON.stringify(
    {
      captureWidth: WIDTH,
      captureScale: SCALE,
      shots: order.filter((s) => bySlug.has(s)).map((s) => bySlug.get(s)),
    },
    null,
    2
  )
)

for (const r of results) console.log(JSON.stringify(r))
const bad = results.filter((r) => !r.ok || r.broken > 0 || r.overflow > 0 || r.oversize)
if (bad.length) {
  console.error(`\n${bad.length} target(s) need attention`)
  process.exitCode = 1
}
