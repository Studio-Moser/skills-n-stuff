# Direction 01: Ledger

Status: exploring
Phase: wide
Folder: `docs/Design Directions/01 Ledger` · Canvas: `Acme · 01 Ledger`
Brief: `docs/Identity Brief.md`. Nothing here overrides it.
Siblings: none built yet.

## Carry forward

None; this is the direction's first round.

## Reference pack

| # | Reference | Borrow this | Not this |
| --- | --- | --- | --- |
| 1 | `References/01 Annual Report.txt` | Figures set as the page's structure | The report's two-column grid |
| 2 | `https://example.com/ledger` | A single ruled baseline that every section hangs from | Its monospace face |

## Premise

The page is a ledger: every claim is an entry with a figure and a source.

**Why this is not a dashboard.** Nothing updates and nothing is a chart.

## Type

Shortlist only in this phase: one grotesque for figures, one text serif.

## Hard rules

1. **Every figure has a source line.** Stops unsupported claims.

## Motion

Entries rule in on scroll. Under `prefers-reduced-motion` the page is the same
ledger, fully ruled, in flow.

## Page structure

Hero entry, proof entries, contact. The order within proof is the builder's call.

## Wins if

- A figure is the largest element on the first screen at both widths.
- Every section hangs from the same ruled baseline.

## Loses if

- A card grid appears anywhere (rule 1 not held).
- A figure appears without its source line (rule 1 not held).

## Scope and checks

Homepage only. A variant writes its own file and nothing else.
