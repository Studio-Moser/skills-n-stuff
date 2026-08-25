---
name: computer-use
description: >-
  Use when a Harness request needs proof from driving a machine, not reading
  code: launch or attach to a live app, page, browser, simulator, or device;
  exercise the flow; and capture fresh visual or runtime evidence you inspect.
  Trigger for opening, clicking through, verifying on screen/device, or proving
  behavior from a worktree under stated path, permission, or artifact
  constraints. Also use when Accessibility, Screen Recording, or simulator
  capability may be missing, so the result must be blocked rather than replaced
  with code inspection. Skip reading existing screenshots, one-off screenshot
  capture without workflow verification, writing tests without running a
  browser, explaining OS settings, or code-only verification.
---

# Harness Computer Use

Execute or verify one bounded computer-use outcome without changing the
request's confirmation or permission boundary.

Read the schema in
[references/harness-contract.md](../../references/harness-contract.md), route
rules in [references/routing.md](../../references/routing.md), packet shape in
[references/handoff.md](../../references/handoff.md), evidence rules in
[references/verification.md](../../references/verification.md), context choice
in [references/context.md](../../references/context.md), and optional state rules
in [references/shelby-integration.md](../../references/shelby-integration.md).

## Validate capability and authority

`operation` must be `computer-use`. Require the exact behavior, platform/app,
verification seam and expected observation, required tools, and authority
ceiling. Confirm every required computer-use capability from the runtime's
actual callable tools; an installed plugin or config entry is not proof.

Preserve `authority.working_directory` exactly. Preserve the runtime confirmation
policy for launching or controlling apps, accounts, devices, settings, and real
data. Opening the requested app or simulator for the approved check is in scope;
closing user apps, changing system settings, authenticating, purchasing,
publishing, sending, or mutating real accounts/data still requires the listed
approval. Source edits default to disallowed unless `allowed_paths` grants them.

If a capability is unavailable, use only an equivalent explicitly authorized by
the request. If none exists, return `status: blocked` with the missing capability;
do not downgrade the check to code inspection.

Use Shelby only when callable tool names prove it is available and canonical
project scope has been resolved. Missing Shelby is non-blocking.

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

Read the returned JSON structurally. A blocked selection returns the complete
blocked HarnessResult. A matching native provider uses the capable native
runtime even when the selected row has `via`; otherwise the returned external
executor must be explicit, callable, and able to enforce every required
computer-use capability and approval. If `via` is absent, use the native runtime
only when the selected provider is native, with the complete HandoffPacket and
requested context mode. Pass the resolved model and effort explicitly on every
dispatch.

The only availability reasons are `quota`, `authentication`, `rate_limit`,
`provider_unavailable`, and preflight `missing_executor`. The resolver owns
`missing_executor`, open-circuit skips, cooldowns, and the single half-open probe;
do not append a preflight skip to `--attempted`. After dispatch, classify only a
bounded typed availability result from the executor boundary; do not infer one
from unbounded raw provider text. On `quota`, `authentication`, `rate_limit`, or
`provider_unavailable`, call `resolve-route.py record-failure` for the selected
provider and executor, append the selected model-effort candidate to
`HARNESS_ATTEMPTED`, and repeat with the unchanged HarnessRequest and confirmation
policy. On success, call `resolve-route.py record-success` for that provider and
executor. Any non-availability response also proves endpoint health, so clear an
outstanding circuit before handling its task or output failure. Task, output,
verification, authority, and approval failures stop without changing providers.
Between iterations, do not change the request's operation, tools, approvals,
working directory, allowed paths, fixed target, sandbox, verification seam, or
confirmation policy; only the attempted list and selected route data change.
Exhausting the unique-provider chain returns `blocked`; the loop cannot exceed
the authorized candidates and cannot downgrade the requested computer-use proof.

In the terminal result, copy the selection's `resolution` to
`route.resolution`; set `route.attempted` to every candidate actually dispatched,
including the terminal candidate; and copy the typed selection `reason` to
`route.fallback_reason`, or leave it empty. Never add preflight skips to
`route.attempted`.

### Internal Codex adapter

For `via: codex`, first require `command -v codex`. Use `read-only` or
`workspace-write` for repo-contained checks. Use `danger-full-access` only when
the request explicitly authorizes machine-wide access and no per-action approval
remains. A non-interactive Codex run cannot surface a required UI confirmation.
Obtain it in the parent first, use an authorized native runtime that can retain
it, or return `blocked`. Once all approvals are cleared, use `approval: never` so
Codex cannot request a later sandbox escalation. If that sandbox/approval pair
would exceed the authority ceiling, choose an authorized native executor or
return `blocked`.

The prompt contains the exact behavior, platform/app, allowed launch or deep-link
commands, fixtures or seed state, source-edit permission, working directory,
allowed paths, approvals, artifact directory, verification seam, and required
HarnessResult return shape. Existing authenticated runtime state may be used only
within the request's approval boundary. Never embed credentials or other secrets.

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-computer-use.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
"$harness/scripts/codex-dispatch.sh" \
  --operation computer-use \
  --cwd "$HARNESS_CWD" \
  --sandbox "$HARNESS_SANDBOX" \
  --approval never \
  --model "$HARNESS_MODEL" \
  --effort "$HARNESS_EFFORT" \
  --prompt "$PROMPT" \
  --report "$REPORT"
```

Pass `--skip-git-repo-check` to the adapter only when the validated working
directory is not a Git repository. The adapter never adds automatic approval,
an approval bypass, or a broader directory. Require the worker to report pass,
fail, or blocked; steps performed; observed behavior; screenshot/log paths; and
actionable findings.

## Verify and return

Treat the report and screenshots as claims. The parent views the decisive
artifacts, confirms they came from the requested runtime state, and reproduces
the relevant observable check when safe. Pass the resolved model and effort
explicitly on any retry. Only the parent or accepting workflow may return
`status: accepted`, after the outcome is delivered and current direct proof
establishes it.

Return every field in the HarnessResult: `status`, `route.requested`,
`route.actual_model`, `route.effort`, `route.provider`, `route.executor`,
`route.resolution`, `route.attempted`, `route.fallback_reason`,
`artifacts.files`, `artifacts.report`, `evidence.fixed_target`,
`evidence.checks`, `evidence.outcome`, `telemetry.attempts`,
`telemetry.elapsed`, `telemetry.verification_failures`,
`telemetry.token_or_quota_usage`, `shelby.project_id`, `shelby.run_id`,
`shelby.checkpoint_ids`, and `blockers`. Optional or unavailable values stay
empty; fields are never omitted.
