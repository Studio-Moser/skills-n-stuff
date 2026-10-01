// Take a picture of each variant's whole scroll, for the gallery to show in
// place of a live page. A direction of twenty live pages is more than a
// browser tab will hold; twenty pictures are not, and the live page is one
// click away in the preview.
//
// Usage: node frames.mjs --dir <directions dir> [--only <folder prefix>] [--force]
//
// For each variant it pictures the frozen plates when they are at least as new
// as the source page, otherwise the source page as a reader who asked for
// reduced motion gets it: the build brief requires that to be a normal
// long-scroll page with every scene present, which is what a picture of the
// whole scroll needs. Viewport heights are pinned to a 900px screen so a
// section sized to the viewport does not stretch.
//
// Output: "<direction>/Frames/<variant>.webp", 640px wide, and Frames.json
// with each picture's size and what it was taken from. A picture newer than
// its page is left alone unless --force.
//
// Needs @playwright/test (or playwright) with Chromium, and sharp, resolvable
// from the current working directory.
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const args = process.argv.slice(2)
const flag = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const dir = flag('--dir') && resolve(flag('--dir'))
const only = flag('--only')
const force = args.includes('--force')
if (!dir || !existsSync(dir)) {
  console.error('usage: frames.mjs --dir <directions dir> [--only <folder prefix>] [--force]')
  process.exit(2)
}

const cwd = process.cwd()
const projectRequire = createRequire(resolve(cwd, 'package.json'))
function requireFirst(names) {
  for (const n of names) {
    try {
      return projectRequire(n)
    } catch {}
  }
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

const WIDTH = 1440
const SCREEN = 900
const OUT_WIDTH = 640
// Chromium paints nothing past 16384 device pixels, so a taller page is
// pictured in pieces and joined.
const PIECE = 8000

// The same grouping the gallery uses: "Homepage <X> - <Title>[.plates].html".
const VARIANT = /^(.*?\b([A-Za-z0-9]{1,12}) - (.+?))(\.plates)?\.html$/
function variants(folder) {
  const groups = new Map()
  for (const name of readdirSync(join(dir, folder))) {
    const m = name.match(VARIANT)
    if (!m || /^Cover\b/i.test(name)) continue
    const g = groups.get(m[1]) ?? { base: m[1] }
    g[m[4] ? 'plates' : 'source'] = name
    groups.set(m[1], g)
  }
  const mtime = (name) => statSync(join(dir, folder, name)).mtimeMs
  return [...groups.values()].map((g) => ({
    ...g,
    from: g.plates && (!g.source || mtime(g.plates) >= mtime(g.source)) ? g.plates : g.source,
  }))
}

// Viewport heights to pixels of a 900px screen, in the page's own styles and
// never inside url(…), where a data URL can contain "3vh" by chance.
const pin = (css) => css.replace(/url\([^)]*\)|(\d*\.?\d+)[dsl]?vh\b/g, (m, n) => (n === undefined ? m : `${+((n * SCREEN) / 100).toFixed(2)}px`))
const pinPage = (html) => html.replace(/(<style[^>]*>)([\s\S]*?)(<\/style>)/gi, (_, open, css, close) => open + pin(css) + close).replace(/\sstyle="[^"]*vh[^"]*"/gi, (m) => pin(m))

const folders = readdirSync(dir, { withFileTypes: true })
  .filter((e) => e.isDirectory() && !e.name.startsWith('.') && (!only || e.name.startsWith(only)))
  .map((e) => e.name)
  .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))

const browser = await chromium.launch()
const context = await browser.newContext({ viewport: { width: WIDTH, height: SCREEN }, deviceScaleFactor: 1, reducedMotion: 'reduce' })
let failed = 0
for (const folder of folders) {
  const list = variants(folder)
  if (!list.length) continue
  const outDir = join(dir, folder, 'Frames')
  const indexPath = join(outDir, 'Frames.json')
  const index = existsSync(indexPath) ? JSON.parse(readFileSync(indexPath, 'utf8')) : {}
  for (const v of list) {
    const file = join(dir, folder, v.from)
    const out = join(outDir, `${v.base}.webp`)
    if (!force && existsSync(out) && statSync(out).mtimeMs >= statSync(file).mtimeMs && index[v.base]) continue
    const page = await context.newPage()
    try {
      const url = pathToFileURL(file).href
      await page.route(url, (route) => route.fulfill({ contentType: 'text/html; charset=utf-8', body: pinPage(readFileSync(file, 'utf8')) }))
      await page.goto(url, { waitUntil: 'load' })
      await page.evaluate(() => document.fonts.ready)
      // Walk the page once so lazy images load, then return to the top.
      const height = await page.evaluate(async (screen) => {
        for (let y = 0; y < document.documentElement.scrollHeight; y += screen) {
          scrollTo(0, y)
          await new Promise((r) => setTimeout(r, 60))
        }
        scrollTo(0, 0)
        await Promise.all([...document.images].filter((i) => !i.complete).map((i) => new Promise((r) => { i.onload = i.onerror = r; setTimeout(r, 3000) })))
        return Math.max(document.documentElement.scrollHeight, document.body.scrollHeight)
      }, SCREEN)
      await page.waitForTimeout(400)

      const pieces = []
      if (height <= 16000) {
        pieces.push({ input: await page.screenshot({ fullPage: true, type: 'png' }), top: 0 })
      } else {
        // ponytail: a fixed header repeats once per piece on a page this tall;
        // hide fixed layers after the first piece if one ever shows up.
        await page.setViewportSize({ width: WIDTH, height: PIECE })
        for (let y = 0; y < height; y += PIECE) {
          await page.evaluate((top) => scrollTo(0, top), y)
          await page.waitForTimeout(150)
          const at = await page.evaluate(() => Math.round(scrollY))
          const shot = await page.screenshot({ type: 'png' })
          // The last piece cannot scroll a full piece down; keep only its new rows.
          pieces.push(at === y ? { input: shot, top: y } : { input: await sharp(shot).extract({ left: 0, top: y - at, width: WIDTH, height: PIECE - (y - at) }).toBuffer(), top: y })
        }
      }
      const outHeight = Math.round((height * OUT_WIDTH) / WIDTH)
      const whole = pieces.length === 1 ? sharp(pieces[0].input) : sharp({ create: { width: WIDTH, height, channels: 3, background: '#ffffff' } }).composite(pieces.map((p) => ({ input: p.input, left: 0, top: p.top }))).png()
      mkdirSync(outDir, { recursive: true })
      await sharp(await whole.toBuffer()).resize(OUT_WIDTH, outHeight, { fit: 'fill' }).webp({ quality: 78 }).toFile(out)
      index[v.base] = { file: `${v.base}.webp`, width: OUT_WIDTH, height: outHeight, from: v.from, pageHeight: height }
      console.log(JSON.stringify({ folder, variant: v.base, from: v.from, pageHeight: height, kilobytes: Math.round(statSync(out).size / 1000) }))
    } catch (error) {
      failed++
      console.log(JSON.stringify({ folder, variant: v.base, error: error.message.split('\n')[0] }))
    } finally {
      await page.close()
    }
  }
  if (Object.keys(index).length) {
    mkdirSync(outDir, { recursive: true })
    writeFileSync(indexPath, JSON.stringify(index, null, 2) + '\n')
  }
}
await browser.close()
process.exit(failed ? 1 : 0)
