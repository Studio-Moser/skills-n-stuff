---
name: sprint-dev
description: >-
  Interactive sprint worker. Presents eligible tracker items with context,
  groups them into proposed PRs, and waits for your approval before building.
  Dispatches parallel sub-agents with self-review and full testing for each
  PR. Manual-only — you decide when to build and what to ship. Trigger:
  "let's build", "work the tracker", "what can we ship", "sprint",
  "implement items", or /product-pulse:sprint-dev.
---

# Product Pulse — Sprint Dev

Interactive skill that presents the research tracker backlog, proposes how items should be grouped into PRs, and — with your approval — dispatches parallel sub-agents to implement, review, test, and PR each batch.

**Manual only.** You decide when to run this and what to build.

---

## Ground Rules

- **Never auto-build.** Always present the proposal and wait for user approval.
- **Parallel when safe.** Dispatch independent PRs in parallel when they don't touch the same files.
- **Every PR must pass.** Sub-agents run self-review + full test suite before PRing.
- **Tracker is sacred.** Only the orchestrator edits the tracker, never sub-agents.
- **Report live.** Tell the user about each PR as it completes, don't batch results.

---

## Phase 0: Sync & Reconcile

### 0.1 Read Product Context

Read `{research_dir}/research-context.md` for project structure, repo info, and tech stack. If missing, tell the user to run `/product-pulse:setup`.

### 0.2 Pull Latest

```bash
git pull origin main 2>/dev/null || true
```

For multi-repo projects, pull all repos listed in research-context.md.

### 0.3 Context Recovery

Search memory for prior sprint-dev runs — check for known blockers, failed items, in-flight branches.

### 0.4 Check Existing Branches

```bash
git branch -a | grep overnight/ 2>/dev/null
```

Note any in-flight branches with open PRs.

### 0.5 Reconcile Awaiting PR Items

Check the **Awaiting PR** section of the tracker. For each item:

```bash
gh pr view <PR-URL> --json state,mergedAt 2>/dev/null
```

- **merged** → move to Completed (add merge date)
- **closed** (rejected) → move back to Open Items
- **open** → leave in Awaiting PR, skip this item

Commit any moves: `docs: reconcile tracker PRs`

---

## Phase 1: Parse, Filter & Propose

### 1.1 Parse the Tracker

Read `{research_dir}/research-tracker.md` and parse the Open Items table.

### 1.2 Read the Weekly Focus List

Find the most recent `*-focus.md` in `{research_dir}/weekly/` (search recursively). Extract focus item numbers, strategic direction, and top 3 priorities.

### 1.3 Filter Eligible Items

Exclusions:
- Items starting with "Monitor" or "Calendar"
- Items in Awaiting PR
- Items with active `overnight/*` branches

Strategic focus (if weekly focus exists):
- **Include** items in the focus list
- **Include** P0/P1 items regardless
- **Exclude** all others

If no focus file exists, include all eligible items sorted by priority.

### 1.4 Cluster Into Proposed PRs

Group items by relatedness — items that touch the same files, the same domain area, or the same feature scope should be in the same PR. Use the product context to understand the project structure.

General cluster categories (adapt to the project):
- **deps** — Package updates, version bumps, security patches
- **feature** — New features or feature enhancements
- **fix** — Bug fixes, error handling improvements
- **infra** — Infrastructure, config, tooling, CI/CD
- **content** — Copy, documentation, editorial changes
- **data** — Data sources, connectors, integrations
- **ui** — Frontend components, pages, visualizations
- **misc** — Items that don't clearly fit

Collision detection: items modifying the same files MUST go in the same cluster.
Batch size cap: max 8 items per batch.

For multi-repo projects, also route each item to its target repo based on the product context.

### 1.5 Present the Proposal (STOP HERE — INTERACTIVE)

Present the full proposal and **wait for user approval**:

```
Product Pulse — Sprint Proposal
=================================

Weekly Direction: {theme or "No weekly brief"}
Top Priorities: {p1} | {p2} | {p3}

Tracker: {N} open, {N} eligible, {N} awaiting PR

--- Proposed PRs ---

PR 1: {cluster name} ({N} items)
Branch: pulse/{cluster}-{YYYY-MM-DD}
  #{n} {item description}
     Why: {context from the research report that found this}
     Effort: {ease} | Impact: {impact} | Priority: {priority}
     Files likely touched: {file hints}
  ...
  Estimated scope: {small/medium/large}

PR 2: ...

--- Not Included ---
{N} items excluded (backlog, not in weekly focus, or watch-and-wait)
```

Ask: **"Which PRs should I build? Say 'all', list specific numbers (e.g. '1 and 3'), or 'none' to just review. You can also drop individual items."**

**WAIT FOR RESPONSE.** Do not proceed without explicit approval.

---

## Phase 2: Build Approved PRs

For each approved PR, in priority order:

### 2A. Create Branch

```bash
git checkout main && git pull
git checkout -b pulse/{cluster}-{YYYY-MM-DD}
```

For worktree-capable projects:
```bash
git worktree add .claude/worktrees/pulse-{cluster}-{date} -b pulse/{cluster}-{YYYY-MM-DD} main
```

### 2B. Dispatch Sub-Agent

Build a comprehensive sub-agent prompt with:
- Batch items (number, description, priority, ease, report link)
- Product context (tech stack, conventions, test commands)
- Branch/worktree path
- Memory context for each item

**Sub-agent workflow requirements:**

1. **Understand** — Read linked research report, relevant source files
2. **Plan** — Brief implementation plan. Medium/Hard items: show plan and get approval
3. **Implement** — Write code. TDD where applicable
4. **Self-Review** — Check against:
   - Security (no injection, no secrets, no OWASP top 10)
   - Quality (no dead code, no debugging artifacts, follows conventions)
   - Correctness (edge cases, error paths, types)
   - Completeness (all items addressed or noted as skipped)
5. **Verify** — Run project test/build commands from product context
6. **Commit** — Atomic commits, clear messages

Dispatch independent PRs in parallel. Conflicting PRs run sequentially.

```
Agent(subagent_type="general-purpose", prompt=built_prompt)
```

### 2C. Report Results

After each sub-agent completes, immediately tell the user:

```
PR Complete: {cluster}
========================
Branch: pulse/{cluster}-{date}
PR: {URL}
Items completed: #{n}, #{n}
Items skipped: #{n} (reason)
Tests: {pass/fail}
Review: {issues found}
```

### 2D. Sync Tracker

- Move completed items → Awaiting PR (with PR URL, date)
- Leave skipped items in Open Items
- Commit: `docs: update tracker — {cluster} batch complete`
- Save to memory

Clean up worktree if used.

---

## Error Recovery

- **Sub-agent failure**: Push partial work if commits exist, otherwise delete branch. Report to user, ask retry or skip.
- **Repo failure**: Reset to main, log affected items, continue with next batch.
- **Never**: force push, modify main directly (except tracker), delete remote branches, skip verification, proceed without user approval.

---

## Phase 3: Summary

```
Product Pulse — Sprint Summary ({date})
==========================================
PRs built: {N} of {N} approved
Items completed: {N}
Items skipped: {N}
PRs created:
  - {cluster}: {URL}
Tracker: {N} remaining open items
```
