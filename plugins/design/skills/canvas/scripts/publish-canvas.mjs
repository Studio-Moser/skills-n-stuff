// Put a project's variant snapshots on Doop: one full-height frame per variant
// named "<Direction folder> · <X> <Title>", with a one-screen "(live)" frame
// above it when the variant has a live page. Re-running updates frames by name
// and re-lays the grid.
//
// Usage: node publish-canvas.mjs --dir <directions dir> --canvas "<name>"
//          [--per-direction] [--only <prefix>] [--embed-source] [--prune]
//          [--assets-dir <dir> --assets-url <url>] [--per-line N]
//          [--invite a@x.com,b@y.com] [--signup]
//
// --per-direction publishes each direction to its own canvas,
// "<name> · <Direction folder>" (and one more per extra round in a folder,
// "… · <round>"). A browser holds every frame of a canvas in memory at once,
// and a whole exploration on one canvas (a hundred frames) makes the tab
// reload until it gives up; a direction is a size it can hold. Without the
// flag everything goes on the one canvas named <name>.
//
// <directions dir> holds one folder per direction; each folder with a
// Snapshots.json (written by freeze.mjs or by hand) is published. Env:
// DOOP_URL, DOOP_EMAIL, DOOP_PASSWORD. --signup creates the account first;
// the server allows it only for SIGNUP_EMAIL_DOMAINS.
import { createHash } from 'node:crypto'
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
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
  console.error('usage: publish-canvas.mjs --dir <directions dir> --canvas "<name>" [--per-direction] [--only <prefix>] [--signup]')
  process.exit(2)
}
const { DOOP_URL, DOOP_EMAIL, DOOP_PASSWORD } = process.env
if (!DOOP_URL || !DOOP_EMAIL || !DOOP_PASSWORD) {
  console.error('set DOOP_URL, DOOP_EMAIL, DOOP_PASSWORD')
  process.exit(2)
}
const base = DOOP_URL.replace(/\/$/, '')
const DIRECTIONS = resolve(dir)
const PER_DIRECTION = args.includes('--per-direction')
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

// With --assets-dir and --assets-url, inlined fonts and images are written
// once to a directory a static host serves and the frame references them by
// URL, so the canvas carries text and structure instead of megabytes of
// base64 per frame (the same font or photo is shared by every variant that
// uses it). The files on disk stay self-contained. The host must send
// Access-Control-Allow-Origin: fonts are fetched in CORS mode from a frame.
const ASSETS_DIR = flag('--assets-dir')
const ASSETS_URL = (flag('--assets-url') ?? '').replace(/\/$/, '')
const EXT = { 'font/woff2': 'woff2', 'font/woff': 'woff', 'image/webp': 'webp', 'image/jpeg': 'jpg', 'image/png': 'png', 'image/svg+xml': 'svg', 'image/gif': 'gif', 'image/avif': 'avif' }
if (ASSETS_DIR) mkdirSync(ASSETS_DIR, { recursive: true })
function hosted(html) {
  if (!ASSETS_DIR || !ASSETS_URL) return html
  return html.replace(/url\((["']?)data:([a-z0-9.+/-]+);base64,([A-Za-z0-9+/=]+)\1\)/g, (whole, _q, mime, b64) => {
    if (b64.length < 3000 || !EXT[mime]) return whole // tiny or unknown: cheaper inline
    const name = `${createHash('sha1').update(b64).digest('hex').slice(0, 20)}.${EXT[mime]}`
    const file = resolve(ASSETS_DIR, name)
    if (!existsSync(file)) writeFileSync(file, Buffer.from(b64, 'base64'))
    return `url(${ASSETS_URL}/${name})`
  })
}

// A variant's live page: its own self-contained file (manifest `live`), or,
// with --embed-source, the address it was frozen from when that address is
// durable (a static export of the real build, not a dev server). The host
// must send Access-Control-Allow-Origin: a frame is sandboxed, so the page
// inside has an opaque origin and fonts and CSS masks are fetched in CORS mode
// (preview:serve-preview static previews do).
//
// An embedded build does not load until the pointer, a key, or the wheel
// reaches the frame, which only happens when it is presented: on the canvas a
// frame is a design object and never receives input. Twenty running pages on
// one canvas is the difference between a tab that works and one that dies.
const EMBED_SOURCE = args.includes('--embed-source')
function liveFor(d, v, name) {
  if (v.live && existsSync(resolve(DIRECTIONS, d, v.live))) return readFileSync(resolve(DIRECTIONS, d, v.live), 'utf8')
  const raw = v.liveUrl ?? (EMBED_SOURCE && /^https?:/.test(v.source ?? '') ? v.source : null)
  if (!raw) return null
  // A directory-style export redirects "/v/k" to "http://…/v/k/" behind a TLS
  // proxy, which the frame blocks as mixed content; ask for the directory.
  const url = /\/[^/.]*$/.test(new URL(raw).pathname) && !raw.endsWith('/') ? `${raw}/` : raw
  const label = name.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;')
  return `<!doctype html><html><head><meta charset="utf-8"><style>
html,body{margin:0;height:100%;overflow:hidden;background:#15181a;color:#f3efe6;font:500 30px/1.3 system-ui,-apple-system,sans-serif}
#poster{position:absolute;inset:0;display:grid;place-items:center;text-align:center}
#poster small{display:block;margin-top:14px;font-size:17px;font-weight:400;opacity:.6}
iframe{border:0;width:100%;height:100%;display:none}
</style></head><body>
<div id="poster"><div>&#9654; Present this frame to play the live build<small>${label}</small></div></div>
<iframe title="${label}"></iframe>
<script>(function(){var f=document.querySelector('iframe'),started=false;
function start(){if(started)return;started=true;f.src=${JSON.stringify(url)};f.style.display='block';document.getElementById('poster').remove()}
['pointermove','pointerdown','keydown','wheel','touchstart'].forEach(function(e){addEventListener(e,start,{passive:true})})})()</script>
</body></html>`
}

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

const folders = readdirSync(DIRECTIONS)
  .filter((d) => existsSync(resolve(DIRECTIONS, d, 'Snapshots.json')))
  .filter((d) => !only || d.startsWith(only))
  .sort()

// What goes on which canvas: [{ canvas, blocks: [{ folder, width, variants }] }].
const plan = []
for (const d of folders) {
  const manifest = JSON.parse(readFileSync(resolve(DIRECTIONS, d, 'Snapshots.json'), 'utf8'))
  const width = manifest.width ?? 1440
  const variants = manifest.variants.filter((m) => m.ok !== false)
  if (!PER_DIRECTION) {
    if (!plan.length) plan.push({ canvas: canvasName, blocks: [] })
    plan[0].blocks.push({ folder: d, width, variants })
    continue
  }
  // One canvas per round of a direction. The first round takes the folder's
  // name; a later round adds what its key adds ("09-color-block-models" after
  // "09-color-block" is "models").
  const rounds = [...new Set(variants.map((v) => v.round ?? d))]
  for (const round of rounds) {
    const extra = round === rounds[0] ? '' : round.replace(rounds[0], '').replace(/^[-_ ]+/, '') || round
    plan.push({
      canvas: `${canvasName} · ${d}${extra ? ` · ${extra}` : ''}`,
      blocks: [{ folder: d, width, variants: variants.filter((v) => (v.round ?? d) === round) }],
    })
  }
}

const canvases = await api('GET', '/api/canvases')
const invitees = (flag('--invite') ?? process.env.DOOP_INVITE ?? '').split(',').map((e) => e.trim()).filter(Boolean)
let total = 0
for (const { canvas: name, blocks } of plan) {
  let canvas = canvases.find((c) => c.name === name)
  if (!canvas) canvas = await api('POST', '/api/canvases', { name })
  // Canvases are private to whoever created them, so reviewers are invited by
  // email (they need a Doop account first). Only the owner may invite; an
  // already-invited email answers 400 and a non-owner 403, neither of which
  // should stop a publish.
  for (const email of invitees) {
    await api('POST', `/api/canvases/${canvas.id}/members`, { email }).catch((e) => {
      if (!/-> 40[03] /.test(String(e))) console.error(`invite ${email}: ${String(e).slice(0, 160)}`)
    })
  }
  const full = await api('GET', `/api/canvases/${canvas.id}`)
  const existing = new Map((full.frames ?? []).map((f) => [f.name, f]))
  const published = new Set()
  const upsert = (frameName, props) => {
    published.add(frameName)
    const prior = existing.get(frameName)
    return prior
      ? api('PATCH', `/api/frames/${prior.id}`, props)
      : api('POST', `/api/canvases/${canvas.id}/frames`, { name: frameName, ...props })
  }

  let y = 0
  let count = 0
  for (const { folder: d, width, variants } of blocks) {
    // Lines of PER_LINE frames, each line as tall as its tallest frame.
    for (let start = 0; start < variants.length; start += PER_LINE) {
      const line = variants.slice(start, start + PER_LINE)
      const liveBand = line.some((v) => liveFor(d, v, '')) ? DEFAULT_HEIGHT + GAP_LIVE : 0
      let x = 0
      for (const v of line) {
        const letter = v.id.length === 1 ? v.id.toUpperCase() : v.id
        const frameName = `${d} · ${letter} ${v.title}`
        const html = hosted(readFileSync(resolve(DIRECTIONS, d, v.file), 'utf8'))
        const height = v.height ?? DEFAULT_HEIGHT
        await upsert(frameName, { html, x, y: y + liveBand, width, height })
        count++
        // The live page, one screen tall, above its plates: select it and
        // press Present to scroll it with its motion running.
        const live = liveFor(d, v, frameName)
        if (live) {
          await upsert(`${frameName} (live)`, { html: live, x, y, width, height: DEFAULT_HEIGHT })
          count++
        }
        x += width + GAP_X
      }
      y += liveBand + Math.max(...line.map((v) => v.height ?? DEFAULT_HEIGHT)) + GAP_LINE
    }
    y += GAP_Y - GAP_LINE
  }
  // --prune removes frames the manifests no longer describe (a renamed
  // variant, a dropped one, a frame from an older layout). Only with a full
  // publish: with --only everything outside that prefix would look stale.
  if (args.includes('--prune') && !only) {
    for (const [frameName, frame] of existing) {
      if (published.has(frameName)) continue
      await api('DELETE', `/api/frames/${frame.id}`)
      console.log(JSON.stringify({ pruned: frameName, canvas: name }))
    }
  }
  total += count
  console.log(JSON.stringify({ canvas: name, id: canvas.id, frames: count, url: `${base}/c/${canvas.id}` }))
}
console.log(`\n${total} frame(s) on ${plan.length} canvas(es)`)
