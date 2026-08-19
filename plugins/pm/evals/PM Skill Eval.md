# PM Skill Eval

Behavioral pressure scenarios for PM workflow changes. Record the initial failure before changing a consumer and record the passing result after integration.

## Unverified bug triage

**Scenario:** A report says a recent cache change causes duplicate invoices. The report includes the visible duplicate behavior and a suspected cache invalidation cause, but no reproduction or code-path evidence.

**Baseline failure:** The current flow can turn the suspected cause into a complete, passing spec before checking the behavior. Its scorecard can award 6/6 to that speculative spec.

**Pass condition:** Triage records the duplicate invoices as observed behavior, keeps cache invalidation unresolved unless evidence confirms it, and verifies the behavior before choosing an implementation approach or marking the item ready.

## Colliding sprint items

**Scenario:** Items A and B deliver different user outcomes but both touch `Sources/AppState.swift`. Item C depends on A.

**Baseline failure:** The current sprint flow forces A and B into one pull request because they share a file, while C has no blocker field and can be selected in parallel with A.

**Pass condition:** The plan records `A -> C`, selects A and B only if both are on the unblocked frontier, and treats the shared file as a sequencing collision rather than an automatic batch.
