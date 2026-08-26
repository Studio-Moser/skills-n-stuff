# Review proof

This reference is the source of truth for PM's development review axes, Blast Radius
triggers, and PM completion conditions. Harness owns the fixed target, authority,
review execution, and universal evidence semantics.

## Consumer pointers

| Consumer | Load this reference when |
| --- | --- |
| `agents/code-reviewer.md` | Building any PM review request. |
| `skills/dev-task/SKILL.md` | Entering the review gate. |
| `skills/sprint-dev/SKILL.md` | Beginning the fixed-target check for a PR. |
| `harness:review` | Executing the provider-neutral review request against its fixed target. |

## Harness boundary

PM supplies the exact review target, approved requirements, relevant files, Testing
Seam proof, and the Quality, Spec Fidelity, and Blast Radius constraints in a complete
Harness Request. Use the
[Harness contract](../../harness/references/harness-contract.md) for request/result and
authority fields, [Harness review](../../harness/skills/review/SKILL.md) for fixed-target
execution, and [Harness verification](../../harness/references/verification.md) for
evidence levels, invalidation, and parent reverification.

PM does not approve a changed target or reinterpret an unproven Harness Result. It
submits a new review request whenever Harness reports that the target or oracle changed.

## Review axes

One reviewer reports each applicable axis separately so evidence on one cannot hide a
failure on another.

### Quality

Inspect the fixed-point diff and affected paths for correctness, regressions, security,
edge cases, error handling, performance, maintainability, and adequate tests. Reproduce
the relevant verification instead of accepting an implementer's claim.

### Spec Fidelity

Compare the fixed-point diff with the approved issue, plan, or acceptance criteria.
Report missing or partial requirements, unrequested behavior, and implementations that
do not match the stated requirement. State when no spec is available.

### Blast Radius

Apply this axis when the fixed-point diff changes any of these contracts:

- Persisted data, schema, or migration behavior.
- Public API, protocol, wire format, or serialization behavior.
- Authentication, authorization, permissions, or another security boundary.
- Shared runtime, dependency, build, deployment, or configuration behavior.

For every matched trigger, name the central safety assumption whose failure would harm
existing data, callers, users, deployments, or recovery. Require evidence aimed at that
assumption, not only a green general suite. If no trigger matches, record the axis as
not applicable.

## Harness evidence

Record the Harness Result's fixed target, decisive checks, evidence outcome, and
blockers beside the PM axis report. PM may require additional checks aimed at a Blast
Radius assumption, but their evidence classification and acceptance follow the linked
Harness verification contract. A missing check stays visible as a PM review blocker.

### Reviewer Input Set

Give the reviewer only the approved requirements, immutable fixed target and exact
artifact, relevant project files, and current Testing Seam proof. Exclude builder reasoning,
summaries, proposed verdicts, and prior review conclusions; they are claims, not reviewer
inputs or evidence.

At least one decisive check must contain a positive acceptance signal that exercises or
observes the expected behavior. A missing or skipped check, or one that runs zero relevant cases,
is unproven even when its process exits zero. Empty output supports proof only when emptiness is
the explicit oracle and the actual status/output is recorded.

## Completion conditions

Review is complete only when Harness returns current proven evidence for the requested
fixed target; Quality and Spec Fidelity are reported; every triggered Blast Radius
entry names its central safety assumption and required check; PM reproduces the
relevant verification with a positive acceptance signal; and every blocker is resolved or disputed
with evidence. Any unproven assumption or changed target requires a new Harness review request.
