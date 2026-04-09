---
name: sprint-dev
description: >-
  Interactive sprint worker. Presents eligible backlog items with context,
  groups them into proposed PRs, and waits for your approval before building.
  Dispatches parallel sub-agents with self-review and full testing for each
  PR. Manual-only — you decide when to build and what to ship. Trigger:
  "let's build", "work the backlog", "what can we ship", "sprint",
  "implement items", or /product-pulse:sprint-dev.
---

# Product Pulse — Sprint Dev

Interactive skill that presents the backlog, proposes how items should be grouped into PRs, and — with your approval — dispatches parallel sub-agents to implement, review, test, and PR each batch.

**Manual only.** You decide when to run this and what to build.

---

## Ground Rules

- **Never auto-build.** Always present the proposal and wait for user approval.
- **Parallel when safe.** Dispatch independent PRs in parallel when they don't touch the same files.
- **Every PR must pass.** Sub-agents run self-review + full test suite before PRing.
- **Backlog is sacred.** Only the orchestrator edits the backlog, never sub-agents.
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
git branch -a | grep pulse/ 2>/dev/null
```

Note any in-flight branches with open PRs.

### 0.5 Reconcile Awaiting PR Items

Check the **Awaiting PR** section of the backlog. For each item:

```bash
gh pr view <PR-URL> --json state,mergedAt 2>/dev/null
```

- **merged** → remove from backlog (log as done)
- **closed** (rejected) → move back to Ready
- **open** → leave in Awaiting PR, skip this item

Commit any moves: `backlog: reconcile PRs`

---

## Phase 1: Parse, Filter & Propose

### 1.1 Parse the Backlog

Read `todos/backlog.md` and parse all sections. Focus on:
- **Ready** table — items with specs that are approved for implementation
- **Roadmap** table — strategic items (only pick up if user has set status to `ready`)
- **Ideas** table — note S-sized items as "quick wins" available for promotion

### 1.2 Read the Weekly Recommendations

Find the most recent `*-recommendations.md` in `{research_dir}/` (search recursively). Extract:
- Suggested items for speccing
- Strategic direction and top 3 priorities
- Quick wins identified

### 1.3 Freshness Check

**For each `ready` item that has a spec** in `todos/specs/`:

1. Read the spec's Code References table
2. For each file listed, diff against the Base SHA:
   ```bash
   git diff {base_sha}..HEAD -- {file_path}
   ```
3. Classify freshness:
   - **Green** (no changes to referenced files) → proceed normally
   - **Yellow** (<20 lines changed across all referenced files) → proceed, but include diff summary in proposal notes
   - **Red** (significant divergence: 20+ lines changed, files deleted, or major refactors) → skip this item, flag for re-spec
4. Log the check in the spec's Freshness Log table:
   ```
   | {today} | sprint-dev | {Green/Yellow/Red} | {summary of changes or "No changes"} |
   ```

If a spec has no Code References table or no Base SHA, treat as Yellow with a note.

### 1.4 Filter Eligible Items

Primary pool: **Ready** items with Green or Yellow freshness.

Quick wins pool: S-sized **Ideas** items (present separately as available for user promotion).

Exclusions:
- Items in Awaiting PR
- Items with active `pulse/*` branches
- Items with Red freshness (flag for re-spec)
- Monitor, Manual, and Dismissed items

### 1.5 Cluster Into Proposed PRs

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

### 1.6 Present the Proposal (STOP HERE — INTERACTIVE)

Present the full proposal and **wait for user approval**:

```
Product Pulse — Sprint Proposal
=================================

Weekly Direction: {theme or "No weekly brief"}
Top Priorities: {p1} | {p2} | {p3}

Backlog: {N} ready, {N} ideas, {N} awaiting PR

--- Freshness Results ---

Green: {N} items (specs current)
Yellow: {N} items (minor drift — see notes)
Red: {N} items (need re-spec, skipped)

--- Proposed PRs ---

PR 1: {cluster name} ({N} items)
Branch: pulse/{cluster}-{YYYY-MM-DD}
  #{n} {item description}
     Spec: todos/specs/{n}-{slug}.md
     Freshness: {Green|Yellow} {notes if Yellow}
     Size: {S|M|L|XL} | Priority: {priority}
     Files likely touched: {file hints}
  ...
  Estimated scope: {small/medium/large}

PR 2: ...

--- Quick Wins (S-sized Ideas — need promotion) ---

  #{n} {item description} — {domain}
  #{n} {item description} — {domain}

  Say "promote #N" to move an idea to Ready for this sprint.

--- Flagged for Re-spec ---

  #{n} {item description} — {reason for Red freshness}

--- Not Included ---
{N} items excluded (ideas without promotion, monitor, manual)
```

Ask: **"Which PRs should I build? Say 'all', list specific numbers (e.g. '1 and 3'), or 'none' to just review. You can also promote quick wins or drop individual items."**

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
- Batch items (number, description, priority, size, spec link)
- **For L/XL items with specs**: include the full spec content — sub-agent follows the Chunks order
- **For S/M items**: include research report context and item description
- Product context (tech stack, conventions, test commands)
- Branch/worktree path
- Memory context for each item
- Freshness notes (Yellow items get diff summary)

**Sub-agent workflow requirements:**

1. **Understand** — Read spec (if exists) or linked research report, relevant source files
2. **Plan** — Brief implementation plan. L/XL items: follow spec Chunks. Medium items: show plan and get approval
3. **Implement** — Write code. TDD where applicable. Follow spec's Acceptance Criteria
4. **Self-Review** — Check against:
   - Security (no injection, no secrets, no OWASP top 10)
   - Quality (no dead code, no debugging artifacts, follows conventions)
   - Correctness (edge cases, error paths, types)
   - Completeness (all items addressed or noted as skipped)
   - Spec compliance (all Acceptance Criteria met for specced items)
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
Spec compliance: {met/partial/N/A}
```

### 2D. Sync Backlog

- Move completed items → Awaiting PR (with PR URL, date)
- Leave skipped items in Ready
- Commit: `backlog: update — {cluster} batch complete`
- Save to memory

Clean up worktree if used.

---

## Error Recovery

- **Sub-agent failure**: Push partial work if commits exist, otherwise delete branch. Report to user, ask retry or skip.
- **Repo failure**: Reset to main, log affected items, continue with next batch.
- **Never**: force push, modify main directly (except backlog), delete remote branches, skip verification, proceed without user approval.

---

## Phase 3: Summary

```
Product Pulse — Sprint Summary ({date})
==========================================
PRs built: {N} of {N} approved
Items completed: {N}
Items skipped: {N}
Freshness: {N} green, {N} yellow, {N} red (skipped)
PRs created:
  - {cluster}: {URL}
Backlog: {N} remaining ready items, {N} ideas
```
