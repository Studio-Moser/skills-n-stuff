// Take pictures of each variant, for the gallery to show in place of a live
// page and for a Figma file. A direction of twenty live pages is more than a
// browser tab will hold; pictures are not, and the live page is one click away
// in the preview.
//
// Usage: node frames.mjs --dir <directions dir> [--only <folder prefix>] [--force]
//
// Each variant is pictured one screen at a time, at two sizes:
//   desktop  1440 × 900
//   mobile    360 × 800
// so every image is one full screen of the page, usable alone as a thumbnail
// and stacked as the whole scroll. One screen is also well inside what a Figma
// file accepts (it shrinks an image past 4096px on a side).
//
// Desktop is pictured from the frozen plates when they are at least as new as
// the source page, otherwise from the source page as a reader who asked for
// reduced motion gets it: the build brief requires that to be a normal
// long-scroll page with every scene present. Viewport heights are pinned to
// the screen so a section sized to the viewport does not stretch.
//
// Mobile needs a page that responds to width, which plates do not. A source
// page is pictured the same way as desktop. A variant that is a page in the
// direction's Build/ folder (`build` in Snapshots.json) is opened from there
// with its motion running and pictured a screen at a time as it is scrolled.
// A variant with neither has no mobile pictures.
//
// Output, per variant, in "<direction>/Frames/":
//   <variant>.webp               the whole desktop scroll, 640px wide, for the gallery's grids
//   <variant>/desktop/01.webp …  one screen each
//   <variant>/mobile/01.webp …   one screen each
// and Frames.json, with the sizes and screens and what each was taken from. A
// picture newer than its page is left alone unless --force.
//
// Needs @playwright/test (or playwright) with Chromium, and sharp, resolvable
// from the current working directory.
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { createRequire } from 'node:module'
import { extname, join, resolve, sep } from 'node:path'
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

const DESKTOP = { name: 'desktop', width: 1440, screen: 900 }
const MOBILE = { name: 'mobile', width: 360, screen: 800 }
const GRID_WIDTH = 640
// Chromium paints nothing past 16384 device pixels, so a taller page is
// pictured in pieces and joined.
const PIECE = 8000
// How long a moving page gets to come to rest after each scroll.
const SETTLE_MS = 900

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
  const manifestPath = join(dir, folder, 'Snapshots.json')
  const entries = existsSync(manifestPath) ? (JSON.parse(readFileSync(manifestPath, 'utf8')).variants ?? []) : []
  return [...groups.values()].map((g) => {
    const entry = entries.find((e) => (g.plates && e.file === g.plates) || (g.source && (e.file === g.source || e.live === g.source))) ?? {}
    const build = entry.build && existsSync(join(dir, folder, 'Build', entry.build)) ? String(entry.build).replace(/^\.?\/+/, '') : null
    return { ...g, build, from: g.plates && (!g.source || mtime(g.plates) >= mtime(g.source)) ? g.plates : g.source }
  })
}

// Viewport heights to pixels of the screen, in the page's own styles and never
// inside url(…), where a data URL can contain "3vh" by chance.
const pin = (css, screen) => css.replace(/url\([^)]*\)|(\d*\.?\d+)[dsl]?vh\b/g, (m, n) => (n === undefined ? m : `${+((n * screen) / 100).toFixed(2)}px`))
const pinPage = (html, screen) => html.replace(/(<style[^>]*>)([\s\S]*?)(<\/style>)/gi, (_, open, css, close) => open + pin(css, screen) + close).replace(/\sstyle="[^"]*vh[^"]*"/gi, (m) => pin(m, screen))

// A page that holds still (plates, or a source page under reduced motion):
// one picture of the whole scroll.
async function wholeScroll(context, file, size) {
  const page = await context.newPage()
  try {
    const url = pathToFileURL(file).href
    await page.route(url, (route) => route.fulfill({ contentType: 'text/html; charset=utf-8', body: pinPage(readFileSync(file, 'utf8'), size.screen) }))
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
    }, size.screen)
    await page.waitForTimeout(400)
    if (height <= 16000) return { height, png: await page.screenshot({ fullPage: true, type: 'png' }) }
    // ponytail: a fixed header repeats once per piece on a page this tall;
    // hide fixed layers after the first piece if one ever shows up.
    await page.setViewportSize({ width: size.width, height: PIECE })
    const pieces = []
    for (let y = 0; y < height; y += PIECE) {
      await page.evaluate((top) => scrollTo(0, top), y)
      await page.waitForTimeout(150)
      const at = await page.evaluate(() => Math.round(scrollY))
      const shot = await page.screenshot({ type: 'png' })
      // The last piece cannot scroll a full piece down; keep only its new rows.
      pieces.push(at === y ? { input: shot, left: 0, top: y } : { input: await sharp(shot).extract({ left: 0, top: y - at, width: size.width, height: PIECE - (y - at) }).toBuffer(), left: 0, top: y })
    }
    return { height, png: await sharp({ create: { width: size.width, height, channels: 3, background: '#ffffff' } }).composite(pieces).png().toBuffer() }
  } finally {
    await page.close()
  }
}

// A page that moves (a real build): scroll a screen at a time, let it come to
// rest, and picture what is on the screen.
async function screenByScreen(context, url, size) {
  const page = await context.newPage()
  try {
    await page.goto(url, { waitUntil: 'load' })
    await page.evaluate(() => document.fonts.ready)
    await page.waitForTimeout(SETTLE_MS)
    const screens = []
    for (let y = 0, n = 0; n < 80; y += size.screen, n++) {
      const total = await page.evaluate(() => Math.max(document.documentElement.scrollHeight, document.body.scrollHeight))
      if (y >= total) break
      await page.evaluate((top) => scrollTo({ top, behavior: 'instant' }), y)
      await page.waitForTimeout(n ? SETTLE_MS : 200)
      const at = await page.evaluate(() => Math.round(scrollY))
      const shot = await page.screenshot({ type: 'png' })
      // A page that snaps, or has run out, stops short of the asked position;
      // keep only the rows not already pictured.
      const seen = y - at
      if (seen <= 2) screens.push(shot)
      else if (size.screen - seen > 8) screens.push(await sharp(shot).extract({ left: 0, top: seen, width: size.width, height: size.screen - seen }).toBuffer())
      if (seen > 2) break
    }
    return screens
  } finally {
    await page.close()
  }
}

// Serve a direction's Build/ at a site root, as it was built to run.
const MIME = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json', '.txt': 'text/plain', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff', '.mp4': 'video/mp4', '.webm': 'video/webm' }
async function serveBuild(root) {
  const server = createServer((req, res) => {
    let abs
    try { abs = resolve(root, '.' + decodeURIComponent(new URL(req.url, 'http://x').pathname)) } catch { return res.writeHead(400).end() }
    if (abs !== root && !abs.startsWith(root + sep)) return res.writeHead(403).end()
    if (existsSync(abs) && statSync(abs).isDirectory()) abs = join(abs, 'index.html')
    if (!existsSync(abs)) return res.writeHead(404).end()
    res.writeHead(200, { 'content-type': MIME[extname(abs).toLowerCase()] ?? 'application/octet-stream' })
    res.end(readFileSync(abs))
  })
  await new Promise((done) => server.listen(0, '127.0.0.1', done))
  return { origin: `http://127.0.0.1:${server.address().port}`, close: () => server.close() }
}

// Write one image per screen and describe them.
async function writeScreens(outDir, base, size, screens) {
  const folder = join(outDir, base, size.name)
  rmSync(folder, { recursive: true, force: true })
  mkdirSync(folder, { recursive: true })
  const list = []
  for (const [i, input] of screens.entries()) {
    const name = `${String(i + 1).padStart(2, '0')}.webp`
    const { height } = await sharp(input).webp({ quality: 78 }).toFile(join(folder, name))
    list.push({ file: `${base}/${size.name}/${name}`, height })
  }
  return { width: size.width, screen: size.screen, height: list.reduce((n, s) => n + s.height, 0), screens: list }
}
const cut = async (png, size, height) => {
  const out = []
  for (let y = 0; y < height; y += size.screen) out.push(await sharp(png).extract({ left: 0, top: y, width: size.width, height: Math.min(size.screen, height - y) }).toBuffer())
  return out
}

const folders = readdirSync(dir, { withFileTypes: true })
  .filter((e) => e.isDirectory() && !e.name.startsWith('.') && (!only || e.name.startsWith(only)))
  .map((e) => e.name)
  .sort((a, b) => a.localeCompare(b, undefined, { numeric: true }))

const browser = await chromium.launch()
const still = (size) => browser.newContext({ viewport: { width: size.width, height: size.screen }, deviceScaleFactor: 1, reducedMotion: 'reduce' })
const desktopStill = await still(DESKTOP)
const mobileStill = await still(MOBILE)
const mobileMoving = await browser.newContext({ viewport: { width: MOBILE.width, height: MOBILE.screen }, deviceScaleFactor: 1 })
let failed = 0
for (const folder of folders) {
  const list = variants(folder)
  if (!list.length) continue
  const outDir = join(dir, folder, 'Frames')
  const indexPath = join(outDir, 'Frames.json')
  const index = existsSync(indexPath) ? JSON.parse(readFileSync(indexPath, 'utf8')) : {}
  const buildRoot = join(dir, folder, 'Build')
  const build = list.some((v) => v.build && !v.source) ? await serveBuild(buildRoot) : null
  for (const v of list) {
    const file = join(dir, folder, v.from)
    const out = join(outDir, `${v.base}.webp`)
    if (!force && existsSync(out) && statSync(out).mtimeMs >= statSync(file).mtimeMs && index[v.base]?.desktop) continue
    try {
      mkdirSync(outDir, { recursive: true })
      rmSync(join(outDir, v.base), { recursive: true, force: true })
      const { height, png } = await wholeScroll(desktopStill, file, DESKTOP)
      const gridHeight = Math.round((height * GRID_WIDTH) / DESKTOP.width)
      await sharp(png).resize(GRID_WIDTH, gridHeight, { fit: 'fill' }).webp({ quality: 78 }).toFile(out)
      const desktop = await writeScreens(outDir, v.base, DESKTOP, await cut(png, DESKTOP, height))

      let mobile = null
      let mobileFrom = null
      if (v.source) {
        const m = await wholeScroll(mobileStill, join(dir, folder, v.source), MOBILE)
        mobile = await writeScreens(outDir, v.base, MOBILE, await cut(m.png, MOBILE, m.height))
        mobileFrom = v.source
      } else if (v.build && build) {
        mobile = await writeScreens(outDir, v.base, MOBILE, await screenByScreen(mobileMoving, `${build.origin}/${v.build}`, MOBILE))
        mobileFrom = `Build/${v.build}`
      }
      index[v.base] = { file: `${v.base}.webp`, width: GRID_WIDTH, height: gridHeight, from: v.from, pageHeight: height, desktop, mobile, mobileFrom }
      console.log(JSON.stringify({ folder, variant: v.base, from: v.from, pageHeight: height, desktopScreens: desktop.screens.length, mobileScreens: mobile ? mobile.screens.length : 0 }))
    } catch (error) {
      failed++
      console.log(JSON.stringify({ folder, variant: v.base, error: error.message.split('\n')[0] }))
    }
  }
  build?.close()
  if (Object.keys(index).length) {
    mkdirSync(outDir, { recursive: true })
    writeFileSync(indexPath, JSON.stringify(index, null, 2) + '\n')
  }
}
await browser.close()
process.exit(failed ? 1 : 0)
