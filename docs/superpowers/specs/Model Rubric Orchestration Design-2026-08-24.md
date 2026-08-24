# Model Rubric Orchestration Design

**Date:** 2026-08-24
**Status:** Proposed
**Change class:** Feature

## Problem

The current model rubric treats `default` as both the everyday model and a
delegated execution route. That collapses two different economic decisions:

1. which model should hold the user conversation, make judgment calls, and
   coordinate work; and
2. which model should consume the much larger execution token volume.

It also scores `cost` from token price, quota, or latency without preserving the
benchmark evidence needed to judge completed work per dollar. A cheap token is
not cheap work when a model uses more tokens, takes more steps, or fails often.

For Tim's configuration, Fable is the preferred orchestrator even though its
published task cost is high. It produces more usable orchestration than Opus in
practice and can conserve its subscription quota by delegating execution to
Codex models. Opus remains eligible, but must not outrank Fable for orchestration
solely because a coding benchmark reports a lower cost.

Harness is distributable, so this preference cannot become a universal
Claude-plus-Codex assumption. Setup must derive a valid rubric from each user's
actual executors, including a single-provider installation.

## Decision

Separate orchestration preference from delegated-work routing, and ground
implementation efficiency in completed benchmark work rather than list token
prices.

The rubric will retain one `routing` map and add an explicit `orchestrator` key.
The remaining keys continue to represent delegated semantic routes:

```yaml
routing:
  orchestrator: claude-fable-5@high
  default: gpt-5.6-sol@medium
  bulk: gpt-5.6-terra@high
  quick: gpt-5.6-sol@low
  explore: claude-sonnet-5@high
  batch: gpt-5.6-luna@max
  taste: claude-fable-5@high
  review: claude-fable-5@high
  independent: gpt-5.6-sol@high
  fallback: claude-opus-5@high
```

These values illustrate Tim's intended rubric, not distributable defaults.
Setup may emit only keys it can satisfy, except `orchestrator`, `default`,
`quick`, and `review`, which every completed rubric must resolve. A single
reachable model may satisfy all four. `bulk`, `explore`, `batch`, `taste`,
`independent`, and `fallback` are optional.

`orchestrator` expresses the preferred model for the top-level session. It does
not authorize a running agent to replace itself. A runtime that can select the
top-level model uses it when starting the session; a runtime that cannot switch
reports the preference as advisory and still uses the delegated routes normally.

`fallback` is an eligible general fallback, not an automatic escalation. The
existing Harness rule still applies: fallback must be explicitly authorized by
the request or caller. Tim's fallback may be Opus while Fable remains his
preferred orchestrator.

## Economic Evidence

Each model-effort row may carry a benchmark observation:

```yaml
- name: gpt-5.6-sol
  effort: medium
  provider: openai
  via: codex
  intelligence: 8
  taste: 8
  trust: 8
  efficiency: 8
  benchmark:
    suite: deepswe
    version: "1.1"
    observed: 2026-08-24
    pass_at_1: 0.611
    mean_task_cost_usd: 1.86
    cost_per_success_usd: 3.05
    mean_output_tokens: 18000
    mean_duration_seconds: 426
```

`cost_per_success_usd` is derived as:

```text
mean_task_cost_usd / pass_at_1
```

This is a comparative benchmark measure, not a promise about a user's bill or
the cost of a different workload. Provider prices remain evidence used by the
benchmark calculation; they do not directly determine a route.

The old overloaded `cost` score becomes `efficiency`: a 1–10 judgment informed
by cost per successful task, token consumption, duration, and the user's billing
constraints. Setup preserves the underlying benchmark fields so the score can
be audited. Subscription quota and latency remain relevant because they are real
constraints, but they no longer erase completion efficiency.

Benchmark evidence is workload-specific:

- DeepSWE governs delegated software implementation economics.
- It informs but does not decide orchestration, taste, exploration, or review.
- `trust` and `taste` are user-owned constraints. They may override benchmark
  rank when correction burden or subjective quality makes a nominally efficient
  model worse in practice.
- Missing benchmark data is explicit. Setup uses provider evidence plus user
  judgment and does not invent numeric observations.

## Capability-Driven Setup

`harness:model-rubric` continues to verify CLI-backed capabilities with
`command -v` and receives the current runtime inventory from `harness:setup`.
It then follows this order:

1. Build candidate model-effort rows only from reachable native runtimes,
   external executors, and provider access the user confirms.
2. Collect billing constraints, trust, taste, and orchestrator preference.
3. Add current benchmark observations where the workload applies.
4. Remove every row whose provider or `via` executor is unavailable.
5. Select `orchestrator` from trusted reachable rows.
6. Derive delegated routes from the remaining rows under capability, authority,
   benchmark-efficiency, latency, taste, and independence constraints.
7. Validate every emitted route against an exact `(name, effort)` row.

The setup procedure must not require Claude, Codex, multiple providers, or an
independent-review route. Expected degradation is:

- **Claude and Codex:** prefer the user's trusted orchestrator; use cross-provider
  delegation where it improves the whole workflow.
- **Claude only:** choose a Claude orchestrator and derive all required routes
  from reachable Claude rows. Omit `independent` unless another provider exists.
- **Codex only:** choose a reachable Codex row for orchestration and required
  routes. Omit Claude-native assumptions such as a required native `explore`.
- **One reachable model-effort row:** reuse it for all required routes and omit
  optional routes. The rubric is valid, though not diversified.
- **No reachable row:** setup is blocked and writes no apparently valid rubric.

No route may silently point at an unavailable executor. Provider diversity is an
optimization and independence capability, never a setup prerequisite.

## Routing Behavior

Harness consumers still request semantic delegated routes and never name a
provider. `execute`, `review`, and `computer-use` resolve those routes exactly as
they do today.

The orchestration preference changes behavior one level above a HarnessRequest:

1. A session starts on `routing.orchestrator` when its host supports explicit
   top-level model selection.
2. The orchestrator retains the user conversation, scope, approvals, task graph,
   and final acceptance decision.
3. It sends bounded HarnessRequests through delegated routes.
4. Delegates return evidence-bearing HarnessResults.
5. The orchestrator reproduces the named proof and synthesizes the final result.

This makes Fable economical for Tim by reserving it for high-leverage context and
judgment while Codex models absorb implementation volume. It does not claim
Fable is inexpensive per benchmark task.

## Refresh and Migration

An ordinary stale-data refresh preserves user-owned capability confirmations,
trust, taste, orchestrator preference, and billing semantics. It refreshes
benchmark observations and recalculates `efficiency` plus delegated routes.

Existing rubrics without `routing.orchestrator` are migrated during the next
explicit rubric refresh or Harness setup:

1. Ask for the orchestrator preference rather than inferring it from `default`.
2. Preserve eligible model rows and user-owned scores.
3. Replace `cost` with `efficiency` after showing the new benchmark evidence.
4. Derive the full routing map from current capabilities.
5. Update `reviewed` and sources only after validation succeeds.

No background sync rewrites the rubric. `harness:sync` may flag staleness, but
`harness:model-rubric` owns migration because preferences require user input.

## Validation and Failure Handling

A completed rubric is valid only when:

- `orchestrator`, `default`, `quick`, and `review` resolve to exact model-effort
  rows;
- every emitted route resolves to a reachable provider and executor;
- every `via` value corresponds to a discovered executor;
- `independent`, when present, resolves to a provider different from the
  orchestrator or named authoring model;
- `taste`, when present, satisfies `taste_min`;
- benchmark derived values are arithmetically consistent within rounding;
- seed placeholders, null required scores, credentials, and machine paths are
  absent.

Unavailable optional capabilities cause route omission, not setup failure.
Malformed evidence, an impossible required route, or zero reachable models blocks
the write. Refresh writes through the existing config-directory symlink so the
agents repository remains the synced source of truth.

## Files Expected to Change

- `plugins/harness/skills/model-rubric/SKILL.md`: evidence collection, interview,
  capability derivation, migration, and validation procedure.
- `plugins/harness/skills/model-rubric/Default_Rubric.yml`: new row schema,
  benchmark evidence, current observations, and corrected anti-patterns.
- `plugins/harness/references/routing.md`: orchestration semantics, required and
  optional routes, and capability degradation.
- `plugins/harness/references/harness-contract.md`: recognize orchestration as a
  top-level preference while keeping delegated HarnessRequests provider-neutral.
- `plugins/harness/tests/*.bats`: schema, capability matrix, migration, benchmark
  arithmetic, and route-resolution contract coverage.
- Public Harness documentation and zero-plugin rubric setup documentation where
  they describe the old `cost` field or route set.
- Tim's synced `config/studio-moser/model-rubric.yml`, updated separately through
  `harness:model-rubric` after the plugin behavior is released and installed.

## Testing

Add focused tests before implementation for:

1. benchmark `cost_per_success_usd` validation;
2. required-route derivation with Claude plus Codex, Claude only, Codex only, one
   row only, and no rows;
3. orchestrator preference outranking benchmark efficiency;
4. Opus remaining eligible without replacing Tim's preferred Fable orchestrator;
5. omission of unavailable optional and cross-provider routes;
6. migration from the current rubric shape;
7. existing Harness contract, portability, secret-scan, and sync behavior.

The final gate is the complete Harness suite, currently 160 tests with zero
baseline failures.
