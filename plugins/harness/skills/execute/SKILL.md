---
name: execute
description: >-
  Use when a workflow has a bounded Harness implementation request that should
  run through a resolved semantic route, whether the available executor is the
  native agent runtime or an internal cross-provider adapter.
---

# Harness Execute

Execute one bounded provider-neutral request. The consumer owns the outcome;
Harness owns routing, dispatch, authority preservation, and proof.

Read the exact request/result schema in
[references/harness-contract.md](../../references/harness-contract.md), route
resolution in [references/routing.md](../../references/routing.md), the packet
shape in [references/handoff.md](../../references/handoff.md), evidence rules in
[references/verification.md](../../references/verification.md), context choice
in [references/context.md](../../references/context.md), and optional state rules
in [references/shelby-integration.md](../../references/shelby-integration.md).

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

Follow Routing. Resolve the active rubric only through its script, then read the
semantic route and matching model row:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
"$harness/scripts/rubric-path.sh"
```

Pass the resolved model and effort explicitly on every dispatch. If either
cannot be selected explicitly by the candidate runtime, that runtime is not a
valid resolution. If `via` is absent, dispatch through the native runtime with
the selected model, effort, context mode, and HandoffPacket as explicit inputs.

### Internal Codex adapter

When the resolved model row says `via: codex`, first run `command -v codex`.
Missing Codex uses only an explicitly authorized fallback; otherwise return
`blocked`. Choose `read-only` when no writes are authorized and
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

The adapter never adds `--add-dir`, automatic approval, or an approval/sandbox
bypass. Do not let the worker commit, push, deploy, edit global config, or take
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
`artifacts.files`, `artifacts.report`, `evidence.fixed_target`,
`evidence.checks`, `evidence.outcome`, `telemetry.attempts`,
`telemetry.elapsed`, `telemetry.verification_failures`,
`telemetry.token_or_quota_usage`, `shelby.project_id`, `shelby.run_id`,
`shelby.checkpoint_ids`, and `blockers`. Optional or unavailable values stay
empty; fields are never omitted.
