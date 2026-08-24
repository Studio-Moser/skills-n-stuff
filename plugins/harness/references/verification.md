# Verification

Verification turns an execution or review claim into current evidence against a
fixed artifact. It is independent of the provider or executor.

## Fixed target

Before review or reverification, identify the exact commit or immutable snapshot
under test and record it as `evidence.fixed_target`. Worker summaries, exit zero,
and old logs are claims. The parent or accepting workflow reproduces the highest
stable observable seam against the returned artifact.

If the target changes, prior proof is invalid. If the oracle changes—the
expected result, verification seam, fixture, or acceptance procedure—prior proof
is also invalid. Reopen verification and record fresh results.

## Evidence levels

- `direct proof`: a current check observes the requested outcome at the stated
  seam on the fixed target. This can support `evidence.outcome: proven`.
- `supporting evidence`: a current check increases confidence but does not
  observe the outcome at the seam. Supporting evidence alone remains unproven.
- `unproven`: no valid current direct proof establishes the outcome. Record
  `evidence.outcome: unproven` and keep the gap visible.

Evidence records the command or procedure and its actual, decisive result. Keep
output bounded and reproducible; do not substitute a worker's interpretation for
the result.

## Acceptance gate

`accepted` requires both the delivered outcome and
`evidence.outcome: proven`. A passing subordinate check does not override a
failed outcome check. A blocked or impossible requirement remains in `blockers`
with `blocked` or `abandoned` status; never silently shrink the requested scope.
