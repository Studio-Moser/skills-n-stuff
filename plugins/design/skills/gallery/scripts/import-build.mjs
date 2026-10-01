// Copy a framework build's static export into a direction's Build/ folder,
// keeping only what its variant pages load, so the gallery can serve the real
// pages, with their motion, from the repository.
//
// A static export holds the whole site. This serves the export on a temporary
// local address, opens each variant's page at a desktop and a phone width,
// scrolls it to the end, and keeps the files those visits requested, plus the
// build's code (_next/static, small) whole, since a script loaded only on an
// interaction would otherwise be missed. It also keeps any asset those pages
// and their stylesheets name by path, for a file fetched only on a hover.
//
// Usage: node import-build.mjs --from <export dir> --dir <directions dir> --direction "<NN Name>" [--routes /v/a/,/v/b/]
//
// Routes default to the path of each variant's `source` address in the
// direction's Snapshots.json; each such variant then gets `"build": "v/a/"`
// (`"./"` for a page at the site's root),
// the page the gallery previews. An existing Build/ folder is replaced.
//
// Needs @playwright/test (or playwright) with Chromium, resolvable from the
// current working directory.
import { createServer } from 'node:http'
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, extname, join, relative, resolve, sep } from 'node:path'

const args = process.argv.slice(2)
const flag = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const from = flag('--from') && resolve(flag('--from'))
const dir = flag('--dir') && resolve(flag('--dir'))
const direction = flag('--direction')
if (!from || !dir || !direction || !existsSync(from) || !existsSync(join(dir, direction))) {
  console.error('usage: import-build.mjs --from <export dir> --dir <directions dir> --direction "<NN Name>" [--routes /v/a/,/v/b/]')
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

const manifestPath = join(dir, direction, 'Snapshots.json')
const manifest = existsSync(manifestPath) ? JSON.parse(readFileSync(manifestPath, 'utf8')) : { variants: [] }
const routeOf = (v) => {
  try {
    return /^https?:/.test(v.source ?? '') ? new URL(v.source).pathname : null
  } catch {
    return null
  }
}
const routes = flag('--routes')?.split(',').map((r) => r.trim()).filter(Boolean) ?? [...new Set(manifest.variants.map(routeOf).filter(Boolean))]
if (!routes.length) {
  console.error('import-build: no routes. Pass --routes, or give the variants in Snapshots.json a `source` address.')
  process.exit(2)
}

const MIME = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json', '.txt': 'text/plain', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.avif': 'image/avif', '.gif': 'image/gif', '.ico': 'image/x-icon', '.woff2': 'font/woff2', '.woff': 'font/woff', '.mp4': 'video/mp4', '.webm': 'video/webm' }

// Serve the export at a site root, as it was built to run, and note each file sent.
const used = new Set()
const server = createServer((req, res) => {
  let abs
  try {
    abs = resolve(from, '.' + decodeURIComponent(new URL(req.url, 'http://x').pathname))
  } catch {
    res.writeHead(400).end()
    return
  }
  if (abs !== from && !abs.startsWith(from + sep)) return res.writeHead(403).end()
  if (existsSync(abs) && statSync(abs).isDirectory()) abs = join(abs, 'index.html')
  if (!existsSync(abs)) return res.writeHead(404).end()
  used.add(relative(from, abs))
  res.writeHead(200, { 'content-type': MIME[extname(abs).toLowerCase()] ?? 'application/octet-stream' })
  res.end(readFileSync(abs))
})
await new Promise((done) => server.listen(0, '127.0.0.1', done))
const origin = `http://127.0.0.1:${server.address().port}`

const browser = await chromium.launch()
const missing = []
for (const [width, height] of [[1440, 900], [390, 844]]) {
  const page = await browser.newPage({ viewport: { width, height } })
  page.on('response', (r) => {
    if (r.status() === 404 && r.url().startsWith(origin) && !/_rsc=/.test(r.url())) missing.push(r.url().slice(origin.length))
  })
  for (const route of routes) {
    await page.goto(origin + route, { waitUntil: 'load' })
    await page.waitForTimeout(800)
    // Scroll a screen at a time so lazy images and scroll-driven scenes load.
    for (let y = 0, last = -1; y !== last; ) {
      last = y
      await page.mouse.move(width / 2, height / 2)
      await page.mouse.wheel(0, height)
      await page.waitForTimeout(450)
      y = await page.evaluate(() => Math.round(scrollY))
    }
    await page.waitForTimeout(600)
  }
  await page.close()
}
await browser.close()
server.close()

// The build's code whole; everything else only if a visit asked for it.
const code = join(from, '_next', 'static')
const walk = (d) => readdirSync(d, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(d, e.name)) : [join(d, e.name)]))
if (existsSync(code)) for (const f of walk(code)) used.add(relative(from, f))

// A page can name a file it only fetches on a hover or a state the visits did
// not reach. Keep any asset the kept pages and stylesheets refer to by a
// root-absolute path.
const ASSET = /(?<=["'(=,\s])\/[^"'()\s,?#]+\.(?:svg|png|jpe?g|webp|avif|gif|ico|woff2?|mp4|webm)\b/gi
for (const rel of [...used].filter((f) => /\.(html|css)$/i.test(f))) {
  for (const ref of readFileSync(join(from, rel), 'utf8').match(ASSET) ?? []) {
    let path
    try { path = decodeURIComponent(ref.slice(1)) } catch { continue }
    const abs = resolve(from, path)
    if (abs.startsWith(from + sep) && existsSync(abs) && statSync(abs).isFile()) used.add(path)
  }
}

const out = join(dir, direction, 'Build')
rmSync(out, { recursive: true, force: true })
let bytes = 0
for (const rel of used) {
  mkdirSync(dirname(join(out, rel)), { recursive: true })
  cpSync(join(from, rel), join(out, rel))
  bytes += statSync(join(from, rel)).size
}

let linked = 0
for (const v of manifest.variants) {
  const route = routeOf(v)
  if (route && routes.includes(route)) {
    // A variant at the site's root is "./", so the field is never empty.
    v.build = route.replace(/^\/+/, '') || './'
    linked++
  }
}
if (linked) writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n')

const total = walk(from).reduce((n, f) => n + statSync(f).size, 0)
console.log(JSON.stringify({ direction, routes: routes.length, files: used.size, megabytes: +(bytes / 1e6).toFixed(1), exportMegabytes: +(total / 1e6).toFixed(1), linkedVariants: linked, missing: [...new Set(missing)].slice(0, 10) }))
