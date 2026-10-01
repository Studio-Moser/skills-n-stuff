#!/usr/bin/env node
// A local gallery for a project's design directions. No build step and no
// dependencies: every page is rendered from the files on disk at request time,
// so it is always current.
//
//   /                       a grid of directions
//   /direction/<folder>     one direction: its brief, references, design
//                           system, and a grid of its variants
//   /doc/<path>.md          any markdown file in the project, rendered
//   /frame?src=…&w=390      one variant at a fixed width (phone preview)
//   /<directions dir>/…     the files themselves, at their repo-relative path
//
// Variants are served at their repo-relative path on purpose: a live-editing
// helper that injects a script into the file (impeccable live) maps the page
// URL back to the source file, and that mapping holds when the URL mirrors the
// path. Thumbnails load through /thumb/…, which strips that script so a grid
// of thumbnails does not open a live session each.
//
// Usage: node gallery.mjs [--dir "docs/Design Directions"] [--port 4600]
//                         [--host 127.0.0.1] [--project "<name>"]
// Run it from the project root. It serves files under --dir and markdown under
// the project root, read-only. Bind another --host only on a private network.
import { createServer } from 'node:http'
import { existsSync, readFileSync, readdirSync, statSync, openSync, readSync, closeSync } from 'node:fs'
import { basename, extname, join, relative, resolve, sep } from 'node:path'

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
  const variants = [...groups.values()].map((g) => {
    const entry = entries.find((v) => (g.plates && v.file === g.plates) || (g.source && (v.file === g.source || v.live === g.source))) ?? {}
    const show = g.source ?? g.plates
    return {
      ...g,
      show,
      label: entry.label ?? '',
      build: entry.liveUrl ?? (/^https?:/.test(entry.source ?? '') ? entry.source : ''),
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
.metric-value{font-variant-numeric:tabular-nums}
.page-title{gap:.5rem}
.thumb{position:relative;display:block;aspect-ratio:16/10;overflow:hidden;background:#f6f8fb;border-bottom:1px solid var(--tblr-border-color);border-radius:var(--tblr-card-border-radius) var(--tblr-card-border-radius) 0 0}
.thumb iframe{position:absolute;top:0;left:0;width:1440px;height:900px;border:0;transform-origin:0 0;transform:scale(var(--s,.25));pointer-events:none}
.thumb img{width:100%;height:100%;object-fit:cover;object-position:top}
.thumb-empty{display:grid;place-items:center;color:var(--tblr-secondary);font-size:.875rem}
.clamp{display:-webkit-box;-webkit-line-clamp:3;-webkit-box-orient:vertical;overflow:hidden}
.section-nav{position:sticky;top:0;z-index:5;background:var(--tblr-body-bg);padding-block:.5rem;margin-bottom:1rem;border-bottom:1px solid var(--tblr-border-color)}
.section-nav .nav-link{min-height:36px}
section[id]{scroll-margin-top:4rem}
.markdown{max-width:78ch}
.markdown h2{margin-top:2rem}.markdown h3{margin-top:1.5rem}
.markdown img{max-width:100%;height:auto}
.markdown table{font-size:.875rem}
.swatches{display:grid;grid-template-columns:repeat(auto-fill,minmax(9rem,1fr));gap:.75rem}
.swatch-chip{height:3.5rem;border-radius:var(--tblr-border-radius);border:1px solid var(--tblr-border-color)}
.swatch code{font-size:.75rem}
.variant-actions{display:flex;flex-wrap:wrap;gap:.5rem}
dialog{border:0;border-radius:var(--tblr-border-radius-lg);padding:0;max-width:34rem;width:calc(100% - 2rem);box-shadow:var(--tblr-box-shadow-dropdown)}
dialog::backdrop{background:rgba(24,36,51,.4)}
dialog pre{white-space:pre-wrap;margin:0}
.stills{display:grid;gap:1rem}
.stills img{width:100%;height:auto;border:1px solid var(--tblr-border-color);border-radius:var(--tblr-border-radius)}
@media (prefers-reduced-motion:reduce){*,*::before,*::after{scroll-behavior:auto!important;transition-duration:.01ms!important}}
`
const SCRIPT = `
const fit = new ResizeObserver((entries) => { for (const e of entries) e.target.style.setProperty('--s', e.contentRect.width / 1440) })
document.querySelectorAll('.thumb').forEach((t) => fit.observe(t))
const dialog = document.querySelector('#edit')
document.addEventListener('click', (event) => {
  const edit = event.target.closest('[data-edit]')
  if (edit) {
    event.preventDefault()
    dialog.querySelector('#edit-ask').textContent = edit.dataset.edit
    dialog.querySelector('#edit-open').href = edit.href
    dialog.showModal()
  }
  if (event.target.closest('#edit-copy')) navigator.clipboard.writeText(dialog.querySelector('#edit-ask').textContent).then(() => { event.target.closest('#edit-copy').textContent = 'Copied' })
  if (event.target.closest('[data-close]')) dialog.close()
})
`

function page({ title, heading, lead = '', crumbs = [], body }) {
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
<div class="page-header d-print-none"><div class="container-xl">
<h1 class="page-title">${heading}</h1>
${lead ? `<p class="text-secondary mt-1 mb-0" style="max-width:80ch">${lead}</p>` : ''}
</div></div>
<main class="page-body"><div class="container-xl">
${body}
</div></main>
<footer class="footer footer-transparent d-print-none"><div class="container-xl">${esc(PROJECT)} design directions · served from <code>${esc(DIR_REL)}</code></div></footer>
</div>
</div>
<dialog id="edit" aria-labelledby="edit-title">
<div class="card mb-0"><div class="card-header"><h3 class="card-title" id="edit-title">Live editing is not running for this direction</h3></div>
<div class="card-body"><p class="text-secondary">Give your agent this, then open the variant. The editing bar appears in the page once the agent has started live mode.</p><pre><code id="edit-ask"></code></pre></div>
<div class="card-footer d-flex gap-2 justify-content-end"><button class="btn" type="button" data-close>Close</button><button class="btn" type="button" id="edit-copy">Copy</button><a class="btn btn-primary" id="edit-open" target="_blank" rel="noopener">Open the variant</a></div></div>
</dialog>
<script>${SCRIPT}</script>
</body>
</html>`
}

const thumb = (abs, title) => `<iframe src="/thumb${fileUrl(abs)}" loading="lazy" tabindex="-1" aria-hidden="true" scrolling="no" title="${esc(title)}"></iframe>`
const metric = (label, value) => `<div class="col-sm-4"><div class="card"><div class="card-body"><div class="subheader">${label}</div><div class="h1 mb-0 metric-value">${value}</div></div></div></div>`
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`
const phaseBadge = (d) => (d.meta.Phase && !/\|/.test(d.meta.Phase) ? `<span class="badge bg-secondary-lt">${esc(d.meta.Phase)}</span>` : '')

function indexPage() {
  const all = directionFolders().map(readDirection)
  const cards = all.map((d) => {
    const first = d.variants[0]
    return `<div class="col-sm-6 col-lg-4"><article class="card">
<a class="thumb${first ? '' : ' thumb-empty'}" href="${urlPath('direction', d.folder)}" aria-label="Open ${esc(d.folder)}">${first ? thumb(join(d.dir, first.show), d.folder) : 'No variants yet'}</a>
<div class="card-body">
<div class="d-flex align-items-center gap-2 mb-2"><h3 class="card-title mb-0"><a class="text-reset" href="${urlPath('direction', d.folder)}">${d.number ? `<span class="text-secondary">${esc(d.number)}</span> ` : ''}${esc(d.name)}</a></h3>${phaseBadge(d)}</div>
<p class="text-secondary clamp mb-0">${esc(d.premise || (d.brief ? '' : 'No brief yet.'))}</p>
</div>
<div class="card-footer text-secondary"><a class="text-reset" href="${urlPath('direction', d.folder)}#variants">${plural(d.variants.length, 'variant')}</a> · ${plural(d.references.length, 'reference')}</div>
</article></div>`
  }).join('\n')
  const body = `<section class="row row-deck row-cards mb-4" aria-label="Summary">
${metric('Directions', all.length)}${metric('Variants', all.reduce((n, d) => n + d.variants.length, 0))}${metric('References', all.reduce((n, d) => n + d.references.length, 0))}
</section>
${all.length ? `<section class="row row-deck row-cards" aria-label="Directions">${cards}</section>` : `<div class="alert alert-info" role="status">No directions in <code>${esc(DIR_REL)}</code> yet. Start one with <code>design:direction-brief</code>.</div>`}`
  return page({ title: `${PROJECT} · Design directions`, heading: 'Design directions', lead: 'Every direction being explored, with its brief, references, design system, and variants.', body })
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

  const variants = d.variants.map((v) => {
    const href = `${base}/${encodeURIComponent(v.show)}`
    const ask = `Start impeccable live on "${rel(v.source ?? '')}" and keep polling until I say stop.`
    return `<div class="col-md-6 col-xl-4"><article class="card">
<a class="thumb" href="${href}" target="_blank" rel="noopener" aria-label="Open ${esc(v.letter)} ${esc(v.title)}">${thumb(join(d.dir, v.show), v.title)}</a>
<div class="card-body">
<div class="d-flex align-items-center gap-2 mb-1"><h3 class="card-title mb-0"><span class="text-secondary">${esc(v.letter)}</span> ${esc(v.title)}</h3>${v.live ? '<span class="badge bg-green-lt">Live</span>' : ''}${v.source ? '' : '<span class="badge bg-secondary-lt">Frozen</span>'}</div>
${v.label ? `<p class="text-secondary mb-0">${esc(v.label)}</p>` : ''}
</div>
<div class="card-footer variant-actions">
<a class="btn btn-sm btn-primary" href="${href}" target="_blank" rel="noopener">Open</a>
${v.source ? `<a class="btn btn-sm" href="${href}" target="_blank" rel="noopener"${v.live ? '' : ` data-edit="${esc(ask)}"`}>Edit</a>` : '<span class="btn btn-sm disabled" aria-disabled="true" title="A frozen copy of a framework build has no source page to edit">Edit</span>'}
<a class="btn btn-sm" href="/frame?src=${encodeURIComponent(href)}&w=390" target="_blank" rel="noopener">Phone</a>
${v.build ? `<a class="btn btn-sm" href="${esc(v.build)}" target="_blank" rel="noopener">Live build</a>` : ''}
${v.source && v.plates ? `<a class="btn btn-sm" href="${base}/${encodeURIComponent(v.plates)}" target="_blank" rel="noopener">Plates</a>` : ''}
${v.note ? `<a class="btn btn-sm" href="/doc${base}/${encodeURIComponent(v.note)}">Notes</a>` : ''}
</div>
</article></div>`
  }).join('\n')

  const references = d.references.map((r) => `<div class="col-sm-6 col-lg-4"><article class="card">
${r.kind === 'file' ? `<a class="thumb thumb-empty" href="${fileUrl(r.file)}" target="_blank" rel="noopener">${esc(extname(r.name).slice(1).toUpperCase() || 'File')}</a>` : `<a class="thumb" href="${urlPath('direction', folder, 'reference', r.name)}"><img src="${fileUrl(r.thumb)}" alt="" loading="lazy"></a>`}
<div class="card-body"><h3 class="card-title mb-1">${esc(r.name)}</h3><p class="text-secondary mb-0">${r.kind === 'file' ? 'File' : r.kind === 'site' ? `${plural(r.stills, 'view')} captured${r.images.length > r.stills ? `, ${plural(r.images.length - r.stills, 'motion strip')}` : ''}` : 'Image'}${r.source ? ` · <a href="${esc(r.source)}" target="_blank" rel="noopener">source</a>` : ''}</p></div>
</article></div>`).join('\n')

  const nav = [['brief', 'Brief'], ['references', `References (${d.references.length})`], ['system', 'Design system'], ['variants', `Variants (${d.variants.length})`]]
  const body = `<nav class="section-nav nav nav-pills d-print-none" aria-label="Sections">${nav.map(([id, label]) => `<a class="nav-link" href="#${id}">${label}</a>`).join('')}</nav>

<section id="brief" class="card mb-4"><div class="card-header"><h2 class="card-title">Brief</h2><div class="card-actions text-secondary"><code>${esc(rel('Brief.md'))}</code></div></div>
<div class="card-body">${d.brief ? `<div class="markdown">${markdown(d.brief.replace(/^# .*\n/, ''), base, { shift: 1 })}</div>` : `<p class="text-secondary mb-0">No <code>Brief.md</code> in this folder. Write one with <code>design:direction-brief</code>.</p>`}</div></section>

<section id="references" class="mb-4"><div class="card mb-3"><div class="card-header"><h2 class="card-title">References</h2><div class="card-actions text-secondary"><code>${esc(rel('References/'))}</code></div></div>
<div class="card-body">${d.referencesNote ? `<div class="markdown">${markdown(d.referencesNote.replace(/^# .*\n/, ''), base + '/References', { shift: 2 })}</div>` : `<p class="text-secondary mb-0">${d.references.length ? 'No <code>References.md</code> yet: the notes on what to borrow from each.' : 'Nothing saved for this direction. <code>design:direction-brief</code> captures links as view stills and copies images here.'}</p>`}</div></div>
${references ? `<div class="row row-cards">${references}</div>` : ''}</section>

<section id="system" class="card mb-4"><div class="card-header"><h2 class="card-title">Design system</h2></div>
<div class="card-body">${d.tokens ? tokenTables(d.tokens) : ''}
${d.design ? `<div class="markdown">${markdown(d.design.replace(/^---[\s\S]*?\n---\n/, '').replace(/^# .*\n/m, ''), base, { shift: 2 })}</div>` : ''}
${d.tokens || d.design ? '' : `<p class="text-secondary mb-0">No <code>tokens.css</code> or <code>DESIGN.md</code> in this folder. The first variant of a direction writes <code>tokens.css</code>; <code>DESIGN.md</code> is written when the direction is ready to refine, and is what live editing reads.</p>`}</div></section>

<section id="variants" class="mb-4"><div class="d-flex align-items-center mb-3"><h2 class="mb-0">Variants</h2><span class="text-secondary ms-auto">${d.hasLiveConfig ? 'Live editing is set up for this direction' : ''}</span></div>
${variants ? `<div class="row row-cards">${variants}</div>` : '<div class="alert alert-info" role="status">No variants yet. Run a round with <code>design:fan-out</code>.</div>'}</section>`

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

function framePage(src, width) {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${width}px</title>
<style>html,body{height:100%;margin:0;background:#182433}body{display:grid;place-items:center}iframe{width:${width}px;height:min(844px,calc(100vh - 2rem));border:0;border-radius:12px;background:#fff;box-shadow:0 20px 60px rgba(0,0,0,.4)}</style></head>
<body><iframe src="${esc(src)}" title="Variant at ${width}px"></iframe></body></html>`
}

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
    if (parts[0] === 'frame') {
      const src = url.searchParams.get('src') ?? ''
      const width = Math.min(1920, Math.max(280, Number(url.searchParams.get('w')) || 390))
      return /^\/[^/]/.test(src) ? send(res, 200, framePage(src, width)) : notFound(res)
    }
    if (parts[0] === 'doc') {
      const abs = resolve(ROOT, ...parts.slice(1))
      if (!inside(ROOT, abs) || !/\.md$/i.test(abs) || parts.includes('node_modules') || !existsSync(abs)) return notFound(res)
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
