# Review proof

This reference is the source of truth for the review target, review axes, blast-radius
triggers, evidence levels, and completion conditions. Consumers load it instead of
redefining those terms.

## Consumer pointers

| Consumer | Load this reference when |
| --- | --- |
| `agents/code-reviewer.md` | Beginning any independent review. |
| `skills/codex-review/SKILL.md` | Preparing the review target and prompt. |
| `skills/dev-task/SKILL.md` | Entering the independent review gate. |
| `skills/sprint-dev/SKILL.md` | Beginning the independent check for a PR. |

## Fixed point

Pin the exact material under review before evaluating it. For committed work, record
the base and head commit SHAs. For uncommitted work, record the HEAD SHA plus an
immutable snapshot or digest covering every included change. The reviewer reports that
fixed point with the verdict.

Confirm the fixed point still matches after review checks run. Any code, schema,
configuration, or test change after pinning creates a new fixed point and reopens review.

## Review axes

One reviewer reports each applicable axis separately so evidence on one cannot hide a
failure on another.

### Quality

Inspect the fixed-point diff and affected paths for correctness, regressions, security,
edge cases, error handling, performance, maintainability, and adequate tests. Reproduce
the relevant verification instead of accepting an implementer's claim.

### Spec fidelity

Compare the fixed-point diff with the approved issue, plan, or acceptance criteria.
Report missing or partial requirements, unrequested behavior, and implementations that
do not match the stated requirement. State when no spec is available.

### Blast radius

Apply this axis when the fixed-point diff changes any of these contracts:

- Persisted data, schema, or migration behavior.
- Public API, protocol, wire format, or serialization behavior.
- Authentication, authorization, permissions, or another security boundary.
- Shared runtime, dependency, build, deployment, or configuration behavior.

For every matched trigger, name the central safety assumption whose failure would harm
existing data, callers, users, deployments, or recovery. Require evidence aimed at that
assumption, not only a green general suite. If no trigger matches, record the axis as
not applicable.

## Evidence expectations

- **Direct proof** executes the highest stable applicable seam against the central
  safety assumption and records the command or procedure, result, and artifact.
- **Supporting evidence** reduces uncertainty but does not exercise that assumption,
  such as inspection, static analysis, a fresh-install check for an upgrade path, or a
  neighboring test.
- **Unproven** means no executed evidence establishes the assumption. State the missing
  proof and treat the gap as a blocker.

Never upgrade claimed, missing, or inferred evidence to Direct proof.

## Completion conditions

Review is complete only when the fixed point remains current; Quality and Spec fidelity
are reported; every triggered Blast radius entry names its central safety assumption
and evidence level; relevant verification has been reproduced; and every blocker is
resolved or disputed with evidence. An Unproven central safety assumption prevents
approval. A changed fixed point reopens review.
