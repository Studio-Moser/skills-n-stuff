// Put a project's variant snapshots on a Doop canvas: one row per direction
// folder, one viewport-sized frame per variant, frames named
// "<Direction folder> · <X> <Title>". Re-running updates frames by name and
// re-lays the grid, so a direction added later slots into row order instead of
// landing on another row.
//
// Usage: node publish-canvas.mjs --dir <directions dir> --canvas "<canvas name>" [--only <prefix>] [--signup]
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
// A viewport, not the page height: the reviewer scrolls inside the frame, so
// sticky stages and scroll-driven motion behave as they did in the browser. A
// full-height frame flattens a sticky page into panels spread over empty ground.
const FRAME_HEIGHT = 900
const GAP_X = 240
const GAP_Y = 400

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
const full = await api('GET', `/api/canvases/${canvas.id}`)
const existing = new Map((full.frames ?? []).map((f) => [f.name, f]))

const folders = readdirSync(DIRECTIONS)
  .filter((d) => existsSync(resolve(DIRECTIONS, d, 'Snapshots.json')))
  .filter((d) => !only || d.startsWith(only))
  .sort()

let y = 0
let count = 0
for (const d of folders) {
  const manifest = JSON.parse(readFileSync(resolve(DIRECTIONS, d, 'Snapshots.json'), 'utf8'))
  const width = manifest.width ?? 1440
  let x = 0
  for (const v of manifest.variants.filter((m) => m.ok !== false)) {
    const letter = v.id.length === 1 ? v.id.toUpperCase() : v.id
    const name = `${d} · ${letter} ${v.title}`
    const html = readFileSync(resolve(DIRECTIONS, d, v.file), 'utf8')
    const prior = existing.get(name)
    const frame = prior
      ? await api('PATCH', `/api/frames/${prior.id}`, { html, x, y, width, height: FRAME_HEIGHT })
      : await api('POST', `/api/canvases/${canvas.id}/frames`, { name, x, y, width, height: FRAME_HEIGHT, html })
    console.log(JSON.stringify({ name, id: frame.id, updated: !!prior, bytes: html.length }))
    count++
    x += width + GAP_X
  }
  y += FRAME_HEIGHT + GAP_Y
}
console.log(`\n${count} frame(s) on "${canvasName}" (${base}/c/${canvas.id})`)
