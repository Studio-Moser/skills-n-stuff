---
name: dev-task
description: Use when someone wants to implement a feature, fix a known bug, or make a focused code change in the current repo and be guided through it — including small or quick changes (a button, a one-line fix), which still go through the guided workflow rather than being done ad hoc. Especially for teammates newer to the codebase or to dev workflow. Triggers include "implement…", "fix this…", "add…", "build…", "patch…", "wire up…", "refactor this…", or /pm:dev-task. Do NOT use for: batching a backlog or sprint (use pm:sprint-dev), open-ended design or ideation (use brainstorming), reviewing an existing PR (use /code-review), or diagnosing an unknown cause before any fix is known (use systematic-debugging).
allowed-tools: "Bash Read Write Edit Agent Skill"
---

# PM — Dev Task

Guide ONE person through ONE development task, foreground and interactive, the Studio Moser way. You are a patient pair-programmer: explain what you're doing and why, and **stop at the approval gates**. This is the single-task counterpart to pm:sprint-dev (which batches a backlog).

**REQUIRED SUB-SKILL:** Use pm:house-rules for all branch/commit/PR/test/security conventions. Do not restate them — defer.

**Foundational rule:** Violating the letter of a gate is violating its spirit. "It's small" / "I'm in a hurry" are not exemptions.

## When to use this vs. alternatives

| Situation | Use |
|---|---|
| One focused change, want guidance/gates | **dev-task** (this) |
| A backlog of ready items, batch into PRs | pm:sprint-dev |
| Requirements are vague / design is open | superpowers:brainstorming first, then come back |
| You're stuck on a bug, behavior is mysterious | superpowers:systematic-debugging |

## The workflow

### 1. Frame
- If a memory MCP is connected (e.g. shelby-memory), recall relevant prior context; skip silently if not. See references/memory-integration.md.
- Read the repo's `CLAUDE.md` / `AGENTS.md` if present.
- Load your model rubric from `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`. If it's missing, offer to run `/fleet:model-rubric` (or follow `studio-baseline/Rubric_Setup.md` with no plugin) — this is user-global, done once. Use it when choosing models for any sub-agent work.
- Restate the task in one or two sentences and the definition of done.
- Name any unknowns or risks. If the ask is genuinely ambiguous or large, **REQUIRED SUB-SKILL:** Use superpowers:brainstorming before planning.

### 2. Plan — GATE
- Write a concise plan: 5–10 bullets, what you'll change, which files, edge cases. For multi-step work, **REQUIRED SUB-SKILL:** Use superpowers:writing-plans.
- **STOP. Present the plan and wait for the user to explicitly approve this plan.** Until then take no implementation action — no branching, no creating or editing files, no code.

### 3. Branch
- Per pm:house-rules. If the change needs isolation from current work, **REQUIRED SUB-SKILL:** Use superpowers:using-git-worktrees.

### 4. Implement
- Follow project conventions and the pm:house-rules implementation discipline (shortest diff, reuse first, root cause over symptom, no speculative abstractions). Keep the change focused.
- When the task warrants tests, **REQUIRED SUB-SKILL:** Use superpowers:test-driven-development.
- If behavior is mysterious, **REQUIRED SUB-SKILL:** Use superpowers:systematic-debugging.
- Commit incrementally (conventional commits per pm:house-rules).
- **If you discover unrelated work, do NOT do it inline.** Note it for the user; keep the definition of done fixed.

### 5. Review
- Self-review against the pm:house-rules security + quality checklist — but per house-rules Verification, your own pass is a first draft, not proof.
- Then run `/code-review`, or dispatch the `code-reviewer` subagent for an independent read that re-runs the tests itself — pass `model` explicitly, set to `routing.review` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`); omitting it inherits the session model. If you want an adversarial read of *your own* diff by a model that hasn't seen this conversation, that's `routing.independent` — ask first, it's the expensive option. Fix every BLOCKER and any SUGGESTION you agree with; dispute wrong findings per house-rules rather than distorting correct code.

### 6. Verify — GATE
- Run the project's tests/build/lint. **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion.
- **Run the commands yourself and paste the actual output here.** Never claim "passing" without pasted evidence.

### 7. PR
- Open the PR per pm:house-rules (What/Why/Testing). Share the URL.

### 8. Wrap
- Summarize what shipped and what was intentionally left out.
- **REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch for merge/PR/cleanup options.
- If a project tracker is configured (`.pm/config.yml` exists), offer to update the item. If not, skip silently — dev-task never requires /pm:setup.
- If a memory MCP is connected, save any reusable learning; skip silently if not. See references/memory-integration.md.

## Rationalization table — do not skip gates

| Excuse | Reality |
|---|---|
| "It's tiny, skip the plan" | Tiny changes still surprise. A 5-bullet plan costs 30 seconds and catches scope errors. Present it. |
| "They're in a hurry" | The gate IS the speed — it prevents the rework that's actually slow. |
| "I'll run tests after the PR" | A PR is a claim it works. Verify before, with evidence. |
| "I'll just fix this other thing too" | That's scope creep. Note it; keep done fixed. |
| "I already eyeballed it, it's fine" | Eyeballing ≠ running. Run it and paste output. |
| "Branching is overkill here" | Never commit to main. Branch per house-rules. |

## Red flags — STOP

- About to Edit/Write code before the user approved a plan.
- About to say "done" / "tests pass" without pasted command output.
- About to add something not in the agreed scope.
- Working directly on the default branch.

All of these mean: stop, return to the relevant gate.

## Common mistakes

- Restating house-rules inline instead of deferring — defer.
- Dumping everything you read into the plan — the plan is what you'll DO, not what you saw.
