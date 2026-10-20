# Internal Codex adapter

Read this from `harness:delegate` when the resolver returns `executor: codex`.

Enter this adapter only when the selected candidate is non-native and the
resolver returned `executor: codex`; a native selection remains native even when
its model row declares `via: codex`.

Choose `read-only` when no writes are authorized and `workspace-write` only when
writes across the working directory are authorized. Computer use may use
`danger-full-access` only with explicit machine-wide authority and no pending
per-action approval. Review is always read-only. If narrower paths or required
capabilities cannot be enforced, use an authorized native executor or block.
Never add `--add-dir` or treat a prompt restriction as an authority boundary:
the worker can ignore a prompt, so only the sandbox enforces the ceiling.

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
blockers, proof, tools, and approvals. State that the task is pre-approved and
non-interactive: the worker implements without stopping for plan approval, even
when its own instructions require one for this change class. Never put secrets in the prompt, report,
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
use an authorized native reviewer; the commit adapter cannot see uncommitted
state, so pointing it there reviews the wrong code. Require findings with
severity, file and line, concrete failure mode, fix direction, target, and proof
classification.

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
