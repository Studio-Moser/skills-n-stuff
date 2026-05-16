---
name: reconcile
description: >-
  Sync project reality with the issue tracker. Scans git history for completed
  items, detects stale work, classifies deferred blockers, updates epic
  progress, proposes CONTEXT.md updates and ADRs. Run after sprints, after
  merges, or periodically.
  Trigger: "reconcile", "sync issues", "clean up backlog", "check progress",
  or /pm:reconcile.
effort: medium
allowed-tools: "Bash Read Write Edit"
---

# PM -- Reconcile

You are the project janitor. Your job is to walk through git history, the issue tracker, and the planning files to make sure everything reflects reality. You close what's done, flag what's stale, classify deferred blockers, update epic rollups, and propose CONTEXT.md and ADR additions when the codebase has evolved.

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

**GitHub backend:**

```bash
gh_owner="$(yq '.github.owner' "$pm_config")"
gh_repo="$(yq '.github.repo' "$pm_config")"
```

**Local backend:**

```bash
items_dir="$primary_repo_root/$(yq '.local.items_dir // ".pm/items"' "$pm_config")"
```

**Trello backend:**

```bash
# Multi-board: every reconcile pass walks every configured board.
boards_count="$(echo "$trello_boards_json" | jq 'length')"
[ "$boards_count" -lt 1 ] && echo "ERROR: no boards configured" && exit 0
```

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

**GitHub backend:**

```bash
for num in "${unique_refs[@]}"; do
  issue_data=$(gh issue view "$num" \
    --json state,title,labels \
    --repo "$gh_owner/$gh_repo" 2>/dev/null) || continue

  state=$(echo "$issue_data" | jq -r '.state')
  title=$(echo "$issue_data" | jq -r '.title')

  # Skip already-closed issues
  [ "$state" = "CLOSED" ] && continue

  # Check if the referencing commit is on the default branch
  for repo in "${repos[@]}"; do
    on_default=$(cd "$repo" && git log "$default_branch" --since="$last_reconcile" --oneline | grep -c "#${num}")
    if [ "$on_default" -gt 0 ]; then
      # Also check for merged PRs referencing this issue
      merged_prs=$(gh pr list \
        --search "$num" \
        --state merged \
        --json number,title \
        --repo "$gh_owner/$gh_repo" 2>/dev/null)

      echo "Issue #${num} (${title}) — referenced on ${default_branch}, appears complete."
      break
    fi
  done
done
```

For each issue that appears complete (referenced on the default branch with a merged PR), present it to the user:

```
Completed: #{number} — {title}
  Evidence: commit on {default_branch}, PR #{pr_number} merged
  Action: Close this issue? (yes / skip)
```

If the user confirms, close the issue:

```bash
gh issue close "$num" \
  --comment "Closed by /pm:reconcile — referenced in merged commits on ${default_branch}." \
  --repo "$gh_owner/$gh_repo"
```

**Local backend:**

```bash
for num in "${unique_refs[@]}"; do
  item_file=$(ls "$items_dir"/${num}-*.yml 2>/dev/null | head -1)
  [ -z "$item_file" ] && continue

  state=$(yq '.closed_at // "null"' "$item_file")
  [ "$state" != "null" ] && continue

  title=$(yq '.title' "$item_file")
  echo "Issue #${num} (${title}) — referenced on ${default_branch}, appears complete."
done
```

On user confirmation for local backend:

```bash
yq -i '.labels -= ["status/ready","status/in-progress","status/in-review","owner/ai","owner/human","owner/operator"] | .labels += ["status/done"] | .closed_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' "$item_file"
```

### 1.2T Trello backend completion tracking

Loop over boards. On each board, read `LIST_REVIEW` cards and reconcile their PR state.

```bash
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # Agent executes:
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # review_id = (find name == $LIST_REVIEW).id
  # cards = mcp__trello__get_cards_by_list_id({ listId: review_id })
  # For each card:
  #   comments = mcp__trello__get_card_comments({ cardId: card.id })
  #   pr_url = first PR URL from card.desc + comments
  #   if pr_url and `gh pr view <pr_url> --json state` == "MERGED":
  #     present to user: "Card '{name}' on '{BOARD_NAME}' — PR merged. Move to Done? (yes/skip)"
  #     if yes:
  #       check-transition.sh review done $trello_statuses_json
  #       mcp__trello__move_card({ cardId: card.id, listId: <done id> })
  #       mcp__trello__add_comment({ cardId: card.id, text: "Moved to Done by /pm:reconcile — PR <pr_url> merged." })
done
```

Epic rollup is GitHub-only (sub-issues are a GitHub feature). Skip Phase 1.3 entirely when `backend == trello`.

### 1.3 Epic rollup (GitHub-only — skip when backend != github.)

Check whether any epics have all sub-issues now closed.

**GitHub backend:**

```bash
epics=$(gh issue list \
  --label "epic" \
  --state open \
  --json number,title \
  --repo "$gh_owner/$gh_repo" 2>/dev/null)
```

For each open epic, query its sub-issues:

```bash
for epic_num in $(echo "$epics" | jq -r '.[].number'); do
  sub_issues=$(gh api graphql -f query='
    query {
      repository(owner: "'"$gh_owner"'", name: "'"$gh_repo"'") {
        issue(number: '"$epic_num"') {
          subIssues(first: 50) {
            nodes { number state }
          }
        }
      }
    }
  ' 2>/dev/null)

  total=$(echo "$sub_issues" | jq '.data.repository.issue.subIssues.nodes | length')
  closed=$(echo "$sub_issues" | jq '[.data.repository.issue.subIssues.nodes[] | select(.state == "CLOSED")] | length')

  if [ "$total" -gt 0 ] && [ "$total" -eq "$closed" ]; then
    echo "Epic #${epic_num} — all ${total} sub-issues closed."
  fi
done
```

If the sub-issues GraphQL API is unavailable, fall back to scanning the epic's body for `#N` references and checking each individually.

Present completed epics:

```
Epic complete: #{epic_number} — {title}
  Sub-issues: {closed}/{total} closed
  Action: Close this epic? (yes / skip)
```

**Local backend:** Scan items where `parent_epic` matches the epic number. If all are closed, flag the epic.

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

Print: `"Phase 1 — {X} item(s) completed, {Y} epic(s) rolled up, {Z} row(s) archived."`

---

## Phase 2: Stale Detection

Pull all open items and flag those with no activity past the threshold.

### 2.1 Identify stale items

**GitHub backend:**

```bash
stale_items=$(gh issue list \
  --state open \
  --json number,title,updatedAt,labels \
  --limit 200 \
  --repo "$gh_owner/$gh_repo" 2>/dev/null)
```

Filter to items whose `updatedAt` is older than `stale_threshold` days:

```bash
cutoff=$(date -u -v-${stale_threshold}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "${stale_threshold} days ago" +%Y-%m-%dT%H:%M:%SZ)

echo "$stale_items" | jq --arg cutoff "$cutoff" \
  '[.[] | select(.updatedAt < $cutoff)]'
```

Exclude items with labels `epic`, `monitor`, or `blocker` -- these are expected to be long-lived.

**Local backend:**

```bash
for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  closed=$(yq '.closed_at // "null"' "$item_file")
  [ "$closed" != "null" ] && continue

  updated=$(yq '.updated_at // .created_at' "$item_file")
  # Compare $updated against $cutoff
done
```

**Trello backend:**

The MCP server's card objects include a `dateLastActivity` field returned by `get_card`. To find stale cards, walk every non-terminal list on every board and check that field. (`done` is excluded — completed cards aren't stale.)

```bash
cutoff=$(date -u -v-${stale_threshold}d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -d "${stale_threshold} days ago" +%Y-%m-%dT%H:%M:%SZ)

stale_cards=()
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # Agent executes for each non-done list (needs_triage, ready_for_agent, in_progress, review, needs_changes, blocked):
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # for each list_name in [LIST_NEEDS_TRIAGE, LIST_READY_FOR_AGENT, LIST_IN_PROGRESS, LIST_REVIEW, LIST_NEEDS_CHANGES, LIST_BLOCKED]:
  #   list_id = lookup
  #   cards = mcp__trello__get_cards_by_list_id({ listId: list_id })
  #   for each card with dateLastActivity < cutoff:
  #     append { id, name, list_name, dateLastActivity, BOARD_ID, BOARD_NAME }
done
```

The "exclude epic/monitor/blocker" rule from the GitHub branch translates to: skip cards whose labels include `epic` or `monitor`. Cards in `LIST_BLOCKED` are explicitly long-lived and are skipped from stale flagging by virtue of the calling list filter — `LIST_BLOCKED` is included in the loop, but the user can choose `skip` to keep them as-is.

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

**retriage (GitHub):**
```bash
gh issue edit "$num" \
  --add-label "status/needs-triage" \
  --remove-label "status/ready,status/in-progress,status/in-review,owner/ai,owner/human,owner/operator" \
  --repo "$gh_owner/$gh_repo"
```

**retriage (local):**
```bash
yq -i '.labels -= ["status/ready","status/in-progress","status/in-review","owner/ai","owner/human","owner/operator"] | .labels += ["status/needs-triage"]' "$item_file"
```

**close (GitHub):**
```bash
gh issue close "$num" \
  --comment "Closed as stale by /pm:reconcile — no activity for ${stale_threshold} days." \
  --repo "$gh_owner/$gh_repo"
```

**close (local):**
```bash
yq -i '.labels += ["stale-closed"] | .closed_at = "'"$(date -u +%Y-%m-%dT%H:%M:%SZ)"'"' "$item_file"
```

**demote (GitHub):** Cycle priority down one level (remove current P-label, add P+1):
```bash
# Determine current priority from labels, then:
gh issue edit "$num" \
  --remove-label "P${current}" \
  --add-label "P${next}" \
  --repo "$gh_owner/$gh_repo"
```

**demote (local):**
```bash
yq -i '.priority = "P'"${next}"'"' "$item_file"
```

If demoting and `planning/todos.md` exists, move the item's row from `## Ready` to `## Monitor` with a note: `"Demoted from Ready — stale for {N} days"`.

**Trello (retriage):** validate then move card back to `LIST_NEEDS_TRIAGE`.

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-transition.sh" \
  "$card_current_list_key" "needs_triage" "$trello_statuses_json" \
  || echo "warning: transition $card_current_list_key -> needs_triage not allowed in current statuses map; skipping"
```

```
mcp__trello__move_card({ cardId: $card_id, listId: $needs_triage_list_id })
mcp__trello__add_comment({ cardId: $card_id, text: "Re-triaged by /pm:reconcile — stale for {N} days." })
```

If the configured `statuses` map does not allow this transition, surface the violation; do NOT silently override. The user can either widen the statuses map (back-edge from any list to `needs_triage`) or pick a different action.

**Trello (close):** archive the card.

```
mcp__trello__add_comment({ cardId: $card_id, text: "Closed as stale by /pm:reconcile — no activity for {N} days." })
mcp__trello__archive_card({ cardId: $card_id })
```

**Trello (demote):** Trello has no first-class priority. Apply or update a `P{N+1}` label via `update_card_details` and, if `planning/todos.md` exists, demote the row from `Ready` to `Monitor` (same as GitHub).

```
mcp__trello__update_card_details({
  cardId: $card_id,
  labels: ["P{next}", ...preserve other labels except old P{current}]
})
```

Print: `"Phase 2 — {X} stale item(s) found. {Y} retriaged, {Z} closed, {W} demoted, {V} skipped."`

---

## Phase 3: Deferred Blocker Handling

> Phase 3 (deferred blocker handling) is GitHub-specific (uses sub-issues). When `backend == trello`, skip this entire phase. The Trello equivalent — child cards / blocking checklists — is out of scope for this plan; if a sub-agent files a "spawned-during-sprint" finding while running on Trello, it should `mcp__trello__add_card_to_list` it to `LIST_NEEDS_TRIAGE` with a label `spawned-during-sprint`, and reconcile-time triage handles it like any other incoming item.

Classify items spawned during sprint execution as blocking or independent.

### 3.1 Pull spawned items

**GitHub backend:**

```bash
spawned=$(gh issue list \
  --label "spawned-during-sprint" \
  --state open \
  --json number,title,body \
  --repo "$gh_owner/$gh_repo" 2>/dev/null)
```

**Local backend:**

```bash
spawned=()
for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  labels="$(yq '.labels[]' "$item_file" 2>/dev/null)"
  echo "$labels" | grep -q "spawned-during-sprint" && spawned+=("$item_file")
done
```

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

**Blocking items (GitHub):**
```bash
gh issue edit "$num" \
  --add-label "blocker" \
  --repo "$gh_owner/$gh_repo"

# Link to parent via sub-issue API — see references/github-sub-issues.md
# for the full GraphQL mutation with comment-based fallback.
parent_id=$(gh issue view "$parent_num" --json id --jq '.id' --repo "$gh_owner/$gh_repo")
child_id=$(gh issue view "$num" --json id --jq '.id' --repo "$gh_owner/$gh_repo")
gh api graphql -f query='mutation{addSubIssue(input:{issueId:"'"$parent_id"'",subIssueId:"'"$child_id"'"}){issue{id}subIssue{id}}}' 2>/dev/null || \
  gh issue comment "$num" --body "Blocking: parent #$parent_num cannot ship without this." --repo "$gh_owner/$gh_repo"
```

**Blocking items (local):**
```bash
yq -i '.labels += ["blocker"] | .parent_epic = '"$parent_num"'' "$item_file"
```

**Independent items (GitHub):**
```bash
gh issue edit "$num" \
  --remove-label "spawned-during-sprint" \
  --add-label "status/needs-triage" \
  --repo "$gh_owner/$gh_repo"
```

**Independent items (local):**
```bash
yq -i '.labels -= ["spawned-during-sprint"] | .labels += ["status/needs-triage"]' "$item_file"
```

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

## Phase 4: CONTEXT.md Maintenance

Scan recent commits for new domain concepts that should be documented in CONTEXT.md.

### 4.1 Collect new files and significant changes

For each configured repo, list files added or modified since the last reconcile:

```bash
new_entities=()
for repo in "${repos[@]}"; do
  changed_files=$(cd "$repo" && git log --since="$last_reconcile" \
    --diff-filter=AM --name-only --oneline 2>/dev/null \
    | grep -v '^[a-f0-9]' | sort -u)

  for f in $changed_files; do
    # Look for files that likely define types, interfaces, or modules
    case "$f" in
      *.swift|*.ts|*.py|*.go|*.rs|*.java|*.rb|*.js)
        new_entities+=("$repo:$f")
        ;;
    esac
  done
done
```

### 4.2 Extract candidate domain terms

For each source file in `new_entities`, scan for patterns that indicate new domain concepts:

- **Type/struct/class definitions**: `struct Foo`, `class Bar`, `type Baz`, `interface Qux`, `enum Quux`
- **Protocol/trait definitions**: `protocol Foo`, `trait Bar`
- **Module/namespace declarations**: `module Foo`, `namespace Bar`, `package foo`
- **New API endpoints**: route definitions, controller actions
- **New constants or configuration keys** that represent domain concepts

Exclude obvious infrastructure types (e.g., `ViewModel`, `Controller`, `Manager`, `Helper`, `Utils`) unless they embed a meaningful domain term.

### 4.3 Propose additions

Read the existing CONTEXT.md:

```bash
context_md_path="$primary_repo_root/$(yq '.context_md // "CONTEXT.md"' "$pm_config")"
```

If CONTEXT.md does not exist, print `"No CONTEXT.md found. Run /pm:setup to create one, or skip."` and move to Phase 5.

For each candidate term, check whether it already appears in CONTEXT.md. If not, propose adding it:

```
Proposed term: {TermName}
  Source: {repo}/{file}:{line}
  Suggested definition: {inferred from context — type declaration, doc comment, or surrounding code}
  Add to CONTEXT.md? (yes / edit / skip)
```

- **yes** -- Add the term to the Terms table in CONTEXT.md as proposed.
- **edit** -- User provides their own definition. Add with the user's text.
- **skip** -- Do not add this term.

When adding a term, append a row to the `## Terms` table:

```markdown
| {TermName} | {definition} | {aliases if any, or "---"} |
```

Print: `"Phase 4 — {X} candidate term(s) found. {Y} added to CONTEXT.md, {Z} skipped."`

---

## Phase 5: ADR Proposals

Scan recent commits for architectural decisions that should be documented.

### 5.1 Identify decision-worthy commits

For each configured repo, review commits since the last reconcile:

```bash
for repo in "${repos[@]}"; do
  cd "$repo" && git log --since="$last_reconcile" --oneline --all \
    --diff-filter=AM --stat 2>/dev/null
done
```

A commit is a candidate for an ADR if it meets ALL THREE criteria:

1. **Hard to reverse** -- introduces a new dependency, changes a data model, adopts a new pattern across multiple files, modifies a public API, or changes a persistence layer.
2. **Surprising without context** -- a future reader would ask "why did we do it this way?" The commit message alone does not explain the trade-off.
3. **Real trade-off** -- there were plausible alternatives that were rejected. Pure bug fixes and minor refactors do not qualify.

Signals to look for:
- New entries in `Package.swift`, `package.json`, `Cargo.toml`, `go.mod`, `Gemfile`, `requirements.txt`, `build.gradle`
- Schema migrations or model changes
- Commits touching 10+ files with a consistent pattern change
- New directories representing architectural boundaries (e.g., `Sources/NewModule/`)
- Replacement of one library with another

### 5.2 Propose ADRs

For each candidate, present to the user:

```
ADR candidate:
  Commit: {sha} — {message}
  Repo: {repo_name}
  Signal: {what triggered the detection — e.g., "new dependency: libfoo added to Package.swift"}
  Proposed title: ADR-{next_number}: {title}
  Create this ADR? (yes / edit / skip)
```

- **yes** -- Create the ADR using the template.
- **edit** -- User adjusts the title or provides additional context before creation.
- **skip** -- Do not create an ADR for this commit.

### 5.3 Write ADRs

Read the ADR template from `plugins/pm/templates/adr-template.md`. Determine the next ADR number:

```bash
adr_dir="$primary_repo_root/$(yq '.adr_dir // "docs/adr"' "$pm_config")"
mkdir -p "$adr_dir"

last_adr=$(ls "$adr_dir" | grep -oE '^[0-9]+' | sort -n | tail -1)
next_adr=$(printf '%04d' $(( ${last_adr:-0} + 1 )))
```

Write the ADR file:

```markdown
# ADR-{next_adr}: {Title}

**Date:** {TODAY}
**Status:** Proposed

## Context

{Why this decision was made. Reference the commit, the problem it solved, and
what alternatives existed. Infer from the commit diff, message, and surrounding
code. Keep factual -- do not speculate beyond what the code shows.}

## Decision

{What was done. Reference specific files, patterns, or dependencies introduced.}

## Consequences

### Positive
- {benefit inferred from the change}

### Negative
- {trade-off or limitation introduced}

### Neutral
- {side-effect worth noting}
```

Save to `{adr_dir}/{next_adr}-{slug}.md`:

```bash
slug=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
adr_file="$adr_dir/${next_adr}-${slug}.md"
```

Print: `"Phase 5 — {X} ADR candidate(s) found. {Y} created, {Z} skipped."`

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
