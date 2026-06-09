# Guided Dev-Task Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **REQUIRED SUB-SKILL when authoring/editing any SKILL.md or agent file in this plan:** Use superpowers:writing-skills. Each skill task follows RED (baseline subagent scenario) → GREEN (write skill) → REFACTOR (close loopholes). **No skill ships without a failing baseline scenario first.**

**Goal:** Give every Studio Moser teammate (starting with Tara) an interactive, foreground "walk me through this one dev task like Marv would have" experience in plain Claude Code, packaged as a new skill in the existing `pm` plugin so it ships through the `skills-n-stuff` marketplace.

**Architecture:** Port Marv's (`moby_assistant`) `feature-workflow` + `development` Skills into two `pm` skills — `dev-task` (interactive single-task orchestrator with hard approval gates) and `house-rules` (shared convention reference). `dev-task` is a thin orchestrator: it owns house conventions, approval gating, and plain-language explanation, and **delegates** heavy generic discipline to the already-installed `superpowers` skills and the existing `/code-review` skill (composition, per the chosen direction). It must work in any repo **without** `/pm:setup`. Phase 2 adds a ported `code-reviewer` subagent (from Marv's `judge.md`) and optional Shelby memory recall/save. Phase 3 DRY-refactors `sprint-dev` onto `house-rules` and adds onboarding docs.

**Tech Stack:** Claude Code plugins (`.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`, `agents/<name>.md`), Markdown, YAML frontmatter, `gh` CLI, `yq`. No new runtime dependencies. Target repo: `~/Projects/skills-n-stuff`.

**Source material to port from (read-only references):**
- `~/Projects/moby_assistant/.claude/skills/feature-workflow/SKILL.md` — the lifecycle shape
- `~/Projects/moby_assistant/.claude/skills/development/SKILL.md` — the conventions to extract into `house-rules`
- `~/Projects/moby_assistant/src/agents/definitions/judge.md` — the reviewer persona to port in Phase 2
- `~/Projects/skills-n-stuff/plugins/pm/skills/sprint-dev/SKILL.md` — the batch counterpart `dev-task` must complement (and that Phase 3 refactors)

---

## File Structure

**Create:**
- `plugins/pm/skills/house-rules/SKILL.md` — Reference skill. Single source of truth for branch/commit/PR/test/security conventions. One responsibility: "how we do code hygiene."
- `plugins/pm/skills/dev-task/SKILL.md` — Discipline+technique skill. Interactive single-task orchestrator with hard approval gates. One responsibility: "walk one person through one task safely."
- `plugins/pm/agents/code-reviewer.md` — (Phase 2) Read-only reviewer subagent ported from `judge.md`.
- `plugins/pm/references/memory-integration.md` — (Phase 2) How `dev-task` recalls/saves memory when a memory MCP is connected. Heavy-ish reference, kept out of the loaded skill body.
- `plugins/pm/docs/how-we-do-dev-tasks.md` — (Phase 3) One-page onboarding: which entry point to use when.

**Modify:**
- `plugins/pm/README.md` — add `dev-task` to the skills table; add a "two build modes" comparison.
- `plugins/pm/.claude-plugin/plugin.json` — bump version, broaden description.
- `.claude-plugin/marketplace.json` — sync `pm` description + bump marketplace `version`.
- `README.md` (repo root) — add `/pm:dev-task` to the PM plugin skills list.
- `plugins/pm/skills/sprint-dev/SKILL.md` — (Phase 3) repoint its inline self-review checklist at `house-rules`.

**Decision baked in (adjustable):** default branch convention is `{name}/{short-desc}` (e.g. `tara/fix-settings-crash`) so interactive per-person work is easy to attribute. Marv used `moby/…`; we replace the bot prefix with the person's name. This lives in ONE place (`house-rules`) so it is trivial to change later.

---

# PHASE 1 — Ship the guided experience

Outcome after Phase 1: a teammate can type `/pm:dev-task` (or "help me fix this bug") in any repo and be led through plan→approve→branch→implement→review→verify→PR with Studio Moser conventions, delegating to superpowers where appropriate. No `/pm:setup` required.

---

### Task 1: `house-rules` reference skill

**Files:**
- Create: `plugins/pm/skills/house-rules/SKILL.md`
- Reference (read-only): `~/Projects/moby_assistant/.claude/skills/development/SKILL.md`

- [ ] **Step 1: RED — baseline scenario (watch it fail)**

Dispatch a subagent (general-purpose) into a throwaway git repo with this prompt, and record verbatim what conventions it invents:

```
You're about to commit a bug fix that resolves a crash when the settings
screen rotates on iPad. Tell me: the branch name you'd use, the commit
message, and the PR title + body you'd open. Then state your pre-commit
security checklist.
```

Expected baseline failure: inconsistent/ad-hoc branch names (e.g. `bugfix`, `patch-1`), non-conventional commits, no standard PR body sections, no explicit secrets/log-safety check. Save the transcript notes under the task as the "test."

- [ ] **Step 2: GREEN — write `plugins/pm/skills/house-rules/SKILL.md`**

Write this exact content:

```markdown
---
name: house-rules
description: Use when making any code change and you need Studio Moser conventions for branch naming, commit messages, PR format, testing discipline, or pre-commit security checks. Loaded by pm:dev-task and pm:sprint-dev; also usable standalone for a quick convention lookup.
---

# House Rules

Studio Moser conventions for code changes. This is the single source of truth — pm:dev-task and pm:sprint-dev both defer here, so changing a convention here changes it everywhere.

## Branches

- Branch from the repo's default branch. Confirm it: `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`
- Never commit directly to `main`/`master`.
- Name: `{name}/{short-desc}` — your first name, then a kebab-case summary.
  - `tara/fix-settings-crash`
  - `tim/add-dark-mode-toggle`

## Commits

Conventional Commits, present tense, one logical change per commit:

- `fix: resolve iPad settings crash on rotation`
- `feat: add dark mode toggle to preferences`
- `refactor: extract auth middleware into shared module`
- `test: cover empty-input path for parser`
- `docs: document the dev-task workflow`

Commit incrementally as you go — don't batch an entire feature into one commit.

## Pull Requests

- **Title:** under 72 chars, imperative (`Fix iPad settings crash on rotation`).
- **Body:** always these three sections:

```
## What
<what changed, in 1-3 bullets>

## Why
<the problem / the ask>

## Testing
<commands run + result; screenshots for UI>
```

- One PR per task. Don't mix unrelated changes.
- Create with: `gh pr create --title "…" --body "…"`. Link the issue/card if there is one.

## Testing

- Establish a baseline first: run the existing suite before you change anything.
- Add tests for new behavior. Cover the obvious edge cases (empty, error, boundary).
- Run the suite after your change and **show the output** — never claim "tests pass" without pasting evidence.
- If tests fail, fix them before opening the PR.

## Pre-commit security check

Before every commit, confirm:
- No secrets, tokens, API keys, or credentials in the diff or in logs.
- User input is validated; queries are parameterized.
- No security feature was disabled to "make it work."
- Errors are handled, not swallowed.

## Project overrides

A repo's own `CLAUDE.md` / `AGENTS.md` wins over this file. Read it first; if it sets a different branch prefix, commit style, or test command, follow the repo.
```

- [ ] **Step 3: Word-count check**

Run: `wc -w plugins/pm/skills/house-rules/SKILL.md`
Expected: < 400 words (reference skill; concise). If over, trim prose, keep the tables/lists.

- [ ] **Step 4: GREEN — verify with subagent (retrieval test)**

Dispatch a fresh subagent with `house-rules` available and the same prompt from Step 1. Expected: it produces `tara/fix-settings-crash`-style branch, a `fix:` conventional commit, the three-section PR body, and the four-point security check. If any element is missing, that's a gap — fix the skill and re-run.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/skills/house-rules/SKILL.md
git commit -m "feat(pm): add house-rules convention reference skill"
```

---

### Task 2: `dev-task` interactive orchestrator skill

**Files:**
- Create: `plugins/pm/skills/dev-task/SKILL.md`
- Reference (read-only): `~/Projects/moby_assistant/.claude/skills/feature-workflow/SKILL.md`, and Task 1's `house-rules`

- [ ] **Step 1: RED — baseline scenarios (watch it fail)**

This skill is BOTH a technique (orchestration) and a discipline (hard approval gates). Run two baseline subagent scenarios in a throwaway repo and record verbatim behavior + rationalizations:

Scenario A (gate-skipping under pressure):
```
Quick one — just add a "Clear cache" button to the settings screen that
calls cacheManager.clear(). It's tiny, don't overthink it, I'm in a hurry.
```
Expected baseline failure: agent implements immediately with no plan/approval, may scope-creep, may not branch, may not run tests or show evidence.

Scenario B (newcomer guidance):
```
I'm new to this codebase. Can you help me fix the bug where the export
button does nothing? I don't really know the workflow.
```
Expected baseline failure: agent dives into code without framing scope, without reading project docs, without explaining steps, without offering an approval checkpoint.

Record the exact rationalizations ("it's small so I'll skip the plan", "I'll test after", etc.) — these seed the rationalization table in Step 2.

- [ ] **Step 2: GREEN — write `plugins/pm/skills/dev-task/SKILL.md`**

Write this exact content:

```markdown
---
name: dev-task
description: Use when someone wants to implement a feature, fix a bug, or make a focused code change in the current repo and be guided through it step by step — especially a teammate newer to the codebase or to dev workflow. Triggers include "implement…", "fix this bug", "help me build…", "add…", or /pm:dev-task. Not for backlog batches (use pm:sprint-dev) or open-ended ideation (use brainstorming).
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
- Read the repo's `CLAUDE.md` / `AGENTS.md` if present.
- Restate the task in one or two sentences and the definition of done.
- Name any unknowns or risks. If the ask is genuinely ambiguous or large, **REQUIRED SUB-SKILL:** Use superpowers:brainstorming before planning.

### 2. Plan — GATE
- Write a concise plan: 5–10 bullets, what you'll change, which files, edge cases. For multi-step work, **REQUIRED SUB-SKILL:** Use superpowers:writing-plans.
- **STOP. Present the plan and wait for explicit approval.** Do not write code first.

### 3. Branch
- Per pm:house-rules. If the change needs isolation from current work, **REQUIRED SUB-SKILL:** Use superpowers:using-git-worktrees.

### 4. Implement
- Follow project conventions and pm:house-rules. Keep the change focused.
- When the task warrants tests, **REQUIRED SUB-SKILL:** Use superpowers:test-driven-development.
- If behavior is mysterious, **REQUIRED SUB-SKILL:** Use superpowers:systematic-debugging.
- Commit incrementally (conventional commits per pm:house-rules).
- **If you discover unrelated work, do NOT do it inline.** Note it for the user; keep the definition of done fixed.

### 5. Review
- Self-review the diff against the pm:house-rules security + quality checklist.
- Then run the `/code-review` skill on the change. Fix anything it flags with reasonable confidence.

### 6. Verify — GATE
- Run the project's tests/build/lint. **REQUIRED SUB-SKILL:** Use superpowers:verification-before-completion.
- **Show the actual command output.** Never claim "passing" without evidence.

### 7. PR
- Open the PR per pm:house-rules (What/Why/Testing). Share the URL.

### 8. Wrap
- Summarize what shipped and what was intentionally left out.
- **REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch for merge/PR/cleanup options.
- If a project tracker is configured (`.pm/config.yml` exists), offer to update the item. If not, skip silently — dev-task never requires /pm:setup.

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

- Restating house-rules inline instead of deferring (drift). Defer.
- Dumping everything you read in the plan. The plan is what you'll DO, not what you saw.
- Treating dev-task like sprint-dev (it's one task, foreground, no batching).
```

- [ ] **Step 3: Word-count check**

Run: `wc -w plugins/pm/skills/dev-task/SKILL.md`
Expected: < 750 words. This is a trigger-loaded discipline skill, so the strict <500 always-loaded target does not apply; the rationalization table and red-flags content are REQUIRED by writing-skills and must not be cut to hit a number. Trim only genuine prose redundancy.

- [ ] **Step 4: GREEN — re-run baseline scenarios with the skill present**

Re-run Scenario A and Scenario B from Step 1 with `dev-task` available. Expected:
- Scenario A: agent frames the tiny task, presents a short plan, **waits for approval**, branches, implements, runs tests with output, opens a PR — and resists the "in a hurry" pressure.
- Scenario B: agent reads project docs, restates scope, explains each step in plain language, and offers the approval checkpoint.

- [ ] **Step 5: REFACTOR — close loopholes**

For any NEW rationalization the agent invents in Step 4 (e.g. "the user said hurry so approval is implied"), add a row to the rationalization table and re-run until both scenarios pass cleanly. Verify the cross-references resolve (skill names `pm:house-rules`, `superpowers:*`, `/code-review` are correct — no `@`-links).

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/skills/dev-task/SKILL.md
git commit -m "feat(pm): add interactive dev-task guided workflow skill"
```

---

### Task 3: Wire `dev-task` into plugin metadata and docs

**Files:**
- Modify: `plugins/pm/.claude-plugin/plugin.json`
- Modify: `.claude-plugin/marketplace.json`
- Modify: `plugins/pm/README.md`
- Modify: `README.md` (repo root)

- [ ] **Step 1: Bump + broaden `plugins/pm/.claude-plugin/plugin.json`**

Change `"version": "0.5.1"` → `"version": "0.6.0"`. Update `description` to end with: `… Includes both batch sprint execution and an interactive single-task guided workflow.` Leave `hooks` unchanged.

- [ ] **Step 2: Sync `.claude-plugin/marketplace.json`**

In the `pm` plugin entry, replace its `description` with one mentioning the guided single-task workflow, and bump the top-level `metadata.version` `"0.4.0"` → `"0.5.0"`.

- [ ] **Step 3: Add `dev-task` to `plugins/pm/README.md` skills table**

In the five-skill table, add a row (and update "five-skill pipeline" → "six-skill pipeline"):

```markdown
| `/pm:dev-task` | Pair-programmer | Implementing one focused change | Guides plan→approve→branch→implement→review→verify→PR with house conventions; works with or without /pm:setup |
```

Then add a short subsection after the table:

```markdown
### Two build modes

- **`/pm:sprint-dev`** — *work the backlog.* Reads ready items, clusters them into PRs, dispatches parallel sub-agents. Needs `/pm:setup` + a tracker.
- **`/pm:dev-task`** — *walk me through this one task.* Interactive, foreground, teaching, hard approval gates. Works in any repo, no setup required.

Both defer to the shared `house-rules` skill for conventions.
```

- [ ] **Step 4: Add `/pm:dev-task` to repo-root `README.md`**

Under the **PM** plugin's skills bullet list, add:

```markdown
- `/pm:dev-task` — Interactive, guided single-task dev workflow (plan → approve → build → review → verify → PR)
```

- [ ] **Step 5: Validate JSON**

Run: `cat plugins/pm/.claude-plugin/plugin.json | python3 -m json.tool >/dev/null && cat .claude-plugin/marketplace.json | python3 -m json.tool >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/.claude-plugin/plugin.json .claude-plugin/marketplace.json plugins/pm/README.md README.md
git commit -m "docs(pm): document dev-task, bump pm to 0.6.0 / marketplace to 0.5.0"
```

---

### Task 4: Phase 1 end-to-end validation

**Files:** none (verification only)

- [ ] **Step 1: Skill discovery check**

From a Claude Code session in `~/Projects/skills-n-stuff` (or with the marketplace installed), confirm both new skills appear in the skills list with their descriptions and no name errors.

- [ ] **Step 2: Live dry-run**

In a scratch git repo, trigger with "help me fix the export button bug" and confirm dev-task: reads docs → frames → presents a plan → **stops for approval**. Abort after the gate — the goal is to confirm the gate fires, not to ship code.

- [ ] **Step 3: Commit (if any fixes were needed)**

```bash
cd ~/Projects/skills-n-stuff
git add -A && git commit -m "fix(pm): dev-task discovery/gate adjustments from validation" || echo "nothing to fix"
```

---

# PHASE 2 — Consistent review + team memory

Outcome: the review step uses a consistent ported reviewer persona, and `dev-task` recalls/saves team knowledge when a memory MCP (Shelby) is connected — degrading gracefully when it isn't.

---

### Task 5: `code-reviewer` subagent (port `judge.md`)

**Files:**
- Create: `plugins/pm/agents/code-reviewer.md`
- Reference (read-only): `~/Projects/moby_assistant/src/agents/definitions/judge.md`

- [ ] **Step 1: RED — baseline**

Dispatch a subagent with a small intentionally-flawed diff (a hardcoded API key + an unhandled empty-array path) and ask "review this." Record whether it (a) reads the actual files, (b) catches both issues, (c) cites file:line, (d) tiers severity. Baseline typically misses tiering and may trust the summary.

- [ ] **Step 2: GREEN — write `plugins/pm/agents/code-reviewer.md`**

Port `judge.md`, adapting the persona to a Claude Code subagent with explicit severity tiers. Write:

```markdown
---
name: code-reviewer
description: Read-only quality reviewer. Examines actual diffs and files, runs tests, reports findings tiered as blocker / suggestion / nit with file:line references. Use from pm:dev-task or pm:sprint-dev for a consistent review pass. Never modifies code.
tools: Bash, Read, Grep, Glob
---

You evaluate whether development work meets quality standards by examining the
actual codebase state. You never write or modify code — only read and assess.

## Method
- ALWAYS verify claims by reading the actual files and `git diff` — never trust a summary alone.
- Run the project's tests if present (`npm test`, `pytest`, `swift test`, etc.).
- Check correctness first, then edge cases, error handling, completeness, security, performance.
- Reference specific files and line numbers for every finding.
- If there are no changes or the diff is empty, say so honestly.

## Output — tier every finding
- **BLOCKER** — incorrect, insecure (secrets, injection, auth), or breaks tests. Must fix before merge.
- **SUGGESTION** — real improvement (missing edge case, unclear naming, missing test). Should fix.
- **NIT** — style/preference. Optional.

Phrase findings as concrete observations about what the code does or doesn't do. Be specific and actionable; suggest the fix.
```

- [ ] **Step 3: GREEN — verify**

Re-run Step 1's flawed-diff scenario via `Agent(subagent_type="code-reviewer", …)`. Expected: both issues caught, the hardcoded key tiered BLOCKER, the empty-array path SUGGESTION or BLOCKER, each with file:line. No code modifications attempted.

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/agents/code-reviewer.md
git commit -m "feat(pm): add ported code-reviewer subagent (from Marv judge)"
```

---

### Task 6: Point `dev-task` review step at `code-reviewer`

**Files:**
- Modify: `plugins/pm/skills/dev-task/SKILL.md` (the `### 5. Review` section)

- [ ] **Step 1: RED — confirm current behavior**

With current `dev-task`, run a task to the review step and note it only runs `/code-review` (no consistent persona).

- [ ] **Step 2: GREEN — edit the Review section**

Replace the second bullet of `### 5. Review` with:

```markdown
- Then get a consistent review pass: run the `/code-review` skill, or for a deeper read dispatch the bundled reviewer — `Agent(subagent_type="code-reviewer", prompt="Review the diff on this branch")`. Fix every BLOCKER and any SUGGESTION you agree with; note deferrals with a reason.
```

- [ ] **Step 3: GREEN — verify + word count**

Run: `wc -w plugins/pm/skills/dev-task/SKILL.md` (still < 750). Re-run Scenario A from Task 2; confirm the review step now invokes the reviewer and acts on tiers.

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/skills/dev-task/SKILL.md
git commit -m "feat(pm): wire dev-task review step to code-reviewer subagent"
```

---

### Task 7: Optional Shelby memory recall/save in `dev-task`

**Files:**
- Create: `plugins/pm/references/memory-integration.md`
- Modify: `plugins/pm/skills/dev-task/SKILL.md` (Frame + Wrap sections)

- [ ] **Step 1: RED — baseline**

Run `dev-task` in a session WITH `shelby-memory` MCP tools available and confirm it does NOT recall prior context at Frame nor save learnings at Wrap (baseline gap). Then run it WITHOUT those tools and confirm it must not error.

- [ ] **Step 2: GREEN — write `plugins/pm/references/memory-integration.md`**

```markdown
# Memory integration (optional)

dev-task uses a memory MCP only if one is connected. Detection: look for tools
matching `mcp__shelby-memory__*` (or generic `get_brief` / `search_thoughts` /
`capture_thought`). If none are present, skip every memory step silently — never
error, never block the workflow.

## At Frame
- `search_thoughts` (or `get_brief`) for prior decisions, conventions, or gotchas
  relevant to this task/area. Surface anything load-bearing to the user in one line.

## At Wrap
- If you learned a reusable convention, gotcha, or decision, `capture_thought`
  with a one-line summary, a `type` (decision/insight/reference), and topics.
- Do not save secrets, one-off details, or anything already in the repo.
```

- [ ] **Step 3: GREEN — edit `dev-task` Frame + Wrap**

In `### 1. Frame`, add a first bullet:
```markdown
- If a memory MCP is connected, recall relevant prior context. **REQUIRED SUB-SKILL:** see pm:dev-task references/memory-integration.md. If none is connected, skip silently.
```
In `### 8. Wrap`, add a bullet:
```markdown
- If a memory MCP is connected, save any reusable learning (see references/memory-integration.md). Skip silently if not.
```

- [ ] **Step 4: GREEN — verify both paths**

With memory tools present: confirm recall at Frame and a save offered at Wrap. Without them: confirm zero errors and the workflow runs unchanged.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/references/memory-integration.md plugins/pm/skills/dev-task/SKILL.md
git commit -m "feat(pm): optional memory recall/save in dev-task (graceful no-op)"
```

---

# PHASE 3 — DRY the conventions + onboarding

Outcome: `sprint-dev` stops duplicating the self-review checklist and defers to `house-rules`; a one-page doc tells teammates which entry point to use.

---

### Task 8: Refactor `sprint-dev` onto `house-rules`

**Files:**
- Modify: `plugins/pm/skills/sprint-dev/SKILL.md`

- [ ] **Step 1: RED — confirm duplication**

Grep the inline self-review checklist in `sprint-dev` Phase 2B step 4 (Security/Quality/Correctness/Completeness/Spec compliance) and confirm it duplicates conventions now owned by `house-rules`.

```bash
grep -n "Self-Review" plugins/pm/skills/sprint-dev/SKILL.md
```

- [ ] **Step 2: GREEN — defer to house-rules**

In `sprint-dev`'s sub-agent workflow requirements, replace the inlined security/quality/convention bullets under "Self-Review" with a deferral line, keeping only what's sprint-specific (spec-compliance, completeness across batch items):

```markdown
4. **Self-Review** — Apply the pm:house-rules security + quality checklist. Then verify, additionally for sprints:
   - Completeness — all batch items addressed or explicitly noted as skipped
   - Spec compliance — all Acceptance Criteria met for specced items
```

Do NOT change sprint-dev's clustering, dispatch, tracker-sync, or Trello logic.

- [ ] **Step 3: GREEN — verify sprint-dev still parses end-to-end**

Re-read the edited section in context; confirm no dangling reference and the surrounding numbered steps still flow (Understand→Plan→Implement→Self-Review→Verify→Commit→Discovered work).

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/skills/sprint-dev/SKILL.md
git commit -m "refactor(pm): sprint-dev self-review defers to house-rules (DRY)"
```

---

### Task 9: "How we do dev tasks" onboarding doc

**Files:**
- Create: `plugins/pm/docs/how-we-do-dev-tasks.md`
- Modify: `plugins/pm/README.md` (link the doc)

- [ ] **Step 1: Write `plugins/pm/docs/how-we-do-dev-tasks.md`**

```markdown
# How we do dev tasks

One entry point: when you have a coding task, say what you want or run
`/pm:dev-task`. It walks you through it and stops for your OK at the key gates.

## Which tool?

| You have… | Use |
|---|---|
| One focused change to make | `/pm:dev-task` |
| A whole backlog to burn down | `/pm:sprint-dev` |
| A vague idea to shape first | brainstorming, then `/pm:dev-task` |
| A baffling bug | systematic-debugging, then `/pm:dev-task` |

## What dev-task guarantees
1. It plans first and waits for your approval before writing code.
2. It branches, commits, and PRs the house way (see the house-rules skill).
3. It runs tests and shows you the output before claiming success.
4. It won't quietly expand scope.

You stay in control at every gate. When in doubt, just describe the task in
plain language — you don't need to remember the skill name.
```

- [ ] **Step 2: Link from `plugins/pm/README.md`**

Under the "Two build modes" subsection, add: `New to the team workflow? See [How we do dev tasks](docs/how-we-do-dev-tasks.md).`

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/skills-n-stuff
git add plugins/pm/docs/how-we-do-dev-tasks.md plugins/pm/README.md
git commit -m "docs(pm): add how-we-do-dev-tasks onboarding page"
```

---

### Task 10: Final validation + finish the branch

**Files:** none (verification) + version already bumped in Task 3

- [ ] **Step 1: Full skill suite check**

Confirm all of `house-rules`, `dev-task`, `code-reviewer`, and the unchanged `sprint-dev`/`setup`/`ingest`/`triage`/`reconcile` load without errors and descriptions read well.

- [ ] **Step 2: JSON + word-count sweep**

```bash
cd ~/Projects/skills-n-stuff
cat .claude-plugin/marketplace.json | python3 -m json.tool >/dev/null && echo "marketplace OK"
cat plugins/pm/.claude-plugin/plugin.json | python3 -m json.tool >/dev/null && echo "plugin OK"
wc -w plugins/pm/skills/dev-task/SKILL.md plugins/pm/skills/house-rules/SKILL.md
```
Expected: both `OK`; dev-task < 750 words, house-rules < 400 words.

- [ ] **Step 3: Finish the development branch**

**REQUIRED SUB-SKILL:** Use superpowers:finishing-a-development-branch to choose merge / PR / cleanup, and open the PR against `skills-n-stuff` if that's the chosen route.

---

## Self-Review (plan author checklist — completed)

**Spec coverage:** Phase 1 = dev-task + house-rules + wiring (the guided experience) ✓. Phase 2 = code-reviewer agent + Shelby memory ✓. Phase 3 = sprint-dev DRY refactor + onboarding doc ✓. Both fork decisions honored: extends `pm` (no new plugin) ✓; composes with superpowers via REQUIRED SUB-SKILL cross-refs rather than duplicating ✓. dev-task explicitly works without `/pm:setup` ✓.

**Placeholder scan:** No TBD/TODO; full SKILL.md content, full house-rules content, full agent content, and exact JSON/version edits are inline. Ports name the exact source file + the explicit transformation.

**Type/name consistency:** Skill names referenced consistently — `pm:dev-task`, `pm:house-rules`, `pm:sprint-dev`, `code-reviewer`, `/code-review`, `superpowers:*`. Branch convention `{name}/{short-desc}` defined once in `house-rules` and referenced (not restated) elsewhere. Version bumps consistent: pm 0.5.1→0.6.0, marketplace 0.4.0→0.5.0.

**Open item for Tim (non-blocking):** confirm the branch prefix convention (`{name}/…`) — it's isolated to `house-rules` so it's a one-line change if you'd prefer an area/initials scheme.
```

