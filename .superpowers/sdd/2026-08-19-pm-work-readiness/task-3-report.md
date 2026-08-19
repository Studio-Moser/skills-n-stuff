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

## Fix Round 1

### Findings addressed

- **I1:** Readiness notes are staged in session memory, displayed in full, and written
  only after explicit confirmation. Editing repeats the display-and-confirm gate; skip
  leaves the item unchanged.
- **I2:** GitHub, local, and Trello now have backend-specific XL parent conversion,
  child creation, initial state, relationship, blocker-ID, and Phase 3 return paths.
  Existing parent relationships are idempotent in Phase 4.
- **I3:** The scorecard requires the highest stable existing boundary or a concrete
  reason for a lower or new seam. The temporary extra field was removed in Fix Round 2.
- **I4:** The template and spec flow expose canonical field names with `{value}` only.
  Their meanings remain in `references/work-readiness.md`; the prior Proof and Blockers
  guidance was removed.
- **M1:** Focused structural contracts cover each defect with whitespace-insensitive
  checks where Markdown wrapping is irrelevant. Behavioral execution is separate.

### RED

Command:

```sh
bats plugins/pm/tests/skill-contracts.bats
```

Initial result after adding the fix-round contracts:

```text
1..5
ok 1 work-readiness reference defines the readiness rules and consumer routes
ok 2 triage and specs consume work-readiness before design and preserve slice fields
not ok 3 readiness notes require explicit approval before persistence
readiness-note approval contract missing: stage; approval prompt; confirmed persistence
not ok 4 XL splitting has executable procedures for every triage backend
incomplete XL backend contract: GitHub, Local, Trello procedures and child IDs missing
not ok 5 spec consumers enforce seam selection without redefining readiness fields
invalid seam/field consumer contract: canonical pointer and Seam Selection missing;
scorecard/evaluator do not enforce the preferred seam or exception reason;
flow/template contain drifting Established, Unresolved, Blockers, and Proof guidance
```

Manual flow tracing found that Phase 4 could write an XL parent relationship a second
time. Its assertion failed before the idempotency rule was added:

```text
not ok 1 XL splitting has executable procedures for every triage backend
incomplete XL backend contract: shared flow does not make existing XL parent links idempotent
```

### GREEN

Focused structural contracts: 6/6 passed.

PM suite:

```text
1..35
all 35 tests passed
```

### Fix-round changed files

- `plugins/pm/skills/triage/SKILL.md`
- `plugins/pm/references/triage-spec-flow.md`
- `plugins/pm/references/triage-scorecard.md`
- `plugins/pm/agents/scorecard-evaluator.md`
- `plugins/pm/templates/spec-template.md`
- `plugins/pm/references/triage-github.md`
- `plugins/pm/references/triage-local.md`
- `plugins/pm/references/triage-trello.md`
- `plugins/pm/evals/PM Skill Eval.md`
- `plugins/pm/tests/skill-contracts.bats`
- `.superpowers/sdd/2026-08-19-pm-work-readiness/task-3-report.md`

### Fix-round self-review

- Verified every mutation in the note flow follows the explicit approval prompt.
- Traced XL identifiers from parent conversion through child creation, relationship
  persistence, blocker values, and the Phase 3 carry-forward list for each backend.
- Confirmed parents use `epic` only and children use the existing
  `status/needs-triage` state; no tracker state was added.
- Confirmed the template and flow contain none of the removed canonical definitions or
  the prior Proof placeholder.
- CodeRabbit review was attempted on the uncommitted fix diff but the service returned
  its free-CLI rate limit. Manual diff and flow review found and fixed the duplicate
  parent-link write described above.

## Fix Round 2

### Findings addressed

- **M1:** Bats is now described and used only as structural protection. The three Task
  3 eval cases contain complete dry-run prompts, observable pass criteria, and a
  protocol requiring a fresh-context agent to read the current skill and routed
  references before writing a result artifact. The controller will run those scenarios
  after this commit.
- **N1:** Removed the non-canonical extra seam field from every consumer. The canonical
  `Testing Seam` value carries the boundary choice and, when a lower or new seam is
  selected, its concrete rationale.

### RED

After changing the structural contracts first:

```text
1..6
ok 1 work-readiness reference defines the readiness rules and consumer routes
ok 2 triage and specs consume work-readiness before design and preserve slice fields
ok 3 readiness notes require explicit approval before persistence
ok 4 XL splitting has executable procedures for every triage backend
not ok 5 spec consumers enforce the canonical testing seam without adding fields
invalid seam/field consumer contract: flow, template, scorecard, and evaluator use a
non-canonical extra field
not ok 6 PM readiness eval defines fresh-context behavioral scenarios
invalid PM behavioral eval contract: protocol, complete prompts, pass criteria, and
artifact paths missing; eval mislabels structural checks as behavior
```

### GREEN

Commands:

```sh
bats plugins/pm/tests/skill-contracts.bats
plugins/pm/tests/run-tests.sh
git diff --check
```

Result:

```text
focused structural contracts: 6/6 passed
PM suite: 35/35 passed
git diff --check: no whitespace errors
```

Fresh-agent behavioral results are intentionally not claimed here. The controller must
run the committed prompts and inspect the observed artifacts listed in
`plugins/pm/evals/PM Skill Eval.md`.

### Fix-round self-review

- Confirmed the extra field is absent from the triage skill, spec flow, template,
  scorecard, and evaluator.
- Confirmed highest-stable-boundary selection and lower/new-seam rationale remain part
  of `Testing Seam` evaluation.
- Confirmed the eval contains no Bats commands or structural-pass claims.
- Confirmed each prompt fixes its backend, item data, evidence, approvals, requested
  output, pass criteria, and observed artifact path.
- CodeRabbit review was attempted on the uncommitted Fix Round 2 diff but remained
  rate-limited. Manual review found and fixed the prompt's artifact-write contradiction
  and assigned raw observation to the fresh agent while the controller owns grading.
