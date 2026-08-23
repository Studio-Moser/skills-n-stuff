---
name: sprint-dev
description: >-
  Use when the user wants to build one or more already-ready `owner/ai` backlog items
  from a configured tracker. Do not use for one named change, an untriaged item, or
  tracker reconciliation.
effort: high
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
- **Every PR must pass.** Each Harness execution request requires self-review and the
  full test suite before opening its PR.
- **Trust the check, not the result summary.** Phase 2C submits a fixed-target Harness
  review request, reproduces verification, and loops findings back until the check
  passes. No code merges on an executor's claim alone.
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

Collision scheduling: compare the likely paths for every pair of proposed slices. For
each scheduling collision, record whether the slices will use isolated worktrees or run
sequentially. Apply the remaining collision and batch-boundary rules from
`references/work-readiness.md`.

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
  Schedule: {parallel | isolated from PR N | sequential after PR N}
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

### 2B. Submit Harness execution requests

For each approved delivery slice, invoke `harness:execute` with
`operation: execute`. Use `route: bulk` for clear-spec or mechanical work,
`route: quick` only for a short latency-sensitive step, and `route: taste` for
user-facing UI, copy, or public API work. PM chooses only this semantic altitude;
Harness resolves execution.

Submit one complete Harness Request per delivery slice:

```yaml
operation: execute
route: {bulk | quick | taste}
outcome: {approved Outcome}
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {item identifiers, approved spec or item body, freshness notes, and current Proof}
  files: [{repository-relative owned implementation and test paths}]
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
verification:
  seam: {Testing Seam procedure}
  expected: {Testing Seam expected result plus project test/build success}
```

The request must carry the approved `Outcome`, `Blockers`, `Testing Seam`, and
current `Proof` verbatim. It also carries batch item metadata, the product context,
memory context when available, and every approved file-ownership constraint.

Submit non-colliding requests concurrently. For each scheduling collision, follow the
approved isolation decision or run the requests sequentially. Parallel requests use
separate worktrees, and each request's `authority.allowed_paths` states its file
ownership ceiling. A newly discovered overlap returns as a blocker; PM then orders or
re-isolates the affected slices instead of widening either request.

Consume each Harness Result without interpreting its concrete route details. A
`blocked`, `failed`, or `abandoned` result stays visible with its blockers. For an
`accepted` result, inspect the changed-file list, report artifact, fixed commit, and
recorded checks. PM then pushes the approved branch and opens one PR for the delivery
slice before moving to review.

### 2C. Fixed-target review and fix loop

Load `references/review-proof.md` in the PM orchestrator and copy its complete review
axes and completion constraints into the request; do not pass that PM-private path to
Harness. Invoke `harness:review` with `operation: review` and `route: review`. Keep the
one-reviewer policy. Use `route: independent` only when the user separately approves
the cost of a fresh-context adversarial review.

Resolve the approved PR base and head to commits, materialize their exact binary
full-index diff, and identify that immutable snapshot by its SHA-256 digest. Base and
head describe the snapshot in request context; they are not the fixed target. Stop if
any command fails or the identifier does not have the required shape.

```bash
BASE_SHA="$(git rev-parse "${BASE_REF}^{commit}")" || exit 1
HEAD_SHA="$(git rev-parse "${HEAD_REF}^{commit}")" || exit 1
REVIEW_ARTIFACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pm-review.XXXXXX")" || exit 1
REVIEW_PATCH="$REVIEW_ARTIFACT_DIR/review.patch"
git diff --binary --full-index "$BASE_SHA" "$HEAD_SHA" > "$REVIEW_PATCH" || exit 1
REVIEW_DIGEST="$(shasum -a 256 "$REVIEW_PATCH" | awk '{print $1}')" || exit 1
REVIEW_FIXED_TARGET="snapshot:sha256:${REVIEW_DIGEST}"
printf '%s\n' "$REVIEW_FIXED_TARGET" | grep -Eq '^snapshot:sha256:[0-9a-f]{64}$' || exit 1
```

```yaml
operation: review
route: {review | independent}
outcome: Report whether this fixed PR target satisfies its approved delivery slice
context:
  project: {canonical project identifier when known}
  mode: fresh
  state: {approved item/spec, acceptance criteria, current Testing Seam Proof, base commit ${BASE_SHA} and head commit ${HEAD_SHA}; the review artifact is their exact diff}
  files: [{changed and review-relevant repository paths, plus ${REVIEW_PATCH}}]
authority:
  working_directory: {absolute PR worktree}
  allowed_paths: [{read-only PR scope, plus ${REVIEW_PATCH}}]
  tools: [{read-only inspection and project verification tools}]
  approvals: []
constraints:
  - |
    PM review axes:
    Quality: inspect the fixed-point diff and affected paths for correctness,
    regressions, security, edge cases, error handling, performance, maintainability,
    and adequate tests. Reproduce relevant verification instead of accepting the
    implementer's claim.
    Spec Fidelity: compare the fixed-point diff with the approved issue, plan, and
    acceptance criteria. Report missing or partial requirements, unrequested behavior,
    and implementations that do not match the requirement; state when no spec exists.
    Blast Radius: apply this axis when the diff changes Persisted data, schema, or
    migration behavior; Public API, protocol, wire format, or serialization behavior;
    Authentication, authorization, permissions, or another security boundary; or
    Shared runtime, dependency, build, deployment, or configuration behavior. For each
    trigger, name the central safety assumption and require a check aimed at it. If no
    trigger matches, record Blast Radius as not applicable.
    Report each applicable axis separately. Completion requires current proven Harness
    evidence for this fixed target, Quality and Spec Fidelity reports, every triggered
    Blast Radius assumption and check, reproduced verification, and no unresolved or
    unevidenced blocker.
  - Score each finding from 0–100 confidence and report file, line, failure mode, and fix direction
  - Do not modify the fixed target
verification:
  seam: {Testing Seam plus applicable blast-radius checks}
  expected: {approved acceptance result and no unresolved finding above 24 confidence}
  fixed_target: ${REVIEW_FIXED_TARGET}
```

Treat the Harness review report as a claim. Recompute the patch digest, confirm the
returned fixed target equals `${REVIEW_FIXED_TARGET}`, reproduce the relevant checks,
and keep only findings with confidence above 24. A changed patch or digest invalidates
the review and requires a new snapshot and request.

If findings clear the bar, run the fix loop for at most two rounds:

1. Submit a new complete Phase 2B `harness:execute` request on the same branch. Its
   outcome is to resolve the accepted findings without widening the slice; use
   `route: bulk` for mechanical fixes or `route: taste` when the finding concerns
   user-facing design, copy, or a public API.
2. Fix each finding or dispute it with concrete evidence when it is false or contradicts
   the approved spec.
3. Require the full tests/build/lint/typecheck plus the named Testing Seam, with actual
   output in the returned evidence.
4. After Harness returns the normal follow-up commit, PM pushes it to the existing PR;
   never force-push.
5. Pin the new commit and submit another complete Harness review request. Confirm every
   prior finding is resolved or evidenced as disputed. If a round remains, repeat;
   otherwise report residual issues instead of merging over them.
6. Post a PR comment summarizing fixes, disputes, evidence, and unresolved findings.

No author is above this check. PM-authored fixes use the same fixed-target Harness
review path.

Report inline:

```
Fixed-target Check: {cluster}
  Fixed point: ${REVIEW_FIXED_TARGET} (base ${BASE_SHA}, head ${HEAD_SHA} in context)
  Axes: {contract report summary}
  Issues found: {N}   Above threshold (>24): {N}
  Round 1 fixed: {N}  disputed: {N}
  Round 2 fixed: {N}  disputed: {N}   (only if a 2nd round ran)
  Re-check: {clean / N residual}
  Completion: {complete / blocked and missing proof}
  Verify output: {pass/fail, pasted}
```

If nothing clears the threshold on the first pass, note "clean" and proceed.

### 2D. Report Results

After each Harness execution and review cycle completes, immediately tell the user:

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

Save to memory and clean up worktree if used.

---

## Error Recovery

- **Harness execution failure**: Preserve any returned commits, otherwise clean up the branch. Report the typed status and blockers, then ask whether to retry or skip.
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
