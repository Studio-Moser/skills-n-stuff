# Task 3 Report: Integrate readiness into triage and specs

## RED

Added a focused consumer contract before changing the five triage/spec consumers.

Command:

```sh
bats plugins/pm/tests/skill-contracts.bats
```

Result:

```text
1..2
ok 1 work-readiness reference defines the readiness rules and consumer routes
not ok 2 triage and specs consume work-readiness before design and preserve slice fields
missing triage/spec readiness contract: triage does not load work-readiness;
triage has no verification-before-spec structure; missing resumption field: Established;
missing resumption field: Unresolved; missing delivery-slice field: Outcome;
missing delivery-slice field: Blockers; missing delivery-slice field: Testing Seam;
missing delivery-slice field: Proof; scorecard does not require one delivery slice;
scorecard does not require a testing seam; evaluator does not require one delivery slice;
evaluator does not require a testing seam; XL flow does not create child slices under a goal epic
```

The reference contract remained green, proving the failure was in its consumers.

## Change

- Moved bug verification to Phase 2 before classification, brainstorming, and design.
- Added persistent `Established` and `Unresolved` notes and prevented unresolved causal
  hypotheses from selecting an implementation approach.
- Required the spec fields `Outcome`, `Blockers`, `Testing Seam`, and `Proof` while
  keeping their definitions in `references/work-readiness.md`.
- Required every agent-ready item to represent one delivery slice. XL parents become
  goal epics with independently written and scored child slices and blocking edges.
- Added a readiness gate that numeric scores and ownership overrides cannot bypass.
- Passed labels and an explicit bug-claim signal to the scorecard evaluator.
- Limited Phase 3 writes to inline spec fixes; Phase 4 retains status, owner, and verdict
  writes.

## Review RED/GREEN

CodeRabbit's first uncommitted review found four valid integration gaps and one proposed
behavior change. Added contract assertions before fixing the valid gaps.

Second RED result:

```text
not ok 2 triage and specs consume work-readiness before design and preserve slice fields
missing triage/spec readiness contract: triage summary omits canonical spec section: Delivery Slice;
scorecard prompt does not pass the triage bug signal; evaluator input cannot identify bug claims;
Phase 3 carry-forward omits S-sized items; Phase 3 does not constrain inline-fix writes
```

After the fixes:

```text
1..2
ok 1 work-readiness reference defines the readiness rules and consumer routes
ok 2 triage and specs consume work-readiness before design and preserve slice fields
```

The remaining review suggestion would have removed the existing human override for a
numeric score outside 4-5/6. It was not applied because the binding design preserves
approval behavior; the new non-bypassable readiness gate supplies the required safety.
The second CodeRabbit review returned zero findings.

## Behavioral evaluations

Ran deterministic walkthrough checks against the consumer instructions:

```text
PASS: unverified bug (4/4 conditions)
PASS: L feature (3/3 conditions)
PASS: XL split (4/4 conditions)
```

- The unverified bug stops before design, records observed behavior separately from the
  cache-cause hypothesis, and cannot pass the readiness gate.
- The L feature has one outcome with the four required slice fields and splits any
  independent outcome into a separate item.
- The XL item becomes a goal epic whose child slices carry blocking edges and are scored
  independently; the parent is never dispatched.

## GREEN

Commands:

```sh
bats plugins/pm/tests/skill-contracts.bats
plugins/pm/tests/run-tests.sh
git diff --check
```

Result:

```text
focused contract: 2/2 passed
PM suite: 1..31, all 31 tests passed
git diff --check: no whitespace errors
```

## Changed files

- `plugins/pm/skills/triage/SKILL.md`
- `plugins/pm/references/triage-spec-flow.md`
- `plugins/pm/references/triage-scorecard.md`
- `plugins/pm/agents/scorecard-evaluator.md`
- `plugins/pm/templates/spec-template.md`
- `plugins/pm/tests/skill-contracts.bats`
- `.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-report.md`

## Self-review

- Confirmed verification precedes every design path and persists resumable evidence.
- Confirmed required field names are repeated by consumers, not their canonical
  definitions.
- Confirmed S, M, and L items and XL children reach Phase 3 while XL epics do not.
- Confirmed a failed readiness gate cannot be promoted by numeric or owner override.
- Confirmed no Task 4 execution behavior or unrelated files changed.
