---
name: codex-implementation
description: Ask the Codex CLI (running whatever model it's configured with) to implement a bounded, well-specified change in the repo. This is how the Codex model is invoked for implementation work. Use when the model-selection rubric routes bulk or mechanical implementation to Codex, when the user asks Claude to have Codex implement something, or when a parallel implementation agent should produce a patch in a worktree. For work Claude should own directly, implement it yourself instead.
---

# Codex Implementation

> **Optional cross-vendor executor.** Requires the OpenAI `codex` CLI. If `command -v codex` fails, this skill isn't available on this machine — say so and implement natively instead. The model-orchestration doctrine (`references/model-orchestration.md`) routes here only when the CLI is present.

Use Codex for bounded, clearly specified implementation work — typically in a worktree or from a parallel implementation agent producing a patch. Do not let Codex commit, push, deploy, or edit global config unless the user explicitly asked for that.

## Workflow

1. Pin the current state with `git status --short` and note any user changes already present.
2. Define the implementation scope: files or behavior to change, files to avoid, constraints, and verification commands.
3. Create a temporary artifact directory for Codex's report.
4. Run `codex exec` with repo write access.
5. After Codex exits, inspect `git status` and `git diff`.
6. Run the cheapest reliable verification yourself when practical.
7. Report what Codex changed, what Claude verified, and any remaining risks.

Use this command shape:

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-implementation.XXXXXX")"
REPORT="$ARTIFACT_DIR/report.md"
PROMPT="$ARTIFACT_DIR/prompt.md"

# Write a self-contained prompt to $PROMPT, then run:
codex exec \
  -C "$PWD" \
  -s workspace-write \
  - < "$PROMPT" > "$REPORT"
```

## Example Prompt

```text
Artifact directory: /tmp/codex-implementation.XXXXXX

Goal:
- Add keyboard navigation to the command palette.

Acceptance criteria:
- ArrowUp and ArrowDown move the highlighted item.
- Enter selects the highlighted item.
- Escape closes the palette.
- Existing mouse behavior keeps working.

Constraints:
- Preserve unrelated user changes.
- Do not commit, push, deploy, or edit global config.
- Follow existing component and test patterns.
- Reuse existing code and platform features; shortest working diff; no speculative abstractions.

Verification:
- Run the focused component tests if available.
- Otherwise run the nearest relevant typecheck or test command and explain the choice.

Report:
- Files changed
- Behavioral summary
- Verification run and result
- Anything blocked or uncertain
```

Keep prompts simple and self-contained. Codex is not Claude: it does what you tell it and little more, so state the goal, constraints, and verification plainly and skip elaborate persona or process instructions.

## Review After Codex

Always inspect Codex's diff before telling the user the work is done. Revert only Codex-created mistakes when you are sure they are not user changes. If Codex leaves the repo in a worse state or changes unrelated files, stop and report the issue with the diff summary.

If `codex` is not installed or the command fails, report the error and offer to implement the change directly instead.
