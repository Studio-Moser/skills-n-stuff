---
name: sprint-dev
description: >-
  Builds ready owner/ai backlog items from the configured tracker as one sprint. Use when the user asks for a sprint.
effort: high
disable-model-invocation: true
allowed-tools: "Bash Read Write Edit Skill"
---

# PM — Sprint Dev

Interactive skill that reads ready items from the configured tracker, proposes how they
should be grouped into PRs, and—with approval—submits bounded implementation and review
requests to Harness. PM retains the issue tracker and PR lifecycle.

**Manual only.** You decide when to run this and what to build.

**Note on GitHub Project sync.** If `github.project_sync.enabled` is set in `.pm/config.yml`, sprint-dev relies on the project's built-in workflows to handle Status transitions when PRs are linked or merged (`Ready → In Progress` when a PR draft is linked, `In Progress → In Review` when the PR is opened for review, `In Review → Done` when merged). No MCP calls are made from this skill — the GitHub-side workflows do the work. Status field bootstrapping for items spawned during sprint execution happens later, via `/pm:triage` or `/pm:reconcile`.

---

## Ground Rules

- **Never auto-build.** Always present the proposal and wait for user approval.
- **Work the frontier.** Dispatch only delivery slices on the unblocked frontier.
- **Schedule collisions.** Apply the scheduling-collision rule in `references/work-readiness.md`; choose isolation or run sequentially for each collision.
- **Every PR must pass.** Run one verification pass at the highest stable Testing Seam
  required by the change class and matched risk.
- **Review by risk.** Self-review every slice. Phase 2C uses a separate fixed-target
  Harness review only when the risk gate requires independent review or the user asks
  for it.
- **Backlog is sacred.** Only PM edits the backlog, never the Harness executor.
- **Report live.** Tell the user about each PR as it completes, don't batch results.
- **Discovered work stays out of scope.** Harness requests require workers to report it
  without fixing it inline; PM files any resulting `spawned-during-sprint` item.

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

Read `CONTEXT.md` from workspace root (multi-repo) or primary repo root (single-repo). Extract domain terms, aliases to avoid, and relationships. These become Harness Request constraints so the executor uses correct terminology.

Read `.pm/out-of-scope/` directory. For each `.md` file, extract the feature name and decision summary. These become negative Harness Request constraints: "Do NOT implement {feature} — see .pm/out-of-scope/{slug}.md for reasoning."

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

If `memory.connector` is set in `pulse-config.yaml` (not `null`), define a recall
intent for prior sprint blockers, failed items, and in-flight branches. Attach it to
Phase 2 Harness requests. PM does not discover or call a memory provider; if Harness
returns no enrichment, continue from tracker, Git, and repository state.

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

**Load `references/work-readiness.md` now.** Use it as the source of truth for delivery
slices, blockers, the unblocked frontier, testing seams, proof, and scheduling
collisions. Do not redefine those terms here.

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

**For each `ready` item that has a spec** in any of `{specs_dirs}` (colon-separated, from the pre-resolved config; default `{primary_repo_root}/planning/specs`):

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

For each primary-pool item, read its approved item body or spec and capture the
canonical `Outcome`, `Blockers`, `Testing Seam`, and current `Proof`. Resolve each
blocking edge against the current tracker state. Apply the canonical unblocked-frontier
and delivery-slice packaging rules from `references/work-readiness.md`. Return items
with missing readiness fields to triage, and retain blocked items for the proposal's
blocked section.

Quick wins pool: S-sized items from `{backlog.ideas}` Ideas subsections (present separately as available for user promotion).

Exclusions:
- Items already carrying `status/in-review` or `status/in-progress` status inline
- Items with active `pulse/*` branches
- Items with Red freshness (flag for re-spec)
- Monitor, Manual, and Dismissed items
- Anything in the Expired / passed-deadline table

### 1.5 Cluster Into Proposed PRs

Start with the unblocked frontier and package proposed PRs using the delivery-slice rule
in `references/work-readiness.md`. Use relatedness only to name and order the proposals.

General cluster categories (adapt to the project):
- **deps** — Package updates, version bumps, security patches
- **feature** — New features or feature enhancements
- **fix** — Bug fixes, error handling improvements
- **infra** — Infrastructure, config, tooling, CI/CD
- **content** — Copy, documentation, editorial changes
- **data** — Data sources, connectors, integrations
- **ui** — Frontend components, pages, visualizations
- **misc** — Items that don't clearly fit

Collision scheduling: apply the canonical parallel-safety check from
`references/work-readiness.md` to every pair of proposed slices before comparing their
likely paths. For each scheduling collision, record whether the slices will use
isolated worktrees or run sequentially. Apply the remaining collision and
batch-boundary rules from `references/work-readiness.md`.

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
  Outcome: {Outcome}
  Blockers: {Blockers or none}
  Testing Seam: {procedure and expected result}
  Proof: {current proof state; normally unproven before implementation}
  Parallel Safety: {independent because ... | sequential because ...}
  Schedule: {parallel | isolated from PR N | sequential after PR N}
  #{n} {item description}
     Source: GitHub Issue #{n} | Local .pm/items/{n}-{slug}.yml
     Spec: {specs_dir}/{n}-{slug}.md (if exists)
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

--- Blocked ---

  #{n} {item description} — waiting on {Blockers}

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

### 2B. Implement approved slices

For each approved delivery slice, load `harness:risk-gate`. Record its mode, matched
triggers, testing seam, delegation decision, and review decision internally. Choose
direct execution or a rubric worker through Harness’s [Execution choice](../../../harness/references/routing.md#execution-choice).

Delegate only when that rule justifies a bounded worker with its own outcome and
verification seam. When delegation is justified, invoke `harness:delegate` with
`operation: execute`. Use `route: bulk` for clear-spec or mechanical work,
`route: quick` only for a short latency-sensitive task, `route: default` for
ordinary implementation, and `route: taste` for
user-facing UI, copy, or public API work. PM chooses only this semantic altitude;
Harness resolves execution. Carry the risk gate's `max_children`, `max_depth`, and
`token_budget` into the request.

Submit one complete Harness Request per delivery slice:

```yaml
operation: execute
route: {bulk | quick | default | taste}
outcome: {approved Outcome}
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {item identifiers, approved spec or item body, freshness notes, and current Proof}
  files: [{repository-relative owned implementation and test paths}]
  memory:
    enabled: {memory.connector is not null}
    recall:
      - purpose: Recover prior blockers, failed sprint attempts, and in-flight branches for this delivery slice
        query: Prior sprint-dev outcomes for this project and the approved item identifiers
        limit: 10
    capture: []
authority:
  working_directory: {absolute approved worktree}
  allowed_paths: [{paths owned by this delivery slice}]
  tools: [{repository tools needed to edit, test, and commit}]
  approvals: []
constraints:
  - "Blockers: {resolved Blockers or none}"
  - {acceptance criteria and negative constraints}
  - {full L/XL spec or S/M item and research constraints}
  - {domain terminology from CONTEXT.md}
  - {out-of-scope decisions from .pm/out-of-scope}
  - Use test-driven development for behavior changes and leave a runnable check for non-trivial logic
  - Preserve trust-boundary validation, data-loss-preventing error handling, security, and accessibility basics
  - Keep the change to the approved slice, run the planned tests, and make atomic conventional commits
  - Commit the approved delivery slice; do not push, open a PR, or edit PM tracker files
  - Report discovered work without implementing it inline
delegation:
  max_children: {risk-gate limit}
  max_depth: {risk-gate limit}
  token_budget: {bounded amount for this track}
verification:
  seam: {Testing Seam procedure}
  expected: {Testing Seam expected result plus project test/build success}
```

The request must carry the approved `Outcome`, `Blockers`, `Testing Seam`, and
current `Proof` verbatim. It also carries batch item metadata, the product context,
memory context when available, and every approved file-ownership constraint.

Submit delegated requests concurrently only when the approved `Parallel Safety` decision says
independent and the existing collision rule from `references/work-readiness.md` is
satisfied. For each scheduling collision, follow the approved isolation decision or
run the requests sequentially. Parallel requests use separate worktrees, and each
request's `authority.allowed_paths` states its file ownership ceiling. A newly
discovered overlap returns as a blocker; PM then orders or re-isolates the affected
slices instead of widening either request.

For direct execution, inspect the current agent's diff and record the same Outcome,
Testing Seam, and Proof fields. For delegated execution, consume each Harness Result
without interpreting its concrete route details. A
`blocked`, `failed`, or `abandoned` result stays visible with its blockers. For an
`accepted` result, inspect the changed-file list, report artifact, fixed commit, and
recorded checks. After direct proof, commit the slice. After an accepted delegated
result, verify and reuse the returned commit instead of committing the same slice
again. Then push the approved branch and open one PR before moving to review.

### 2C. Conditional fixed-target review and fix loop

Load `references/review-proof.md` in the PM orchestrator and copy its complete review
axes and completion constraints into the self-review. Continue directly to Phase 2D
when self-review and one verification pass prove an ordinary slice.

Invoke `harness:delegate` with `operation: review` and `route: review` only when the
risk gate requires independent review or the user explicitly asks for a separate
review. Keep the one-reviewer policy. Use `route: independent` only when the user
separately approves the cost of a provider-separated fresh-context adversarial review.

When that separate review is required, load `references/sprint-review-loop.md` and
follow its fixed-target procedure: materialize the exact diff, submit one review
request, run at most two fix rounds, and report the round summary.

### 2D. Report Results

After each implementation and any required review cycle completes, immediately tell
the user:

```
PR Complete: {cluster}
========================
Branch: pulse/{cluster}-{date}
PR: {URL}
Items completed: #{n}, #{n}
Items skipped: #{n} (reason)
Outcome: {Outcome delivered / not delivered}
Tests: {pass/fail}
Proof: {Testing Seam command or procedure and actual result}
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
- **PR already merged** before the Harness Result returned -> remove the row from its sprint section and add a row to `## Done (last 7 days)` in `$backlog_active`
- **Skipped/failed** -> leave in its current section with status unchanged

If a sprint subsection now has zero `status/ready` rows left, leave the section header in place unless the whole sprint is complete; in that case delete the entire subsection and summarize it in the commit message.

Commit:
```bash
git add "$backlog_active" "$backlog_ideas"
git commit -m "backlog: update — {cluster} batch complete ({N} items)"
git push origin "$default_branch"
```

Retain any optional memory identifiers from the accepted Harness review result, then
clean up the worktree if used. PM does not call a memory provider directly.

---

## Error Recovery

- **Implementation failure**: Preserve any returned commits, otherwise clean up the branch. Report the direct failure or delegated typed status and blockers, then ask whether to retry or skip.
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

If any built PR changes a user-visible web feature, end with a one-line offer of a
recorded walkthrough. Invoke `pm:feature-walkthrough` only if the user accepts.
