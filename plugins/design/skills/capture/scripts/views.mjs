// Screenshot a page view by view, for design critique.
//
// For each width it scrolls to every screen-height stop, lets the page settle,
// and shoots the viewport. At desktop it also records motion: from each rest
// position it sends one wheel gesture, as a reader would, and shoots frames
// while the page moves, joined into one strip per transition. A report lists
// console errors, broken images and horizontal overflow per width.
//
// Usage: node views.mjs <url> <outDir> [--widths 1440,390] [--hide "sel1, sel2"]
//   url      full URL of the page to shoot
//   outDir   created if missing; earlier files are overwritten
//   --widths comma-separated CSS widths; desktop widths (>= 700) record motion
//   --hide   extra selectors to hide (dev overlays); nextjs-portal is always hidden
//
// Needs @playwright/test (or playwright) with Chromium, and sharp, resolvable
// from the current working directory. Run it from the project root.
import { mkdirSync, writeFileSync, existsSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { createRequire } from 'node:module'

const args = process.argv.slice(2)
const positional = args.filter((a, i) => !a.startsWith('--') && !(i > 0 && args[i - 1].startsWith('--')))
const [url, outArg] = positional
if (!url || !outArg) {
  console.error('Usage: node views.mjs <url> <outDir> [--widths 1440,390] [--hide "sel1, sel2"]')
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

const out = resolve(outArg)
mkdirSync(out, { recursive: true })

const HEIGHTS = { 1440: 900, 390: 844, 1280: 800, 768: 1024, 375: 812 }
const WIDTHS = (flag('--widths') ?? '1440,390').split(',').map((s) => {
  const width = Number(s.trim())
  return { name: String(width), width, height: HEIGHTS[width] ?? Math.round(width * 0.625), motion: width >= 700 }
})
const HIDE_CSS = ['nextjs-portal', ...(flag('--hide') ?? '').split(',').map((s) => s.trim()).filter(Boolean)]
  .map((sel) => `${sel} { display: none !important; }`)
  .join('\n')
// Frame times after the wheel gesture, in ms: mid-gesture to settled.
const FRAMES = [80, 200, 350, 550, 900, 1400]
const pad = (n) => String(n).padStart(2, '0')

const browser = await chromium.launch()
const report = { url, widths: {} }
try {
  for (const w of WIDTHS) {
    const page = await browser.newPage({
      viewport: { width: w.width, height: w.height },
      deviceScaleFactor: 1,
      ...(w.width < 700 ? { isMobile: true, hasTouch: true } : {}),
    })
    const errors = []
    page.on('console', (m) => m.type() === 'error' && errors.push(m.text()))
    page.on('pageerror', (e) => errors.push(String(e)))
    await page.goto(url, { waitUntil: 'networkidle', timeout: 180000 })
    await page.addStyleTag({ content: HIDE_CSS })
    await page.waitForTimeout(2500)
    // Walk the page once so lazy images load, then return to the top.
    const total = await page.evaluate(() => document.documentElement.scrollHeight)
    const stops = Math.max(1, Math.ceil(total / w.height - 0.05))
    for (let i = 0; i < stops; i++) {
      await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), i * w.height)
      await page.waitForTimeout(250)
    }
    await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }))
    await page.waitForTimeout(1500)

    for (let i = 0; i < stops; i++) {
      await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), i * w.height)
      await page.waitForTimeout(1600)
      await page.screenshot({ path: resolve(out, `${w.name}-${pad(i + 1)}.png`) })
    }

    if (w.motion) {
      for (let i = 0; i < stops - 1; i++) {
        await page.evaluate((y) => window.scrollTo({ top: y, behavior: 'instant' }), i * w.height)
        await page.waitForTimeout(1600)
        await page.mouse.move(w.width / 2, w.height / 2)
        const t0 = Date.now()
        await page.mouse.wheel(0, Math.round(w.height * 0.6))
        const frames = []
        for (const t of FRAMES) {
          const wait = t - (Date.now() - t0)
          if (wait > 0) await page.waitForTimeout(wait)
          frames.push(await page.screenshot())
        }
        const thumbW = 480
        const thumbH = Math.round((thumbW * w.height) / w.width)
        const tiles = await Promise.all(frames.map((f) => sharp(f).resize(thumbW, thumbH).png().toBuffer()))
        await sharp({
          create: { width: thumbW * 3 + 8 * 2, height: thumbH * 2 + 8, channels: 3, background: '#111' },
        })
          .composite(
            tiles.map((input, k) => ({
              input,
              left: (k % 3) * (thumbW + 8),
              top: Math.floor(k / 3) * (thumbH + 8),
            }))
          )
          .png()
          .toFile(resolve(out, `motion-${w.name}-${pad(i + 1)}-to-${pad(i + 2)}.png`))
      }
    }

    const health = await page.evaluate(() => ({
      scrollWidth: document.documentElement.scrollWidth,
      innerWidth: window.innerWidth,
      scrollHeight: document.documentElement.scrollHeight,
      brokenImages: [...document.images]
        .filter((img) => img.complete && img.naturalWidth === 0)
        .map((img) => img.currentSrc || img.src),
    }))
    report.widths[w.name] = { stops, ...health, consoleErrors: errors }
    await page.close()
  }
} finally {
  await browser.close()
}
writeFileSync(resolve(out, 'report.json'), JSON.stringify(report, null, 2))
console.log(JSON.stringify(report, null, 2))
const unhealthy = Object.values(report.widths).some(
  (w) => w.scrollWidth > w.innerWidth || w.brokenImages.length || w.consoleErrors.length
)
if (unhealthy) process.exitCode = 1
