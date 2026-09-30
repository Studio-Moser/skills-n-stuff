// Freeze running pages into one self-contained HTML file per variant, stored
// beside the direction's brief and indexed by a Snapshots.json per direction.
//
// This is how a variant built in a framework (a Next.js route on a branch, a
// dev server) becomes a portable artifact any canvas can hold. Each file is
// what the page rendered at the capture width after a full scroll, captured
// under forced reduced motion so every JS-revealed section is in its visible,
// settled state, with CSS, fonts and images inlined by single-file and every
// <script> removed afterwards. CSS-driven motion survives; JS-driven motion
// does not, and the spec beside the file describes it.
//
// Usage: node freeze.mjs <targets.json> --dir <directions dir> [--only <direction key>]
//
// targets.json is the capture.mjs shape (directions[].variants[] with id, url,
// optional label, optional reducedMotion:false). Each direction needs a
// `folder` (name under --dir) or a key whose first segment matches a folder's
// leading token ("03-drawn" -> "03 Drawn"). A variant's title comes from a spec
// beside it named "Homepage <X> - <Title>.md" when one exists, else from label.
//
// Needs Node 23+ (single-file's browser bridge uses the global CloseEvent),
// Google Chrome or a Playwright Chromium, and @playwright/test (or playwright)
// resolvable from the current working directory, used to measure the result.
import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

if (Number(process.versions.node.split('.')[0]) < 23) {
  console.error(`node ${process.versions.node}: run this with Node 23 or newer`)
  process.exit(2)
}
const args = process.argv.slice(2)
const targetsPath = args.find((a) => !a.startsWith('--') && a.endsWith('.json'))
const flag = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const dir = flag('--dir')
if (!targetsPath || !dir) {
  console.error('usage: freeze.mjs <targets.json> --dir <directions dir> [--only <direction key>]')
  process.exit(2)
}
const only = flag('--only')
const cfg = JSON.parse(readFileSync(targetsPath, 'utf8'))
const DIRECTIONS = resolve(dir)
const WIDTH = cfg.captureWidth ?? 1440
const HIDE = (cfg.hideSelectors ?? ['nextjs-portal']).concat('[data-preview-chrome]').join(',')

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

function browserPath() {
  if (process.env.FREEZE_BROWSER) return process.env.FREEZE_BROWSER
  const chrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  return existsSync(chrome) ? chrome : chromium.executablePath()
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

function titleFor(folder, id, label) {
  const letter = id.length === 1 ? id.toUpperCase() : null
  if (letter) {
    const spec = readdirSync(folder).find((f) => f.startsWith(`Homepage ${letter} - `) && f.endsWith('.md'))
    if (spec) return spec.slice(`Homepage ${letter} - `.length, -3)
  }
  return (label ?? id)
    .replace(/^[A-Za-z],\s*/, '')
    .replace(/[^A-Za-z0-9 ().-]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

const fileNameFor = (id, title) => `Homepage ${id.length === 1 ? id.toUpperCase() : id} - ${title}.html`

function freeze(url, out, reducedMotion) {
  execFileSync(
    'npx',
    [
      '-y',
      'single-file-cli',
      url,
      out,
      '--browser-executable-path',
      browserPath(),
      ...(reducedMotion ? ['--browser-args', '["--force-prefers-reduced-motion"]'] : []),
      '--browser-width',
      String(WIDTH),
      '--browser-height',
      '900',
      '--browser-wait-until',
      'networkIdle',
      '--browser-wait-delay',
      '2500',
      // Let the page hydrate and reveal while single-file scrolls; the scripts
      // are stripped afterwards so the saved DOM is the revealed state.
      '--block-scripts',
      'false',
      '--load-deferred-images-dispatch-scroll-event',
      'true',
      // State-dependent rules and elements hidden until scrolled must survive.
      '--remove-hidden-elements',
      'false',
      '--remove-unused-styles',
      'false',
      '--removed-elements-selector',
      HIDE,
      '--compress-HTML',
      'false',
    ],
    { stdio: ['ignore', 'ignore', 'inherit'], timeout: 240000 }
  )
}

const stripScripts = (html) =>
  html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '')
    .replace(/<link\b[^>]*rel=["']?(preload|modulepreload|prefetch)["']?[^>]*>/gi, '')

async function measure(file) {
  const browser = await chromium.launch()
  const page = await browser.newPage({ viewport: { width: WIDTH, height: 900 } })
  const errors = []
  page.on('pageerror', (e) => errors.push(String(e)))
  await page.goto(pathToFileURL(file).href, { waitUntil: 'load' })
  await page.waitForTimeout(500)
  const stats = await page.evaluate(() => ({
    height: Math.max(document.body.scrollHeight, document.documentElement.scrollHeight),
    overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    imgs: document.images.length,
    broken: [...document.images].filter((i) => i.complete && i.naturalWidth === 0).length,
  }))
  await browser.close()
  return { ...stats, errors: errors.length }
}

const results = []
for (const d of cfg.directions) {
  if (only && d.key !== only) continue
  const folder = folderFor(d)
  const manifestPath = resolve(folder, 'Snapshots.json')
  const manifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : { variants: [] }
  for (const v of d.variants) {
    const title = titleFor(folder, v.id, v.label)
    const file = resolve(folder, fileNameFor(v.id, title))
    const reducedMotion = v.reducedMotion !== false
    const entry = {
      id: v.id,
      title,
      file: fileNameFor(v.id, title),
      label: v.label ?? null,
      source: v.url,
      round: d.key,
      reducedMotion,
      capturedAt: new Date().toISOString(),
    }
    try {
      freeze(v.url, file, reducedMotion)
      writeFileSync(file, stripScripts(readFileSync(file, 'utf8')))
      Object.assign(entry, await measure(file), { bytes: statSync(file).size, ok: true })
    } catch (e) {
      Object.assign(entry, { ok: false, err: String(e).slice(0, 200) })
    }
    manifest.variants = manifest.variants.filter((m) => m.id !== v.id).concat(entry)
    results.push(entry)
    console.log(JSON.stringify(entry))
  }
  manifest.variants.sort((a, b) => a.id.localeCompare(b.id))
  manifest.width = WIDTH
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n')
}

const bad = results.filter((r) => !r.ok || r.broken > 0 || r.overflow > 0)
if (bad.length) {
  console.error(`\n${bad.length} snapshot(s) need attention`)
  process.exitCode = 1
}
