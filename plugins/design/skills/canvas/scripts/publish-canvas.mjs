// Put a project's variant snapshots on a Doop canvas: one row per direction
// folder, one full-height frame per variant, frames named
// "<Direction folder> · <X> <Title>". Re-running updates frames by name and
// re-lays the grid, so a direction added later slots into row order instead of
// landing on another row.
//
// Usage: node publish-canvas.mjs --dir <directions dir> --canvas "<canvas name>" [--only <prefix>] [--embed-source] [--invite a@x.com,b@y.com] [--signup]
//
// <directions dir> holds one folder per direction; each folder with a
// Snapshots.json (written by freeze.mjs or by hand) is published. Env:
// DOOP_URL, DOOP_EMAIL, DOOP_PASSWORD. --signup creates the account first;
// the server allows it only for SIGNUP_EMAIL_DOMAINS.
import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const args = process.argv.slice(2)
const flag = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const dir = flag('--dir')
const canvasName = flag('--canvas')
const only = flag('--only')
if (!dir || !canvasName) {
  console.error('usage: publish-canvas.mjs --dir <directions dir> --canvas "<name>" [--only <prefix>] [--signup]')
  process.exit(2)
}
const { DOOP_URL, DOOP_EMAIL, DOOP_PASSWORD } = process.env
if (!DOOP_URL || !DOOP_EMAIL || !DOOP_PASSWORD) {
  console.error('set DOOP_URL, DOOP_EMAIL, DOOP_PASSWORD')
  process.exit(2)
}
const base = DOOP_URL.replace(/\/$/, '')
const DIRECTIONS = resolve(dir)
// Doop frames do not scroll for viewers, so a frame is the full height of its
// page (a plates file already lays every screen out in its settled state);
// the manifest's height is used, with one screen as the fallback.
const DEFAULT_HEIGHT = 900
const GAP_LIVE = 160
const GAP_X = 240
// A direction wraps onto a new line after PER_LINE frames so one long round
// does not stretch the canvas into a strip that Fit cannot show; lines of the
// same direction sit closer together than directions do.
const PER_LINE = Number(flag('--per-line') ?? 8)
const GAP_LINE = 400
const GAP_Y = 1600

let cookie = ''
async function api(method, path, body) {
  const res = await fetch(base + path, {
    method,
    // better-auth rejects a sign-in without an Origin matching BETTER_AUTH_URL.
    headers: { 'content-type': 'application/json', origin: base, ...(cookie ? { cookie } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  const set = res.headers.getSetCookie?.() ?? []
  if (set.length) cookie = set.map((c) => c.split(';')[0]).join('; ')
  if (!res.ok) throw new Error(`${method} ${path} -> ${res.status} ${(await res.text()).slice(0, 200)}`)
  const text = await res.text()
  return text ? JSON.parse(text) : null
}

if (args.includes('--signup')) {
  await api('POST', '/api/auth/sign-up/email', { name: DOOP_EMAIL.split('@')[0], email: DOOP_EMAIL, password: DOOP_PASSWORD })
}
await api('POST', '/api/auth/sign-in/email', { email: DOOP_EMAIL, password: DOOP_PASSWORD })

const canvases = await api('GET', '/api/canvases')
let canvas = canvases.find((c) => c.name === canvasName)
if (!canvas) canvas = await api('POST', '/api/canvases', { name: canvasName })
// The publishing account owns the canvas and canvases are private, so the
// people who review it have to be invited by email (they need a Doop account
// first). Already-invited and owner emails answer 400, which is fine.
for (const email of (flag('--invite') ?? process.env.DOOP_INVITE ?? '').split(',').map((e) => e.trim()).filter(Boolean)) {
  await api('POST', `/api/canvases/${canvas.id}/members`, { email }).catch((e) => {
    if (!/-> 400 /.test(String(e))) console.error(`invite ${email}: ${String(e).slice(0, 160)}`)
  })
}
const full = await api('GET', `/api/canvases/${canvas.id}`)
const existing = new Map((full.frames ?? []).map((f) => [f.name, f]))
// A variant's live page: its own self-contained file (manifest `live`), or,
// with --embed-source, the address it was frozen from when that address is
// durable (a static export of the real build, not a dev server). The embed is
// lazy so a canvas of fifty running pages loads only what is near the viewport.
// The host must send Access-Control-Allow-Origin: a frame is sandboxed, so the
// page inside has an opaque origin and fonts and CSS masks are fetched in CORS
// mode (preview:serve-preview static previews do).
const EMBED_SOURCE = args.includes('--embed-source')
function liveFor(d, v, name) {
  if (v.live && existsSync(resolve(DIRECTIONS, d, v.live))) return readFileSync(resolve(DIRECTIONS, d, v.live), 'utf8')
  const url = v.liveUrl ?? (EMBED_SOURCE && /^https?:/.test(v.source ?? '') ? v.source : null)
  if (!url) return null
  return `<!doctype html><html><head><meta charset="utf-8"><style>html,body{margin:0;height:100%;overflow:hidden;background:#fff}iframe{border:0;width:100%;height:100%;display:block}</style></head><body><iframe src="${url}" title="${name.replace(/"/g, '&quot;')}" loading="lazy"></iframe></body></html>`
}

async function upsert(name, props) {
  const prior = existing.get(name)
  return prior
    ? api('PATCH', `/api/frames/${prior.id}`, props)
    : api('POST', `/api/canvases/${canvas.id}/frames`, { name, ...props })
}

const folders = readdirSync(DIRECTIONS)
  .filter((d) => existsSync(resolve(DIRECTIONS, d, 'Snapshots.json')))
  .filter((d) => !only || d.startsWith(only))
  .sort()

let y = 0
let count = 0
for (const d of folders) {
  const manifest = JSON.parse(readFileSync(resolve(DIRECTIONS, d, 'Snapshots.json'), 'utf8'))
  const width = manifest.width ?? 1440
  const variants = manifest.variants.filter((m) => m.ok !== false)
  // Lines of PER_LINE frames, each line as tall as its tallest frame.
  for (let start = 0; start < variants.length; start += PER_LINE) {
    const line = variants.slice(start, start + PER_LINE)
    const liveBand = line.some((v) => liveFor(d, v, '')) ? DEFAULT_HEIGHT + GAP_LIVE : 0
    let x = 0
    for (const v of line) {
      const letter = v.id.length === 1 ? v.id.toUpperCase() : v.id
      const name = `${d} · ${letter} ${v.title}`
      const html = readFileSync(resolve(DIRECTIONS, d, v.file), 'utf8')
      const height = v.height ?? DEFAULT_HEIGHT
      const frame = await upsert(name, { html, x, y: y + liveBand, width, height })
      console.log(JSON.stringify({ name, id: frame.id, bytes: html.length, height }))
      count++
      // The live page, one screen tall, above its plates: select it and press
      // Present to scroll it with its motion running.
      const live = liveFor(d, v, name)
      if (live) {
        await upsert(`${name} (live)`, { html: live, x, y, width, height: DEFAULT_HEIGHT })
        count++
      }
      x += width + GAP_X
    }
    y += liveBand + Math.max(...line.map((v) => v.height ?? DEFAULT_HEIGHT)) + GAP_LINE
  }
  y += GAP_Y - GAP_LINE
}
console.log(`\n${count} frame(s) on "${canvasName}" (${base}/c/${canvas.id})`)
