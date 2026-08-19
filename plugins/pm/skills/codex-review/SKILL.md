---
name: codex-review
description: Use when an explicit request or model-routing decision calls for the Codex CLI to independently review a fixed diff, commit, branch, or implementation. Do not use for the current agent's ordinary native review.
---

# Codex Review

> **Optional cross-vendor executor.** Requires the OpenAI `codex` CLI. If `command -v codex` fails, this skill isn't available on this machine — say so and fall back to a native review. The model-orchestration doctrine (`references/model-orchestration.md`) routes here only when the CLI is present.

Use Codex as an independent reviewer when the user wants a second-pass review or when a change is broad enough that another agent's perspective is useful.

Prefer Claude's normal review process for small local checks. Do not delegate review just to avoid reading the code yourself. Treat Codex's output as evidence, not authority.

## Workflow

1. Load `references/review-proof.md` and establish its fixed point for the review target.
2. Create a temporary artifact directory for the Codex report.
3. Run `codex review` with the fixed point, task requirements, and available proof in a
   focused review prompt.
4. Confirm the target still matches the fixed point, then verify important findings
   against the code before presenting them. Apply the reference's completion conditions.

Use one of these command shapes:

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")"
REPORT="$ARTIFACT_DIR/report.md"
PROMPT="$ARTIFACT_DIR/prompt.md"

# Review staged, unstaged, and untracked changes.
codex -C "$PWD" review --uncommitted - < "$PROMPT" > "$REPORT"

# Review current branch against a base branch.
codex -C "$PWD" review --base main - < "$PROMPT" > "$REPORT"

# Review a single commit.
codex -C "$PWD" review --commit <sha> - < "$PROMPT" > "$REPORT"
```

## Review Prompt

Ask Codex to use a code-review stance:

```text
Read `plugins/pm/references/review-proof.md` and apply its review contract to this fixed
point: {base/head SHAs or uncommitted snapshot digest}.

Requirements: {approved issue, spec, or "none available"}
Available verification and proof: {commands, results, and artifacts, or "none"}

Prioritize findings over summary. For each finding include:
- severity
- file and line reference
- concrete failure mode
- suggested fix direction

Report the contract's axis results, evidence classifications, completion state, and
approval verdict. Do not edit files or invent evidence.
```

Add task-specific context when useful: requirements, risky areas, expected behavior, relevant tests, or files Claude is unsure about.

## Reporting Back

Before relaying a Codex finding, inspect the cited code or diff enough to decide whether the finding is real. In the user-facing response, separate confirmed issues from Codex suggestions you did not verify.

If Codex finds nothing, say that clearly and mention what review target it inspected.

If `codex` is not installed or the command fails, report the error and offer to review the changes directly instead.
