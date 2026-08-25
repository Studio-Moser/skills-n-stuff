# Provider-Resilient Harness Routing Design

**Date:** 2026-08-24
**Status:** Proposed
**Change class:** Feature

## Problem

Harness currently resolves each semantic route to one exact `model@effort` row.
The rubric may name one generic `routing.fallback`, but that value is neither
route-specific nor standing authorization. A consumer must authorize a repair
after the selected provider or executor is already unavailable.

This fails in normal subscription use. A taste request can resolve to Claude
while the Anthropic subscription is temporarily out of usage, even though a
reachable Codex row still satisfies the developer's taste floor. Repeating the
request retries the same unavailable provider, and teaching Product Pulse or PM
to select another provider would violate Harness's control-plane boundary.

Harness needs deterministic, cross-provider fallback that preserves semantic
quality and authority, avoids repeatedly probing a known-unavailable endpoint,
and automatically returns to the preferred provider after it recovers.

## Decision

Add ordered fallback chains per semantic route, one deterministic route
resolver, and a machine-local availability circuit breaker.

The primary route remains backward-compatible:

```yaml
routing:
  orchestrator: claude-fable-5@high
  default: gpt-5.6-sol@medium
  bulk: gpt-5.6-terra@high
  taste_min: 9
  taste: claude-fable-5@high
  review: claude-fable-5@high

fallbacks:
  orchestrator: [gpt-5.6-sol@high]
  default: [claude-sonnet-5@high]
  bulk: [claude-sonnet-5@high]
  taste: [gpt-5.6-sol@high]
  review: [gpt-5.6-sol@high]
```

Each `fallbacks.<route>` list is an ordered chain of exact model-effort rows.
Its presence is the developer's standing authorization for Harness to change
providers only when the prior candidate has an availability failure. Consumers
continue to request semantic routes and never inspect the rubric or select a
provider.

`routing.fallback` becomes a legacy field. It is not treated as an automatic
fallback because one generic model cannot safely preserve taste, latency,
batch, computer-use, or independence constraints. An explicit rubric refresh
migrates it to compatible per-route chains and then removes it.

## Route Eligibility

The resolver evaluates the primary followed by its fallbacks. A candidate is
eligible only when all of these hold:

1. Its exact `(name, effort)` row exists.
2. The row's provider is enabled in `capabilities`.
3. Its executor is reachable: a row without `via` must match the native runtime
   provider; a row with `via` requires that declared executor to be callable.
4. The candidate preserves the HarnessRequest's operation, tools, approvals,
   working directory, allowed paths, and other authority boundaries.
5. A `taste` candidate meets `routing.taste_min`.
6. An `independent` candidate differs from every supplied authoring provider and
   any other provider boundary required by the request.
7. The candidate's provider is different from every earlier provider in that
   route chain. Same-provider retries are escalation, not fallback.
8. Its provider/executor circuit is not open, or this request has atomically
   claimed the one permitted half-open probe.

Every candidate runs at most once per HarnessRequest. If no eligible candidate
remains, Harness returns `status: blocked` with `evidence.outcome: unproven` and
the unavailable route details in `blockers`.

`routing.orchestrator` is eligible for the same fallback-chain validation so a
host can choose an available top-level model before session start. A running
agent still never replaces itself to satisfy the orchestration preference.

## Deterministic Resolver

Add `plugins/harness/scripts/resolve-route.py` as Harness's only executable
route-selection implementation. The execution, review, computer-use, setup, and
model-rubric skills call this script rather than interpreting fallback chains in
prose.

The resolver has three bounded operations:

1. `select`: load and validate the rubric, evaluate route candidates and circuit
   state, atomically claim an expired half-open probe when needed, and return one
   JSON resolution.
2. `record-failure`: record a typed availability failure for the selected
   provider/executor and calculate its next retry time.
3. `record-success`: close the selected provider/executor circuit and clear its
   failure counter.

`select` accepts the semantic route, native provider, callable executors,
authoring-provider exclusions when relevant, unavailable candidates already
attempted by this request, state path, and an injectable current time for tests.
Its result is one of:

```json
{
  "status": "resolved",
  "resolution": "primary",
  "model": "claude-fable-5",
  "effort": "high",
  "provider": "anthropic",
  "executor": "native"
}
```

```json
{
  "status": "fallback",
  "resolution": "fallback",
  "model": "gpt-5.6-sol",
  "effort": "high",
  "provider": "openai",
  "executor": "codex",
  "reason": "quota"
}
```

```json
{
  "status": "blocked",
  "attempted": ["claude-fable-5@high", "gpt-5.6-sol@high"],
  "blockers": ["no eligible taste candidate remains"]
}
```

The script uses safe YAML loading and validates the constrained rubric schema
before selecting anything. A missing parser dependency is a typed setup blocker,
not permission to guess. JSON output contains no credentials or raw executor
logs.

## Availability Failures

Automatic provider fallback applies only to these typed failures:

- `quota`: subscription or account usage exhausted;
- `authentication`: credentials are absent, expired, or refused;
- `rate_limit`: a temporary request-rate limit;
- `provider_unavailable`: a provider service or required model endpoint is
  temporarily unavailable; and
- `missing_executor`: the declared external executor is not callable.

Missing executors and native-provider mismatches are cheap preflight exclusions;
they do not create timed circuit state. Provider dispatch adapters translate
their bounded error into one of the remaining availability categories before
calling `record-failure`. Native execution skills do the same from the runtime's
typed dispatch failure.

Unknown errors, worker task failures, invalid output, failed verification,
authority failures, and approval blockers never trigger provider fallback. They
return their existing typed result or use a separately authorized escalation.
This prevents provider switching from hiding a real task or proof failure.

## Circuit Breaker

Provider health is transient machine state, not personal configuration. Store it
at:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/studio-moser/harness/provider-health.json
```

Key each circuit by provider plus executor so a broken external profile does not
disable a separate native runtime. Store only:

```json
{
  "version": 1,
  "circuits": {
    "anthropic|native": {
      "state": "open",
      "reason": "quota",
      "failure_count": 1,
      "last_failure_at": "2026-08-24T20:00:00Z",
      "unavailable_until": "2026-08-25T20:00:00Z",
      "probe_claimed_at": null
    }
  }
}
```

Do not store raw errors, quota amounts, usernames, credentials, profiles, or
request content. The state file is never synced or committed.

Cooldown policy is deterministic:

| Failure | Retry schedule |
| --- | --- |
| Quota | Provider reset timestamp when supplied; otherwise 24 hours |
| Authentication | 24 hours |
| Rate limit or provider outage | 15 minutes, then 1 hour, 6 hours, and 24 hours |

When `unavailable_until` passes, the circuit becomes half-open. File locking and
atomic replacement allow exactly one request to claim the probe. Other concurrent
requests skip that candidate and continue through their route chain. A successful
dispatch calls `record-success` and closes the circuit. Another availability
failure reopens it at the next cooldown step. A process that dies after claiming
a probe cannot suppress the provider forever: a stale probe lease expires after
the corresponding short outage interval.

The retry timestamp controls whether dispatch may begin; it does not schedule a
background job. The next eligible HarnessRequest performs the probe.

## Execution Flow

For every Harness operation:

1. Validate the HarnessRequest and freeze its authority ceiling.
2. Call `resolve-route.py select` for the requested semantic route.
3. Dispatch the returned candidate with explicit model, effort, provider, and
   executor.
4. On success, close any claimed circuit and continue normal verification.
5. On a typed availability failure, record the failure, exclude that candidate,
   and repeat selection.
6. On any non-availability failure, stop without changing providers.
7. Return one complete HarnessResult and let the parent reproduce the existing
   verification seam before acceptance.

Context, files, tools, approvals, sandbox, fixed target, and verification remain
identical across provider attempts. Fallback never widens authority and never
turns an unproven result into acceptance.

## HarnessResult Observability

Extend `route` in the HarnessResult with:

```yaml
route:
  requested: taste
  actual_model: gpt-5.6-sol
  effort: high
  provider: openai
  executor: codex
  resolution: fallback
  attempted: [claude-fable-5@high, gpt-5.6-sol@high]
  fallback_reason: quota
```

`resolution` is `primary` or `fallback`. `attempted` is the bounded ordered list
of candidates for which dispatch actually began; preflight and open-circuit skips
remain in the resolver's bounded check evidence. `fallback_reason` is empty for a
primary resolution and otherwise uses the typed availability category. Existing
`telemetry.attempts` records the total dispatch count.

This makes recurring fallback and unavailable providers observable without
exposing raw provider responses or changing consumer-owned report schemas.

## Rubric Creation and Migration

`harness:model-rubric` derives fallback chains whenever two or more providers
have semantically compatible reachable rows:

1. Preserve the user's primary route choices.
2. Choose backups from other providers under the same trust, taste, latency,
   batch, independence, and operation constraints.
3. Show the complete route chains before writing them on first setup or migration.
4. Validate every chain and reject duplicate providers or unresolved rows.
5. Remove legacy `routing.fallback` only after explicit per-route chains validate.

Single-provider rubrics remain valid with no `fallbacks` entries. Provider
diversity enables resilience but is never required for setup. A stale rubric is
not silently rewritten by sync; setup or an explicit model-rubric refresh owns
migration.

Tim's user-global rubric is migrated only after this Harness release is installed.
The live file remains unchanged during plugin development.

## Product Pulse and Other Consumers

Product Pulse, PM, and other consumers continue to submit only semantic routes.
They do not authorize a concrete model, inspect health state, implement cooldowns,
or repair a blocked provider route.

The temporary Product Pulse-specific Codex retry is removed. The pending Shelby
OpenBot/CopilotKit deep dive becomes the first end-to-end acceptance case: its
`taste` request should skip or open the unavailable Claude circuit, select the
qualifying Codex fallback, preserve the accepted evidence bundles, and return an
accepted/proven synthesis draft.

## Security and Failure Boundaries

- Circuit state is local, minimal, non-secret, and atomically written.
- Fallback attempts inherit the exact original authority and approval ceiling.
- No executor may be selected solely from an error string or model name.
- A fallback row must already be authorized by the developer's rubric and pass
  semantic eligibility checks.
- An unavailable or malformed rubric, health state, parser, executor, or required
  route returns a typed blocker rather than a guessed provider.
- Independent review never degrades to the authoring provider.
- A fallback worker's report remains a claim until the accepting parent reproduces
  the fixed verification seam.

## Files Expected to Change

- `plugins/harness/scripts/resolve-route.py`: deterministic route selection,
  circuit transitions, atomic state, and bounded JSON results.
- `plugins/harness/references/routing.md`: ordered fallback, retry, cooldown, and
  provider-independence semantics.
- `plugins/harness/references/harness-contract.md`: new HarnessResult route fields.
- `plugins/harness/skills/execute/SKILL.md`, `review/SKILL.md`, and
  `computer-use/SKILL.md`: invoke the resolver and classify availability failures.
- `plugins/harness/skills/model-rubric/SKILL.md` and `Default_Rubric.yml`: derive,
  migrate, and validate per-route chains.
- `plugins/harness/skills/setup/SKILL.md`: require resolver-backed rubric
  validation and report missing dependencies.
- `plugins/harness/tests/*.bats`: resolver, circuit, migration, contract, adapter,
  authority, and regression coverage.
- Harness README, release metadata, and plugin version files required by the
  repository's release convention.
- The Product Pulse deep-dive skill experiment is removed; no consumer owns
  provider fallback.

## Testing

Write focused tests before implementation for:

1. primary resolution and explicit model/effort/executor propagation;
2. unavailable Claude primary selecting an eligible Codex fallback;
3. unavailable Codex primary selecting an eligible Claude native fallback;
4. immediate later requests skipping an open circuit without dispatch;
5. one half-open probe after a fake-clock cooldown and concurrent claim safety;
6. successful probe closing the circuit;
7. repeated outage advancing 15-minute, 1-hour, 6-hour, and 24-hour cooldowns;
8. reset-aware quota cooldown and the 24-hour default;
9. task, verification, approval, and authority failures never switching provider;
10. taste fallback rejecting a row below `taste_min`;
11. independent fallback rejecting an authoring provider;
12. malformed, exhausted, duplicate-provider, and single-provider chains;
13. legacy `routing.fallback` migration without unsafe automatic use;
14. complete HarnessResult fallback provenance with no raw error leakage; and
15. unchanged Product Pulse and PM provider-neutral boundaries.

The complete Harness, Product Pulse, PM, portability, secret-scan, and version
suites must pass. The final live acceptance test uses the pending Shelby deep dive
and reproduces its citation, project-reference, frontmatter, and report-path seam.

## Non-Goals

- Retrying failed work merely because another model might perform better.
- Automatic escalation to a stronger or more expensive row.
- Background provider polling or scheduled quota checks.
- Synchronizing provider health between machines.
- Adding arbitrary provider adapters without an enforceable authority boundary.
- Letting consumers select models, executors, or fallback providers.
