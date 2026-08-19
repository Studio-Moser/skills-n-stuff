---
name: codex-implementation
description: Ask the Codex CLI (running whatever model it's configured with) to implement a bounded, well-specified change in the repo. This is how the Codex model is invoked for implementation work. Use when the model-selection rubric routes bulk or mechanical implementation to Codex, when the user asks Claude to have Codex implement something, or when a parallel implementation agent should produce a patch in a worktree. For work Claude should own directly, implement it yourself instead.
---

# Codex Implementation

> **Optional cross-vendor executor.** Requires the OpenAI `codex` CLI. If `command -v codex` fails, this skill isn't available on this machine — say so and implement natively instead. The model-orchestration doctrine (`references/model-orchestration.md`) routes here only when the CLI is present.

Use Codex for bounded, clearly specified implementation work — typically in a worktree or from a parallel implementation agent producing a patch. Do not let Codex commit, push, deploy, or edit global config unless the user explicitly asked for that.

## Workflow

1. Pin the current state with `git status --short` and note any user changes already present.
2. Load `references/work-readiness.md`. Define one delivery slice with its approved
   `Outcome`, `Blockers`, `Testing Seam`, and current `Proof`, plus files or behavior to
   change, files to avoid, and constraints. If a blocker is unresolved, stop and report
   it instead of invoking Codex.
3. Create a temporary artifact directory for Codex's report.
4. Run `codex exec` with repo write access.
5. After Codex exits, inspect `git status` and `git diff`.
6. Execute the named `Testing Seam` yourself and record its actual result as `Proof`.
7. Report what Codex changed, whether the outcome was delivered, the proof, and any remaining risks.

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

Delivery slice:
- Outcome: Keyboard users can navigate, select, and dismiss command-palette results.
- Blockers: none
- Testing Seam: Run the existing command-palette component test through keyboard
  navigation; ArrowUp/ArrowDown change the highlight, Enter selects, and Escape closes.
- Proof: unproven before implementation

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
- This is a non-interactive run: no user is present to answer questions or approve
  plans. Do not stop at any plan-approval or confirmation gate — proceed directly
  to implementation within the scope above.

Verification:
- Execute the Testing Seam above and record the command and actual result as Proof.
- Also run the nearest relevant typecheck or broader test command if the project requires it.

Report:
- Files changed
- Outcome delivered or not delivered
- Verification run and result
- Proof from the Testing Seam
- Anything blocked or uncertain
```

Keep prompts simple and self-contained. Codex is not Claude: it does what you tell it and little more, so state the goal, constraints, and verification plainly and skip elaborate persona or process instructions.

## Success-shaped failures to check for

**The approval-gate no-op.** Session-level instructions on the machine (e.g. the
superpowers plugin enabled in Codex) can make Codex plan and then halt asking the
user to "reply approved" — which non-interactive `exec` can never answer. Codex
then exits 0 having changed nothing, which looks like success. The non-interactive
constraint line in the prompt above preempts this; still, always confirm via
`git status --short` that files actually changed before trusting the report. If
Codex halted at a gate anyway, resume the session with the approval:

```bash
cd "$REPO"   # resume rejects -C/-s/-m; re-pass sandbox and model as -c overrides
codex exec resume --last \
  -c sandbox_mode="workspace-write" \
  -c model="<model>" -c model_reasoning_effort="<effort>" \
  "approved" > "$ARTIFACT_DIR/report2.md" 2>&1
```

**"Verified" that verified nothing.** Codex reports whatever command it ran; that
command may not cover the change (e.g. a repo where `npm run check` is only
typecheck + lint, no tests). Treat Codex's verification claims as unverified until
you re-run the real test suite yourself — step 6 is mandatory, not optional, and
must include the tests, not just the command Codex happened to name.

## Review After Codex

Always inspect Codex's diff before telling the user the work is done. Revert only Codex-created mistakes when you are sure they are not user changes. If Codex leaves the repo in a worse state or changes unrelated files, stop and report the issue with the diff summary.

If `codex` is not installed or the command fails, report the error and offer to implement the change directly instead.
