---
name: risk-gate
description: "Use before repository work touching security, money, persisted data, a public contract, several repositories, no testing seam, or more than one context window, or when the user explicitly requests planning, delegation, or review. Never for Polish or Small changes."
allowed-tools: "Read"
---

# Harness — Risk Gate

Classify orchestration from observable facts. Do not estimate complexity from prose,
file count alone, or model reputation.

## Triggers

Match a trigger when the requested change affects:

- authentication, authorization, permissions, secrets, or another security boundary;
- payment, billing, pricing, or money movement;
- persisted data, schema, migrations, destructive writes, or recovery behavior;
- a public API, protocol, wire format, serialization, or compatibility contract;
- multiple repositories or an exclusive shared environment;
- work with no stable testing seam or no positive acceptance signal;
- work expected to span a context window or require resumable state; or
- an explicit user request for a plan, managed workflow, delegation, parallel agents,
  adversarial review, or independent review.

## Decision

- **Direct:** no trigger matches. No structured workflow is needed; direct execution
  or a rubric worker uses one task-appropriate proof pass.
- **Structured:** a trigger matches. Record the matched trigger, bounded outcome,
  authority, testing seam, and recovery point internally before implementation.
- **Independent review:** require a fresh reviewer for authentication, payment,
  destructive persistence or migration, public compatibility changes without complete
  contract coverage, subjective user-facing work without deterministic proof, or an
  explicit request for independent review. Other structured work uses self-review and
  its testing seam.

Before waiving independent review for a public compatibility change, map each changed
public contract to a named assertion and its observed result. For stateful behavior,
cover each required transition (both directions for reversible states) and every
affected control, including action routing, visible state, and accessibility state
where applicable. Derive expected
outcomes from the acceptance contract, not the implementation. Planned tests and a
green suite alone do not establish complete coverage. Revisit the review decision
after verification: missing or indirect assertions remain coverage gaps; close them
with direct proof or require independent review. Keep this mapping in working notes;
report only gaps that affect the review decision.

Delegation is separate from risk classification. Use
[Execution choice](../../references/routing.md#execution-choice) to select direct
execution or one bounded rubric worker by capability, verifiability, and total cost.
Tiny edits and individual tool calls stay local. A cheaper worker never reduces
required verification or review.

## Limits

Every delegated request carries these limits unless the user sets stricter ones:

```yaml
delegation:
  max_children: 1
  max_depth: 1
  token_budget: bounded amount chosen for this track
```

Use more than one child only for multiple independent tracks authorized by the user or
an active managed workflow. Never delegate to the same active model and effort; the
Harness resolver short-circuits that route to direct execution. Stop delegation when
the budget, depth, or child limit is reached.

Keep mode, matched triggers, testing seam, delegation decision and limits, and review
decision in working state. Report only useful progress, consequential tradeoffs,
blockers, required approvals, and verification results; do not announce classification.
