# Triage — GitHub Backend Detail

Backend-specific procedure blocks for `/pm:triage`, split out of `triage/SKILL.md` so Trello/local users don't have to read past them. Only relevant when `backend == github`; skip this whole file otherwise. Variables (`$gh_owner`, `$gh_repo`, `{number}`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

## Phase 0.2: Pull Needs-Triage Items — GitHub

```bash
gh_owner="$(yq '.github.owner' "$pm_config")"
gh_repo="$(yq '.github.repo' "$pm_config")"

triage_items=$(gh issue list \
  --label "status/needs-triage" \
  --state open \
  --json number,title,body,labels,assignees \
  --limit 100 \
  --repo "$gh_owner/$gh_repo")
```

## Phase 0.3: Load Existing Open Items (dedup pool) — GitHub

Same `gh issue list` call as above but without `--label` filter, piped through `jq` to exclude `status/needs-triage` items.

## Phase 1: Process rejections — GitHub

Write the same `oos_file` markdown (this is backend-agnostic; see SKILL.md), then close the item:

```bash
gh issue close {number} \
  --comment "Rejected during triage. See \`.pm/out-of-scope/${slug}.md\` for decision record." \
  --repo "$gh_owner/$gh_repo"

gh issue edit {number} \
  --remove-label "status/needs-triage" \
  --repo "$gh_owner/$gh_repo"
```

## Phase 1: Process duplicates — GitHub

```bash
gh issue close {number} \
  --comment "Duplicate of #{duplicate_number}. Closing." \
  --repo "$gh_owner/$gh_repo"

gh issue edit {number} \
  --remove-label "status/needs-triage" \
  --add-label "duplicate" \
  --repo "$gh_owner/$gh_repo"
```

## Phase 2, Step 2b.1: Create XL epic and children — GitHub

Run only after the user approves the displayed XL split. Convert the current issue into
the goal epic, removing every existing workflow and size label so `epic` is its only
label:

```bash
epic_number={number}
gh issue view "$epic_number" --json labels --jq '.labels[].name' \
  --repo "$gh_owner/$gh_repo" |
while IFS= read -r label; do
  gh issue edit "$epic_number" --remove-label "$label" --repo "$gh_owner/$gh_repo"
done
gh issue edit "$epic_number" \
  --body "{confirmed Goal/Why body}" \
  --add-label "epic" \
  --repo "$gh_owner/$gh_repo"
```

Create confirmed children in blocker-first order. Each child starts in the existing
`status/needs-triage` state with its confirmed size and no owner label. Use the issue
numbers already captured for any `Blockers` values in `{child spec content}`.

```bash
xl_child_ids=()

# Repeat for each confirmed child.
child_url=$(gh issue create \
  --title "{child title}" \
  --body "{child spec content, including Part of Epic #${epic_number}}" \
  --label "status/needs-triage,size/{child_size}" \
  --repo "$gh_owner/$gh_repo")
child_number="${child_url##*/}"

# Follow references/github-sub-issues.md with epic_number as the parent and
# child_number as the child, including its documented comment fallback.
xl_child_ids+=("$child_number")
```

After all children are created, load the issues in `xl_child_ids` and return them to
the shared flow as the Phase 3 carry-forward items. Do not return `epic_number` as an
implementation item.

## Phase 2, Step 2c: Write spec to backend — GitHub

Update the issue body with the canonical spec content from
`references/triage-spec-flow.md` (§ Step 2c):

```bash
gh issue edit {number} \
  --body "{spec content}" \
  --repo "$gh_owner/$gh_repo"
```

## Phase 4.2: Update backend (promote) — GitHub

```bash
# Combine all labels into one edit call
gh issue edit {number} \
  --remove-label "status/needs-triage" \
  --add-label "status/ready,{owner_label},{size_label}" \
  --repo "$gh_owner/$gh_repo"

# Add priority and target-repo labels if applicable
gh issue edit {number} --add-label "priority/p{priority}" --repo "$gh_owner/$gh_repo"
gh issue edit {number} --add-label "repo/{target_repo_name}" --repo "$gh_owner/$gh_repo"
```

Where `{owner_label}` is `owner/ai` (6/6 verdict) or `owner/human` (4-5/6 verdict).

## Phase 4.2a: Mirror Status field to GitHub Project (optional) — GitHub

After the `gh issue edit` calls above succeed, if `github.project_sync.enabled: true` AND `github.project_sync.status_field_sync: true` in `.pm/config.yml`, mirror the new `status/ready` value onto the project's Status field.

Use the detection pattern: try to load `mcp__github__projects_write` via:

```
ToolSearch query: "select:mcp__github__projects_write,mcp__github__projects_list"
```

If the tools do NOT load, print ONCE per `/pm:triage` session:

```
warning: project_sync is enabled in config but the github MCP server is
         not available. Install /plugin install github@claude-plugins-official
         and set GITHUB_PERSONAL_ACCESS_TOKEN. Continuing in label-only mode.
```

Track that you've warned so you don't repeat per item. Skip the MCP calls and continue with the next item.

If the tools load:

1. Look up the project item ID for this issue. Call `mcp__github__projects_list` with method `list_project_items`, scoped to `project_owner`/`project_number` from config, filtered by the issue's URL (`https://github.com/{gh_owner}/{gh_repo}/issues/{number}`). The response gives an item ID.

   If the issue is not yet a project item (e.g. created after `/pm:setup`), call `mcp__github__projects_write` with method `add_item` first, then read back the new item ID.

2. Look up the Status field option ID for the target status. Use the cached `status_field_id` from config; resolve the option ID for `status_map["status/ready"]` (e.g. `"Ready"`) — query field options via `projects_list` if you don't have them cached.

3. Call `mcp__github__projects_write` with method `update_item_field_value`, passing the item ID, field ID, and option ID.

On any MCP error, log it and continue — never block the canonical label update on a Project mirror failure.

## Phase 4.3: Link to a parent epic — GitHub

Listing open epics (for the "infer from open epics" step):

```bash
gh issue list --label epic --state open --repo "$gh_owner/$gh_repo"
```

Match by area (memory work → the memory epic; a specific UI surface → that surface's epic; sync/reliability → the reliability epic; etc.).

Creating a new epic (when none fits), using the Goal/Why body template from SKILL.md:

```bash
gh issue create \
  --title "{epic title}" \
  --body "{Goal/Why body from the template above}" \
  --label "epic" \
  --repo "$gh_owner/$gh_repo"
```

Capture the new epic's number to use as `{epic_number}` below.

Create the **native sub-issue relationship**; this is the canonical mechanism that drives epic grouping and the epic progress bar. Follow `references/github-sub-issues.md`, using `{epic_number}` as the parent and `{number}` as the child (GraphQL `addSubIssue`, with the comment-based fallback).

- An issue can have **only one parent**. If the child already has a different parent, `removeSubIssue` from the old parent first, then `addSubIssue` to the correct one — otherwise the add fails with a VALIDATION error.
- If `github.project_sync.enabled` AND the project has a custom **Epic** field, also set it (`gh project item-edit --id {item_id} --field-id {epic_field_id} --project-id {project_id} --text "#{epic_number} {epic_title}"`, or the `projects_write` `update_item_field_value` MCP call) so the native sub-issue tree and the group-by-Epic-field view agree.
