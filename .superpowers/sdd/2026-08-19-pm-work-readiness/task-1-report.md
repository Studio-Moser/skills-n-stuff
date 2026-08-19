# Task 1 Report: Restore the Baseline Suite

## RED

Command:

```sh
plugins/pm/tests/run-tests.sh
```

Result:

```text
exit=1
not ok 1 no bare [[ ]] assertion sits in a non-final position without || return 1
# (in test file bats-assertions.bats, line 62)
#   `[ "$status" -eq 0 ]' failed
ok 2 ...
...
ok 29 missing file gives usage
```

The guard identified three non-final bare assertions:

```text
plugins/machine/tests/render-codex-agents.bats:90
plugins/machine/tests/rubric-audit.bats:34
plugins/machine/tests/rubric-audit.bats:69
```

## Change

Added `|| return 1` to each of the three reported assertions. No other test assertions or production files were changed.

## GREEN

Commands:

```sh
plugins/pm/tests/run-tests.sh
plugins/machine/tests/run-tests.sh
```

Output:

```text
PM suite: 1..29, all 29 tests ok, PM_EXIT=0
machine suite: 1..82, all 82 tests ok, MACHINE_EXIT=0
```

Additional check:

```sh
git diff --check
```

Result: no whitespace errors.

## Changed files

- `plugins/machine/tests/render-codex-agents.bats`
- `plugins/machine/tests/rubric-audit.bats`
- `.superpowers/sdd/2026-08-19-pm-work-readiness/task-1-report.md`

## Self-review

- Confirmed the patch matches the guard's three reported locations exactly.
- Confirmed final-position bare `[[ ... ]]` assertions were left unchanged because their status already determines the test result.
- Confirmed no unrelated files are modified and `git diff --check` passes.
- Confirmed both required suites pass after the change.
