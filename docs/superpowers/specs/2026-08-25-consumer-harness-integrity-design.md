# Consumer Harness Integrity Design

## Goal

Make PM delivery acceptance and Product Pulse research synthesis fail closed when proof
or branch coverage is incomplete, without expanding the Harness core or adding another
orchestration layer.

## Architecture

Harness keeps its current request/result contract. PM and Product Pulse tighten only
the consumer rules they already own:

- PM decides whether review evidence proves a delivery slice, limits correction loops,
  and decides whether ready slices are semantically safe to run concurrently.
- Product Pulse records the outcome of every research branch before synthesis and makes
  degraded coverage visible to both the synthesizer and the reader.

Both consumers reuse the existing Harness Result fields: `status`, `evidence.checks`,
`evidence.outcome`, `telemetry.elapsed`, and `blockers`. No new field or adapter is
required.

## Delivery Harness Requirements

1. At least one decisive check must contain a positive acceptance signal that exercises
   or observes the expected behavior. A missing or skipped check, or one that runs zero
   relevant cases, cannot establish proof. Empty output counts only when emptiness is
   the explicit oracle and the actual status/output is recorded.
2. The Reviewer Input Set contains only approved requirements, the immutable target and
   exact artifact, relevant project files, and current testing-seam proof. Builder
   reasoning, summaries, proposed verdicts, and prior review conclusions are claims,
   not reviewer inputs or evidence.
3. `pm:dev-task` permits at most two fix/review rounds after the initial review. Any
   remaining issue is a visible blocker; it does not trigger a third correction round.
4. Before PM schedules two slices concurrently, it confirms that neither consumes the
   other's outcome and that they do not share a mutable contract, persisted state, or
   exclusive environment. File isolation resolves file collisions only. Unknown
   semantic independence means sequential execution.

## Research Harness Requirements

1. Before synthesis, each Product Pulse workflow builds a branch manifest containing
   one row for every expected research input branch. Each row records branch identity,
   Harness status, evidence outcome, blockers, and elapsed time when available.
2. Only `status: accepted` plus `evidence.outcome: proven` and reproduced verification
   may contribute research content. Every other expected branch remains in the manifest
   and is excluded from claims.
3. The synthesis request receives the complete manifest. Coverage counts a branch as
   accepted only when its status is accepted and its evidence is proven; an
   accepted/unproven result is reported separately as unproven. If accepted/proven
   branches are fewer than expected, the draft and final report say coverage is
   degraded and never describe a missing branch as scanned, researched, or covered.
4. Daily expects one branch per configured domain. Weekly expects its five analyst roles
   plus any required adjudications. Deep dive expects every scheduled resource,
   concept-bundle, and adjudication branch that can feed synthesis.

## File Budget

Delivery changes modify six existing files:

- `plugins/pm/references/review-proof.md`
- `plugins/pm/references/work-readiness.md`
- `plugins/pm/skills/dev-task/SKILL.md`
- `plugins/pm/skills/sprint-dev/SKILL.md`
- `plugins/pm/tests/skill-contracts.bats`
- `plugins/pm/evals/PM Skill Eval.md`

Research changes modify four existing files:

- `plugins/product-pulse/skills/daily-research/SKILL.md`
- `plugins/product-pulse/skills/weekly-strategist/SKILL.md`
- `plugins/product-pulse/skills/deep-dive/SKILL.md`
- `plugins/product-pulse/tests/harness-boundary.bats`

There are no new implementation files.

## Non-goals

Do not change Harness schemas, routes, adapters, or result semantics. Do not add a DAG
runtime, graph DSL, shared orchestration reference, retry engine, telemetry store, or
dependency. Do not modify Shelby. Defer GitHub write readback, model-upgrade ablations,
deep-dive preparation parallelism, and additional timing aggregation.

## Verification

Use fresh-context pressure scenarios to establish behavioral RED and GREEN evidence.
Use existing Bats suites for deterministic structural contracts. Run the complete PM,
Product Pulse, and Harness suites before claiming the combined refinement is ready;
Harness should remain unchanged and its suite protects that boundary.
