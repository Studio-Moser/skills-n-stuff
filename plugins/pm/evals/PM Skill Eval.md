# PM Skill Eval

Behavioral pressure scenarios for PM workflow changes. Record the initial failure before changing a consumer and record the passing result after integration.

## Unverified bug triage

**Scenario:** A report says a recent cache change causes duplicate invoices. The report includes the visible duplicate behavior and a suspected cache invalidation cause, but no reproduction or code-path evidence.

**Baseline failure:** The current flow can turn the suspected cause into a complete, passing spec before checking the behavior. Its scorecard can award 6/6 to that speculative spec.

**Pass condition:** Triage records the duplicate invoices as observed behavior, keeps cache invalidation unresolved unless evidence confirms it, and verifies the behavior before choosing an implementation approach or marking the item ready.

**Reproducible check:**
`bats --filter "readiness notes require explicit approval" plugins/pm/tests/skill-contracts.bats`

## L feature

**Scenario:** An L-sized account-export feature has an existing UI-to-download flow that
can prove its user-visible outcome. A draft plan proposes several implementation chunks
and a new lower-level unit-test seam.

**Baseline failure:** The old spec shape can accept the chunks without one delivery
slice, explicit blockers, or any reason for ignoring the existing stable flow.

**Pass condition:** The spec contains one delivery slice and all required readiness
fields. It selects the highest stable existing boundary, or records a concrete reason
for choosing a lower or new seam.

**Reproducible check:**
`bats --filter "spec consumers enforce seam selection" plugins/pm/tests/skill-contracts.bats`

## XL split

**Scenario:** An XL identifier migration must expand a compatible schema, migrate
callers in green batches, and contract the old path only after every caller moves.

**Baseline failure:** The old flow can leave the XL item as one oversized assignment
and does not define how any backend creates, links, or returns its child identifiers.

**Pass condition:** Triage creates a goal epic and blocker-first child slices. GitHub,
local, and Trello each preserve their existing needs-triage state, record the epic
relationship, and return child identifiers for independent scoring.

**Reproducible check:**
`bats --filter "XL splitting has executable procedures" plugins/pm/tests/skill-contracts.bats`

## Colliding sprint items

**Scenario:** Items A and B deliver different user outcomes but both touch `Sources/AppState.swift`. Item C depends on A.

**Baseline failure:** The current sprint flow forces A and B into one pull request because they share a file, while C has no blocker field and can be selected in parallel with A.

**Pass condition:** The plan records `A -> C`, selects A and B only if both are on the unblocked frontier, and treats the shared file as a sequencing collision rather than an automatic batch.
