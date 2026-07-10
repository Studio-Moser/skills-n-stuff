# Reconcile — GitHub Backend Detail

Backend-specific procedure blocks for `/pm:reconcile`, split out of `reconcile/SKILL.md` so Trello/local users don't have to read past them. Only relevant when `backend == github`; skip this whole file otherwise. Variables (`$gh_owner`, `$gh_repo`, `$stale_threshold`, `$default_branch`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

Epic rollup, orphan-epic sweep, and epic normalization (Phase 1.3 / 1.3b / 1.3c) are GitHub-only entirely — sub-issues are a GitHub feature, so these phases don't exist for other backends.

## Phase 0.2: Load Backend Config — GitHub

```bash
gh_owner="$(yq '.github.owner' "$pm_config")"
gh_repo="$(yq '.github.repo' "$pm_config")"
```

## Phase 1.2: Completion Tracking — GitHub

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

## Phase 1.3: Epic Rollup — GitHub

Check whether any epics have all sub-issues now closed.

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

## Phase 1.3b: Orphan-epic Sweep — GitHub

Every open todo should sit under exactly one epic (that's what makes the board's group-by-Parent-issue / Sprint Plan view readable). Flag any open issue that is **neither under an epic nor a deliberate exception** so it gets parented before it silently rots in "No Parent."

```bash
# Open issues that are not themselves epics and carry no opt-out label.
candidates=$(gh issue list --state open --limit 400 \
  --json number,title,labels --repo "$gh_owner/$gh_repo" \
  | jq -r '[.[] | select((.labels|map(.name)) as $l
      | ($l|index("epic")|not) and ($l|index("no-epic")|not))] | .[].number')
```

For each candidate, check its parent via the sub-issues API (`{repository{issue(number:N){parent{number}}}}`). If `parent` is null, it's an orphan. Present the orphans:

```
Orphan todos (no parent epic):
  #{number} — {title}    → suggest: Epic #{inferred} ({why})

{N} orphan(s). Parent them now? (yes / skip)
```

On `yes`, infer the epic by area (same matching as `/pm:triage` Phase 4.3 — memory→memory epic, a UI surface→that surface's epic, sync/reliability→reliability, etc.), confirm ambiguous ones, then `addSubIssue` (and set the project **Epic** field if `project_sync` is on). Items that genuinely belong nowhere get a `no-epic` label rather than a parent. This is the safety net for items promoted before this rule existed, or linked by hand.

## Phase 1.3c: Epic Normalization — GitHub

Epics are **goal containers** (see `/pm:triage` Phase 4.3): they carry no workflow status, and their body is a Goal/Why statement — not a checklist of constituent items (the sub-issue tree is the source of truth for membership). This phase brings existing epics into line with both rules. It's the retrofit for epics created before the convention, or by hand.

Pull every open epic with its labels and body:

```bash
gh issue list --label epic --state open --limit 200 \
  --json number,title,labels,body --repo "$gh_owner/$gh_repo" > /tmp/pm_epics.json
```

**Status labels.** An epic carrying any `status/*` label is wrong — its progress is the sub-issue progress bar, not a board column.

```bash
jq -r '[.[] | select((.labels|map(.name)) as $l | ($l|any(startswith("status/"))))]
    | .[] | "\(.number)\t\(.title)\t\([.labels[].name | select(startswith("status/"))] | join(","))"' /tmp/pm_epics.json
```

**Body shape.** An epic body needs reshaping if it isn't already a clean Goal/Why statement — i.e. it has no `## Goal` section, or it contains an item checklist (`- [ ]` / `- [x]` lines) or a bare list of sub-issue links (`#N` enumerations standing in for the sub-issue tree). For each such epic, **rewrite** the body into the Goal/Why shape:

- **Goal** — the end-state the epic drives toward, distilled from the title and whatever intent the current body expresses.
- **Why** — the outcome/value once it's done.
- **Preserve genuine prose.** If the body holds real context, constraints, or design notes beyond the checklist, fold them into Goal/Why (or keep a short `## Notes` tail) — only the item checklist and bare `#N` enumerations get dropped, since those duplicate the sub-issue tree.

Use the `Epic body template` from `/pm:triage` Phase 4.3 as the target shape. Don't fabricate a goal you can't support from the title/body — if an epic's intent is genuinely unreadable, list it for manual attention instead of guessing.

Present both corrections together:

```
Epic normalization:
  #{number} — {title}
    status labels → strip: {status/* labels}        (omit line if none)
    body          → reshape to Goal/Why             (omit line if already clean)
    proposed body:
      {the rewritten Goal/Why body}

{N} epic(s) to normalize. Apply? (yes / skip / one-by-one)
```

On `yes`, for each epic:

```bash
# strip any status/* labels (leave the `epic` label in place)
gh issue edit {number} --remove-label "{status_label}" --repo "$gh_owner/$gh_repo"
# rewrite the body
gh issue edit {number} --body "{rewritten Goal/Why body}" --repo "$gh_owner/$gh_repo"
```

`one-by-one` walks each epic's proposed rewrite for individual yes/skip — use it when several bodies carry prose worth eyeballing. Never touch open/closed state here; this only normalizes labels and body. GitHub keeps issue edit history, so a rewrite is recoverable.

## Phase 2.1: Stale Detection — GitHub

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

## Phase 2.2: Stale Item Actions — GitHub

**retriage (GitHub):**
```bash
gh issue edit "$num" \
  --add-label "status/needs-triage" \
  --remove-label "status/ready,status/in-progress,status/in-review,owner/ai,owner/human,owner/operator" \
  --repo "$gh_owner/$gh_repo"
```

After the label edit succeeds, mirror the change to the Project Status field if `github.project_sync.enabled: true` AND `github.project_sync.status_field_sync: true`. Use the detection pattern:

```
ToolSearch query: "select:mcp__github__projects_write,mcp__github__projects_list"
```

If the tools do NOT load, print ONCE per `/pm:reconcile` session:

```
warning: project_sync is enabled in config but the github MCP server is
         not available. Install /plugin install github@claude-plugins-official
         and set GITHUB_PERSONAL_ACCESS_TOKEN. Continuing in label-only mode.
```

Track the warning state so it doesn't repeat per item. Skip the MCP call and continue.

If the tools load:

1. Find the project item ID via `mcp__github__projects_list` (method `list_project_items`, filter by the issue URL). If the issue isn't a project item, call `projects_write` `add_item` first.
2. Resolve the Status option ID for `status_map["status/needs-triage"]` (typically `"Needs Triage"`).
3. Call `mcp__github__projects_write` method `update_item_field_value` with the item ID, the cached `status_field_id`, and the resolved option ID.

On error, log and continue — labels are canonical, mirror failures are non-blocking.

The other reconcile actions (close, demote, skip) either close the issue (built-in GitHub workflow handles Status → Done automatically when configured) or don't touch status, so no mirror call is needed.

**close (GitHub):**
```bash
gh issue close "$num" \
  --comment "Closed as stale by /pm:reconcile — no activity for ${stale_threshold} days." \
  --repo "$gh_owner/$gh_repo"
```

**demote (GitHub):** Cycle priority down one level (remove current P-label, add P+1):
```bash
# Determine current priority from labels, then:
gh issue edit "$num" \
  --remove-label "P${current}" \
  --add-label "P${next}" \
  --repo "$gh_owner/$gh_repo"
```

## Phase 3.1: Pull Spawned Items — GitHub

```bash
spawned=$(gh issue list \
  --label "spawned-during-sprint" \
  --state open \
  --json number,title,body \
  --repo "$gh_owner/$gh_repo" 2>/dev/null)
```

## Phase 3.2: Classify Spawned Items — GitHub

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

**Independent items (GitHub):**
```bash
gh issue edit "$num" \
  --remove-label "spawned-during-sprint" \
  --add-label "status/needs-triage" \
  --repo "$gh_owner/$gh_repo"
```

If `github.project_sync.enabled` AND `status_field_sync: true`, mirror the Status field change to `"Needs Triage"` using the same detection pattern and MCP call sequence as § Phase 2.2: Stale Item Actions — GitHub (retriage) above. Reuse the one-time warning state for this run.
