# Work readiness

This reference defines when an item is ready to specify, schedule, or assign for
development. It is the source of truth for the PM terms below; consumers require its
fields without redefining them.

## Consumer pointers

| Consumer | Load this reference when |
| --- | --- |
| `skills/triage/SKILL.md` | Verifying a bug claim and creating an M/L/XL spec. |
| `skills/sprint-dev/SKILL.md` | Selecting ready work and proposing execution batches. |
| `skills/dev-task/SKILL.md` | Turning an approved item into an implementation assignment. |
| `harness:execute` | Receiving an assignable PM delivery slice as a Harness Request. |

## Harness boundary

PM decides whether a slice is assignable and supplies its Outcome, Blockers, Testing
Seam, current Proof, relevant files, and development constraints. Put those values in
the `context`, `constraints`, and `verification` fields defined by the
[Harness contract](../../harness/references/harness-contract.md) and
[handoff reference](../../harness/references/handoff.md).

Harness owns authority enforcement, execution, and universal evidence semantics. PM
consumes the returned status, artifacts, blockers, and evidence under the
[Harness verification contract](../../harness/references/verification.md); it does not
change readiness fields based on concrete execution details.

## Verified claims

Treat a reported problem as a claim until evidence establishes it. Record separately:

- **Observed behavior**: what a reporter or reproduction actually shows.
- **Correlation**: a condition that appears with the behavior but does not establish why it occurs.
- **Hypothesis**: a proposed explanation that may direct investigation but cannot choose the implementation approach.
- **Confirmed cause**: an explanation supported by a reproduction, failing test, trace, or inspected code path.

Use `Established` for evidence that is confirmed and `Unresolved` for claims, gaps, or hypotheses still needing investigation.

### Completion conditions

A bug can enter a spec only after its observed behavior is verified or the item explicitly records why verification is impractical. An unresolved hypothesis must not become a chosen approach.

## Testing seams

A testing seam is the highest stable boundary where a delivery outcome can be proved. A plan should prefer an existing seam over adding a lower-level check. An executable test, reproducible scenario, API boundary, UI flow, migration fixture, or equivalent check can serve as that seam. Name the seam before implementation, including the procedure and expected result. If the selected seam is lower than an existing stable boundary or must be newly added, the `Testing Seam` value includes the concrete reason.

### Completion conditions

Every M/L/XL delivery slice names one testing seam. A slice is not complete without recorded proof from that seam, or an explicit statement that proof is unproven and why.

## Delivery slices

A delivery slice is one independently deliverable, verifiable outcome. It carries:

- **Outcome**: the user- or system-visible result.
- **Blockers**: the prerequisite slices or facts, or `none`.
- **Testing seam**: the check that proves the outcome.
- **Proof**: PM's record of the executed check and Harness evidence for the slice.

Each proposed pull request completes one delivery slice. Multiple items may share a
pull request only when they are required steps for that same outcome; separate outcomes
remain separate slices even when they touch the same domain or files.

### Completion conditions

A slice is ready to start only when its blockers are resolved and its outcome and testing seam are named. It is complete only when its outcome is delivered and its proof is recorded.

## Blocking edges and frontiers

A blocking edge `A -> B` means B cannot produce its outcome until A is complete. The unblocked frontier is every ready slice whose blockers are resolved and whose outcome and testing seam are named. The execution pool is the unblocked frontier; retain blocked slices for reporting but do not dispatch them. Select work from that frontier before considering batch shape.

Shared files are scheduling collisions: order the colliding slices or isolate their changes. They do not automatically make the slices one outcome or one pull request.

Before parallel dispatch, confirm that neither slice consumes the other slice's outcome
and that there is no shared mutable contract, persisted state, or exclusive environment.
File isolation resolves file collisions only. Unknown semantic independence requires
sequential execution.

### Completion conditions

Before dispatch, each proposed slice has explicit blockers and the selected work is on the unblocked frontier. A collision has an ordering or isolation decision, not forced batching.
Each proposed slice records a parallel-safety decision.

## Wide refactors

An XL item or wide refactor is work with multiple independently deliverable outcomes, broad touch points, or an upgrade path that cannot be proved as one slice. Create a goal epic and split it into agent-ready child delivery slices with blocking edges. Use the expand → migrate callers in green batches → contract sequence: add the compatible path, move callers with passing proof in each batch, then remove the old path only after all callers have migrated.

### Completion conditions

Do not dispatch a wide refactor as one implementation assignment. The epic is complete only when each child slice has delivered its outcome and recorded its proof.
