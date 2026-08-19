# Task 2 Report: Add work-readiness contracts

## RED

Added `plugins/pm/tests/skill-contracts.bats` before creating the reference. The contract requires the work-readiness reference, its five rule sections, completion conditions, and routes for triage, sprint execution, and worker entry points.

Command:

```sh
bats plugins/pm/tests/skill-contracts.bats
```

Result:

```text
1..1
not ok 1 work-readiness reference defines the readiness rules and consumer routes
# (in test file plugins/pm/tests/skill-contracts.bats, line 39)
#   `[ "$status" -eq 0 ]' failed
```

The failure was expected: `plugins/pm/references/work-readiness.md` did not exist.

## Change

- Added `plugins/pm/references/work-readiness.md` as the single source of truth for verified claims, testing seams, delivery slices, blocking edges and frontiers, and wide refactors. Each rule has explicit completion conditions.
- Added consumer-routing entries for triage, sprint-dev, dev-task, and codex-implementation without changing those consumers' behavior. Their loading behavior is scoped to Tasks 3 and 4.
- Added `plugins/pm/evals/PM Skill Eval.md` with the recorded unverified-bug and colliding-sprint baseline failures and passing conditions.
- Kept the contract separate from `skill-frontmatter.bats`, per the task ruling.

## GREEN

Commands:

```sh
bats plugins/pm/tests/skill-contracts.bats
plugins/pm/tests/run-tests.sh
git diff --no-index --check /dev/null {each-task-file}
```

Result:

```text
focused contract: 1..1, 1 test passed
PM suite: 1..30, all 30 tests passed
per-task-file diff checks: no whitespace errors
```

## Changed files

- `plugins/pm/tests/skill-contracts.bats`
- `plugins/pm/references/work-readiness.md`
- `plugins/pm/evals/PM Skill Eval.md`
- `.superpowers/sdd/2026-08-19-pm-work-readiness/task-2-report.md`

## Self-review

- The contract exercises the delivered reference and fails if it or a required consumer route is removed from the reference.
- Definitions live only in the new reference; the evaluation file records behaviors rather than duplicating workflow guidance.
- No consumer skill was changed ahead of its assigned integration task.
