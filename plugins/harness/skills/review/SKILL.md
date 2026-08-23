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

## Resolve and dispatch

Resolve the route and matching model row through Harness:

```bash
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/rubric-path.sh" --check
"$harness/scripts/rubric-path.sh"
```

Pass the resolved model and effort explicitly on every dispatch. If `via` is
absent, use the native runtime with the chosen context mode and complete
HandoffPacket. Missing required capability produces only an authorized fallback
or `blocked`; never silently weaken independence or authority.

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
`artifacts.files`, `artifacts.report`, `evidence.fixed_target`,
`evidence.checks`, `evidence.outcome`, `telemetry.attempts`,
`telemetry.elapsed`, `telemetry.verification_failures`,
`telemetry.token_or_quota_usage`, `shelby.project_id`, `shelby.run_id`,
`shelby.checkpoint_ids`, and `blockers`. Optional or unavailable values stay
empty; fields are never omitted.
