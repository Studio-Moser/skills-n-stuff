# Routing

Routing translates a consumer's semantic route into one explicit model, effort,
provider, and executor. Only Harness reads the rubric or interprets executor
metadata.

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

## Rubric lookup and explicit dispatch

1. Resolve the active rubric through `scripts/rubric-path.sh`; do not guess a
   repository or user-global path.
2. Look up the requested semantic key in `routing`. Its value must be
   `model@effort`.
3. Find the matching `models` row by both `name` and `effort`. Resolve its
   provider and confirm the provider/model is reachable through discovered
   capabilities.
4. Interpret optional model-row `via` as executor metadata. When present, it
   selects that external executor; when absent, use the native agent or current
   runtime. A consumer never branches on `via`.
5. Pass the resolved model and effort explicitly on every dispatch. Never rely
   on a runtime default. Record the requested route and concrete dispatch in the
   result.

A stale, missing, malformed, or internally inconsistent rubric is a resolution
failure, not permission to invent a model choice.

## Resolution outcomes

Every lookup produces one typed route-resolution outcome:

- `resolved`: the requested route and all required capabilities are available.
- `fallback`: the requested resolution is unavailable and the request explicitly
  authorized a named fallback route or executor that preserves its boundaries.
- `blocked`: no authorized safe resolution exists.

If a required capability is missing, return `fallback` only when that fallback
was authorized; otherwise `blocked`. Never silently change independence,
provider boundary, computer-use requirements, permission scope, working
directory, or required approvals.

Escalation is distinct from fallback: it is a bounded retry at a stronger
configured resolution after failed verification. Escalate only when the request
or caller authorizes it, retain the original authority and outcome, and record
the attempt. There is no implicit universal escalation ladder.
