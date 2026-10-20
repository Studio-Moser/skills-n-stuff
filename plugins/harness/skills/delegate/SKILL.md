---
name: delegate
description: >-
  Delegates bounded execution, fixed-target or independent review, or computer-use checks to a subagent or Codex through Harness routing. Use when an agent hands such work to a worker.
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
never substitute a parent checkout, because the worker would then act on a tree
the request did not authorize.

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
digest. Default authority to read-only. A moving current diff cannot be the fixed
target, because its findings would not attach to a stable revision. If the target, digest, requirements, seam, fixture, or oracle
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
them. If no explicitly authorized equivalent capability exists, return `status: blocked`
rather than downgrade to code inspection, which cannot observe runtime behavior.

## Resolve and dispatch

Resolve the active rubric only through Harness:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
RUBRIC_PATH="$("$harness/scripts/rubric-path.sh")"
```

Populate the resolver inputs before the loop:

- `HARNESS_ROUTE`: the request's semantic route.
- `HARNESS_NATIVE_PROVIDER`: the rubric `provider` value of the host runtime
  that can spawn native subagents, such as `anthropic` in Claude Code or
  `openai` in Codex.
- `HARNESS_EXECUTORS`: a JSON list of callable external executors, `[]` when
  none. Before selection, include `codex` in `HARNESS_EXECUTORS` only when
  `codex-app-server.py check` returns `{"status":"available"}`;
  `command -v codex` alone is insufficient.
- `HARNESS_AUTHORING_PROVIDERS`: for `independent` only, every provider that
  authored the target.
- `HARNESS_ACTIVE_CANDIDATE` and `HARNESS_ATTEMPTED`: described below.

Populate `HARNESS_ACTIVE_CANDIDATE` from trustworthy host runtime metadata when
the host exposes the current model and effort. Prefer that metadata to an
inherited shell value, which may describe a parent session. If no trustworthy
identity exists, leave it empty and record that direct same-candidate admission
was unavailable.

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

For `independent`, add the authoring-providers argument described above; the
shorter call would let an authoring provider review its own work. Read the returned JSON structurally. A blocked selection
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
classification below to its typed result. In Claude Code, the equivalent native
dispatch is the Agent tool: pass the resolved model and effort as its `model`
and `effort` parameters, with the packet as the prompt.

The only availability reasons are `quota`, `authentication`, `rate_limit`,
`provider_unavailable`, and preflight `missing_executor`. The resolver owns
preflight skips, open circuits, cooldowns, and the single half-open probe. After
dispatch, classify only a bounded typed executor result; raw provider text is
unstable and may carry secrets.
On the four timed availability failures, call `resolve-route.py record-failure`
for the selected provider and executor, append its model-effort candidate to
`HARNESS_ATTEMPTED`, and select again with the unchanged HarnessRequest. On
success, call `resolve-route.py record-success`. A non-availability response also
proves endpoint health, so clear an outstanding circuit before handling its task
or output failure.

Task, output, verification, authority, and approval failures stop without
changing providers. Between iterations, keep operation, tools, approvals,
working directory, allowed paths, fixed target, sandbox, confirmation policy,
and verification seam unchanged; a fallback changes only the provider. Exhausting the authorized unique-provider chain
returns blocked. The attempted candidates and selection reason remain internal
resolver-loop state; they are not HarnessResult fields.

### Codex executor

When the resolver returns `executor: codex`, read
[references/codex-adapter.md](../../references/codex-adapter.md) before
dispatch. It owns the sandbox, approval, prompt, exit-code, and review rules for
the external Codex adapter.

## Verify and return

Treat the worker report as a claim; findings, screenshots, and checks are claims
too. Confirm a review target still matches its fixed point. In the parent,
inspect every material finding and artifact, then reproduce the relevant checks
and prove the highest stable observable verification seam. For computer use, view decisive
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
`evidence.outcome`; and `blockers`. Optional or unavailable values stay empty
rather than omitted, so every consumer parses one shape.
