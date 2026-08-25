---
name: review
description: >-
  Use when delegating or performing a review of a frozen, pinned target — a
  commit SHA, tag, or immutable plan/patch snapshot — through Harness routing.
  Covers: dispatching the configured review route; running or requesting an
  independent, fresh-context, cross-provider, or adversarial review (which needs
  explicit cost approval first); reviewing work authored by another model or
  worker so the reviewer stays independent of the author; and natively
  re-verifying, reproducing, confirming, or withdrawing findings that an
  external or sub-agent reviewer claimed against that fixed target. Also use to
  return a typed blocked or accepted HarnessResult for such a request.

  Do not use for ordinary review of a moving working tree or uncommitted diff,
  replying to or fixing GitHub PR comments, visual or browser-based UI review,
  or evaluating prompts, rubrics, vendors, or documents.
---

# Harness Review

Review one immutable target through provider-neutral routing. A reviewer reports
findings and evidence; the parent decides whether the fixed target is accepted.

Read the schema in
[references/harness-contract.md](../../references/harness-contract.md), route
rules in [references/routing.md](../../references/routing.md), packet shape in
[references/handoff.md](../../references/handoff.md), fixed-target and evidence
rules in [references/verification.md](../../references/verification.md), context
choice in [references/context.md](../../references/context.md), and optional state
rules in [references/shelby-integration.md](../../references/shelby-integration.md).

## Fix and validate the target

`operation` must be `review`. Only `review` and `independent` are valid review
routes. Require `verification.fixed_target` before dispatch: a commit SHA or an
immutable snapshot with a recorded digest. Also require the review outcome,
requirements or constraints, authority ceiling, verification seam, expected
result, and available proof.

An `independent` request requires explicit user approval for its cost and uses
`fresh` context. Ordinary review uses the requested supported context mode.
Preserve `authority.working_directory` exactly and default review authority to
read-only. Never inspect a moving “current diff” as though it were the recorded
target. If the target, digest, requirements, seam, fixture, or oracle changes,
invalidate the proof and reopen review.

Use Shelby only when callable tool names prove it is available, after resolving
canonical project scope. Its absence does not block review.

When `context.memory.enabled` is true, resolve each recall intent within that scope
before dispatch. Hold every capture intent until the parent reproduces the fixed-
target proof and the result has `evidence.outcome: proven`; optional capture failure
does not change the review status. Consumers do not discover or invoke provider tools.

## Resolve and dispatch

Resolve the active rubric only through Harness:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
RUBRIC_PATH="$("$harness/scripts/rubric-path.sh")"
```

Run one bounded selection loop. `HARNESS_ATTEMPTED` starts as `[]` and contains
only ordered candidates already dispatched by this request and then recorded as
unavailable. Call the canonical resolver on every iteration:

```bash
ROUTE_RESULT="$($harness/scripts/resolve-route.py select \
  --rubric "$RUBRIC_PATH" \
  --route "$HARNESS_ROUTE" \
  --native-provider "$HARNESS_NATIVE_PROVIDER" \
  --executors "$HARNESS_EXECUTORS" \
  --attempted "$HARNESS_ATTEMPTED")"
```

For `independent`, that same `select` call must also pass
`--authoring-providers "$HARNESS_AUTHORING_PROVIDERS"` containing every provider
that authored the fixed target; never issue the shorter call for that route.
Read the returned JSON structurally. A blocked selection returns the complete
blocked HarnessResult. A matching native provider uses native review even when
the selected row has `via`; otherwise the returned external executor must be
explicit and callable. If `via` is absent, use the native runtime only when the
selected provider is native, with the chosen context mode and complete
HandoffPacket. Pass the resolved model and effort explicitly on every dispatch.

The only availability reasons are `quota`, `authentication`, `rate_limit`,
`provider_unavailable`, and preflight `missing_executor`. The resolver owns
`missing_executor`, open-circuit skips, cooldowns, and the single half-open probe;
do not append a preflight skip to `--attempted`. After dispatch, classify only a
bounded typed availability result from the executor boundary; do not infer one
from unbounded raw provider text. On `quota`, `authentication`, `rate_limit`, or
`provider_unavailable`, call `resolve-route.py record-failure` for the selected
provider and executor, append the selected model-effort candidate to
`HARNESS_ATTEMPTED`, and repeat with the unchanged HarnessRequest and same fixed
target. On success, call `resolve-route.py record-success` for that provider and
executor. Any non-availability response also proves endpoint health, so clear an
outstanding circuit before handling its task or output failure. Task, output,
verification, authority, and approval failures stop without changing providers.
Between iterations, do not change the request's operation, tools, approvals,
working directory, allowed paths, fixed target, sandbox, or verification seam;
only the attempted list and selected route data change. Exhausting the
unique-provider chain returns `blocked`; the loop cannot exceed the authorized
candidates and must never weaken independence or authority.

In the terminal result, copy the selection's `resolution` to
`route.resolution`; set `route.attempted` to every candidate actually dispatched,
including the terminal candidate; and copy the typed selection `reason` to
`route.fallback_reason`, or leave it empty. Never add preflight skips to
`route.attempted`.

### Internal Codex adapter

For `via: codex`, require `command -v codex`. Create a temporary report and a
self-contained prompt containing the fixed target, requirements, available
proof, review axes supplied by the consumer, authority, and exact HarnessResult
return shape. Do not include secrets or unbounded logs.

Obtain any independent-review cost approval before dispatch. Any other
outstanding approval returns an authorized fallback or `blocked`; the
non-interactive adapter cannot surface it. A cleared request uses
`approval: never` so Codex cannot escalate beyond the read-only review.

For a commit target, use the native fixed-commit review command:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-review.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
"$harness/scripts/codex-dispatch.sh" \
  --operation review \
  --cwd "$HARNESS_CWD" \
  --sandbox read-only \
  --approval never \
  --model "$HARNESS_MODEL" \
  --effort "$HARNESS_EFFORT" \
  --prompt "$PROMPT" \
  --report "$REPORT" \
  --fixed-target "$HARNESS_FIXED_TARGET"
```

For a branch range or uncommitted state, first materialize the exact patch and
digest in the temporary artifact directory. Use an authorized native reviewer
that can consume that immutable artifact; if none is available, return `blocked`.
The commit-only Codex review adapter must not be pointed at a moving
`--uncommitted` target. Never add a write sandbox or an approval bypass to a
review.

Require findings first. Each finding includes severity, file and line, concrete
failure mode, and fix direction. The report also names the target and classifies
each check as direct proof, supporting evidence, or unproven. Confirm the target
still matches its fixed point after the worker returns.

## Reproduce and return

Treat the worker report as a claim. The parent inspects every material finding
against the fixed target and must reproduce the relevant checks at the highest
stable seam. Pass the resolved model and effort explicitly on any retry. Only the
parent or accepting workflow may return `status: accepted`, after the review
outcome exists and current direct proof establishes it.

Return every field in the HarnessResult: `status`, `route.requested`,
`route.actual_model`, `route.effort`, `route.provider`, `route.executor`,
`route.resolution`, `route.attempted`, `route.fallback_reason`,
`artifacts.files`, `artifacts.report`, `evidence.fixed_target`,
`evidence.checks`, `evidence.outcome`, `telemetry.attempts`,
`telemetry.elapsed`, `telemetry.verification_failures`,
`telemetry.token_or_quota_usage`, `shelby.project_id`, `shelby.run_id`,
`shelby.checkpoint_ids`, and `blockers`. Optional or unavailable values stay
empty; fields are never omitted.
