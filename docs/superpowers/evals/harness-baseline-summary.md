# Harness Old/New Evaluation Summary

## Fixed revisions and artifact boundary

- Frozen old `skills-n-stuff`: `63f1c5bdf98561913961a74e38c422bf5b8513bd`
- Candidate starting revision: `3deb5d7f4915de916fcc36d41999bac7f72129f0`
- Frozen `agents`: `a2c632cae74bad56121f18fd54b6f31bb1bae8cc`

The immutable Task 1 snapshot remains at
`${TMPDIR:-/tmp}/studio-harness-eval/baseline-snapshot/`. Task 9 runs, grading,
aggregates, viewer, comparator/analyzer output, and trigger results stay below
`${TMPDIR:-/tmp}/studio-harness-eval/`; they are not committed. Local artifacts
exclude credentials, mutable Shelby state, and the developer-resolved rubric.
This summary contains no raw transcript or personal route values.

## Method

All eight Task 1 IDs, prompts, and expected outputs were preserved. Each final
case ran current and frozen old with the same eval definition, plan-mode
isolation, Claude Code `2.1.241`, and Claude Opus executor and grader. All 16
executors exited successfully. The official grader, aggregator, static viewer,
blind comparator, and post-hoc analyzer were used.

The initial compound assertions scored current `3/8` and old `4/8`. The analyzer
found seven of eight nondiscriminating and showed that compound pass/fail erased
partial behavior. The scenarios stayed exact; three or four granular ownership,
routing, authority, and proof assertions were added, then both sides were rerun.

## Final behavioral comparison

| Eval | Current | Frozen old |
| --- | ---: | ---: |
| `pm-cross-vendor-implementation` | 1/4 | 1/4 |
| `fixed-target-independent-review` | 3/4 | 0/4 |
| `product-pulse-fanout-synthesis` | 3/4 | 0/4 |
| `standalone-computer-use` | 2/4 | 2/4 |
| `missing-rubric` | 3/3 | 1/3 |
| `missing-required-executor` | 3/3 | 2/3 |
| `missing-shelby` | 2/4 | 2/4 |
| `non-development-execution` | 2/4 | 2/4 |
| **Total** | **19/30** | **10/30** |

| Official mean per eval | Current | Frozen old | Delta |
| --- | ---: | ---: | ---: |
| Assertion pass rate | 65.62% | 34.38% | +31.24 pp |
| Total time, executor plus grader | 435.72 s | 345.18 s | +90.54 s |
| Executor time only | 177.02 s | 151.29 s | +25.73 s |
| Processed tokens | 500,589 | 398,530 | +102,059 |
| Tool calls | 19.38 | 16.13 | +3.25 |
| Executor errors | 0 | 0 | 0 |

Human review was stricter than partial-credit grading: current had sound
terminal behavior in 2/8 cases (`missing-rubric` and
`missing-required-executor`); old had 0/8. Other current runs were plans or
lacked the delivered artifact/proof. Product Pulse also inspected Harness
control-plane material instead of invoking the named skill. A grader pass never
overrode visible failure.

The initial blind comparator preferred current in 5/8 cases and old in 3/8. The
corrected analyzer attributed real current advantages to review isolation and
typed capability blockers, and real gaps to an incoherent taste route,
incomplete terminal results, Product Pulse leakage, and non-code lifecycle
drift. Shared confounds were plan-only runs, underspecified targets, and one run
per configuration.

## Evidence-backed fixes

- `taste` now resolves through exact `routing.taste`, derived during setup from
  reachable rows at or above `routing.taste_min`; the minimum is not a runtime
  route.
- Execute requires a complete typed result on every terminal path and keeps
  bounded non-code work outside branch, PR, tracker, and automated-test
  lifecycles unless requested.
- Daily, weekly, and deep-dive Product Pulse instructions invoke the named
  Harness skill and prohibit reading, resolving, or repairing its control plane.
- Review and computer-use descriptions changed only after held-out improvement.
  Setup, execute, and Daily Research retained their original descriptions.

No PM behavior changed: the run correctly reported that no ready slice existed
rather than inventing one.

## Trigger evaluation

Each tracked set has 20 manually reviewed unique queries: 10 positive and 10
near-miss negative. The official optimizer used a fixed 60/40 split, three Opus
repetitions, threshold `0.5`, and at most five iterations. Scores are query-level
train/held-out passes.

| Family | Original | Selected | Change |
| --- | ---: | ---: | --- |
| Setup | 12/12, 8/8 | 12/12, 8/8 | none |
| Execute | 10/12, 6/8 | 10/12, 6/8 | none |
| Review | 9/12, 6/8 | 12/12, 8/8 | applied |
| Computer use | 9/12, 6/8 | 10/12, 7/8 | applied |
| Daily Research boundary | 11/12, 8/8 | 11/12, 8/8 | none |

Claude Code `2.1.241` exposes the evaluator's temporary `.claude/commands`
fixture as a slash command, not an auto-triggerable skill. An unmodified probe
therefore stayed at 50% with zero positive activations. A temporary compatibility
copy changed only the fixture location to
`.claude/skills/<stable-name>/SKILL.md` and disabled session persistence. Split,
repetitions, model, threshold, optimizer, and schemas stayed official; the copy
is not tracked.

## Verification and limits

| Suite | Final result |
| --- | ---: |
| Harness Bats | 116 passed, 0 failed |
| PM Bats | 49 passed, 0 failed |
| Product Pulse Bats | 9 passed, 0 failed |

The aggregate is comparative evidence for this fixed environment, not a general
success rate. With one run per configuration, standard deviations measure
dispersion across eight scenarios, not repeat variance. Plan mode prevents
claims that execution-heavy cases delivered their artifacts. The full
multi-plugin Product Pulse run still failed to auto-invoke Harness despite the
consumer boundary fix; that remains an integration trigger concern, not grounds
to broaden a description that held 8/8 on its targeted held-out set.
