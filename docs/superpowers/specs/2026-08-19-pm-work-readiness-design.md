# PM Work Readiness Design

## Goal

Make PM turn uncertain work into independently verifiable delivery slices and require evidence for risky changes without adding parallel workflows or reviewers.

## Architecture

Two plain references own shared judgment rules. `references/work-readiness.md` defines verified claims, testing seams, delivery slices, blocking edges, frontiers, and wide refactors. `references/review-proof.md` defines fixed-point review, review axes, blast-radius triggers, evidence levels, and review completion.

PM skills keep their ordered steps and load a reference only when the relevant branch begins. Templates contain required fields without duplicating their definitions. One reviewer applies quality and spec on every review and blast radius only when a trigger matches.

## Required behavior

- Triage verifies bug claims before design and records established versus unresolved information.
- M/L/XL specs name a testing seam and delivery slices with blocking edges.
- XL work becomes agent-ready child slices under a goal epic rather than one oversized item.
- Sprint execution works the unblocked frontier. Shared files create scheduling collisions, not automatic batching.
- Reviews pin the compared range. Contract-sensitive changes prove their central safety assumption or mark it unproven.
- Ingestion separates source evidence from its proposed outcome.
- Backend-only ingest and setup procedures load only for the selected backend.
- Skill descriptions describe invocation conditions rather than summarizing workflows.

## Non-goals

No imported Matt or PStack skills, new PM commands, additional reviewer, new tracker state, broad word blacklist, or handoff system. Reconcile and codex-computer-use behavior remain unchanged.

## Verification

Deterministic Bats tests protect reference routing, frontmatter, and structural contracts. `plugins/pm/evals/PM Skill Eval.md` records five behavioral scenarios: unverified bug, L feature, XL split, colliding ready items, and schema-changing review.
