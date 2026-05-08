---
name: sprint-dev
description: >-
  Interactive sprint worker. Reads ready-for-agent items from GitHub Issues
  (or local backlog), presents them with context, groups into proposed PRs,
  and waits for your approval before building. Dispatches parallel sub-agents
  with self-review and full testing. Reads CONTEXT.md for domain terminology
  and .pm/out-of-scope/ for negative constraints. Trigger: "let's build",
  "work the backlog", "what can we ship", "sprint", or /pm:sprint-dev.
effort: high
allowed-tools: "Bash Read Write Edit Agent Skill"
---

# PM — Sprint Dev

Interactive skill that reads ready items from GitHub Issues (or local backlog), proposes how they should be grouped into PRs, and — with your approval — dispatches parallel sub-agents to implement, review, test, and PR each batch. Updates the issue tracker when work completes.

**Manual only.** You decide when to run this and what to build.

---

## Ground Rules

- **Never auto-build.** Always present the proposal and wait for user approval.
- **Parallel when safe.** Dispatch independent PRs in parallel when they don't touch the same files.
- **Every PR must pass.** Sub-agents run self-review + full test suite before PRing.
- **Backlog is sacred.** Only the orchestrator edits the backlog, never sub-agents.
- **Report live.** Tell the user about each PR as it completes, don't batch results.
- **Discovered work stays out of scope.** Sub-agents do NOT fix things they find along the way — they file issues tagged `spawned-during-sprint`.

---

## Phase 0: Sync & Reconcile

### 0.0 Pre-resolved Configuration

All config values are pre-resolved at skill load time. If you see `ERROR:` in the output below, stop and tell the user.

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/discover-config.sh`
```

Parse the key=value pairs above. The `backend` value (`github` or `local`) determines how items are loaded and updated throughout the rest of this skill. When using the GitHub backend, `gh_owner` and `gh_repo` identify the target repository for all `gh` CLI commands.

### 0.1 Read Product Context

Read `{research_dir}/research-context.md` for project structure, repo info, and tech stack. If missing, tell the user to run `/pm:setup`.

### 0.1.5 Read Domain Knowledge

Read `CONTEXT.md` from workspace root (multi-repo) or primary repo root (single-repo). Extract domain terms, aliases to avoid, and relationships. These will be passed to sub-agents in their prompts so they use correct terminology.

Read `.pm/out-of-scope/` directory. For each `.md` file, extract the feature name and decision summary. These become negative constraints in sub-agent prompts: "Do NOT implement {feature} — see .pm/out-of-scope/{slug}.md for reasoning."

If neither file/directory exists, continue without them — they're optional.

### 0.2 Pull Latest (all configured repos)

Iterate `repos:` from `pulse-config.yaml`. For each repo, resolve its absolute path relative to `{primary_repo_root}`'s parent directory, then pull the default branch:

```bash
for repo_path in $(yq '.repos[].path' pulse-config.yaml); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  echo "=== Pulling $abs ==="
  cd "$abs" && git checkout "$default_branch" && git pull origin "$default_branch" || echo "pull failed for $abs"
done
```

If any pull fails, note it and continue. Single-element `repos:` is the monorepo case — same loop, one iteration.

### 0.3 Context Recovery (if memory configured)

If `memory.connector` is set in `pulse-config.yaml` (not `null`), look for MCP tools matching that prefix. If found, search memory for prior sprint-dev runs — known blockers, failed items, in-flight branches. If `memory.connector: null` or no matching tools are found, skip this phase.

### 0.4 Check Existing Branches

```bash
git branch -a | grep pulse/ 2>/dev/null
```

Note any in-flight branches with open PRs.

### 0.5 Reconcile items with `awaiting-pr` status

The standalone **Awaiting PR** section was retired — items in flight now carry the `awaiting-pr` (or `in-progress`) status inline in their sprint-section row. Scan both backlog files:

```bash
grep -E '\| (awaiting-pr|in-progress) \|' "$backlog_active" "$backlog_ideas"
```

For each row with `awaiting-pr`, find its PR URL (the row should embed a `[#N](https://github.com/...)` link) and check the PR state:

```bash
gh pr view <PR-URL> --json state,mergedAt 2>/dev/null
```

- **merged** -> add a row to `## Done (last 7 days)` in `$backlog_active` and remove the row from its sprint section
- **closed** (rejected) -> flip the status back to `ready` in its sprint-section row (or move the row back into `$backlog_ideas` if it was originally an idea the user promoted)
- **open** -> leave as-is

Commit any moves:
```bash
git add "$backlog_active" "$backlog_ideas"
git commit -m "backlog: reconcile PRs"
git push origin "$default_branch"
```

(direct push to default branch is OK here — sprint-dev is interactive only)

---

## Phase 1: Parse, Filter & Propose

### 1.1 Load Ready Items

Load items based on the configured backend.

**GitHub backend:**
```bash
gh issue list --label "ready-for-agent" --state open --json number,title,body,labels --limit 50 --repo "$gh_owner/$gh_repo"
```
Parse each issue. Extract from the body:
- Acceptance criteria (look for `## Acceptance Criteria` header)
- Code references (look for `## Code References` header)
- Target repo (from labels or body)
- Size (from size/* label)
- Priority (from body or label)

**Local backend:**
Scan `.pm/items/` for files with `labels: [ready-for-agent]`. Parse YAML.

**Fallback:**
If no backend items found, fall back to reading `planning/todos.md` Ready section (backward compatibility with product-pulse workflow).

Additionally, from `{backlog.ideas}` (`$backlog_ideas`), collect S-sized items that could be promoted directly (S items don't need specs). Present these separately as "quick wins available if you want to promote them." Skip the **Expired / passed-deadline** table — those items are explicitly idle.

### 1.2 Read the Weekly Recommendations

Find the most recent `*-recommendations.md` in `{research_dir}/` (search recursively). Extract:
- Suggested items for speccing
- Strategic direction and top 3 priorities
- Quick wins identified

### 1.3 Freshness Check

**For each `ready` item that has a spec** in `{primary_repo_root}/planning/specs/`:

1. Read the spec's Code References table
2. For each file listed, diff against the Base SHA:
   ```bash
   git diff {base_sha}..HEAD -- {file_path}
   ```
3. Classify freshness:
   - **Green** (no changes to referenced files) -> proceed normally
   - **Yellow** (<20 lines changed across all referenced files) -> proceed, but include diff summary in proposal notes
   - **Red** (significant divergence: 20+ lines changed, files deleted, or major refactors) -> skip this item, flag for re-spec
4. Log the check in the spec's Freshness Log table:
   ```
   | {today} | sprint-dev | {Green/Yellow/Red} | {summary of changes or "No changes"} |
   ```

If a spec has no Code References table or no Base SHA, treat as Yellow with a note.

### 1.4 Filter Eligible Items

Primary pool: items from the configured backend with `ready-for-agent` label/status and Green or Yellow freshness.

Quick wins pool: S-sized items from `{backlog.ideas}` Ideas subsections (present separately as available for user promotion).

Exclusions:
- Items already carrying `awaiting-pr` or `in-progress` status inline
- Items with active `pulse/*` branches
- Items with Red freshness (flag for re-spec)
- Monitor, Manual, and Dismissed items
- Anything in the Expired / passed-deadline table

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
PM — Sprint Proposal
=================================

Weekly Direction: {theme or "No weekly brief"}
Top Priorities: {p1} | {p2} | {p3}

Backend: {github|local}
Items loaded: {N} ready | {N} awaiting PR | {N} ideas
Domain terms: {N} loaded from CONTEXT.md (or "none")
Out-of-scope constraints: {N} loaded from .pm/out-of-scope/

--- Freshness Results ---

Green: {N} items (specs current)
Yellow: {N} items (minor drift — see notes)
Red: {N} items (need re-spec, skipped)

--- Proposed PRs ---

PR 1: {cluster name} ({N} items)
Branch: pulse/{cluster}-{YYYY-MM-DD}
  #{n} {item description}
     Source: GitHub Issue #{n} | Local .pm/items/{n}-{slug}.yml
     Spec: planning/specs/{n}-{slug}.md (if exists)
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

**Domain terminology (from CONTEXT.md):**
{Include the Terms table so the agent uses correct names}

**Out-of-scope constraints:**
{For each .pm/out-of-scope/ entry: "Do NOT implement {feature}. Reason: {decision summary}"}

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
7. **Discovered work** — If you find something that needs to be done but isn't in your current spec, do NOT do it inline. Instead, create a GitHub Issue (or note for the orchestrator) tagged `spawned-during-sprint` with a description of what was found and why it matters. Your definition of done stays fixed to the original spec.

Dispatch independent PRs in parallel. Conflicting PRs run sequentially.

```
Agent(subagent_type="general-purpose", prompt=built_prompt)
```

### 2C. Code Review & Fix

After each sub-agent creates its PR, run the `code-review` skill against that PR. The review scores each issue 0-100 for confidence (0 = false positive, 25 = somewhat confident, 50 = moderately confident, 75 = highly confident, 100 = certain).

**Filter**: keep issues with a confidence score **above 24** (i.e., 25+). Fix everything that clears this bar.

If any issues clear the bar, dispatch a follow-up sub-agent on the same branch:

1. Check out the PR branch
2. Address each filtered issue
3. Run the full verify protocol (tests/build/lint/typecheck per project)
4. Commit as new commits — `fix: address code review findings`
5. Push to the same branch (never force push)
6. Post a PR comment summarizing what was fixed and which issues (if any) were intentionally deferred with reasons

Report inline:

```
Code Review: {cluster}
  Issues found: {N}
  Above threshold (>24): {N}
  Fixes pushed: {yes/no} {commit sha if yes}
```

If nothing clears the threshold, note "clean" and proceed.

### 2D. Report Results

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

### 2D.5 Update Issue Tracker

For each completed item:

**GitHub backend:**
```bash
# Comment on the issue with PR link
gh issue comment {number} --body "Implemented in PR {pr_url}. Spec compliance: {met/partial}. Tests: {pass/fail}." --repo "$gh_owner/$gh_repo"

# Close the issue if PR is merged
gh issue close {number} --repo "$gh_owner/$gh_repo"
```

**Local backend:**
Update `.pm/items/{number}-{slug}.yml` with `status: done` and `pr: {pr_url}`.

If the item has a parent epic, check epic progress:
```bash
# Count open vs closed sub-issues
gh api graphql -f query='{ node(id: "{epic_node_id}") { ... on Issue { subIssues { totalCount } closedSubIssues: subIssues(states: CLOSED) { totalCount } } } }'
```

### 2E. Sync Backlog

For each item in the batch:

**GitHub backend:**
- **PR open, not yet merged** -> the issue remains open with a comment linking the PR (added in 2D.5)
- **PR already merged** -> the issue is closed (done in 2D.5) and a row is added to `## Done (last 7 days)` in `$backlog_active` if one exists
- **Skipped/failed** -> leave the issue open with status unchanged

**Local backend:**
- **PR open, not yet merged** -> update `.pm/items/{number}-{slug}.yml` with `status: awaiting-pr` and `pr: {pr_url}`
- **PR already merged** -> update `.pm/items/{number}-{slug}.yml` with `status: done` and `pr: {pr_url}`
- **Skipped/failed** -> leave the item file unchanged

**Backlog file sync (both backends):**
If `$backlog_active` and `$backlog_ideas` exist (backward-compatible with product-pulse workflow):
- **PR open, not yet merged** -> flip the status in its sprint-section row from `ready` -> `awaiting-pr` and embed the PR link inline in the item description
- **PR already merged** before the sub-agent returned -> remove the row from its sprint section and add a row to `## Done (last 7 days)` in `$backlog_active`
- **Skipped/failed** -> leave in its current section with status unchanged

If a sprint subsection now has zero `ready` rows left, leave the section header in place unless the whole sprint is complete; in that case delete the entire subsection and summarize it in the commit message.

Commit:
```bash
git add "$backlog_active" "$backlog_ideas"
git commit -m "backlog: update — {cluster} batch complete ({N} items)"
git push origin "$default_branch"
```

Save to memory and clean up worktree if used.

---

## Error Recovery

- **Sub-agent failure**: Push partial work if commits exist, otherwise delete branch. Report to user, ask retry or skip.
- **Repo failure**: Reset to main, log affected items, continue with next batch.
- **Never**: force push, modify main directly (except backlog), delete remote branches, skip verification, proceed without user approval.

---

## Phase 3: Summary

```
PM — Sprint Summary ({date})
==========================================
Backend: {github|local}
PRs built: {N} of {N} approved
Items completed: {N}
Items skipped: {N}
Issues updated: {N} commented, {N} closed
Spawned issues: {N} (tagged spawned-during-sprint)
Freshness: {N} green, {N} yellow, {N} red (skipped)
PRs created:
  - {cluster}: {URL}
Backlog: {N} remaining ready items, {N} ideas
Domain terms applied: {yes/no}
Out-of-scope constraints enforced: {N}
```
