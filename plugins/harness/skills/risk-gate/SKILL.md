---
name: risk-gate
description: >-
  Use before implementing repository work only when it touches a security or money
  boundary, persisted data or schema, a public contract, multiple repositories, has no
  stable testing seam, is expected to outlive the current context window, or the user
  explicitly requests planning, delegation, managed execution, or independent review.
  Do not use for ordinary bounded repository work.
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

- **Direct:** no trigger matches. The current agent implements and runs one
  task-appropriate proof pass.
- **Structured:** a trigger matches. State the matched trigger, bounded outcome,
  authority, testing seam, and recovery point before implementation. The current agent
  still implements by default.
- **Independent review:** require a fresh reviewer for authentication, payment,
  destructive persistence or migration, public compatibility changes without complete
  contract coverage, subjective user-facing work without deterministic proof, or an
  explicit request for independent review. Other structured work uses self-review and
  its testing seam.

Delegation is separate from classification. Delegate only one independently useful
substantial track with its own outcome and verification seam. Small tool calls,
mechanical edits, and work that needs the parent context stay with the current agent.

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

Return only: mode, matched triggers, testing seam, delegation decision and limits, and
review decision.
