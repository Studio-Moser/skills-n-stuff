#!/usr/bin/env node
// A local gallery for a project's design directions. No build step and no
// dependencies: every page is rendered from the files on disk at request time,
// so it is always current.
//
//   /                       a grid of directions
//   /direction/<folder>     one direction: its brief, references, design
//                           system, and a grid of its variants
//   /doc/<path>.md          any markdown file in the project, rendered
//   /edit/<path>.html       start impeccable live for a variant, then open it
//   /build/<folder>/…       a direction's static framework build, from Build/
//   /<directions dir>/…     the files themselves, at their repo-relative path
//
// Variants are served at their repo-relative path on purpose: a live-editing
// helper that injects a script into the file (impeccable live) maps the page
// URL back to the source file, and that mapping holds when the URL mirrors the
// path.
//
// A grid shows pictures, not live pages: frames.mjs writes one picture of each
// variant's whole scroll into the direction's Frames/ folder. A variant with
// no picture yet gets a short live thumbnail through /thumb/…, which strips
// the live-editing script so a thumbnail does not open a live session.
//
// Usage: node gallery.mjs [--dir "docs/Design Directions"] [--port 4600]
//                         [--host 127.0.0.1] [--project "<name>"]
//                         [--impeccable <path to the impeccable script>]
// Run it from the project root. It serves files under --dir and markdown under
// the project root. The one thing it changes on disk is /edit: it writes a
// direction's live-editing config when there is none and runs `impeccable
// live`, which adds its script to that direction's pages. Bind another --host
// only on a private network.
import { createServer } from 'node:http'
import { spawnSync } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, openSync, readSync, closeSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, dirname, extname, join, relative, resolve, sep } from 'node:path'

const args = process.argv.slice(2)
const flag = (name, fallback) => {
  const i = args.indexOf(name)
  return i >= 0 && args[i + 1] ? args[i + 1] : fallback
}
const ROOT = resolve(process.cwd())
const DIR = resolve(ROOT, flag('--dir', 'docs/Design Directions'))
const PORT = Number(flag('--port', 4600))
const HOST = flag('--host', '127.0.0.1')
const PROJECT = flag('--project', basename(ROOT))
const DIR_REL = relative(ROOT, DIR).split(sep).join('/')
if (!existsSync(DIR)) {
  console.error(`gallery: ${DIR} does not exist. Run from the project root, or pass --dir.`)
  process.exit(2)
}

const TABLER = '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@tabler/core@1.5.1/dist/css/tabler.min.css" integrity="sha384-tLWyEXulonaekaXL6+fCZQJv/MujuGIpVTBzuVEpwSqFDEfLkPA/PAYGTSBBJO2X" crossorigin="anonymous">'
const MIME = {
  '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8', '.md': 'text/markdown; charset=utf-8',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp', '.gif': 'image/gif',
  '.svg': 'image/svg+xml', '.avif': 'image/avif', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.mp4': 'video/mp4', '.webm': 'video/webm', '.pdf': 'application/pdf', '.txt': 'text/plain; charset=utf-8',
}
const IMAGE = /\.(png|jpe?g|webp|gif|svg|avif)$/i

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])
const urlPath = (...parts) => '/' + parts.flatMap((p) => String(p).split('/')).filter(Boolean).map(encodeURIComponent).join('/')
const fileUrl = (abs) => urlPath(relative(ROOT, abs).split(sep).join('/'))
const read = (p) => (existsSync(p) ? readFileSync(p, 'utf8') : null)
const inside = (parent, child) => child === parent || child.startsWith(parent + sep)
const list = (p) => (existsSync(p) ? readdirSync(p, { withFileTypes: true }).filter((e) => !e.name.startsWith('.')) : [])
const byName = (a, b) => a.name.localeCompare(b.name, undefined, { numeric: true })

// ---- markdown ---------------------------------------------------------------
// Enough of markdown for briefs: headings, paragraphs, nested lists, tables,
// fenced code, quotes, rules, and inline code, emphasis, links and images.
// `base` is the URL of the folder the file lives in, for relative links.
function inline(text, base) {
  const held = []
  const hold = (html) => `\u0000${held.push(html) - 1}\u0000`
  const href = (u) => {
    if (/^(https?:|mailto:|#|\/)/.test(u)) return u
    const [path, hash] = u.split('#')
    const target = base + '/' + path.split('/').map((s) => { try { return encodeURIComponent(decodeURIComponent(s)) } catch { return encodeURIComponent(s) } }).join('/')
    return (/\.md$/i.test(path) ? '/doc' : '') + target + (hash ? '#' + hash : '')
  }
  let s = text.replace(/`([^`]+)`/g, (_, c) => hold(`<code>${esc(c)}</code>`))
  s = esc(s)
  s = s.replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, (_, alt, u) => hold(`<img src="${esc(href(u))}" alt="${alt}" loading="lazy">`))
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, t, u) => hold(`<a href="${esc(href(u.replace(/&amp;/g, '&')))}">${t}</a>`))
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>').replace(/(^|[\s(])\*([^*\s][^*]*)\*/g, '$1<em>$2</em>')
  s = s.replace(/(^|[\s(])(https?:\/\/[^\s<)]+)/g, (_, pre, u) => `${pre}<a href="${u}">${u}</a>`)
  return s.replace(/\u0000(\d+)\u0000/g, (_, i) => held[i])
}

function markdown(src, base, { shift = 0 } = {}) {
  const lines = src.replace(/\r/g, '').split('\n')
  const out = []
  const cells = (l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim())
  let i = 0
  while (i < lines.length) {
    const l = lines[i]
    if (!l.trim()) { i++; continue }
    if (/^```/.test(l)) {
      const code = []
      for (i++; i < lines.length && !/^```/.test(lines[i]); i++) code.push(lines[i])
      i++
      out.push(`<pre><code>${esc(code.join('\n'))}</code></pre>`)
      continue
    }
    const h = l.match(/^(#{1,6})\s+(.*)$/)
    if (h) {
      const level = Math.min(6, h[1].length + shift)
      const id = h[2].toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
      out.push(`<h${level} id="${id}">${inline(h[2], base)}</h${level}>`)
      i++
      continue
    }
    if (/^(-{3,}|\*{3,})\s*$/.test(l)) { out.push('<hr>'); i++; continue }
    if (/^\s*\|/.test(l) && /^\s*\|?\s*:?-{2,}/.test(lines[i + 1] ?? '')) {
      const head = cells(l)
      const rows = []
      for (i += 2; i < lines.length && /^\s*\|/.test(lines[i]); i++) rows.push(cells(lines[i]))
      out.push(`<div class="table-responsive"><table class="table table-vcenter"><thead><tr>${head.map((c) => `<th>${inline(c, base)}</th>`).join('')}</tr></thead><tbody>${rows.map((r) => `<tr>${r.map((c) => `<td>${inline(c, base)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`)
      continue
    }
    if (/^>\s?/.test(l)) {
      const quote = []
      for (; i < lines.length && /^>\s?/.test(lines[i]); i++) quote.push(lines[i].replace(/^>\s?/, ''))
      out.push(`<blockquote>${markdown(quote.join('\n'), base, { shift })}</blockquote>`)
      continue
    }
    const item = /^(\s*)([-*+]|\d+\.)\s+(.*)$/
    if (item.test(l)) {
      // Nested lists by indentation; continuation lines join their item.
      const stack = []
      let html = ''
      const close = (to) => { while (stack.length > to) html += `</li></${stack.pop().tag}>` }
      for (; i < lines.length; i++) {
        const m = lines[i].match(item)
        if (!m) {
          if (lines[i].trim() && /^\s+/.test(lines[i]) && stack.length) { html += ' ' + inline(lines[i].trim(), base); continue }
          break
        }
        const indent = m[1].length
        const tag = /\d/.test(m[2]) ? 'ol' : 'ul'
        while (stack.length && indent < stack[stack.length - 1].indent) close(stack.length - 1)
        if (!stack.length || indent > stack[stack.length - 1].indent) { stack.push({ indent, tag }); html += `<${tag}><li>` }
        else html += '</li><li>'
        html += inline(m[3].replace(/^\[( |x)\]\s+/i, (_, c) => (c === ' ' ? '☐ ' : '☑ ')), base)
      }
      close(0)
      out.push(html)
      continue
    }
    const para = []
    for (; i < lines.length && lines[i].trim() && !/^(#{1,6}\s|```|>\s?|\s*\||(-{3,}|\*{3,})\s*$)/.test(lines[i]) && !item.test(lines[i]); i++) para.push(lines[i].trim())
    // A header block of "Key: value" lines reads better one per line.
    out.push(`<p>${para.map((p) => inline(p, base)).join(para.every((p) => /^\*{0,2}[A-Z][\w ]{1,24}:/.test(p)) ? '<br>' : ' ')}</p>`)
  }
  return out.join('\n')
}

// ---- reading a direction ------------------------------------------------------
const VARIANT = /^(.*?\b([A-Za-z0-9]{1,12}) - (.+?))(\.plates)?\.html$/

// Has a live-editing helper injected its script? It sits just before </body>.
function isLive(file) {
  try {
    const size = statSync(file).size
    const fd = openSync(file, 'r')
    const buf = Buffer.alloc(Math.min(4096, size))
    readSync(fd, buf, 0, buf.length, size - buf.length)
    closeSync(fd)
    return /\/live\.js\?token=/.test(buf.toString('utf8'))
  } catch { return false }
}

function readDirection(folder) {
  const dir = join(DIR, folder)
  const brief = read(join(dir, 'Brief.md'))
  const manifest = (() => { try { return JSON.parse(read(join(dir, 'Snapshots.json')) ?? '{}') } catch { return {} } })()
  const entries = Array.isArray(manifest.variants) ? manifest.variants : []
  const number = (folder.match(/^(\d+)\s+/) ?? [])[1] ?? ''
  const name = folder.replace(/^\d+\s+/, '')

  // Header lines between the title and the first section: "Status: …".
  const meta = {}
  let premise = manifest.premise ?? ''
  if (brief) {
    const head = brief.split(/^## /m)[0]
    for (const m of head.matchAll(/^\**([A-Z][\w ]{1,24})\**:\**\s*(.+)$/gm)) meta[m[1].trim()] = m[2].trim()
    const section = brief.split(/^## +Premise.*$/m)[1]
    if (!premise && section) premise = section.split(/^## /m)[0].trim().split(/\n\s*\n/)[0].replace(/\s+/g, ' ')
  }

  // Variants: a source page, its frozen plates, or both, grouped by name.
  const groups = new Map()
  for (const e of list(dir)) {
    if (!e.isFile() || /^Cover\b/i.test(e.name)) continue
    const m = e.name.match(VARIANT)
    if (!m) continue
    const g = groups.get(m[1]) ?? { base: m[1], letter: m[2], title: m[3] }
    g[m[4] ? 'plates' : 'source'] = e.name
    groups.set(m[1], g)
  }
  // Pictures of each variant's whole scroll, from frames.mjs.
  const frames = (() => { try { return JSON.parse(read(join(dir, 'Frames', 'Frames.json')) ?? '{}') } catch { return {} } })()
  const variants = [...groups.values()].map((g) => {
    const entry = entries.find((v) => (g.plates && v.file === g.plates) || (g.source && (v.file === g.source || v.live === g.source))) ?? {}
    const show = g.source ?? g.plates
    // What the variant's picture is taken from: frozen plates when they are at
    // least as new as the source page (frames.mjs applies the same rule).
    const newer = (a, b) => statSync(join(dir, a)).mtimeMs >= statSync(join(dir, b)).mtimeMs
    const long = g.plates && (!g.source || newer(g.plates, g.source)) ? g.plates : g.source
    return {
      ...g,
      show,
      // The picture, when there is one, and whether the page changed since.
      frame: (() => {
        const f = frames[g.base]
        const abs = f && join(dir, 'Frames', f.file)
        return f && existsSync(abs) ? { ...f, abs, stale: statSync(abs).mtimeMs < statSync(join(dir, long)).mtimeMs } : null
      })(),
      label: entry.label ?? '',
      // `build` in the manifest is the variant's page inside the direction's
      // Build/ folder ("v/a/"); `hosted` is where the same build runs elsewhere.
      build: entry.build && existsSync(join(dir, 'Build', entry.build)) ? String(entry.build).replace(/^\/+/, '') : '',
      hosted: entry.liveUrl ?? (/^https?:/.test(entry.source ?? '') ? entry.source : ''),
      captured: entry.capturedAt ?? '',
      note: existsSync(join(dir, g.base + '.md')) ? g.base + '.md' : '',
      live: g.source ? isLive(join(dir, g.source)) : false,
      order: entries.indexOf(entry),
    }
  }).sort((a, b) => (a.order < 0 || b.order < 0 ? 0 : a.order - b.order) || a.base.localeCompare(b.base, undefined, { numeric: true }))

  // References: images and captured sites saved beside the brief.
  const refDir = join(dir, 'References')
  const references = list(refDir).sort(byName).flatMap((e) => {
    if (e.isFile() && IMAGE.test(e.name)) return [{ name: e.name.replace(/\.[^.]+$/, ''), kind: 'image', thumb: join(refDir, e.name), images: [join(refDir, e.name)] }]
    if (e.isFile()) return e.name === 'References.md' ? [] : [{ name: e.name, kind: 'file', file: join(refDir, e.name), images: [] }]
    if (!e.isDirectory()) return []
    const images = list(join(refDir, e.name)).filter((f) => f.isFile() && IMAGE.test(f.name)).sort(byName).map((f) => join(refDir, e.name, f.name))
    if (!images.length) return []
    const stills = images.filter((p) => !/^motion-/.test(basename(p)))
    let source = ''
    try { source = JSON.parse(read(join(refDir, e.name, 'report.json')) ?? '{}').url ?? '' } catch { /* no report */ }
    return [{ name: e.name, kind: 'site', thumb: stills[0] ?? images[0], images, stills: stills.length, source }]
  })

  return {
    folder, dir, number, name, brief, meta, premise, variants, references,
    referencesNote: read(join(refDir, 'References.md')),
    tokens: read(join(dir, 'tokens.css')),
    design: read(join(dir, 'DESIGN.md')),
    hasLiveConfig: existsSync(join(dir, '.impeccable', 'live', 'config.json')),
  }
}

const directionFolders = () => list(DIR).filter((e) => e.isDirectory() && (/^\d+\s/.test(e.name) || existsSync(join(DIR, e.name, 'Brief.md')) || existsSync(join(DIR, e.name, 'Snapshots.json')))).sort(byName).map((e) => e.name)

// ---- pages ------------------------------------------------------------------
const STYLE = `
body{min-width:320px}
.navbar .container-xl{gap:1rem}
.crumbs{margin-left:auto;font-size:.8125rem}
.page-title{gap:.5rem}
.thumb{position:relative;display:block;aspect-ratio:16/10;overflow:hidden;background:#f6f8fb;border-bottom:1px solid var(--tblr-border-color);border-radius:var(--tblr-card-border-radius) var(--tblr-card-border-radius) 0 0}
.thumb iframe{position:absolute;top:0;left:0;width:1440px;height:900px;border:0;transform-origin:0 0;transform:scale(var(--s,.25));pointer-events:none}
.thumb img{width:100%;height:100%;object-fit:cover;object-position:top}
.row-cards .card{border-color:rgba(24,36,51,.08);box-shadow:0 1px 2px rgba(24,36,51,.05),0 6px 18px rgba(24,36,51,.07);transition:box-shadow .15s}
.row-cards .card:hover{box-shadow:0 2px 4px rgba(24,36,51,.06),0 10px 26px rgba(24,36,51,.11)}
.tile{display:grid;grid-template-columns:minmax(0,5fr) minmax(0,6fr);gap:1.75rem;padding:1.75rem;background:#fff}
.tile-text{display:flex;flex-direction:column;min-width:0}
.tile-name{font-size:1.75rem;line-height:1.15;margin:.35rem 0 .75rem}
.tile-premise{font-size:1rem;line-height:1.5;display:-webkit-box;-webkit-line-clamp:7;-webkit-box-orient:vertical;overflow:hidden;margin-bottom:1rem}
.tile-meta{margin-top:auto;font-size:.8125rem}
.tile-variants{display:flex;flex-direction:column;min-width:0}
.desk{position:relative;aspect-ratio:10/7.4}
.desk .thumb{position:absolute;width:52%;border:0;border-radius:4px;box-shadow:0 1px 2px rgba(24,36,51,.14),0 5px 14px rgba(24,36,51,.16)}
.tile-more{font-size:.8125rem;margin:auto 0 0;text-align:right}
@media (max-width:640px){.tile{grid-template-columns:1fr}}
.thumb-empty{display:grid;place-items:center;color:var(--tblr-secondary);font-size:.875rem}
.clamp{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.section-nav{padding-block:.5rem;margin-bottom:1rem;border-bottom:1px solid var(--tblr-border-color)}
.section-nav .nav-link{min-height:36px}
.markdown{max-width:78ch}
.markdown h2{margin-top:2rem}.markdown h3{margin-top:1.5rem}
.markdown img{max-width:100%;height:auto}
.markdown table{font-size:.875rem}
.swatches{display:grid;grid-template-columns:repeat(auto-fill,minmax(9rem,1fr));gap:.75rem}
.swatch-chip{height:3.5rem;border-radius:var(--tblr-border-radius);border:1px solid var(--tblr-border-color)}
.swatch code{font-size:.75rem}
.variants{display:grid;grid-template-columns:repeat(auto-fill,minmax(17.5rem,1fr));gap:2.25rem 1.5rem;align-items:start}
.variant{margin:0;min-width:0}
.variant-bar{display:flex;align-items:center;gap:.5rem;min-height:1.75rem;margin-bottom:.375rem;font-size:.8125rem}
.variant-title{min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.variant-title b{color:var(--tblr-secondary);font-weight:600;margin-right:.125rem}
.variant-tools{display:flex;flex:none;gap:.125rem;opacity:0;transition:opacity .12s}
.variant:hover .variant-tools,.variant:focus-within .variant-tools{opacity:1}
@media (hover:none){.variant-tools{opacity:1}}
.tool{display:grid;place-items:center;width:1.75rem;height:1.75rem;padding:0;border:0;border-radius:var(--tblr-border-radius);background:transparent;color:var(--tblr-secondary);cursor:pointer}
.tool:hover,.tool:focus-visible{background:rgba(24,36,51,.08);color:var(--tblr-body-color)}
.tool svg,.pv-bar svg{width:1.125rem;height:1.125rem;fill:none;stroke:currentColor;stroke-width:1.75;stroke-linecap:round;stroke-linejoin:round}
.live-dot{flex:none;width:.5rem;height:.5rem;border-radius:50%;background:var(--tblr-green)}
.frame{display:block;overflow:hidden;background:#fff;border-radius:3px;cursor:zoom-in;box-shadow:0 0 0 1px rgba(24,36,51,.08),0 4px 14px rgba(24,36,51,.08)}
.frame:focus-visible{outline:2px solid var(--tblr-primary);outline-offset:2px}
.frame img{display:block;width:100%;height:auto}
.frame .thumb{border:0;border-radius:0}
.stale-dot{flex:none;width:.5rem;height:.5rem;border-radius:50%;background:var(--tblr-yellow)}
dialog{border:0;padding:0}
dialog::backdrop{background:rgba(24,36,51,.55)}
#info{width:min(52rem,calc(100% - 2rem));max-height:86vh;border-radius:var(--tblr-border-radius-lg);box-shadow:var(--tblr-box-shadow-dropdown);overflow:hidden}
#info[open]{display:flex;flex-direction:column}
#info .info-head{display:flex;align-items:center;gap:1rem;padding:1rem 1.5rem;border-bottom:1px solid var(--tblr-border-color)}
#info .info-head h2{margin:0;font-size:1.125rem}
#info .info-body{padding:1.25rem 1.5rem 1.5rem;overflow:auto}
#preview{width:100vw;height:100vh;max-width:none;max-height:none;background:transparent;overflow:hidden}
#preview[open]{display:flex;flex-direction:column}
#preview::backdrop{background:rgba(13,18,26,.9)}
.pv-stage{flex:1;min-height:0;display:grid;place-items:center}
.pv-box{position:relative;background:#fff;border-radius:6px;box-shadow:0 20px 60px rgba(0,0,0,.35)}
.pv-box iframe{position:absolute;top:0;left:0;border:0;border-radius:6px;transform-origin:0 0;background:#fff}
.pv-handle{position:absolute;touch-action:none}
.pv-handle::after{content:"";position:absolute;inset:0;margin:auto;border-radius:3px;background:rgba(255,255,255,.75)}
.pv-handle[data-axis=x]{top:0;bottom:0;right:-14px;width:12px;cursor:ew-resize}
.pv-handle[data-axis=x]::after{width:4px;height:44px}
.pv-handle[data-axis=y]{left:0;right:0;bottom:-14px;height:12px;cursor:ns-resize}
.pv-handle[data-axis=y]::after{width:44px;height:4px}
.pv-handle[data-axis=xy]{right:-14px;bottom:-14px;width:14px;height:14px;cursor:nwse-resize}
.pv-handle[data-axis=xy]::after{width:6px;height:6px}
#preview.dragging iframe{pointer-events:none}
.pv-bar{flex:none;display:flex;align-items:center;justify-content:center;gap:.25rem;height:3.25rem;color:#fff}
.pv-bar button,.pv-bar a{display:grid;place-items:center;width:2.25rem;height:2.25rem;padding:0;border:0;border-radius:var(--tblr-border-radius);background:transparent;color:rgba(255,255,255,.72);cursor:pointer}
.pv-bar button:hover,.pv-bar a:hover,.pv-bar .active{background:rgba(255,255,255,.16);color:#fff}
.pv-size{min-width:9rem;text-align:center;font-size:.8125rem;font-variant-numeric:tabular-nums;color:rgba(255,255,255,.8)}
.pv-title{max-width:22rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-size:.8125rem;margin-right:.75rem}
.pv-gap{width:1rem}
.stills{display:grid;gap:1rem}
.stills img{width:100%;height:auto;border:1px solid var(--tblr-border-color);border-radius:var(--tblr-border-radius)}
@media (prefers-reduced-motion:reduce){*,*::before,*::after{scroll-behavior:auto!important;transition-duration:.01ms!important}}
`
const SCRIPT = `
const fit = new ResizeObserver((entries) => { for (const e of entries) e.target.style.setProperty('--s', e.contentRect.width / 1440) })
document.querySelectorAll('.thumb').forEach((t) => fit.observe(t))
// Tabs: one panel at a time, chosen by the address's hash so a link or the
// back button lands on the right one.
const tabs = [...document.querySelectorAll('[role=tab]')]
const showTab = () => {
  if (!tabs.length) return
  const wanted = tabs.find((t) => t.hash === location.hash) ?? tabs[0]
  for (const t of tabs) {
    const on = t === wanted
    t.classList.toggle('active', on)
    t.setAttribute('aria-selected', on)
    document.getElementById(t.getAttribute('aria-controls')).hidden = !on
  }
}
addEventListener('hashchange', showTab)
showTab()
// Notes: a variant's details and its notes file, in a scrolling dialog.
const info = document.querySelector('#info')
const openInfo = (el) => {
  info.querySelector('h2').textContent = el.dataset.title
  const body = info.querySelector('.info-body')
  body.replaceChildren(document.getElementById(el.dataset.info).content.cloneNode(true))
  const notes = body.querySelector('[data-notes]')
  if (notes) fetch(notes.dataset.notes).then((r) => r.text()).then((html) => { notes.innerHTML = html })
  info.showModal()
  body.scrollTop = 0
}

// Preview: the live page in a frame the owner can resize, with device presets.
const pv = document.querySelector('#preview')
const pvBox = pv && pv.querySelector('.pv-box')
const pvFrame = pv && pvBox.querySelector('iframe')
const PRESETS = { laptop: [1440, 900], tablet: [834, 1112], mobile: [390, 844] }
let pvSize = [0, 0]
let pvPreset = 'full'
const pvFull = () => [Math.round(innerWidth * 0.9), Math.round(Math.min(innerHeight * 0.9, innerHeight - 84))]
const pvRender = () => {
  if (pvPreset === 'full') pvSize = pvFull()
  const [w, h] = pvSize
  const s = Math.min(1, (innerWidth - 56) / w, (innerHeight - 84) / h)
  pvBox.style.width = w * s + 'px'
  pvBox.style.height = h * s + 'px'
  pvFrame.style.width = w + 'px'
  pvFrame.style.height = h + 'px'
  pvFrame.style.transform = 'scale(' + s + ')'
  pv.querySelector('.pv-size').textContent = w + ' × ' + h + (s < 1 ? ' · ' + Math.round(s * 100) + '%' : '')
  pv.querySelectorAll('[data-preset]').forEach((b) => b.classList.toggle('active', b.dataset.preset === pvPreset))
}
const openPreview = (el) => {
  pv.querySelector('.pv-title').textContent = el.dataset.title
  pv.querySelector('.pv-open').href = el.dataset.preview
  pvFrame.src = el.dataset.preview
  pvPreset = 'full'
  pv.showModal()
  pvRender()
}
if (pv) {
  pv.addEventListener('close', () => { pvFrame.src = 'about:blank' })
  addEventListener('resize', () => { if (pv.open) pvRender() })
  pv.querySelectorAll('.pv-handle').forEach((handle) => handle.addEventListener('pointerdown', (down) => {
    down.preventDefault()
    handle.setPointerCapture(down.pointerId)
    const from = pvSize.slice()
    const s = pvBox.clientWidth / pvSize[0]
    const axis = handle.dataset.axis
    pv.classList.add('dragging')
    // The frame is centred, so an edge moves half as far as the size changes.
    const move = (e) => {
      if (axis !== 'y') pvSize[0] = Math.max(280, Math.round(from[0] + (2 * (e.clientX - down.clientX)) / s))
      if (axis !== 'x') pvSize[1] = Math.max(320, Math.round(from[1] + (2 * (e.clientY - down.clientY)) / s))
      pvPreset = ''
      pvRender()
    }
    const up = () => {
      pv.classList.remove('dragging')
      handle.removeEventListener('pointermove', move)
      handle.removeEventListener('pointerup', up)
    }
    handle.addEventListener('pointermove', move)
    handle.addEventListener('pointerup', up)
  }))
}

document.addEventListener('click', (event) => {
  const tab = event.target.closest('[role=tab]')
  if (tab) { event.preventDefault(); history.replaceState(null, '', tab.hash); showTab() }
  const infoButton = event.target.closest('[data-info]')
  if (infoButton) return openInfo(infoButton)
  const preview = event.target.closest('[data-preview]')
  if (preview) return openPreview(preview)
  const preset = event.target.closest('[data-preset]')
  if (preset) { pvPreset = preset.dataset.preset; if (PRESETS[pvPreset]) pvSize = PRESETS[pvPreset].slice(); pvRender() }
  if (event.target.closest('[data-close]') || event.target.classList.contains('pv-stage')) event.target.closest('dialog').close()
})
document.addEventListener('keydown', (event) => {
  if ((event.key === 'Enter' || event.key === ' ') && event.target.matches('.frame')) { event.preventDefault(); openPreview(event.target) }
})
`

function page({ title, heading = '', lead = '', crumbs = [], body }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<title>${esc(title)}</title>
${TABLER}
<style>${STYLE}</style>
</head>
<body>
<div class="page">
<header class="navbar navbar-expand-md navbar-light d-print-none" aria-label="Primary">
<div class="container-xl">
<a class="navbar-brand" href="/">${esc(PROJECT)} <span class="text-secondary fw-normal ms-2">Design directions</span></a>
<nav class="crumbs text-secondary" aria-label="Breadcrumb">${crumbs.map((c) => (c.href ? `<a href="${c.href}">${esc(c.label)}</a>` : esc(c.label))).join(' / ')}</nav>
</div>
</header>
<div class="page-wrapper">
${heading ? `<div class="page-header d-print-none"><div class="container-xl">
<h1 class="page-title">${heading}</h1>
${lead ? `<p class="text-secondary mt-1 mb-0" style="max-width:80ch">${lead}</p>` : ''}
</div></div>` : `<h1 class="visually-hidden">${esc(title)}</h1>`}
<main class="page-body"><div class="container-xl">
${body}
</div></main>
<footer class="footer footer-transparent d-print-none"><div class="container-xl">${esc(PROJECT)} design directions · served from <code>${esc(DIR_REL)}</code></div></footer>
</div>
</div>
<dialog id="info" aria-labelledby="info-title">
<div class="info-head"><h2 id="info-title"></h2><button class="tool ms-auto" type="button" data-close aria-label="Close">${ICON.x}</button></div>
<div class="info-body"></div>
</dialog>
<dialog id="preview" aria-label="Preview">
<div class="pv-stage"><div class="pv-box"><iframe title="Variant preview"></iframe>
<div class="pv-handle" data-axis="x" aria-hidden="true"></div><div class="pv-handle" data-axis="y" aria-hidden="true"></div><div class="pv-handle" data-axis="xy" aria-hidden="true"></div></div></div>
<div class="pv-bar"><span class="pv-title"></span>
<button type="button" data-preset="full" aria-label="Fill the window" title="Fill the window">${ICON.full}</button>
<button type="button" data-preset="laptop" aria-label="Laptop, 1440 by 900" title="Laptop · 1440 × 900">${ICON.laptop}</button>
<button type="button" data-preset="tablet" aria-label="Tablet, 834 by 1112" title="Tablet · 834 × 1112">${ICON.tablet}</button>
<button type="button" data-preset="mobile" aria-label="Phone, 390 by 844" title="Phone · 390 × 844">${ICON.mobile}</button>
<span class="pv-size" aria-live="polite"></span>
<a class="pv-open" target="_blank" rel="noopener" aria-label="Open in a new tab" title="Open in a new tab">${ICON.external}</a>
<span class="pv-gap"></span>
<button type="button" data-close aria-label="Close" title="Close">${ICON.x}</button></div>
</dialog>
<script>${SCRIPT}</script>
</body>
</html>`
}

const svg = (paths) => `<svg viewBox="0 0 24 24" aria-hidden="true">${paths.map((d) => `<path d="${d}"/>`).join('')}</svg>`
const ICON = {
  info: svg(['M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0', 'M12 9h.01', 'M11 12h1v4h1']),
  eye: svg(['M10 12a2 2 0 1 0 4 0a2 2 0 0 0 -4 0', 'M21 12c-2.4 4 -5.4 6 -9 6c-3.6 0 -6.6 -2 -9 -6c2.4 -4 5.4 -6 9 -6c3.6 0 6.6 2 9 6']),
  pencil: svg(['M4 20h4l10.5 -10.5a2.828 2.828 0 1 0 -4 -4l-10.5 10.5v4', 'M13.5 6.5l4 4']),
  full: svg(['M16 4l4 0l0 4', 'M14 10l6 -6', 'M8 20l-4 0l0 -4', 'M4 20l6 -6', 'M16 20l4 0l0 -4', 'M14 14l6 6', 'M8 4l-4 0l0 4', 'M4 4l6 6']),
  laptop: svg(['M3 19l18 0', 'M5 7a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v8a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1z']),
  tablet: svg(['M5 4a1 1 0 0 1 1 -1h12a1 1 0 0 1 1 1v16a1 1 0 0 1 -1 1h-12a1 1 0 0 1 -1 -1v-16z', 'M11 17a1 1 0 1 0 2 0a1 1 0 0 0 -2 0']),
  mobile: svg(['M6 5a2 2 0 0 1 2 -2h8a2 2 0 0 1 2 2v14a2 2 0 0 1 -2 2h-8a2 2 0 0 1 -2 -2v-14z', 'M11 4h2', 'M12 17v.01']),
  external: svg(['M12 6h-6a2 2 0 0 0 -2 2v10a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-6', 'M11 13l9 -9', 'M15 4h5v5']),
  x: svg(['M18 6l-12 12', 'M6 6l12 12']),
}
// A variant's picture: its whole scroll when `whole`, else cropped to the top.
// Until frames.mjs has pictured a variant, a short live thumbnail stands in.
const picture = (d, v, whole) => v.frame
  ? `<img src="${fileUrl(v.frame.abs)}" width="${v.frame.width}" height="${v.frame.height}" alt="" loading="lazy" decoding="async">`
  : whole ? `<span class="thumb">${thumb(join(d.dir, v.show), v.title)}</span>` : thumb(join(d.dir, v.show), v.title)
const thumb = (abs, title) => `<iframe src="/thumb${fileUrl(abs)}" loading="lazy" tabindex="-1" aria-hidden="true" scrolling="no" title="${esc(title)}"></iframe>`
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`
const phaseBadge = (d) => (d.meta.Phase && !/\|/.test(d.meta.Phase) ? `<span class="badge bg-secondary-lt">${esc(d.meta.Phase)}</span>` : '')

// Where a variant's picture lies on its tile: a loose two-by-two, each one
// nudged and turned a little, like prints dropped on a desk. Seeded by the
// variant's name so a tile looks the same on every load.
function scatter(seed, i, count) {
  let h = 2166136261
  for (const c of seed) h = Math.imul(h ^ c.charCodeAt(0), 16777619)
  const next = () => ((h = Math.imul(h ^ (h >>> 15), 2246822507) ^ Math.imul(h ^ (h >>> 13), 3266489909)), ((h >>> 0) % 1000) / 1000)
  const slots = count === 1 ? [[24, 22]] : count === 2 ? [[4, 14], [44, 34]] : [[2, 3], [46, 9], [7, 48], [44, 51]]
  const [x, y] = slots[i % slots.length]
  const left = x + (next() - 0.5) * 8
  const top = y + (next() - 0.5) * 8
  const turn = (next() - 0.5) * 14
  return `left:${left.toFixed(1)}%;top:${top.toFixed(1)}%;rotate:${turn.toFixed(1)}deg;z-index:${1 + Math.floor(next() * 4)}`
}

function indexPage() {
  const all = directionFolders().map(readDirection)
  const cards = all.map((d) => {
    const shown = d.variants.slice(0, 4)
    const more = d.variants.length - shown.length
    return `<div class="col-lg-6"><article class="card tile">
<div class="tile-text">
${d.number ? `<div class="subheader">${esc(d.number)}</div>` : ''}
<h2 class="tile-name"><a class="stretched-link text-reset" href="${urlPath('direction', d.folder)}">${esc(d.name)}</a> ${phaseBadge(d)}</h2>
<p class="tile-premise">${esc(d.premise || (d.brief ? '' : 'No brief yet.'))}</p>
<div class="tile-meta text-secondary">${plural(d.variants.length, 'variant')} · ${plural(d.references.length, 'reference')}</div>
</div>
<div class="tile-variants"><div class="desk">${shown.map((v, i) => `<span class="thumb" style="${scatter(d.folder + v.base, i, shown.length)}">${picture(d, v, false)}</span>`).join('')}${shown.length ? '' : '<p class="text-secondary mb-0">No variants yet</p>'}</div>${more > 0 ? `<p class="tile-more text-secondary">and ${more} more</p>` : ''}</div>
</article></div>`
  }).join('\n')
  const body = `${all.length ? `<section class="row row-deck row-cards" aria-label="Directions">${cards}</section>` : `<div class="alert alert-info" role="status">No directions in <code>${esc(DIR_REL)}</code> yet. Start one with <code>design:direction-brief</code>.</div>`}`
  return page({ title: `${PROJECT} · Design directions`, body })
}

// Custom properties from tokens.css, split into colours and everything else.
function tokenTables(css) {
  const props = [...css.matchAll(/(--[\w-]+)\s*:\s*([^;}]+)[;}]/g)].map((m) => [m[1], m[2].trim()])
  const seen = new Set()
  const unique = props.filter(([k]) => !seen.has(k) && seen.add(k))
  const isColor = (v) => /^(#[0-9a-f]{3,8}|(rgb|hsl|oklch|oklab|lab|lch|color)\([^)]*\))$/i.test(v)
  const colors = unique.filter(([, v]) => isColor(v))
  const rest = unique.filter(([, v]) => !isColor(v))
  const families = [...new Set([...css.matchAll(/@font-face\s*{[^}]*font-family:\s*["']?([^;"'}]+)/g)].map((m) => m[1].trim()))]
  return `${colors.length ? `<h3 class="card-title">Colour</h3><div class="swatches mb-4">${colors.map(([k, v]) => `<div class="swatch"><div class="swatch-chip" style="background:${esc(v)}"></div><code>${esc(k)}</code><br><span class="text-secondary small">${esc(v)}</span></div>`).join('')}</div>` : ''}
${families.length ? `<h3 class="card-title">Typefaces</h3><p>${families.map(esc).join(', ')}</p>` : ''}
${rest.length ? `<h3 class="card-title">Tokens</h3><div class="table-responsive"><table class="table table-sm"><tbody>${rest.map(([k, v]) => `<tr><td><code>${esc(k)}</code></td><td class="text-secondary">${esc(v.length > 120 ? v.slice(0, 117) + '…' : v)}</td></tr>`).join('')}</tbody></table></div>` : ''}`
}

function directionPage(folder) {
  const d = readDirection(folder)
  const base = urlPath(DIR_REL, folder)
  const rel = (name) => `${DIR_REL}/${folder}/${name}`

  const variants = d.variants.map((v, i) => {
    const file = (name) => `${base}/${encodeURIComponent(name)}`
    const name = `${v.letter} ${v.title}`
    // Everything the gallery shows comes from this folder on disk, so it works
    // the same on any machine with the repository: the source page, else the
    // variant's page in the direction's static build, else its plates. A build
    // hosted elsewhere is only ever a link in the notes.
    const built = v.build ? `${urlPath('build', folder)}/${v.build.split('/').map(encodeURIComponent).join('/')}` : ''
    const preview = v.source ? file(v.source) : built || file(v.show)
    const details = [v.label, v.source ? 'Source page' : 'Framework build', v.captured ? `captured ${v.captured.slice(0, 10)}` : ''].filter(Boolean).join(' · ')
    const links = [
      `<a href="${preview}" target="_blank" rel="noopener">Open the page</a>`,
      v.plates ? `<a href="${file(v.plates)}" target="_blank" rel="noopener">Plates</a>` : '',
      // A hosted copy is worth a link only when the build is not here.
      v.hosted && !v.build ? `<a href="${esc(v.hosted)}" target="_blank" rel="noopener">Hosted at ${esc(new URL(v.hosted).host)}</a>` : '',
    ].filter(Boolean).join(' · ')
    return `<figure class="variant">
<figcaption class="variant-bar"><span class="variant-title"><b>${esc(v.letter)}</b> ${esc(v.title)}</span>${v.live ? '<span class="live-dot" title="Live editing is on"></span>' : ''}${v.frame?.stale ? '<span class="stale-dot" title="The page changed after this picture was taken. Run frames.mjs to refresh it."></span>' : ''}
<span class="variant-tools">
<button class="tool" type="button" data-info="info-${i}" data-title="${esc(name)}" aria-label="Notes on ${esc(name)}" title="Notes">${ICON.info}</button>
<button class="tool" type="button" data-preview="${esc(preview)}" data-title="${esc(name)}" aria-label="Preview ${esc(name)}" title="Preview">${ICON.eye}</button>
${v.source ? `<a class="tool" href="/edit${file(v.source)}" target="_blank" rel="noopener" aria-label="Edit ${esc(name)} with impeccable live" title="Edit with impeccable live">${ICON.pencil}</a>` : ''}
</span></figcaption>
<div class="frame" role="button" tabindex="0" data-preview="${esc(preview)}" data-title="${esc(name)}" aria-label="Preview ${esc(name)}">${picture(d, v, true)}</div>
<template id="info-${i}"><p class="text-secondary">${esc(details)}</p><p><code>${esc(rel(v.show))}</code></p><p>${links}</p>${v.note ? `<hr><div class="markdown" data-notes="/doc${file(v.note)}?fragment=1">Loading the notes…</div>` : '<hr><p class="text-secondary mb-0">No notes file for this variant.</p>'}</template>
</figure>`
  }).join('\n')

  const references = d.references.map((r) => `<div class="col-sm-6 col-lg-4"><article class="card">
${r.kind === 'file' ? `<a class="thumb thumb-empty" href="${fileUrl(r.file)}" target="_blank" rel="noopener">${esc(extname(r.name).slice(1).toUpperCase() || 'File')}</a>` : `<a class="thumb" href="${urlPath('direction', folder, 'reference', r.name)}"><img src="${fileUrl(r.thumb)}" alt="" loading="lazy"></a>`}
<div class="card-body"><h3 class="card-title mb-1">${esc(r.name)}</h3><p class="text-secondary mb-0">${r.kind === 'file' ? 'File' : r.kind === 'site' ? `${plural(r.stills, 'view')} captured${r.images.length > r.stills ? `, ${plural(r.images.length - r.stills, 'motion strip')}` : ''}` : 'Image'}${r.source ? ` · <a href="${esc(r.source)}" target="_blank" rel="noopener">source</a>` : ''}</p></div>
</article></div>`).join('\n')

  const nav = [['variants', `Variants (${d.variants.length})`], ['brief', 'Brief'], ['references', `References (${d.references.length})`], ['system', 'Design system']]
  const body = `<nav class="section-nav nav nav-pills d-print-none" role="tablist" aria-label="Sections">${nav.map(([id, label], i) => `<a class="nav-link${i ? '' : ' active'}" role="tab" id="tab-${id}" href="#${id}" aria-controls="${id}" aria-selected="${i ? 'false' : 'true'}">${label}</a>`).join('')}</nav>

<section id="variants" class="mb-4" role="tabpanel" aria-labelledby="tab-variants">${d.hasLiveConfig ? '<p class="text-secondary">Live editing is set up for this direction.</p>' : ''}
${variants ? `<div class="variants">${variants}</div>` : '<div class="alert alert-info" role="status">No variants yet. Run a round with <code>design:fan-out</code>.</div>'}</section>

<section id="brief" hidden role="tabpanel" aria-labelledby="tab-brief" class="card mb-4"><div class="card-header"><h2 class="card-title">Brief</h2><div class="card-actions text-secondary"><code>${esc(rel('Brief.md'))}</code></div></div>
<div class="card-body">${d.brief ? `<div class="markdown">${markdown(d.brief.replace(/^# .*\n/, ''), base, { shift: 1 })}</div>` : `<p class="text-secondary mb-0">No <code>Brief.md</code> in this folder. Write one with <code>design:direction-brief</code>.</p>`}</div></section>

<section id="references" hidden role="tabpanel" aria-labelledby="tab-references" class="mb-4"><div class="card mb-3"><div class="card-header"><h2 class="card-title">References</h2><div class="card-actions text-secondary"><code>${esc(rel('References/'))}</code></div></div>
<div class="card-body">${d.referencesNote ? `<div class="markdown">${markdown(d.referencesNote.replace(/^# .*\n/, ''), base + '/References', { shift: 2 })}</div>` : `<p class="text-secondary mb-0">${d.references.length ? 'No <code>References.md</code> yet: the notes on what to borrow from each.' : 'Nothing saved for this direction. <code>design:direction-brief</code> captures links as view stills and copies images here.'}</p>`}</div></div>
${references ? `<div class="row row-cards">${references}</div>` : ''}</section>

<section id="system" hidden role="tabpanel" aria-labelledby="tab-system" class="card mb-4"><div class="card-header"><h2 class="card-title">Design system</h2></div>
<div class="card-body">${d.tokens ? tokenTables(d.tokens) : ''}
${d.design ? `<div class="markdown">${markdown(d.design.replace(/^---[\s\S]*?\n---\n/, '').replace(/^# .*\n/m, ''), base, { shift: 2 })}</div>` : ''}
${d.tokens || d.design ? '' : `<p class="text-secondary mb-0">No <code>tokens.css</code> or <code>DESIGN.md</code> in this folder. The first variant of a direction writes <code>tokens.css</code>; <code>DESIGN.md</code> is written when the direction is ready to refine, and is what live editing reads.</p>`}</div></section>`

  return page({
    title: `${folder} · ${PROJECT}`,
    heading: `${d.number ? `<span class="text-secondary">${esc(d.number)}</span> ` : ''}${esc(d.name)} ${phaseBadge(d)}`,
    lead: esc(d.premise),
    crumbs: [{ label: 'Directions', href: '/' }, { label: folder }],
    body,
  })
}

function referencePage(folder, name) {
  const d = readDirection(folder)
  const r = d.references.find((x) => x.name === name)
  if (!r || r.kind === 'file') return null
  return page({
    title: `${name} · ${folder}`,
    heading: esc(name),
    lead: r.source ? `<a href="${esc(r.source)}" target="_blank" rel="noopener">${esc(r.source)}</a>` : '',
    crumbs: [{ label: 'Directions', href: '/' }, { label: folder, href: urlPath('direction', folder) + '#references' }, { label: name }],
    body: `<div class="stills">${r.images.map((p) => `<figure class="mb-0"><img src="${fileUrl(p)}" alt="" loading="lazy"><figcaption class="text-secondary small mt-1">${esc(basename(p))}</figcaption></figure>`).join('')}</div>`,
  })
}

function docPage(abs) {
  const rel = relative(ROOT, abs).split(sep).join('/')
  const src = readFileSync(abs, 'utf8')
  const title = (src.match(/^# +(.*)$/m) ?? [])[1] ?? basename(abs, '.md')
  const base = urlPath(rel.split('/').slice(0, -1).join('/'))
  const under = inside(DIR, abs) ? relative(DIR, abs).split(sep)[0] : ''
  return page({
    title: `${title} · ${PROJECT}`,
    heading: esc(title),
    crumbs: [{ label: 'Directions', href: '/' }, ...(under && under !== basename(abs) ? [{ label: under, href: urlPath('direction', under) }] : []), { label: basename(abs) }],
    body: `<div class="card"><div class="card-body"><div class="markdown">${markdown(src.replace(/^# .*\n/, ''), base === '/' ? '' : base, { shift: 1 })}</div></div></div>`,
  })
}

// ---- static builds ----------------------------------------------------------
// A direction can hold the static export of a framework build in Build/. Such
// pages refer to their own files by root-absolute paths ("/_next/…"), which
// only work at a site's root. The build is mounted at /build/<folder>/ and,
// as each text file is served, a root-absolute reference to one of the
// build's own top-level entries gets the mount's prefix.
const TEXT = /^(text\/|application\/json)/
function buildFile(folder, rest) {
  const root = join(DIR, folder, 'Build')
  let abs = resolve(root, ...rest)
  if (!inside(root, abs) || !existsSync(abs)) return null
  if (statSync(abs).isDirectory()) abs = join(abs, 'index.html')
  if (!existsSync(abs)) return null
  const type = MIME[extname(abs).toLowerCase()] ?? 'application/octet-stream'
  if (!TEXT.test(type)) return { body: readFileSync(abs), type }
  const tops = list(root).map((e) => e.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')
  // In script, only a quoted path is a path; in markup and styles it may also
  // follow "=", "(", a comma or a space (srcset, url()).
  const before = type.startsWith('text/javascript') ? '["\'`]' : '["\'`(=,\\s]'
  const own = new RegExp(`(?<=${before})\\/(?=(?:${tops})(?:[\\/"'\`?#)\\\\\\s]|$))`, 'g')
  return { body: readFileSync(abs, 'utf8').replace(own, urlPath('build', folder) + '/'), type }
}

// ---- live editing ------------------------------------------------------------
const LIVE_CONFIG = { files: ['*.html'], exclude: ['*.plates.html', 'Cover*.html'], insertBefore: '</body>', commentSyntax: 'html', cspChecked: true }
const impeccableBin = () => [flag('--impeccable'), process.env.IMPECCABLE_BIN, ...[ROOT, homedir()].flatMap((r) => ['.agents', '.claude'].map((d) => join(r, d, 'skills', 'impeccable', 'scripts', 'impeccable')))].find((p) => p && existsSync(p))

// Start impeccable live for one variant. Returns null when it is running, or
// what stopped it. The direction needs its own DESIGN.md: that is what makes
// live mode treat the direction folder as its project.
function startLive(abs) {
  if (isLive(abs)) return null
  const dir = dirname(abs)
  const relPath = relative(ROOT, abs).split(sep).join('/')
  const ask = `Start impeccable live on "${relPath}" and keep polling until I say stop.`
  if (!existsSync(join(dir, 'DESIGN.md'))) return { title: 'This direction has no DESIGN.md yet', why: `Live editing varies an element inside a direction's identity, and reads that identity from <code>${esc(relative(ROOT, dir))}/DESIGN.md</code>. Ask your agent to write it from the brief, then press Edit again.`, ask: `Write DESIGN.md for "${relative(ROOT, dir)}" from its brief and tokens, then start impeccable live on "${relPath}" and keep polling.` }
  const bin = impeccableBin()
  if (!bin) return { title: 'impeccable is not installed where the gallery can find it', why: 'Pass <code>--impeccable &lt;path to its script&gt;</code> when starting the gallery, or ask your agent to start live mode.', ask }
  const config = join(dir, '.impeccable', 'live', 'config.json')
  if (!existsSync(config)) {
    mkdirSync(dirname(config), { recursive: true })
    writeFileSync(config, JSON.stringify(LIVE_CONFIG, null, 2) + '\n')
  }
  const run = spawnSync(bin, ['live', '--target', relPath], { cwd: ROOT, encoding: 'utf8', timeout: 90000 })
  let out = {}
  try { out = JSON.parse(run.stdout) } catch { /* reported below */ }
  if (out.ok) return null
  return { title: 'Live mode did not start', why: `impeccable reported <code>${esc(out.error ?? run.error?.message ?? 'no result')}</code>${out.missing ? ` (missing: ${esc(out.missing.join(', '))})` : ''}.`, ask }
}

const editProblemPage = (problem) => page({
  title: problem.title,
  heading: esc(problem.title),
  crumbs: [{ label: 'Directions', href: '/' }],
  body: `<div class="card"><div class="card-body"><p>${problem.why}</p><p class="text-secondary mb-2">To give your agent:</p><pre style="white-space:pre-wrap"><code>${esc(problem.ask)}</code></pre></div></div>`,
})

// ---- server -----------------------------------------------------------------
const send = (res, status, body, type = 'text/html; charset=utf-8') => {
  res.writeHead(status, { 'content-type': type, 'cache-control': 'no-store' })
  res.end(body)
}
const notFound = (res) => send(res, 404, page({ title: 'Not found', heading: 'Not found', crumbs: [{ label: 'Directions', href: '/' }], body: '<p><a href="/">Back to the directions</a></p>' }))

const server = createServer((req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost')
    let parts
    try { parts = url.pathname.split('/').filter(Boolean).map(decodeURIComponent) } catch { return send(res, 400, 'Bad request', 'text/plain') }
    if (req.method !== 'GET' && req.method !== 'HEAD') return send(res, 405, 'Read-only', 'text/plain')
    if (parts.some((p) => p === '..' || p.startsWith('.'))) return notFound(res)

    if (!parts.length) return send(res, 200, indexPage())
    if (parts[0] === 'direction' && parts[1] && existsSync(join(DIR, parts[1])) && inside(DIR, resolve(DIR, parts[1]))) {
      if (parts.length === 2) return send(res, 200, directionPage(parts[1]))
      if (parts[2] === 'reference' && parts[3]) {
        const html = referencePage(parts[1], parts[3])
        return html ? send(res, 200, html) : notFound(res)
      }
    }
    if (parts[0] === 'build' && parts[1] && inside(DIR, resolve(DIR, parts[1]))) {
      const file = buildFile(parts[1], parts.slice(2))
      return file ? send(res, 200, file.body, file.type) : notFound(res)
    }
    if (parts[0] === 'edit') {
      // Only a click in the gallery, or a typed address, may start live mode.
      if (!['same-origin', 'none', undefined].includes(req.headers['sec-fetch-site'])) return send(res, 403, 'Open this from the gallery', 'text/plain')
      const abs = resolve(ROOT, ...parts.slice(1))
      if (!inside(DIR, abs) || !/\.html$/i.test(abs) || /\.plates\.html$/i.test(abs) || !existsSync(abs)) return notFound(res)
      const problem = startLive(abs)
      if (problem) return send(res, 409, editProblemPage(problem))
      res.writeHead(302, { location: fileUrl(abs), 'cache-control': 'no-store' })
      return res.end()
    }
    if (parts[0] === 'doc') {
      const abs = resolve(ROOT, ...parts.slice(1))
      if (!inside(ROOT, abs) || !/\.md$/i.test(abs) || parts.includes('node_modules') || !existsSync(abs)) return notFound(res)
      if (url.searchParams.has('fragment')) {
        const base = urlPath(relative(ROOT, dirname(abs)).split(sep).join('/'))
        return send(res, 200, markdown(readFileSync(abs, 'utf8').replace(/^# .*\n/, ''), base === '/' ? '' : base, { shift: 2 }))
      }
      return send(res, 200, docPage(abs))
    }
    const strip = parts[0] === 'thumb'
    const abs = resolve(ROOT, ...(strip ? parts.slice(1) : parts))
    if (!inside(DIR, abs) || !existsSync(abs) || !statSync(abs).isFile()) return notFound(res)
    const type = MIME[extname(abs).toLowerCase()] ?? 'application/octet-stream'
    if (strip && type.startsWith('text/html')) {
      // A thumbnail is the page without any live-editing script, with relative
      // URLs still resolving against the file's own folder.
      const baseHref = fileUrl(abs).split('/').slice(0, -1).join('/') + '/'
      const html = readFileSync(abs, 'utf8').replace(/<script[^>]*\/live\.js\?token=[^>]*><\/script>/g, '').replace(/<head([^>]*)>/i, `<head$1><base href="${baseHref}">`)
      return send(res, 200, html, type)
    }
    return send(res, 200, readFileSync(abs), type)
  } catch (error) {
    console.error(error)
    send(res, 500, 'Gallery error: ' + error.message, 'text/plain')
  }
})

server.listen(PORT, HOST, () => {
  const { port } = server.address()
  console.log(`gallery: http://${HOST === '0.0.0.0' ? 'localhost' : HOST}:${port}  (${DIR_REL}, ${directionFolders().length} directions)`)
})
