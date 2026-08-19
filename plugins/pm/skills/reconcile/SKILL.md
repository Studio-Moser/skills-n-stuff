---
name: reconcile
description: >-
  Use when the issue tracker may be stale after merges or sprints, or needs a periodic
  reality check against git history and current project state. Do not use for deciding
  new items or implementing ready work.
effort: medium
allowed-tools: "Bash Read Write Edit"
---

# PM -- Reconcile

You are the project janitor. Your job is to walk through git history, the issue tracker, and the planning files to make sure everything reflects reality. You close what's done, flag what's stale, classify deferred blockers, update epic rollups, normalize epics (strip stray status labels, reshape bodies to Goal/Why), and propose CONTEXT.md and ADR additions when the codebase has evolved.

You are NOT the triage agent -- that's `/pm:triage`. You sync state; others classify and prioritize new work.

---

## Ground Rules

- **Partially interactive.** Completion tracking presents evidence and asks for confirmation before closing issues. Blocker classification runs automatically. Stale item decisions, CONTEXT.md proposals, and ADR proposals require user confirmation.
- **Multi-repo aware.** Scan git history across ALL configured repos, not just primary.
- **Idempotent.** Running reconcile twice in succession produces no additional changes -- the `last_reconcile` timestamp prevents re-processing.
- **Non-destructive.** Never close or modify an issue without evidence (a merged commit on the default branch, user confirmation for stale items). When in doubt, flag for the user.
- **No fabrication.** Domain term proposals and ADR proposals are grounded in actual commits and diffs. Do not invent terms or decisions.
- **Error tolerant.** If one repo or one phase fails, log the error and continue with the rest.

---

## Phase 0: Discover Config

### 0.0 Pre-resolved Configuration

All config values are pre-resolved at skill load time. If you see `ERROR:` in the output below, stop and tell the user.

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/discover-config.sh`
```

Parse the key=value pairs above. The `research_dirs` value is colon-separated (split on `:`). The `repos_json` value is a JSON array of repo objects.

### 0.1 Load State and Repos

Read the last reconcile timestamp and build the list of repos to scan.

```bash
state_file="$primary_repo_root/.pm/state.yml"
if [ ! -f "$state_file" ]; then
  cat > "$state_file" << 'EOF'
last_ingested: {}
last_reconcile: null
EOF
fi

last_reconcile="$(yq '.last_reconcile // "2 weeks ago"' "$state_file")"
stale_threshold="$(yq '.triage.stale_threshold_days // 30' "$pm_config")"

# Build repo list from pulse-config.yaml
repos=()
while IFS= read -r repo_path; do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  [ -d "$abs/.git" ] && repos+=("$abs")
done < <(yq '.repos[].path' "$config_path")

# Fallback: if no repos configured, use primary only
if [ ${#repos[@]} -eq 0 ]; then
  repos=("$primary_repo_root")
fi
```

### 0.2 Load Backend Config

**Backend dispatch.** PM uses one backend per project. Load ONLY `references/reconcile-<backend>.md` (`reconcile-github.md`, `reconcile-trello.md`, or `reconcile-local.md`) and follow its steps wherever a phase below is marked **(backend step)**. Ignore the other backends' files. Note: epic rollup/orphan/normalization is GitHub-only; it lives in `reconcile-github.md`.

**(backend step)** — follow your loaded `references/reconcile-<backend>.md` (§ Phase 0.2: Load Backend Config). Trello: § Phase 0: Discover Config — board validation. (Skip if backend != trello.)

Print: `"Reconciling {N} repo(s) since {last_reconcile}. Backend: {backend}."`

---

## Phase 1: Completion Tracking

Scan git history across all repos for issue references, then check whether those issues should be marked done.

### 1.1 Collect issue references from git history

For each configured repo, extract issue numbers mentioned in commits since the last reconcile:

```bash
all_refs=()
for repo in "${repos[@]}"; do
  refs=$(cd "$repo" && git log --since="$last_reconcile" --oneline --all 2>/dev/null | grep -oE '#[0-9]+' | sort -u)
  for ref in $refs; do
    num="${ref#\#}"
    all_refs+=("$num")
  done
done

# Deduplicate across repos
unique_refs=($(printf '%s\n' "${all_refs[@]}" | sort -un))
```

If no issue references are found, print `"No issue references found in recent commits."` and skip to Phase 1.3.

### 1.2 Check each referenced issue

For each unique issue number, determine whether it should be closed.

**(backend step)** — follow your loaded `references/reconcile-<backend>.md` (§ Phase 1.2: Completion Tracking).

### 1.2T Trello backend completion tracking

**(backend step)** — follow your loaded `references/reconcile-trello.md` (§ Phase 1.2T: Completion tracking — Trello). (Skip if backend != trello.)

Epic rollup is GitHub-only (sub-issues are a GitHub feature). Skip Phase 1.3 entirely when `backend == trello`.

### 1.3 Epic rollup (GitHub-only — skip when backend != github.)

Check whether any epics have all sub-issues now closed.

**(backend step)** — follow your loaded `references/reconcile-github.md` (§ Phase 1.3: Epic Rollup — GitHub). Local backend: **(backend step)** — follow your loaded `references/reconcile-local.md` (§ Phase 1.3: Epic Rollup — Local).

> Closing a finished epic is a **lifecycle** action (open → closed), not a workflow-status change. Epics never carry a `status/*` label — see the guard in Phase 1.3c.

### 1.3b Orphan-epic sweep (GitHub-only — skip when backend != github.)

Every open todo should sit under exactly one epic (that's what makes the board's group-by-Parent-issue / Sprint Plan view readable). Flag any open issue that is **neither under an epic nor a deliberate exception** so it gets parented before it silently rots in "No Parent."

**(backend step)** — follow your loaded `references/reconcile-github.md` (§ Phase 1.3b: Orphan-epic Sweep — GitHub).

### 1.3c Epic normalization — status labels + body (GitHub-only — skip when backend != github.)

Epics are **goal containers** (see `/pm:triage` Phase 4.3): they carry no workflow status, and their body is a Goal/Why statement — not a checklist of constituent items (the sub-issue tree is the source of truth for membership). This phase brings existing epics into line with both rules. It's the retrofit for epics created before the convention, or by hand.

**(backend step)** — follow your loaded `references/reconcile-github.md` (§ Phase 1.3c: Epic Normalization — GitHub).

### 1.4 Update planning files

If `planning/todos.md` exists, move completed items from the Ready section to the Done section.

Read `planning/todos.md`. For each row in `## Ready` subsections, check whether the item's issue number appears in the completion list from Phase 1.2. If it does:

1. Remove the row from `## Ready`.
2. Add a row to `## Done (last 7 days)`:
   ```markdown
   | #{number} | {title} | #{pr_number} | {TODAY} |
   ```

Then archive old Done items. For any row in `## Done (last 7 days)` whose Merged date is older than 7 days:

1. Remove the row from Done.
2. Append it to `planning/archive/done-{YYYY}-Q{N}.md`, where `{YYYY}` is the year and `{N}` is the quarter (1-4) of the merged date.

Archive file format (create if it does not exist):

```markdown
# Done -- {YYYY} Q{N}

Archived items completed during {YYYY} Q{N}.

| # | Item | PR | Merged |
|---|------|----|--------|
| #{number} | {title} | #{pr_number} | {date} |
```

Append new rows to the existing table if the file already exists.

Print: `"Phase 1 — {X} item(s) completed, {Y} epic(s) rolled up, {E} epic(s) normalized, {Z} row(s) archived."`

---

## Phase 2: Stale Detection

Pull all open items and flag those with no activity past the threshold.

### 2.1 Identify stale items

**(backend step)** — follow your loaded `references/reconcile-<backend>.md` (§ Phase 2.1: Stale Detection). Trello: § Phase 2.1: Stale detection — Trello. (Skip if backend != trello.)

### 2.2 Present stale items

If no stale items are found, print `"No stale items detected."` and skip to Phase 3.

For each stale item, present:

```
Stale: #{number} — {title}
  Last updated: {updatedAt} ({N} days ago)
  Labels: {labels}
  Action? (retriage / close / demote / skip)
```

- **retriage** -- Add `status/needs-triage` label, remove current status/owner labels. The item re-enters the triage pipeline.
- **close** -- Close the issue with a comment noting it was closed as stale.
- **demote** -- Lower priority (e.g., P1 to P2, or move from Ready to Monitor in `planning/todos.md`).
- **skip** -- Leave as-is. The item will be flagged again on the next reconcile unless it gets activity.

Process the user's choice:

**(backend step)** — follow your loaded `references/reconcile-<backend>.md` (§ Phase 2.2: Stale Item Actions) for the retriage/close/demote commands. Trello: § Phase 2.2: Stale item actions — Trello. (Skip if backend != trello.)

If demoting and `planning/todos.md` exists, move the item's row from `## Ready` to `## Monitor` with a note: `"Demoted from Ready — stale for {N} days"`.

Print: `"Phase 2 — {X} stale item(s) found. {Y} retriaged, {Z} closed, {W} demoted, {V} skipped."`

---

## Phase 3: Deferred Blocker Handling

> Phase 3 (deferred blocker handling) is GitHub-specific (uses sub-issues). Skip this entire phase when `backend == trello`. **(backend step)** — follow your loaded `references/reconcile-trello.md` (§ Phase 3: Deferred blocker handling — Trello fallback) for the fallback handling of spawned-during-sprint items on Trello.

Classify items spawned during sprint execution as blocking or independent.

### 3.1 Pull spawned items

**(backend step)** — follow your loaded `references/reconcile-<backend>.md` (§ Phase 3.1: Pull Spawned Items).

If no spawned items are found, print `"No spawned-during-sprint items to classify."` and skip to Phase 4.

### 3.2 Classify each spawned item

For each spawned item, read its body and determine whether it blocks a parent issue.

Detection heuristics:
- Look for `#N` references in the issue body -- these are candidate parent issues.
- If a parent reference is found, check whether the parent is still open.
- Read the parent's body and acceptance criteria. If this spawned item addresses a requirement of the parent that the parent cannot ship without, classify as **blocking**.
- If no parent reference, or the parent is already closed, or the spawned item is a nice-to-have improvement, classify as **independent**.

For each spawned item, present:

```
Spawned: #{number} — {title}
  Parent: #{parent_number} — {parent_title} (OPEN)
  Classification: {BLOCKING | INDEPENDENT}
  Reason: {one-line explanation}
```

Process automatically based on classification:

**(backend step)** — follow your loaded `references/reconcile-<backend>.md` (§ Phase 3.2: Classify Spawned Items) for the blocking/independent commands.

### 3.3 Report blocking chains

After classifying all spawned items, report any blocking chains -- sequences where A blocks B which blocks C:

```
Blocking chains detected:

  #{leaf} — {title}
    blocks #{mid} — {title}
      blocks #{root} — {title}

{N} blocking chain(s). Review priority of root items.
```

If no blocking chains exist (all blockers are single-level), skip the chain report.

Print: `"Phase 3 — {X} spawned item(s) classified. {Y} blocking, {Z} independent."`

---

## Phases 4 & 5: CONTEXT.md Maintenance and ADR Proposals

Both phases scan git history since `last_reconcile` and propose repo-doc updates —
new domain terms for CONTEXT.md, then ADRs for decision-worthy commits. Every write is
user-confirmed (yes / edit / skip); neither phase touches the issue tracker.

**Load `references/reconcile-context-and-adr.md` and follow it for both phases.**

Carry forward for the Phase 7 summary: candidate terms found/added/skipped, and ADR
candidates found/created/skipped.

---

## Phase 6: Update State

Write the current timestamp to `.pm/state.yml` as `last_reconcile`, preserving other fields.

```bash
state_file="$primary_repo_root/.pm/state.yml"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

yq -i ".last_reconcile = \"$timestamp\"" "$state_file"
```

Verify the write succeeded:

```bash
stored="$(yq '.last_reconcile' "$state_file")"
echo "State updated: last_reconcile = $stored"
```

---

## Phase 7: Summary

Print the full reconciliation report:

```
PM -- Reconcile Complete
=========================
Period:                  {last_reconcile} to {now}
Repos scanned:           {N}
Backend:                 {github or local or trello}
{If Trello: "Cards reconciled across {N} board(s). Moved to Done: {X}. Stale flagged: {Y} ({retriaged} retriaged, {closed} archived, {demoted} demoted)."}

Completion tracking:
  Items completed:       {X}
  Epics rolled up:       {Y}
  Epics normalized:      {E}  ({S} status-stripped, {B} bodies reshaped)
  Rows archived:         {Z}

Stale detection:
  Stale items found:     {A}
  Retriaged:             {B}
  Closed:                {C}
  Demoted:               {D}
  Skipped:               {E}

Blocker classification:
  Spawned items:         {F}
  Classified blocking:   {G}
  Classified independent:{H}
  Blocking chains:       {I}

CONTEXT.md:
  Terms proposed:        {J}
  Terms added:           {K}

ADRs:
  Candidates found:      {L}
  ADRs created:          {M}

{If GitHub: "Issues updated in {owner}/{repo}"}
{If local: "Items updated in {items_dir}"}

{If B > 0: "Retriaged items will appear in next /pm:triage run."}
{If G > 0: "Blocking items need priority review -- run /pm:triage."}
{If K > 0: "CONTEXT.md updated with {K} new term(s)."}
{If M > 0: "{M} ADR(s) created in {adr_dir}/ -- review and accept."}

Next reconcile: run /pm:reconcile again after your next sprint or merge cycle.
```

---

## Error Handling

- **pulse-config.yaml missing**: Stop -- run `/product-pulse:setup` or `/pm:setup`.
- **.pm/config.yml missing**: Stop -- run `/pm:setup`.
- **No repos configured**: Fall back to primary repo only. Warn: `"No repos listed in pulse-config.yaml -- scanning primary repo only."`
- **Git log fails for a repo**: Log the error, skip that repo, continue with others.
- **gh CLI unavailable or unauthenticated**: Stop for GitHub backend -- install `gh` and run `gh auth login`.
- **Sub-issues GraphQL API unavailable**: Fall back to comment-based linking for epic rollup and blocker classification.
- **CONTEXT.md missing**: Skip Phase 4 with a warning. Recommend running `/pm:setup`.
- **ADR directory missing**: Create it automatically in Phase 5. No error.
- **planning/todos.md missing**: Skip planning file updates in Phase 1.4 and Phase 2. Warn: `"planning/todos.md not found -- skipping backlog updates."`.
- **State file missing**: Create with `last_reconcile: null`. This triggers a full scan on first run (defaults to 2 weeks of history).
- **No issues referenced in git history**: Not an error. Skip to Phase 2 with a note.
- **User stops mid-reconcile**: Print a partial summary covering completed phases. State is NOT updated (Phase 6 only runs at the end) so the next reconcile re-covers the same period.
- **Zero items across all phases**: Print: `"Nothing to reconcile -- project state is clean."` Update the state timestamp so the next run starts fresh.
