---
name: codex-computer-use
description: Use when a request needs the Codex CLI to independently operate or inspect a local app, browser, simulator, or screenshot-capable UI. Do not use for checks available through code reading, typechecking, linting, or ordinary tests.
---

# Codex Computer Use

> **Optional cross-vendor executor.** Requires the OpenAI `codex` CLI. If `command -v codex` fails, this skill isn't available on this machine — say so and verify by another means. The model-orchestration doctrine (`references/model-orchestration.md`) routes here only when the CLI is present.

Use Codex as a separate local verification agent when the task needs real UI interaction, screenshots, simulator/browser/device state, or an independent runtime check outside Claude's current context.

Do not use this for ordinary code reading, typechecking, linting, or tests Claude can run directly. Launching apps, simulators, or browsers to verify the requested work is fine without asking; ask first only if the run could disrupt the user's environment beyond that (closing their apps, changing system settings, acting on real accounts or data).

## Workflow

1. Define exactly what behavior to verify and on what platform.
2. Create a temporary artifact directory for screenshots, logs, and the report.
3. Write a self-contained prompt and run `codex exec` with the sandbox level the task needs.
4. Read the report and screenshots, and verify key claims before presenting them.

```bash
ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/codex-computer-use.XXXXXX")"
REPORT="$ARTIFACT_DIR/report.md"
PROMPT="$ARTIFACT_DIR/prompt.md"

# Write a self-contained prompt to $PROMPT, then run:
codex exec \
  -C "$PWD" \
  -s danger-full-access \
  - < "$PROMPT" > "$REPORT"
```

Use `-s danger-full-access` for GUI automation, iOS simulators, desktop app launching, screenshots, or access outside the repo. For non-GUI checks that only need the repo and artifact directory, prefer `-s workspace-write`. Add `--skip-git-repo-check` when the working directory is not a git repository.

## Prompt Requirements

Tell Codex:

- The exact behavior to verify.
- The platform and app type, such as iOS, macOS, web, Electron, CLI, or desktop.
- Known launch commands, test credentials, seed data, deep links, or fixtures.
- Whether source edits are allowed. Default to no edits.
- Where screenshots, logs, and the final report should be saved.
- To return pass, fail, or blocked, plus steps performed, observed behavior, screenshot paths, and actionable feedback.

Keep the prompt specific enough that Codex does not need the surrounding Claude conversation.
