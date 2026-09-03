---
name: execute
description: >-
  MANDATORY before acting on explicit bounded Harness execution involving a
  HarnessRequest, HarnessResult, Routing_Request file, semantic routing, or a
  typed pre-dispatch blocker such as a missing model rubric or missing
  executor, whether execution is native or uses an internal cross-provider
  adapter.
---

# Harness Execute

Execute one bounded provider-neutral request. The consumer owns the outcome;
Harness owns routing, dispatch, authority preservation, and proof.

Read only the references whose predicates match the active path:

- Read [the Harness contract](../../references/harness-contract.md) when
  validating a request or constructing a terminal result.
- Read [routing](../../references/routing.md) only after preflight succeeds and
  route selection is needed.
- Read [handoff](../../references/handoff.md) only before delegated dispatch.
- Read [verification](../../references/verification.md) only when accepting an
  artifact or review claim.
- Read [context](../../references/context.md) only when context mode must be
  selected.
- Read [Shelby integration](../../references/shelby-integration.md) only when
  Shelby is callable or the request enables memory.

## Validate the request

`operation` must be `execute`. Require a bounded observable outcome, route,
verification seam and expected result, and an authority ceiling. Default
delegated implementation to `fresh` when `context.mode` is omitted; use another
mode only under the Context rules.

Preserve `authority.working_directory` exactly after confirming it exists. Treat
`authority.allowed_paths`, tools, and approvals as ceilings, not suggestions.
Canonicalize paths only to validate that they stay inside the ceiling; never
replace the requested working directory with a parent checkout. A malformed
request, unresolved blocker, unavailable required tool, pending approval that a
non-interactive worker cannot obtain, or permission boundary the executor cannot
enforce returns `status: blocked` before dispatch.

For an environment-provided action, use this sequence once:

1. An advertised `describe`, schema, or public-contract command is mandatory:
   run it before forming or calling any action, even when request fields look
   sufficient. Never reuse the whole request as an action payload.
2. Build the action payload only from the documented fields, then call the action.
3. Parse the typed response structurally. When it contains `check`, begin the
   `evidence.checks` entry with that value verbatim; append the procedure only as
   provenance. When it contains `reason`, copy that value verbatim to
   `route.fallback_reason` and begin the blocker with `<reason>:` followed by the
   documented recovery action.

For the resulting pre-dispatch block, encode a checked absolute path as
`path:<absolute-path>` in `evidence.fixed_target`. Keep `artifacts.files` to
delivered task outputs outside the HarnessResult envelope—normally `[]` on this
path; the result file itself never counts.

Use Shelby only when callable tool names prove it is available. Resolve one
canonical project scope first; otherwise follow the repository/temp fallback.

When `context.memory.enabled` is true, translate each consumer-owned recall intent
inside that canonical scope before dispatch and add only the bounded result to the
worker packet. Consumers never supply or invoke provider tools. Hold every capture
intent until the accepting workflow has reproduced the verification seam and the
result has `evidence.outcome: proven`; optional capture failure leaves the execution
result intact and the unavailable Shelby identifiers empty.

Every terminal path returns the complete HarnessResult, including a block before
dispatch or a failed attempt; prose is not a substitute for the result. Preserve
all fields and leave unavailable values empty.

For a bounded non-code file transformation, preserve the requested task type and
scope. When the parent runtime can perform the work inside the authority ceiling,
that is native execution: perform the transformation and verify it with direct
structural or traceability checks. Do not add a branch, commit, PR, tracker write,
or automated test unless the request explicitly asks for it. If the required
write is outside the authority ceiling, return the complete blocked result.

## Resolve and dispatch

Follow Routing. Resolve the active rubric only through its script:

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

For `independent`, that same call also passes
`--authoring-providers "$HARNESS_AUTHORING_PROVIDERS"` containing every provider
that authored the target. The resolver always adds the persistent orchestrator
provider; callers supply the complete request-specific author list.

Read the returned JSON structurally. A blocked selection returns the complete
blocked HarnessResult. A matching native provider uses the native runtime even
when the selected model row has `via`; otherwise the returned external executor
must be explicit and callable. If `via` is absent, dispatch through the native
runtime only when the selected provider is native. Pass the resolved model and
effort explicitly with the selected context mode and complete HandoffPacket. If
either cannot be selected explicitly, stop rather than change providers.

The only resolver-loop reasons that authorize provider fallback are `quota`,
`authentication`, `rate_limit`, `provider_unavailable`, and preflight
`missing_executor`. Other typed pre-dispatch reasons, including
`missing_model_rubric`, stop before selection and use the blocked-result encoding
in the Harness contract; they never authorize provider switching. The resolver
owns `missing_executor`, open-circuit skips, cooldowns, and the single half-open
probe; do not append a preflight skip to `--attempted`. After dispatch, classify
only a bounded typed availability result from the executor boundary; do not
infer one from unbounded raw provider text. On `quota`, `authentication`,
`rate_limit`, or `provider_unavailable`, call `resolve-route.py record-failure`
for the selected provider and executor (including a known quota retry time when
present), append the selected model-effort candidate to `HARNESS_ATTEMPTED`, and
repeat with the unchanged HarnessRequest. On success, call `resolve-route.py
record-success` for that provider and executor. Any non-availability response
also proves endpoint health, so clear an outstanding circuit before handling its
task or output failure. Task, output, verification, authority, and approval
failures stop without changing providers. Between iterations, do not change the
request's operation, tools, approvals, working directory, allowed paths, fixed
target, sandbox, or verification seam; only the attempted list and selected
route data change. Exhausting the unique-provider chain returns `blocked`; the
loop cannot exceed the authorized candidates.

In the terminal result, copy the selection's `resolution` to
`route.resolution`; set `route.attempted` to every candidate actually dispatched,
including the terminal candidate; and copy the typed selection `reason` to
`route.fallback_reason`, or leave it empty. Never add preflight skips to
`route.attempted`.

### Internal Codex adapter

Enter this adapter only when the selected candidate is non-native and the
resolver returned `executor: codex`; a native selection remains native even when
its model row declares `via: codex`. Before the first selection, include `codex`
in `HARNESS_EXECUTORS` only when `codex-app-server.py check` returns
`{"status":"available"}`. That check requires both the executable and the typed
Codex App Server terminal-error seam; `command -v codex` alone is insufficient.
Choose
`read-only` when no writes are authorized and
`workspace-write` only when writes across the working directory are authorized.
If narrower allowed paths cannot be enforced, use an authorized native executor
that can enforce them or return `blocked`; a prompt-only restriction is not an
authority boundary.

Derive approval policy before dispatch. If any `authority.approvals` item remains
outstanding, the non-interactive external adapter cannot surface it: return an
authorized fallback or `blocked`. After the parent obtains every required
approval, dispatch with `approval: never`; in Codex this denies later escalation
instead of silently approving it. If the sandbox and approval policy together
cannot enforce the request ceiling, do not invoke Codex.

Read the guarded adapter's compact JSON and exit code, never stderr or raw
provider text. Exit 69 with `{"status":"missing_executor"}` means the executable
or required App Server seam disappeared after discovery: remove `codex` from the
callable inventory and reselect without `record-failure` or an appended dispatch
attempt. Only exit 75 with
`{"status":"availability_failure","reason":"..."}` authorizes a timed
availability record, and the reason must be one of the resolver's four timed
categories. Exit 1 with `{"status":"failed"}` stops without changing providers;
it covers untyped, task, policy, sandbox, malformed-protocol, and generic worker
failures. Exit 0 with `{"status":"succeeded"}` places only the final agent text
in the report. No adapter result contains raw error text, logs, or secrets.

Create a temporary artifact directory and a self-contained prompt. The prompt's
positive recipe is: outcome, working directory, allowed paths, constraints,
verification seam, and the required HarnessResult return shape. Include the
current state, relevant files, unresolved blockers, current proof, allowed
tools, and approvals only when populated. Never put secrets in the prompt,
report, evidence, or command line. Do not copy environment variables or
secret-bearing profiles, and never widen sandbox, path, tool, or approval authority.

After assigning the validated values to the variables below, use the guarded
adapter script. It validates the operation/sandbox combination and passes cwd,
sandbox, approval, model, and effort explicitly:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-execute.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
"$harness/scripts/codex-dispatch.sh" \
  --operation execute \
  --cwd "$HARNESS_CWD" \
  --sandbox "$HARNESS_SANDBOX" \
  --approval never \
  --model "$HARNESS_MODEL" \
  --effort "$HARNESS_EFFORT" \
  --prompt "$PROMPT" \
  --report "$REPORT"
```

The driver starts an ephemeral App Server thread read-only, then applies the
explicit selected sandbox at turn scope so project trust is not widened or
persisted. The adapter never adds `--add-dir`, automatic approval, or an
approval/sandbox bypass. Do not let the worker commit, push, deploy, edit global config, or take
any other external action unless the request explicitly grants it. A
non-interactive prompt proceeds within the approved packet without stopping at
internal plan gates; a still-required user approval blocked dispatch above.

Pin Git status before dispatch and inspect status plus diff afterward. Exit zero
and a report without artifact changes are success-shaped failures, not delivery.
If the worker reports an authority failure, obtain any required approval in the
parent and start a new guarded attempt with the same or narrower sandbox; never
resume through a broader ambient configuration.

## Verify and return

Treat the worker report and its checks as claims. The parent fixes the returned
artifact, inspects it, and reproduces the highest stable verification seam.
Only the parent or accepting workflow may return `status: accepted`, after the
outcome is delivered and fresh direct proof establishes it.

Return every field in the HarnessResult: `status`, `route.requested`,
`route.actual_model`, `route.effort`, `route.provider`, `route.executor`,
`route.resolution`, `route.attempted`, `route.fallback_reason`,
`artifacts.files`, `artifacts.report`, `evidence.fixed_target`,
`evidence.checks`, `evidence.outcome`, `telemetry.attempts`,
`telemetry.elapsed`, `telemetry.verification_failures`,
`telemetry.token_or_quota_usage`, `shelby.project_id`, `shelby.run_id`,
`shelby.checkpoint_ids`, and `blockers`. Optional or unavailable values stay
empty; fields are never omitted.
