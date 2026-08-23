---
name: computer-use
description: >-
  Use when a Harness request requires a real local app, browser, simulator,
  screenshot, device, or other computer-use capability that code reading,
  typechecking, linting, and ordinary tests cannot provide.
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

Resolve the semantic route and matching model row through Harness:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
"$harness/scripts/rubric-path.sh"
```

Pass the resolved model and effort explicitly on every dispatch. If `via` is
absent, use the capable native runtime with the complete HandoffPacket and the
requested context mode.

### Internal Codex adapter

For `via: codex`, first require `command -v codex`. Use `read-only` or
`workspace-write` for repo-contained checks. Use `danger-full-access` only when
the request explicitly authorizes machine-wide access and the runtime still
retains every required confirmation; if that broad sandbox would exceed the
authority ceiling, choose an authorized native executor or return `blocked`.

The prompt contains the exact behavior, platform/app, allowed launch or deep-link
commands, fixtures or seed state, source-edit permission, working directory,
allowed paths, approvals, artifact directory, verification seam, and required
HarnessResult return shape. Existing authenticated runtime state may be used only
within the request's approval boundary. Never embed credentials or other secrets.

```bash
command -v codex >/dev/null 2>&1 || exit 127
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/harness-computer-use.XXXXXX")"
PROMPT="$ARTIFACT_DIR/prompt.md"
REPORT="$ARTIFACT_DIR/report.md"
codex exec \
  -C "$HARNESS_CWD" \
  -s "$HARNESS_SANDBOX" \
  -m "$HARNESS_MODEL" \
  -c model_reasoning_effort="$HARNESS_EFFORT" \
  - < "$PROMPT" > "$REPORT"
```

Add `--skip-git-repo-check` only when the validated working directory is not a
Git repository. Never add an approval bypass or broader directory. Require the
worker to report pass, fail, or blocked; steps performed; observed behavior;
screenshot/log paths; and actionable findings.

## Verify and return

Treat the report and screenshots as claims. The parent views the decisive
artifacts, confirms they came from the requested runtime state, and reproduces
the relevant observable check when safe. Pass the resolved model and effort
explicitly on any retry. Only the parent or accepting workflow may return
`status: accepted`, after the outcome is delivered and current direct proof
establishes it.

Return every field in the HarnessResult: `status`, `route.requested`,
`route.actual_model`, `route.effort`, `route.provider`, `route.executor`,
`artifacts.files`, `artifacts.report`, `evidence.fixed_target`,
`evidence.checks`, `evidence.outcome`, `telemetry.attempts`,
`telemetry.elapsed`, `telemetry.verification_failures`,
`telemetry.token_or_quota_usage`, `shelby.project_id`, `shelby.run_id`,
`shelby.checkpoint_ids`, and `blockers`. Optional or unavailable values stay
empty; fields are never omitted.
