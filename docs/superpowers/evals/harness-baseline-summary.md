# Harness Baseline Summary

## Fixed revisions

- `skills-n-stuff`: `63f1c5bdf98561913961a74e38c422bf5b8513bd`
- `agents`: `a2c632cae74bad56121f18fd54b6f31bb1bae8cc`

## Snapshot boundary

The immutable local snapshot is at `${TMPDIR:-/tmp}/studio-harness-eval/baseline-snapshot/`. It contains the evaluated Machine, PM, Product Pulse, and Studio Baseline sources, plus the portable `agents` files required by the brief. It excludes the developer-resolved rubric from `agents/config/studio-moser/model-rubric.yml`, credentials, Shelby state, and `.skill-lock.json`. Versioned public rubric templates and rubric-handling source files remain because they are part of the required Machine and Studio Baseline source snapshot.

## Runners

- Bats `1.14.0` (installed with Homebrew; no product dependency changed)
- Claude Code `2.1.241`
- Machine plugin `0.5.0`
- PM plugin `0.18.0`
- Product Pulse plugin `0.4.0`

## Repository baseline

| Suite | Result |
| --- | --- |
| Machine Bats | 82 passed, 0 failed, exit 0 |
| PM Bats | 42 passed, 0 failed, exit 0 |

## Behavioral baseline

The frozen-old and no-skill configurations were launched together for every case. Local-only artifacts are below `${TMPDIR:-/tmp}/studio-harness-eval/baseline-runs/<eval-id>/{old,no-skill}/` and include `outputs/`, `transcript.md`, `timing.json`, and `grading.json`.

| Eval ID | Old | No-skill |
| --- | ---: | ---: |
| `pm-cross-vendor-implementation` | 0/1 | 0/1 |
| `fixed-target-independent-review` | 0/1 | 0/1 |
| `product-pulse-fanout-synthesis` | 0/1 | 0/1 |
| `standalone-computer-use` | 0/1 | 0/1 |
| `missing-rubric` | 0/1 | 0/1 |
| `missing-required-executor` | 0/1 | 0/1 |
| `missing-shelby` | 0/1 | 0/1 |
| `non-development-execution` | 0/1 | 0/1 |

Aggregate: 0 passed, 16 failed, 16 total. All 16 CLI runs exited 0; duration totaled 2059.076 seconds (128.692-second mean). The runner did not expose token counts, so no token metric is claimed.

## Known baseline failures

The behavioral expectations are deliberately Harness-owned future contracts. At this fixed revision, `plugins/harness` and its observable execution, review, computer-use, route-resolution, and typed-result behavior do not exist; the 0/16 behavioral result is therefore the baseline gap, not an exemption. No Machine or PM Bats failures were recorded.
