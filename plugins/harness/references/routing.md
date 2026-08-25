# Routing

Routing translates a consumer's semantic route into one explicit model, effort,
provider, and executor. Only Harness reads the rubric or interprets executor
metadata.

## Top-level orchestration

`orchestrator` selects the preferred model for the top-level session; it is not
a delegated HarnessRequest route. A running agent never replaces itself to
satisfy `routing.orchestrator`.

- `routing.orchestrator` is used when a host starts a top-level session and
  supports explicit model selection.
- If the host cannot switch the running model, report the preference as
  advisory and continue resolving delegated routes.
- The orchestrator retains context and delegates bounded work so expensive
  judgment tokens do not absorb execution volume.
- `routing.fallback` is optional and still requires caller authorization under
  the existing typed fallback rules.

`routing.fallback` names an eligible general fallback but never authorizes an
automatic fallback or escalation. `fallbacks.<route>` is the only standing
authorization for automatic fallback; `routing.fallback` grants none. Provider
diversity remains optional when a route has no fallback chain; a single
reachable model-effort row may satisfy every required route.

## Semantic routes

- `bulk`: clear-spec, mechanical, independently verifiable work.
- `quick`: short, latency-sensitive work.
- `default`: ordinary interactive work without a stronger reason.
- `taste`: user-facing judgment such as UI, copy, or public API design.
- `batch`: configured, appropriate unattended fan-out.
- `review`: strong review of a fixed target.
- `independent`: a context-independent adversarial review. It requires explicit
  cost approval from the user before dispatch.

`taste` resolves through the exact `routing.taste` value. Rubric setup selects
that value from the reachable rows at or above `routing.taste_min`, under the
developer's cost and trust preferences. `routing.taste_min` is an input to
rubric setup, not a runtime route value.

## Ordered candidate resolution

1. Resolve the active rubric through `scripts/rubric-path.sh`; do not guess a
   repository or user-global path.
2. Candidate order is exactly `routing.<route>` followed by
   `fallbacks.<route>` in listed order. Each value must be `model@effort`, and a
   provider may appear only once in the chain.
3. Find each candidate's `models` row by both `name` and `effort`. Every `taste`
   candidate must satisfy `routing.taste_min`. Every `independent` candidate
   differs from the persistent `routing.orchestrator` provider and every
   request-supplied authoring provider. A rubric with `routing.independent` but
   no orchestrator boundary fails closed. Provider and executor names cannot
   contain the reserved circuit-key delimiter `|`.
4. When a candidate's provider matches the native provider, use native execution
   even if its model row declares `via`. Otherwise `via` must name a callable
   external executor; a consumer never invents or implicitly selects one.
   `validate` checks every primary and fallback row individually, so one reachable
   candidate cannot mask another unreachable authorized row.
5. Call `scripts/resolve-route.py select` with the semantic route, native
   provider, callable executors, every authoring provider for `independent`, and
   the ordered unavailable candidates already dispatched by this request in
   `--attempted`.
6. Pass the selected model and effort explicitly on every dispatch. Never rely
   on a runtime default. Record the requested route and concrete dispatch in the
   result.

A stale, missing, malformed, or internally inconsistent rubric is a resolution
failure, not permission to invent a model choice.

## Bounded selection loop

Automatic provider switching is limited to `quota`, `authentication`,
`rate_limit`, `provider_unavailable`, and preflight `missing_executor`.
`missing_executor` is classified by the resolver before dispatch. After a
dispatch, the executor boundary may classify only the other four reasons; it
must not parse raw provider text beyond that bounded typed classification seam.

External Codex availability is classified only from
`turn/completed.turn.error.codexErrorInfo`. The guarded App Server driver maps
`usageLimitExceeded` to `quota`; `unauthorized` or HTTP 401/403 to
`authentication`; HTTP 429 to `rate_limit`; and `serverOverloaded`,
`internalServerError`, structured connection/stream/disconnect/too-many-attempts
without a non-5xx status, or HTTP 5xx to `provider_unavailable`. All untyped,
missing, malformed, task, policy, sandbox, context/session-budget, and other
failures stop. Raw error text, logs, and secrets are never adapter output.

A missing or incompatible Codex App Server is preflight `missing_executor` and
never creates a timed circuit or dispatch attempt. Capability discovery includes
`codex` only when `scripts/codex-app-server.py check` proves the required schema
and initialize-only stdio handshake.
If the seam disappears after selection, remove `codex` from the callable
inventory and reselect without recording failure or appending the candidate.

On a typed post-dispatch availability failure, call `record-failure` without any
raw error or secret-bearing value, append that dispatched candidate to
`--attempted`, and select again. On success, call `record-success`. Preflight
skips and candidates omitted by an open circuit are not dispatch attempts and
are not appended. The resolver rejects an attempted candidate unless its exact
provider/executor has matching recorded typed availability state. Stop when the
ordered chain is exhausted.

Every attempt preserves the original HarnessRequest's operation, tools,
approvals, working directory, allowed paths, fixed target, sandbox, and
verification seam. Task, output, verification, authority, and approval failures
stop without changing providers. A malformed route, unavailable state, missing
authorization, failed taste or independence gate, or exhausted chain returns
`blocked`.

The final HarnessResult records `route.resolution` as `primary` or `fallback`,
`route.attempted` as the ordered candidates actually dispatched, and
`route.fallback_reason` as the typed availability reason that caused fallback or
empty. A matching native provider is still a primary or fallback candidate by
its position in the authorized chain; executor choice does not change that
provenance.

## Provider health circuits

Timed availability failures open a local circuit for 24 hours for `quota` and
`authentication`, and for 15 minutes, 1 hour, 6 hours, then 24 hours for repeated
`rate_limit` or `provider_unavailable` failures. A provider/executor success
clears its circuit. `missing_executor` is a preflight fact and is not persisted.

While a circuit is open, selection skips that provider/executor endpoint. After
a cooldown expires, exactly one selector may claim the half-open probe for 15
minutes. Other concurrent selectors continue through the authorized chain. The
local health state contains only provider, executor, typed reason, failure count,
and timestamps; it contains no raw error or secret-bearing value.

Every selection holds the sibling circuit lock, including the first selection
before a health document exists. The lock file may therefore precede the JSON
state file; the JSON file is written only when health is recorded.

## Fallback versus escalation

Escalation is distinct from fallback: it is a bounded retry at a stronger
configured resolution after failed verification. Escalate only when the request
or caller authorizes it, retain the original authority and outcome, and record
the attempt. There is no implicit universal escalation ladder.
