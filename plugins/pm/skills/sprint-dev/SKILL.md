---
name: sprint-dev
description: >-
  Interactive sprint worker. Reads status/ready + owner/ai items from GitHub Issues
  (or local backlog), presents them with context, groups into proposed PRs,
  and waits for your approval before building. Dispatches parallel sub-agents
  with self-review and full testing. Reads CONTEXT.md for domain terminology
  and .pm/out-of-scope/ for negative constraints. Trigger: "let's build",
  "work the backlog", "what can we ship", "sprint", or /pm:sprint-dev.
  Do NOT use for a single named change (that's /pm:dev-task), for classifying
  or speccing items that are not yet status/ready (that's /pm:triage), or for
  syncing completed work (that's /pm:reconcile) — sprint-dev only batches and
  builds items already marked status/ready + owner/ai.
effort: high
allowed-tools: "Bash Read Write Edit Agent Skill"
---

# PM — Sprint Dev

Interactive skill that reads ready items from GitHub Issues (or local backlog), proposes how they should be grouped into PRs, and — with your approval — dispatches parallel sub-agents to implement, review, test, and PR each batch. Updates the issue tracker when work completes.

**Manual only.** You decide when to run this and what to build.

**Note on GitHub Project sync.** If `github.project_sync.enabled` is set in `.pm/config.yml`, sprint-dev relies on the project's built-in workflows to handle Status transitions when PRs are linked or merged (`Ready → In Progress` when a PR draft is linked, `In Progress → In Review` when the PR is opened for review, `In Review → Done` when merged). No MCP calls are made from this skill — the GitHub-side workflows do the work. Status field bootstrapping for items spawned during sprint execution happens later, via `/pm:triage` or `/pm:reconcile`.

---

## Ground Rules

- **Never auto-build.** Always present the proposal and wait for user approval.
- **Parallel when safe.** Dispatch independent PRs in parallel when they don't touch the same files.
- **Every PR must pass.** Sub-agents run self-review + full test suite before PRing.
- **Trust the check, not the worker.** A sub-agent's self-review and "tests pass" are its opening claim, not proof. Phase 2C independently re-executes verification and loops findings back until the check actually passes — no code merges on a worker's own say-so, the orchestrator's included.
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

**Backend dispatch.** PM uses one backend per project. Load ONLY `references/sprint-dev-<backend>.md` (`sprint-dev-github.md`, `sprint-dev-trello.md`, or `sprint-dev-local.md`) and follow its steps wherever a phase below is marked **(backend step)**. Ignore the other backends' files.

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

### 0.5 Reconcile items with `status/in-review` status

The standalone **Awaiting PR** section was retired — items in flight now carry the `status/in-review` (or `status/in-progress`) status inline in their sprint-section row. Scan both backlog files:

```bash
grep -E '\| (status/in-review|status/in-progress) \|' "$backlog_active" "$backlog_ideas"
```

For each row with `status/in-review`, find its PR URL (the row should embed a `[#N](https://github.com/...)` link) and check the PR state:

```bash
gh pr view <PR-URL> --json state,mergedAt 2>/dev/null
```

- **merged** -> add a row to `## Done (last 7 days)` in `$backlog_active` and remove the row from its sprint section
- **closed** (rejected) -> flip the status back to `status/ready` in its sprint-section row (or move the row back into `$backlog_ideas` if it was originally an idea the user promoted)
- **open** -> leave as-is

Commit any moves:
```bash
git add "$backlog_active" "$backlog_ideas"
git commit -m "backlog: reconcile PRs"
git push origin "$default_branch"
```

(direct push to default branch is OK here — sprint-dev is interactive only)

**(backend step, Trello only)** — follow your loaded `references/sprint-dev-trello.md` (§ Phase 0.5: Reconcile in-review items — Trello) for reconciling `LIST_REVIEW` cards against PR state and the needs-changes backwards move. GitHub/local: already handled by the grep/`gh pr view` logic above.

---

## Phase 1: Parse, Filter & Propose

### 1.1 Load Ready Items

Load items based on the configured backend.

**(backend step)** — follow your loaded `references/sprint-dev-<backend>.md` (§ Phase 1.1: Load Ready Items). Trello's variant also covers how per-board `worker_instructions`/`review_policy` flow to Phase 2B and 2D.5.

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

Primary pool: items from the configured backend with `status/ready` + `owner/ai` labels and Green or Yellow freshness.

Quick wins pool: S-sized items from `{backlog.ideas}` Ideas subsections (present separately as available for user promotion).

Exclusions:
- Items already carrying `status/in-review` or `status/in-progress` status inline
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

**Pick the model and effort per task altitude.** Load the current developer's rubric from `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml` (if missing, offer to run `/machine:model-rubric` — or follow `studio-baseline/Rubric_Setup.md` with no plugin — before dispatching, or fall back to the default model). Route by it: route clear-spec / mechanical implementation to a cheaper capable model, reserve the strongest model for ambiguous or taste-sensitive work (UI, copy, API/SDK design), and keep reasoning effort matched to difficulty rather than defaulting to the ceiling. If no rubric exists, dispatch with the default model. Dispatch the chosen `model@effort` routing value per `references/model-orchestration.md` (split it; `via: codex` rows dispatch through the codex skills; natives pass Agent `model` tier + `effort`); don't predefine reviewer/explorer/adversarial archetypes — let the orchestrator pick roles per task.

Build a comprehensive sub-agent prompt with:
- Batch items (number, description, priority, size, spec link)
- **For L/XL items with specs**: include the full spec content — sub-agent follows the Chunks order
- **For S/M items**: include research report context and item description
- Product context (tech stack, conventions, test commands)
- Branch/worktree path
- Memory context for each item
- Freshness notes (Yellow items get diff summary)
- **Implementation discipline** (state it in the prompt — sub-agents don't auto-load it): the pm:house-rules implementation discipline — reuse existing code / stdlib / platform first, shortest diff that fully solves it, no speculative abstractions or unrequested refactors, root cause over symptom.

**Domain terminology (from CONTEXT.md):**
{Include the Terms table so the agent uses correct names}

**Out-of-scope constraints:**
{For each .pm/out-of-scope/ entry: "Do NOT implement {feature}. Reason: {decision summary}"}

**Sub-agent workflow requirements:**

1. **Understand** — Read spec (if exists) or linked research report, relevant source files
2. **Plan** — Brief implementation plan. L/XL items: follow spec Chunks. Medium items: show plan and get approval
3. **Implement** — Write code. TDD where applicable. Follow spec's Acceptance Criteria
4. **Self-Review** — Apply the pm:house-rules security + quality checklist (correctness, edge cases, error handling, no secrets, no dead code or debug artifacts, conventions). Then additionally for sprints:
   - Completeness — all batch items addressed or explicitly noted as skipped
   - Spec compliance — all Acceptance Criteria met for specced items
5. **Verify** — Run project test/build commands from product context
6. **Commit** — Atomic commits, clear messages
7. **Discovered work** — If you find something that needs to be done but isn't in your current spec, do NOT do it inline. Instead, create a GitHub Issue (or note for the orchestrator) tagged `spawned-during-sprint` with a description of what was found and why it matters. Your definition of done stays fixed to the original spec.

Dispatch independent PRs in parallel. Conflicting PRs run sequentially.

**State file ownership up front.** Batch grouping keeps *known* conflicts apart, but parallel workers still collide on files neither batch's items named — shared types, barrel exports, config, lockfiles. Before dispatching, list the paths each batch is expected to touch and put them in that worker's prompt: "You own `{paths}`. Do not edit files owned by another batch — if your work requires a change outside your paths, stop and report it to the orchestrator instead of making it." Overlaps you find while building that list are a signal the batches should run sequentially.

Ownership in the prompt is an instruction, not a guarantee — nothing stops a worker editing outside its paths. When batches run genuinely in parallel, give each one its own worktree (`git worktree add ../{repo}-{batch} -b {branch} origin/main`, `isolation: 'worktree'` for workflow agents) so collisions are impossible rather than merely discouraged. See the concurrent-sessions section of `pm:house-rules`.

**Pick the model per batch from the rubric** (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`) and **always dispatch per `references/model-orchestration.md`** — split each `model@effort` value, honor `via:`, and pass model + effort explicitly; omitting either inherits session defaults and silently defeats the routing. Clear-spec/mechanical batches → `routing.bulk`; latency-sensitive single steps → `routing.quick`; unattended fan-out → `routing.batch` (only if set — never for attended work); user-facing batches (UI, copy, API surface) → a row with `taste >= routing.taste_min`. Unsure between two tiers → take the cheaper and escalate on failure.

```
Agent(subagent_type="general-purpose", model=<tier from rubric>, effort=<effort from rubric>, prompt=built_prompt)
```

Three or more independent batches is the case for a dynamic workflow instead of loose parallel Agent calls — propose it with its rough shape and cost, and wait for a yes unless the session has already opted in to multi-agent orchestration. Inside the script, every `agent()` carries its own `model`.

### 2C. Independent Check & Fix Loop

The sub-agent's own "done / tests pass" is a **claim, not proof** — it self-reviewed and self-verified, so it can't be the final word. Every PR gets an independent check that re-executes the work, and findings loop back until the check actually passes.

After each sub-agent creates its PR, run the `code-review` skill against that PR. The review **re-runs the project's verification itself** (build/tests/lint/typecheck) rather than trusting the sub-agent's reported result, and scores each issue 0-100 for confidence (0 = false positive, 25 = somewhat, 50 = moderate, 75 = high, 100 = certain).

**Filter**: keep issues with a confidence score **above 24** (i.e., 25+).

If any issues clear the bar, run the fix loop (max 2 rounds):

1. Dispatch a follow-up sub-agent on the same branch (check out the PR branch), dispatched per `references/model-orchestration.md`'s procedure — `routing.bulk` for mechanical fixes, the batch's original model@effort when the finding is subtle.
2. For each filtered issue, either fix it **or** dispute it: if the finding is wrong for this codebase (a false positive, or it contradicts the spec — e.g. flagging content as "too short" that the spec says should be short), leave the code as-is and record a one-line justification instead of forcing a change. Disputes are legitimate; don't pad or distort correct work to satisfy a bad finding.
3. Run the full verify protocol (tests/build/lint/typecheck per project) and **paste the actual output** — never report "passing" without evidence.
4. Commit as new commits — `fix: address code review findings`. Push to the same branch (never force push).
5. **Re-check**: re-run the reviewer against the new commits, confirming each previously-filtered issue is now resolved or justified-as-disputed. If new above-threshold issues remain and a round is left, loop; otherwise stop and report the residual issues rather than merging over them.
6. Post a PR comment summarizing what was fixed, what was disputed (with reasons), and any issue left unresolved after the loop.

No rank is above this check — if the orchestrator itself hand-edited any code (e.g. a shared fix across branches), that code goes through the same check, not around it.

Report inline:

```
Independent Check: {cluster}
  Issues found: {N}   Above threshold (>24): {N}
  Round 1 fixed: {N}  disputed: {N}
  Round 2 fixed: {N}  disputed: {N}   (only if a 2nd round ran)
  Re-check: {clean / N residual}
  Verify output: {pass/fail, pasted}
```

If nothing clears the threshold on the first pass, note "clean" and proceed.

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

**(backend step)** — follow your loaded `references/sprint-dev-<backend>.md` (§ Phase 2D.5: Update Issue Tracker). GitHub's variant also covers the parent-epic progress check; Trello's covers the review_policy decision matrix, the check-transition.sh gate, and the initial ready->in-progress dispatch move.

### 2E. Sync Backlog

For each item in the batch:

**(backend step)** — follow your loaded `references/sprint-dev-<backend>.md` (§ Phase 2E: Sync Backlog). Trello: N/A — its card sync happens in 2D.5; the `#{number}` token in `planning/todos.md` rows is the Trello card's short id (e.g. `t-AbCdEfGh`) and the embedded PR link is the same `[#N](https://github.com/...)` form, otherwise the sync logic below is identical.

**Backlog file sync (both backends):**
If `$backlog_active` and `$backlog_ideas` exist (backward-compatible with product-pulse workflow):
- **PR open, not yet merged** -> flip the status in its sprint-section row from `status/ready` -> `status/in-review` and embed the PR link inline in the item description
- **PR already merged** before the sub-agent returned -> remove the row from its sprint section and add a row to `## Done (last 7 days)` in `$backlog_active`
- **Skipped/failed** -> leave in its current section with status unchanged

If a sprint subsection now has zero `status/ready` rows left, leave the section header in place unless the whole sprint is complete; in that case delete the entire subsection and summarize it in the commit message.

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
Backend: {github|local|trello}
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
{If Trello: "Cards updated across {N} board(s); {moved_to_in_progress} in-progress, {moved_to_review} in review, {moved_to_done} done, {moved_to_needs_changes} needs-changes."}
```
