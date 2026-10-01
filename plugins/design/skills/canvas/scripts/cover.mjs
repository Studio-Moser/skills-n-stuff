// Write a Cover page for each direction's canvas: the direction's number and
// name in type large enough to read in a dashboard thumbnail, its premise, and
// a labelled thumbnail of every variant, so a wall of canvases says which is
// which. publish-canvas.mjs puts it first on the canvas and writes it last,
// because Doop shows a canvas's most recently updated frame as its thumbnail.
//
// Usage: node cover.mjs --dir <directions dir> --project "<name>" [--only <prefix>]
//
// One cover per round of a direction, beside its Snapshots.json: "Cover.html"
// for the first round, "Cover - <round>.html" for a later one (the same
// naming publish-canvas.mjs uses for canvases). The premise comes from the
// manifest's `premise`, else the first paragraph under "## Premise" in the
// folder's Brief.md.
//
// A cover is self-contained on purpose: system fonts and thumbnails inlined
// as small JPEGs. Doop renders dashboard thumbnails on its server, which
// cannot reach a tailnet asset host, so anything fetched would come out blank.
//
// Needs @playwright/test (or playwright) with Chromium, and sharp, resolvable
// from the current working directory.
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

const args = process.argv.slice(2)
const flag = (name) => {
  const i = args.indexOf(name)
  return i >= 0 ? args[i + 1] : undefined
}
const dir = flag('--dir')
const project = flag('--project') ?? ''
const only = flag('--only')
if (!dir) {
  console.error('usage: cover.mjs --dir <directions dir> --project "<name>" [--only <prefix>]')
  process.exit(2)
}
const DIRECTIONS = resolve(dir)

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

const words = (s) => String(s ?? '').replace(/^[A-Za-z],\s*/, '').toLowerCase().replace(/[^a-z0-9]+/g, '')
const sameWords = (a, b) => words(a) === words(b)
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')

function premiseFor(folder, manifest) {
  if (manifest.premise) return manifest.premise
  const brief = resolve(DIRECTIONS, folder, 'Brief.md')
  if (!existsSync(brief)) return ''
  const m = /^##\s+Premise\s*\n+([\s\S]*?)(?:\n\s*\n|\n#)/m.exec(readFileSync(brief, 'utf8'))
  if (!m) return ''
  const text = m[1].replace(/[*_`]/g, '').replace(/\[([^\]]+)\]\([^)]*\)/g, '$1').replace(/\s+/g, ' ').trim()
  // two sentences is what fits; the brief has the rest
  const two = text.match(/^(.+?[.!?])\s+(.+?[.!?])(\s|$)/)
  const out = two ? `${two[1]} ${two[2]}` : text
  return out.length > 300 ? `${out.slice(0, 297).replace(/\s+\S*$/, '')}…` : out
}

function coverHtml({ number, name, round, premise, variants, date }) {
  const n = variants.length
  const cols = n <= 4 ? 2 : n <= 6 ? 3 : 4
  const tiles = variants
    .map(
      (v) => `<figure><img src="${v.thumb}" alt=""><figcaption><b>${esc(v.letter)}</b> ${esc(v.title)}${
        v.label ? `<small>${esc(v.label)}</small>` : ''
      }</figcaption></figure>`
    )
    .join('')
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=1440">
<title>${esc(`${number} ${name}`)} · Cover</title>
<style>
html,body{margin:0}
body{width:1440px;height:900px;overflow:hidden;background:#f6f3ec;color:#1b1d1f;font-family:Georgia,'Times New Roman','Liberation Serif',serif;display:grid;grid-template-columns:560px 1fr}
.id{padding:64px 0 56px 72px;display:flex;flex-direction:column}
.project{font:600 20px/1 'Helvetica Neue',Helvetica,Arial,'Liberation Sans',system-ui,sans-serif;letter-spacing:.02em}
.number{font-size:230px;line-height:.86;margin:54px 0 0 -8px;letter-spacing:-.04em}
h1{font-size:92px;line-height:.98;font-weight:400;margin:14px 0 0;letter-spacing:-.02em}
.round{font:500 26px/1.2 'Helvetica Neue',Helvetica,Arial,'Liberation Sans',system-ui,sans-serif;margin-top:16px;opacity:.7}
.premise{font-size:21px;line-height:1.42;margin:28px 0 0;max-width:440px}
.meta{margin-top:auto;font:500 17px/1.4 'Helvetica Neue',Helvetica,Arial,'Liberation Sans',system-ui,sans-serif;opacity:.62}
.grid{padding:64px 72px 56px 40px;display:grid;grid-template-columns:repeat(${cols},1fr);gap:22px 22px;align-content:start}
figure{margin:0}
figure img{display:block;width:100%;aspect-ratio:16/10;object-fit:cover;object-position:top;border:1px solid rgba(27,29,31,.16);background:#fff}
figcaption{font:500 ${cols === 4 ? 14 : 16}px/1.3 'Helvetica Neue',Helvetica,Arial,'Liberation Sans',system-ui,sans-serif;margin-top:8px}
figcaption b{display:inline-block;min-width:1.1em;font-weight:700}
figcaption small{display:block;font-size:${cols === 4 ? 12 : 13}px;font-weight:400;opacity:.62;margin-top:2px}
</style></head>
<body>
<div class="id">
  <div class="project">${esc(project)}</div>
  <div class="number">${esc(number)}</div>
  <h1>${esc(name)}</h1>
  ${round ? `<div class="round">${esc(round)}</div>` : ''}
  ${premise ? `<p class="premise">${esc(premise)}</p>` : ''}
  <div class="meta">${n} variant${n === 1 ? '' : 's'} · ${esc(date)}</div>
</div>
<div class="grid">${tiles}</div>
</body></html>
`
}

const folders = readdirSync(DIRECTIONS)
  .filter((d) => existsSync(resolve(DIRECTIONS, d, 'Snapshots.json')))
  .filter((d) => !only || d.startsWith(only))
  .sort()

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 })
for (const d of folders) {
  const manifest = JSON.parse(readFileSync(resolve(DIRECTIONS, d, 'Snapshots.json'), 'utf8'))
  const variants = manifest.variants.filter((m) => m.ok !== false)
  const rounds = [...new Set(variants.map((v) => v.round ?? d))]
  const [, number = '', name = d] = /^(\S+)\s+(.+)$/.exec(d) ?? []
  for (const round of rounds) {
    const extra = round === rounds[0] ? '' : round.replace(rounds[0], '').replace(/^[-_ ]+/, '') || round
    const tiles = []
    for (const v of variants.filter((x) => (x.round ?? d) === round)) {
      // the variant's first screen, as the thumbnail that says which it is
      await page.goto(pathToFileURL(resolve(DIRECTIONS, d, v.file)).href, { waitUntil: 'load' })
      await page.waitForTimeout(700)
      const shot = await page.screenshot({ clip: { x: 0, y: 0, width: 1440, height: 900 } })
      const jpeg = await sharp(shot).resize(480, 300).jpeg({ quality: 72 }).toBuffer()
      tiles.push({
        letter: v.id.length === 1 ? v.id.toUpperCase() : v.id,
        title: v.title,
        // "K, copy 13 final, built directly" -> "copy 13 final, built directly";
        // dropped when the title was made from the label and says the same
        label: sameWords(v.label, v.title) ? '' : (v.label ?? '').replace(/^[A-Za-z],\s*/, ''),
        thumb: `data:image/jpeg;base64,${jpeg.toString('base64')}`,
      })
    }
    const file = resolve(DIRECTIONS, d, extra ? `Cover - ${extra}.html` : 'Cover.html')
    writeFileSync(
      file,
      coverHtml({
        number,
        name,
        round: extra,
        premise: premiseFor(d, manifest),
        variants: tiles,
        date: new Date().toISOString().slice(0, 10),
      })
    )
    console.log(JSON.stringify({ folder: d, round: extra || null, cover: file, variants: tiles.length }))
  }
}
await browser.close()
