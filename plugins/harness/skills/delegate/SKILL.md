---
name: delegate
description: >-
  Use when an agent should delegate bounded execution, fixed-target review, or computer-use verification through Harness routing and authority controls.
---

# Harness Delegate

Delegate one provider-neutral request. The consumer owns the outcome and decides
whether delegation is justified; Harness owns validation, routing, dispatch,
authority preservation, and proof. Ordinary direct work stays with the consumer.

Read the schema in
[references/harness-contract.md](../../references/harness-contract.md), route
rules in [references/routing.md](../../references/routing.md), packet shape in
[references/handoff.md](../../references/handoff.md), and evidence rules in
[references/verification.md](../../references/verification.md). Read
[references/context.md](../../references/context.md) only when choosing or
validating a non-default context mode. Read
[references/shelby-integration.md](../../references/shelby-integration.md) only
when memory is enabled or callable Shelby tools are available.

## Validate the request

`operation` must be `execute`, `review`, or `computer-use`. Require a bounded
observable outcome, semantic route, verification seam and expected result, and
an authority ceiling. Preserve `authority.working_directory` exactly after
confirming it exists. Treat allowed paths, tools, sandbox, confirmation policy,
and approvals as ceilings. Canonicalize paths only to validate containment;
never substitute a parent checkout.

When `delegation` is present, require positive `max_children` and `max_depth`.
The validated rubric supplies the maximum defaults; a request may lower but not
widen them. Enforce the effective limits before spawning. Pass `token_budget`
when the selected runtime supports it; otherwise return `blocked`.

Default delegated implementation to `fresh` when `context.mode` is omitted.
Use another mode only under Context. A malformed request, unresolved blocker,
missing capability, unavailable required tool, outstanding approval that a
non-interactive worker cannot obtain, or authority boundary the executor cannot
enforce returns a complete `status: blocked` HarnessResult before dispatch.

For a bounded non-code file transformation, preserve the requested task and scope.
Do not add a branch, commit, PR, tracker write, or automated test unless the
request asks for it. A required write outside the authority ceiling is blocked.

Use Shelby only when callable tool names prove it is available. Resolve one
canonical project scope before recall or capture. Translate consumer-owned
`context.memory` recall intents before dispatch and add only bounded results to
the packet. Hold capture intents until the accepting workflow reproduces proof
and `evidence.outcome: proven`; optional Shelby absence or capture failure does
not change the operation result. Shelby activity is not part of HarnessResult.

### Review

For `operation: review`, validate the review route. Only `review` and `independent` are valid review routes.
Require `verification.fixed_target` before dispatch: a commit SHA or immutable snapshot with a recorded
digest. Default authority to read-only. Never review a moving current diff as the
fixed target. If the target, digest, requirements, seam, fixture, or oracle
changes, invalidate prior proof and reopen review.

An `independent` review requires explicit user approval for its cost, uses
`fresh` context, and supplies every provider that authored the target through
`--authoring-providers "$HARNESS_AUTHORING_PROVIDERS"`. The resolver also excludes
the persistent orchestrator provider. Direct dispatch is self-review and cannot
satisfy an independent request.

### Computer use

For `operation: computer-use`, require the exact behavior, platform or app,
expected observation, required tools, and fresh visual or runtime evidence.
Confirm every required computer-use capability from callable runtime tools; an
installed plugin or config entry is not proof. Preserve the runtime confirmation
policy for apps, accounts, devices, settings, and real data. Opening an approved
app or simulator is in scope; closing user apps, changing settings,
authenticating, purchasing, publishing, sending, or mutating real data requires
the listed approval. Source edits are disallowed unless `allowed_paths` grants
them. If no explicitly authorized equivalent capability exists, return `status: blocked`;
never downgrade the request to code inspection.

## Resolve and dispatch

Resolve the active rubric only through Harness:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
RUBRIC_PATH="$("$harness/scripts/rubric-path.sh")"
```

Populate `HARNESS_ACTIVE_CANDIDATE` from trustworthy host runtime metadata when
the host exposes the current model and effort. Never rely on an inherited shell
value when runtime metadata is available. If no trustworthy identity exists,
leave it empty and record that direct same-candidate admission was unavailable.

Run one bounded selection loop. `HARNESS_ATTEMPTED` starts as `[]` and tracks
only candidates dispatched by this request and then recorded as unavailable.
Call the canonical resolver on every iteration:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
HARNESS_ACTIVE_CANDIDATE="${HARNESS_ACTIVE_CANDIDATE:-}"
ROUTE_RESULT="$("$harness/scripts/resolve-route.py" select \
  --rubric "$RUBRIC_PATH" \
  --route "$HARNESS_ROUTE" \
  --native-provider "$HARNESS_NATIVE_PROVIDER" \
  --executors "$HARNESS_EXECUTORS" \
  --active-candidate "$HARNESS_ACTIVE_CANDIDATE" \
  --attempted "$HARNESS_ATTEMPTED")"
```

For `independent`, add the authoring-providers argument described above; never
issue the shorter call. Read the returned JSON structurally. A blocked selection
returns a complete blocked result. If the selected candidate equals the active
candidate and the operation is not independent review, execute the bounded
request directly with `executor: current` and `dispatch: direct`. Otherwise
continue only for `dispatch: delegated`.

A matching native provider uses the native runtime even if its row declares
`via`. If `via` is absent, dispatch through the native runtime only when the
selected provider is native. Pass the resolved model and effort explicitly with the selected
context mode and complete HandoffPacket. If either cannot be selected explicitly,
stop rather than change providers.

When the current native tool inventory advertises `spawn_agent`, dispatch by
calling `spawn_agent` directly with the selected model, effort, context mode, and packet.
`list_agents` reports active agents; an empty result does not mean `spawn_agent`
is unavailable. Do not report `missing_executor` or `blocked` while `spawn_agent`
is advertised and has not been called. After the call, apply the availability
classification below to its typed result.

The only availability reasons are `quota`, `authentication`, `rate_limit`,
`provider_unavailable`, and preflight `missing_executor`. The resolver owns
preflight skips, open circuits, cooldowns, and the single half-open probe. After
dispatch, classify only a bounded typed executor result, never raw provider text.
On the four timed availability failures, call `resolve-route.py record-failure`
for the selected provider and executor, append its model-effort candidate to
`HARNESS_ATTEMPTED`, and select again with the unchanged HarnessRequest. On
success, call `resolve-route.py record-success`. A non-availability response also
proves endpoint health, so clear an outstanding circuit before handling its task
or output failure.

Task, output, verification, authority, and approval failures stop without
changing providers. Between iterations, never change operation, tools,
approvals, working directory, allowed paths, fixed target, sandbox, confirmation
policy, or verification seam. Exhausting the authorized unique-provider chain
returns blocked. The attempted candidates and selection reason remain internal
resolver-loop state; they are not HarnessResult fields.

### Internal Codex adapter

Enter this adapter only when the selected candidate is non-native and the
resolver returned `executor: codex`; a native selection remains native even when
its model row declares `via: codex`. Before selection, include `codex` in
`HARNESS_EXECUTORS` only when
`codex-app-server.py check` returns `{"status":"available"}`; `command -v codex`
alone is insufficient.

Choose `read-only` when no writes are authorized and `workspace-write` only when
writes across the working directory are authorized. Computer use may use
`danger-full-access` only with explicit machine-wide authority and no pending
per-action approval. Review is always read-only. If narrower paths or required
capabilities cannot be enforced, use an authorized native executor or block.
Never add `--add-dir` or treat a prompt restriction as an authority boundary.

Obtain every required approval in the parent before dispatch. The external
adapter is non-interactive, so a cleared request uses `approval: never`; this
denies later escalation. If the sandbox and approval pair cannot enforce the
ceiling, do not invoke Codex.

Read only the adapter's compact JSON and exit code. Exit 69 with
`{"status":"missing_executor"}` means remove `codex` from the callable inventory
and reselect without `record-failure` or an appended dispatch attempt. Only exit
75 with `{"status":"availability_failure","reason":"..."}` authorizes a timed availability record,
and its reason must be one of the four categories. Exit 1 with
`{"status":"failed"}` stops without changing providers. Exit 0 with
`{"status":"succeeded"}` places only final agent text in the report. Adapter
output never includes raw errors, logs, or secrets.

Create a temporary artifact directory and self-contained prompt. Include the
outcome, working directory, allowed paths, constraints, verification seam, and
the required HarnessResult return shape, plus populated current state, files,
blockers, proof, tools, and approvals. Never put secrets in the prompt, report,
evidence, environment copy, or command line; never widen sandbox, path, tool, or
approval authority.

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-delegate.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
"$harness/scripts/codex-dispatch.sh" \
  --operation "$HARNESS_OPERATION" \
  --cwd "$HARNESS_CWD" \
  --sandbox "$HARNESS_SANDBOX" \
  --approval never \
  --model "$HARNESS_MODEL" \
  --effort "$HARNESS_EFFORT" \
  --prompt "$PROMPT" \
  --report "$REPORT" \
  ${HARNESS_FIXED_TARGET:+--fixed-target "$HARNESS_FIXED_TARGET"}
```

For review, the adapter accepts only a commit target, materializes it in a
temporary read-only workspace, and injects the SHA as a binding instruction.
Materialize any patch or plan snapshot plus digest in the artifact directory and
use an authorized native reviewer; never point the commit adapter at uncommitted
state. Require findings with severity, file and line, concrete failure mode, fix
direction, target, and proof classification.

For computer use outside Git, pass `--skip-git-repo-check` only for the validated
working directory. The prompt includes behavior, platform or app, allowed launch
or deep-link commands, fixtures, source-edit permission, approvals, artifact
directory, and expected observation. Require pass, fail, or blocked; performed
steps; observed behavior; screenshot or log paths; and actionable findings.

The adapter starts an ephemeral App Server thread read-only, applies only the
explicit sandbox at turn scope, and creates writable worker cache directories
inside the dispatch artifact directory. It never persists project trust. For
write operations, pin Git status before dispatch and inspect status and diff
afterward. Exit zero without the requested artifact change is a failure-shaped
claim. Never let a worker commit, push, deploy, edit global config, or take other
external action unless explicitly granted.

## Verify and return

Treat the worker report as a claim; findings, screenshots, and checks are claims
too. Confirm a review target still matches its fixed point. The parent inspects
every material finding and artifact, then reproduce the relevant checks and prove
the highest stable observable verification seam. For computer use, view decisive
artifacts, confirm their runtime state, and reproduce the observable check when
safe. Run a command-based verification seam in one dedicated tool call so its
exit status belongs to that seam; record inspection separately.

Only the parent or accepting workflow may return `status: accepted`, after the
outcome is delivered and fresh direct proof establishes it. Every terminal path
returns the complete HarnessResult; prose is not a substitute for the result.
Keep the complete
HarnessResult in the workflow state or an artifact, then render a concise user
update unless the machine contract is requested.

Return exactly: `status`; `route.requested`, `route.model`, `route.effort`,
`route.provider`, `route.executor`, `route.dispatch`; `artifacts.files`,
`artifacts.report`; `evidence.fixed_target`, `evidence.checks`,
`evidence.outcome`; and `blockers`. Optional or unavailable values stay empty;
fields are never omitted.
