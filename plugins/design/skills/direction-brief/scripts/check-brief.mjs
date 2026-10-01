// Readiness check for one design direction: is everything a round needs written
// down? Run before handing a direction to design:fan-out.
//
// Usage: node check-brief.mjs "<direction folder>" [--copy "<copy direction file>"]
//
// Fails (exit 1, one line per problem) on: no Brief.md; a required section
// missing or empty; a {slot} left from the template; a Reference pack with
// fewer than two entries, or an entry whose local path does not exist; fewer
// than two Wins if or Loses if lines; a Motion section that never mentions
// reduced motion; a --copy file that is missing or still has slots.
import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'

const args = process.argv.slice(2)
const folder = args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--copy')
const copyAt = args.indexOf('--copy')
const copy = copyAt >= 0 ? args[copyAt + 1] : null
if (!folder) {
  console.error('usage: check-brief.mjs "<direction folder>" [--copy "<copy direction file>"]')
  process.exit(2)
}

const SECTIONS = ['Carry forward', 'Reference pack', 'Premise', 'Type', 'Hard rules', 'Motion', 'Page structure', 'Wins if', 'Loses if', 'Scope and checks']
const problems = []

// A template slot is {words in braces}; CSS and JSON inside a brief are not.
const slots = (text) => [...text.replace(/```[\s\S]*?```/g, '').matchAll(/\{[A-Za-z][^{}\n:;]*\}/g)].map((m) => m[0])

// Body of each "## Heading", keyed by heading text.
function sections(text) {
  const out = {}
  const parts = text.split(/^## +/m).slice(1)
  for (const part of parts) {
    const nl = part.indexOf('\n')
    out[part.slice(0, nl < 0 ? undefined : nl).trim()] = nl < 0 ? '' : part.slice(nl + 1).trim()
  }
  return out
}

const bullets = (body) => body.split('\n').filter((l) => /^- +\S/.test(l) && l.replace(/^- +/, '').trim().length > 2)

const briefPath = resolve(folder, 'Brief.md')
if (!existsSync(briefPath)) {
  problems.push(`Brief.md: not found in ${folder}`)
} else {
  const text = readFileSync(briefPath, 'utf8')
  const all = sections(text)
  // A heading may extend the name ("Motion and scroll" is the Motion section).
  const found = {}
  for (const name of SECTIONS) {
    const key = Object.keys(all).find((h) => h.toLowerCase().startsWith(name.toLowerCase()))
    if (key !== undefined) found[name] = all[key]
  }
  for (const name of SECTIONS) {
    if (!(name in found)) problems.push(`Brief.md: section "${name}" is missing`)
    else if (!found[name]) problems.push(`Brief.md: section "${name}" is empty`)
  }
  for (const s of new Set(slots(text))) problems.push(`Brief.md: unfilled slot ${s}`)

  // Reference pack rows: | n | `path or URL` | borrow | not |
  const rows = (found['Reference pack'] ?? '')
    .split('\n')
    .filter((l) => /^\|\s*\d+\s*\|/.test(l))
    .map((l) => l.split('|').slice(1, -1).map((c) => c.trim()))
    .filter((c) => c[1])
  if (rows.length < 2) problems.push(`Brief.md: Reference pack has ${rows.length} filled entries; a direction needs at least two`)
  for (const [n, ref, borrow, not] of rows) {
    if (!borrow) problems.push(`Brief.md: Reference pack ${n} has no "Borrow this"`)
    if (!not) problems.push(`Brief.md: Reference pack ${n} has no "Not this"`)
    const path = (ref.match(/`([^`]+)`/) ?? [])[1]
    if (path && !/^https?:\/\//.test(path) && !existsSync(resolve(folder, path)) && !existsSync(resolve(path)))
      problems.push(`Brief.md: Reference pack ${n} points at ${path}, which does not exist`)
  }

  for (const name of ['Wins if', 'Loses if']) {
    const n = bullets(found[name] ?? '').length
    if (name in found && n < 2) problems.push(`Brief.md: "${name}" has ${n} lines; write at least two a critic can check`)
  }
  if (found.Motion && !/reduced[- ]motion/i.test(found.Motion))
    problems.push('Brief.md: Motion does not say what the page is under prefers-reduced-motion')
}

if (copy) {
  if (!existsSync(resolve(copy))) problems.push(`copy direction: ${copy} not found`)
  else {
    const text = readFileSync(resolve(copy), 'utf8')
    for (const s of new Set(slots(text))) problems.push(`copy direction: unfilled slot ${s}`)
    if (!/^Status:.*approved/im.test(text)) problems.push('copy direction: Status is not "approved by the owner"; builders use these lines verbatim')
  }
}

if (problems.length) {
  for (const p of problems) console.error(`FAIL ${p}`)
  process.exit(1)
}
console.log(`ready: ${folder}${copy ? ` with ${copy}` : ''}`)
