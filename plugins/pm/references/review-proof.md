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
| `harness:delegate` | Executing the provider-neutral review request against its fixed target. |

## Harness boundary

PM supplies the exact review target, approved requirements, relevant files, Testing
Seam proof, and the Quality, Spec Fidelity, and Blast Radius constraints in a complete
Harness Request. Use the
[Harness contract](../../harness/references/harness-contract.md) for request/result and
authority fields, [Harness delegate](../../harness/skills/delegate/SKILL.md) for fixed-target
execution, and [Harness verification](../../harness/references/verification.md) for
evidence levels, invalidation, and parent reverification.

PM does not approve a changed target or reinterpret an unproven Harness Result. It
submits a new review request whenever Harness reports that the target or oracle changed.

## Project review contract

When the repository root contains `REVIEW.md`, include it in the Reviewer Input Set and
apply its project-specific failure modes, sensitive paths, required checks, and
exclusions. The project contract is additive: it may strengthen or focus this reference,
but it cannot weaken Harness evidence semantics, omit a required review axis, authorize
an unproven result, or expand the reviewer's authority.

If `REVIEW.md` changes after the target was fixed, the review oracle changed. Materialize
a new target and submit a new review request. If it conflicts with this reference, keep
the non-negotiable PM and Harness requirement and report the conflict as a blocker.

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

## Actionable findings

A blocking finding names its severity, file and line or narrowest location, trigger or
execution path, concrete failure mode and consequence, evidence that the reviewed
change introduced or exposed it, and a fix direction or proof needed to dispute it.
Block on actionable correctness, security, specification, or Blast Radius failures.

Do not use a numerical confidence threshold as an acceptance gate. Report a severe
concern without enough proof as an unresolved risk, not a proven defect. Omit optional
cleanup, style preferences, and speculative maintainability suggestions unless the
approved task requires them. Mark a verified pre-existing issue separately from a
regression in the fixed target. If nothing actionable remains, state `No findings`.

## Rereview convergence

The first review covers the full fixed target. After a remediation, review the delta
from the previously reviewed head and the behavior affected by that delta while retaining
unresolved earlier blockers. Verify every prior disposition, suppress repeated findings
without new evidence, and report all observed instances of one bug class together.

Stop early when neither the target nor a relevant risk changed. The two-round PM limit
stops automated correction; it never authorizes merging with residual blockers. A new
unrelated discovery becomes separate work unless it blocks the approved outcome.

### Reviewer Input Set

Give the reviewer only the approved requirements, immutable fixed target and exact
artifact, relevant project files, applicable root `REVIEW.md`, and current Testing Seam proof. Exclude builder reasoning,
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
with evidence. Every applicable `REVIEW.md` requirement must also be satisfied. Any
unproven assumption, changed target, or changed review contract requires a new Harness review request.
