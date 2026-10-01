# Round {N}: {short name}

Date: {YYYY-MM-DD}
Frozen brief: `{path}` (signed {date})
Variant build brief: `{path}`
Medium: html | code
Review: Figma file `{URL}`, pages served at `{server address, e.g. http://localhost:3000}` | gallery `http://127.0.0.1:4600/direction/<NN Name>`
Critic: explore | none
Cap: 7 variants

## Why this round

One paragraph. What the last round taught (point at its Carry forward lines),
and what this round is trying to see. Not what it should conclude.

## Variants

| id | direction | copy | method | route | dials | borrows from |
| --- | --- | --- | --- | --- | --- | --- |
| e | `{directions dir}/03 Ledger` | `{copy dir}/02 Proof First` | impeccable | fable | | Ledger § Reference pack 1, 3 |
| f | `{directions dir}/03 Ledger` | `{copy dir}/02 Proof First` | taste | taste | V9 M7 D3 | Ledger § Reference pack 2 |
| g | `{directions dir}/04 Field` | `{copy dir}/02 Proof First` | frontend-design | default | | Field § Reference pack 1, 2 |

Column rules:

- `method` is exactly one installed design skill, or `none`. Stacking is not
  allowed; two skills make a variant unattributable.
- `route` is a Claude model alias (`fable`, `opus`, `sonnet`) for a local
  subagent, or a Harness semantic route (`taste`, `default`, `bulk`) for a
  delegated builder. Never a raw provider model ID.
- `dials` applies to the `taste` method only: DESIGN_VARIANCE, MOTION_INTENSITY,
  VISUAL_DENSITY, 1 to 10 each.
- Two rows that differ only in `route` are an ablation. Say so in "Why this
  round" so the owner reads them as a pair.

## Results

Filled by `design:fan-out` when the round finishes. One block per variant.

### {id}: {title the builder gave it}

- Method: {skill} · Model: {resolved model@effort} · Route: {semantic route or alias}
- Argues: {one line from the builder's report}
- File or route: `{Homepage X - Title.html}` or {preview URL}
- Page address: {the address stored on its Figma frame} · Figma frame: `{node id}`
- Builder self-review passes: {n}, {what each changed, one clause each}
- Critic (explore): {k} fails remaining, or clean
- Builder's note: {anything the builder flagged, verbatim}
