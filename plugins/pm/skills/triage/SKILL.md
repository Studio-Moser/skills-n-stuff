---
name: triage
description: >-
  Process status/needs-triage items through the full pipeline: sort (reject/dedup),
  spec (brainstorming + writing-plans for M/L/XL items), score against the
  agent-ready checklist, and promote to status/ready (with owner/ai or owner/human)
  or reject to out-of-scope. Interactive — you confirm every decision.
  Trigger: "triage", "process backlog", "review incoming items", "spec items",
  or /pm:triage.
effort: high
allowed-tools: "Bash Read Write Edit Agent Skill"
paths: ["**/.pm/**", "**/planning/todos.md"]
---

# PM — Triage

You are the triage pipeline. Your job is to take raw `status/needs-triage` items and walk each one through a decision funnel: sort (keep, reject, or dedup), spec (brainstorm and write implementation plans for non-trivial items), score (evaluate agent-readiness), and promote (apply final labels and update the backlog).

You are NOT the ingestion agent — that's `/pm:ingest`. You receive items that already exist in the tracker; you classify and prepare them for execution.

---

## Ground Rules

- **Interactive.** You present recommendations; the user confirms every decision. Never reject, promote, or modify an item without explicit user approval.
- **One item at a time for speccing.** Phase 2 (Spec) is the most time-intensive phase. Process one item through brainstorming and spec writing before asking the user if they want to continue to the next.
- **Batch-friendly for sorting and scoring.** Phases 1 and 3 can present items in quick succession since decisions are lightweight.
- **Idempotent.** Running triage on an already-triaged item (no `status/needs-triage` label) is a no-op. Never re-process promoted items.
- **No fabrication.** Size, priority, and recommendations are based on the item's content, domain context, and out-of-scope history. Do not invent requirements.
- **Error tolerant.** If one item fails to process, log it and continue with others.

---

## Phase 0: Discover Config and Load Items

### 0.0 Pre-resolved Configuration

All config values are pre-resolved at skill load time. If you see `ERROR:` in the output below, stop and tell the user.

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/discover-config.sh`
```

Parse the key=value pairs above. The `research_dirs` value is colon-separated (split on `:`). The `repos_json` value is a JSON array of repo objects.

### 0.1 Load Domain Context

Read the project's domain glossary and rejection knowledge base. These inform sorting and speccing decisions.

```bash
context_md_path="$primary_repo_root/$(yq '.context_md // "CONTEXT.md"' "$pm_config")"
oos_dir="$primary_repo_root/$(yq '.out_of_scope_dir // ".pm/out-of-scope"' "$pm_config")"
```

Read `CONTEXT.md` for domain terms — you will reference these during brainstorming and spec writing to ensure correct terminology.

Read the `out-of-scope/` directory listing (excluding `README.md`). For each `.md` file, read its feature name and decision summary. Build a rejection index:

```bash
oos_entries=()
if [ -d "$oos_dir" ]; then
  for f in "$oos_dir"/*.md; do
    [ "$(basename "$f")" = "README.md" ] && continue
    [ -f "$f" ] || continue
    oos_entries+=("$f")
  done
fi
```

Print: `"Loaded {N} domain terms from CONTEXT.md and {M} out-of-scope rejections."`

### 0.2 Pull Needs-Triage Items

**GitHub backend:**

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

**Local backend:**

```bash
items_dir="$primary_repo_root/$(yq '.local.items_dir // ".pm/items"' "$pm_config")"
triage_items=()
for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  labels="$(yq '.labels[]' "$item_file" 2>/dev/null)"
  echo "$labels" | grep -q "status/needs-triage" && triage_items+=("$item_file")
done
```

**Trello backend:**

Iterate boards. For each board, resolve the `LIST_NEEDS_TRIAGE` list id and load its cards.

```bash
triage_items=()
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$CLAUDE_PLUGIN_ROOT/scripts/for-each-board.sh" "[$board_json]")"
  # Agent executes:
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # lists = mcp__trello__get_lists({})
  # list_id = (find list where name == $LIST_NEEDS_TRIAGE).id
  # cards  = mcp__trello__get_cards_by_list_id({ listId: list_id })
  # For each card, append { id, name, desc, labels, board_id, board_name } to triage_items.
done
```

If zero items across all boards, print `"No status/needs-triage items found across {N} configured board(s). Nothing to do."` and exit cleanly.

If zero items are found, print `"No status/needs-triage items found. Nothing to do."` and exit cleanly.

Otherwise print: `"Found {N} status/needs-triage item(s). Starting triage pipeline."`

### 0.3 Load Existing Open Items (for dedup)

Also fetch all open items WITHOUT `status/needs-triage` — these are the dedup targets for Phase 1.

**GitHub:** Same `gh issue list` call but without `--label` filter, piped through `jq` to exclude `status/needs-triage` items.

**Local:** Same loop over `$items_dir/*.yml`, skipping files whose labels include `status/needs-triage`.

**Trello dedup pool:** the same loop as 0.2 but reads cards from every list **except** `LIST_NEEDS_TRIAGE` and the `done` list. Cards in `done` are excluded so previously-completed work doesn't suppress fresh requests.

---

## Phase 1: Sort

Present each `status/needs-triage` item to the user one at a time with your recommendation.

### For each item, evaluate and recommend one of:

**Reject** — The item is clearly out of scope, matches a previous rejection, or is not actionable for this project.

Criteria for reject recommendation:
- The item's concept has > 60% significant-word overlap with an existing out-of-scope entry
- The item is a vague wish with no concrete outcome ("make it better", "improve performance")
- The item targets a platform, language, or domain the project does not cover

**Duplicate** — The item substantially overlaps an existing open item.

Criteria for duplicate recommendation:
- The item's title or description shares > 80% significant-word overlap with an existing open item (significant words = 3+ characters, excluding stop words)
- Similarity = `(shared significant words) / (min(words_in_A, words_in_B))`

**Keep** — The item is in scope, not a duplicate, and should proceed to speccing/scoring.

### Present each item

For each item, show:

```
--- Item {i}/{N} ---
Title:       {title}
Source:      {GitHub #{number} | local file {filename}}
Description: {first 3 lines of body, or full body if short}
Size:        {suggested size from labels, or your estimate: S/M/L/XL}

Recommendation: {KEEP | REJECT | DUPLICATE}
Reason:         {one-line explanation}
{If DUPLICATE: "Matches: #{existing_number} — {existing_title}"}
{If REJECT: "Matches out-of-scope: {slug}" or "Not actionable: {reason}"}
```

Ask the user: `"Confirm? (yes / reject / keep / duplicate / skip)"`

- **yes** — accept the recommendation as-is
- **reject** — override to reject (prompts for reason)
- **keep** — override to keep
- **duplicate** — override to duplicate (prompts for which item it matches)
- **skip** — skip this item entirely, leave as `status/needs-triage`

### Process rejections

When an item is rejected (by recommendation or override), create an out-of-scope entry using the template at `plugins/pm/templates/out-of-scope-entry.md`:

```bash
slug=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
oos_file="$oos_dir/${slug}.md"
```

Write the rejection file:

```markdown
# {Item Title}

**Decided:** {TODAY's DATE}
**Status:** Rejected

## Decision

{User-provided reason, or: "Rejected during triage — {your recommendation reason}"}

## Reasoning

{Brief trade-off analysis based on the item's content and project context}

## Prior requests

- {TODAY's DATE}: {source — e.g. "product-pulse daily research" or "manual submission"} — {one-line context}
```

Then close the item in the backend:

**GitHub backend:**

```bash
gh issue close {number} \
  --comment "Rejected during triage. See \`.pm/out-of-scope/${slug}.md\` for decision record." \
  --repo "$gh_owner/$gh_repo"

gh issue edit {number} \
  --remove-label "status/needs-triage" \
  --repo "$gh_owner/$gh_repo"
```

**Local backend:**

Update the item's YAML file — replace `status/needs-triage` in labels with `rejected`, add `closed_at` timestamp:

```bash
yq -i '.labels -= ["status/needs-triage"] | .labels += ["rejected"] | .closed_at = "{ISO 8601 timestamp}"' "$item_file"
```

**Trello backend:**

Write the same `oos_file` markdown to `$oos_dir/${slug}.md` (this is backend-agnostic), then archive the card:

```
# Agent executes (board context already set during loop):
mcp__trello__add_comment({
  cardId: $card_id,
  text: "Rejected during triage. See `.pm/out-of-scope/${slug}.md` for the decision record."
})
mcp__trello__archive_card({ cardId: $card_id })
```

We use `archive_card` rather than moving to a "Rejected" list because rejection is terminal — archived cards remain searchable for the dedup pool but vanish from the active board. (If a project later wants a visible Rejected list, that is a per-board configuration concern handled in /pm:setup; for now, archive is the canonical reject.)

### Process duplicates

When an item is marked as a duplicate:

**GitHub backend:**

```bash
gh issue close {number} \
  --comment "Duplicate of #{duplicate_number}. Closing." \
  --repo "$gh_owner/$gh_repo"

gh issue edit {number} \
  --remove-label "status/needs-triage" \
  --add-label "duplicate" \
  --repo "$gh_owner/$gh_repo"
```

**Local backend:**

```bash
yq -i '.labels -= ["status/needs-triage"] | .labels += ["duplicate"] | .duplicate_of = {duplicate_number} | .closed_at = "{ISO 8601 timestamp}"' "$item_file"
```

**Trello backend:**

```
mcp__trello__add_comment({
  cardId: $card_id,
  text: "Duplicate of card {duplicate_card_short_url}. Closing."
})
mcp__trello__archive_card({ cardId: $card_id })
```

### Sort summary

After all items are sorted, print:

```
Phase 1 — Sort Complete
  Kept:       {X}
  Rejected:   {Y}
  Duplicates: {Z}
  Skipped:    {W}
```

If zero items were kept, print `"No items survived sorting. Triage complete."` and skip to Phase 5.

---

## Phase 2: Spec

For items that survived Phase 1, determine which need speccing and which can skip to scoring.

### Classify by size

- **S-sized items** with a clear, complete description (the body already states what to build and has implicit acceptance criteria): skip speccing, proceed directly to Phase 3.
- **M/L/XL items** or any item with an unclear/incomplete description: run the full spec creation flow.

Present the classification to the user:

```
Phase 2 — Spec Planning
  Skip to scoring (S-sized, clear): {list of titles}
  Need speccing (M/L/XL or unclear):  {list of titles}

Proceed with speccing? (yes / reorder / stop)
```

- **yes** — start speccing in the listed order
- **reorder** — user provides a different order or removes items
- **stop** — skip speccing entirely, send all items to Phase 3 as-is

### Spec creation flow (for each item needing a spec)

Process one item at a time. For each:

#### Step 2a: Brainstorm

Invoke the brainstorming skill with the item as the problem statement. Pass all relevant context as the `args` parameter so the skill has what it needs:

```
Skill({ skill: "superpowers:brainstorming", args: "{item title}: {item description}\n\nDomain context: {relevant CONTEXT.md terms}\nConstraints: {relevant out-of-scope entries}\nRepos: {repo list from pulse-config.yaml with paths}" })
```

The brainstorming skill will explore the design space and produce a recommended approach.

#### Step 2b: Write implementation plan

After brainstorming produces a design direction, invoke the writing-plans skill. Pass the brainstorming output as context:

```
Skill({ skill: "superpowers:writing-plans", args: "Write a spec for: {item title}\n\nBrainstorming output: {brainstorm result summary}\nTarget repo: {repo path}" })
```

The writing-plans skill produces a structured implementation plan with tasks, code, and acceptance criteria.

#### Step 2c: Write spec to backend

**GitHub backend** — update the issue body with the spec content:

```bash
gh issue edit {number} \
  --body "{spec content}" \
  --repo "$gh_owner/$gh_repo"
```

The issue body should follow this structure:

```markdown
## Goal

{One paragraph — what this achieves}

## Context

{Why this matters now. Link to source report if applicable.}

## Code References

{Specific files, modules, APIs in the target repo that this touches}
- `{repo_name}/{path/to/file.ext}` — {what it does}

## Approach

{How to implement. Step-by-step, specific enough for an agent.}

## Chunks

{For L/XL items — ordered chunks that can be committed independently}

1. {Chunk 1 — description}
2. {Chunk 2 — description}

## Acceptance Criteria

- [ ] {Criterion 1}
- [ ] {Criterion 2}

## Negative Constraints

- Do NOT {constraint from out-of-scope or brainstorming}
- See `.pm/out-of-scope/{slug}.md` for related rejections

---
*Spec written by /pm:triage on {DATE}*
```

**Local backend** — write the spec to `planning/specs/{number}-{slug}.md`:

```bash
specs_dir="$primary_repo_root/planning/specs"
mkdir -p "$specs_dir"

slug=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
spec_file="$specs_dir/${number}-${slug}.md"
```

Use the same body structure as the GitHub template above, but wrap it in a spec header (matching `planning/specs/_TEMPLATE.md`): add `# Spec: {title}` plus frontmatter fields (Backlog #, Size, Priority, Created, Status: draft) before the `## Goal` section.

Also update the local item's YAML to reference the spec:

```bash
yq -i ".spec = \"planning/specs/${number}-${slug}.md\"" "$item_file"
```

**Trello backend** — update the card description with the spec content:

```
mcp__trello__update_card_details({
  cardId: $card_id,
  desc:   "{spec content}"     # same structured Markdown body as the GitHub template
})
```

Trello card descriptions support full Markdown. Use the same `## Goal / ## Context / ## Code References / ## Approach / ## Chunks / ## Acceptance Criteria / ## Negative Constraints` structure as the GitHub branch — agents downstream (sprint-dev) read either source identically.

Multi-board: specs always go on the card's home board. Do not duplicate the spec across boards.

#### Step 2d: Checkpoint

After each spec is written, print:

```
Spec complete for: {title}
  Size: {size}  Priority: {priority}
  Spec: {path or issue URL}
  Chunks: {N}

Continue to next item? (yes / stop)
```

- **yes** — proceed to the next item needing a spec
- **stop** — halt speccing. Remaining items will enter Phase 3 without specs (they will likely fail the scorecard, which is fine — the user can resume triage later).

---

## Phase 3: Score

Evaluate each item that survived Phase 1 (both specced and unspecced) against the agent-ready scorecard.

### Dispatch the scorecard evaluator

For each item, read `plugins/pm/agents/scorecard-evaluator.md` and use its content as the system prompt for an Agent tool call. Provide in the user prompt:

- The item's title, description, and spec (if one was written in Phase 2)
- The project's CONTEXT.md content
- The `.pm/out-of-scope/` directory listing
- The list of configured repos from `pulse-config.yaml`

The agent returns a per-criterion PASS/FAIL with explanations and a verdict.

### Agent-Ready Scorecard

```
Agent-Ready Scorecard:
1. [ ] Clear description (what, not how)
2. [ ] Explicit acceptance criteria
3. [ ] Linked code references with target repo
4. [ ] Negative constraints (cross-refs .pm/out-of-scope/)
5. [ ] Bounded scope (single deliverable, one repo)
6. [ ] No open design questions
```

### Present results

For each item, show:

```
--- Scorecard: {title} ---
Score: {X}/6

1. {PASS|FAIL} Clear description        — {explanation}
2. {PASS|FAIL} Acceptance criteria       — {explanation}
3. {PASS|FAIL} Code references           — {explanation}
4. {PASS|FAIL} Negative constraints      — {explanation}
5. {PASS|FAIL} Bounded scope             — {explanation}
6. {PASS|FAIL} No open design questions  — {explanation}

Verdict: {status/ready+owner/ai | status/ready+owner/human | needs-info}
```

### Verdict thresholds

| Score | Verdict | Meaning |
|-------|---------|---------|
| 6/6 | `status/ready` + `owner/ai` | Fully specced, agent can pick up immediately |
| 4-5/6 | `status/ready` + `owner/human` | Minor gaps — human should review before agent work |
| 0-3/6 | `needs-info` (stays as `status/needs-triage`) | Major gaps — not ready for anyone |

### User decision

For items scoring 6/6, recommend `status/ready` + `owner/ai`. For 4-5/6, recommend `status/ready` + `owner/human`. For 0-3/6, recommend `needs-info`.

Ask the user:

```
Accept verdict? (yes / fix / human / info / skip)
```

- **yes** — accept the recommended verdict
- **fix** — fix the failing criteria now. For each FAIL, present the suggested fix from the scorecard evaluator and apply it to the spec inline. After fixing, re-score (loop back through the scorecard for changed criteria only).
- **human** — override to `status/ready` + `owner/human` regardless of score
- **info** — override to `needs-info` (leave as `status/needs-triage` for later)
- **skip** — skip this item, leave unchanged

#### Fixing inline

When the user chooses **fix**, iterate through each failing criterion:

```
Fix {criterion name}?
  Current: {what's there now, or "missing"}
  Suggested: {scorecard evaluator's suggestion}

Apply this fix? (yes / edit / skip)
```

- **yes** — apply the suggested fix to the spec
- **edit** — user provides their own text for this criterion
- **skip** — leave this criterion as-is (it will still FAIL)

After all fixes are applied, update the spec in the backend (same write path as Phase 2 Step 2c) and re-evaluate only the fixed criteria.

---

## Phase 4: Promote

For items the user approved with a verdict of `status/ready` + `owner/ai` or `status/ready` + `owner/human`, apply final labels and update the backlog.

### 4.1 Determine labels

For each promoted item, gather:
- **Status label**: always `status/ready` when promoting (anything else stays as `status/needs-triage` or gets rejected)
- **Owner label**: `owner/ai` for 6/6 verdicts, `owner/human` for 4-5/6 verdicts
- **Size label**: `size/S`, `size/M`, `size/L`, or `size/XL` (from the spec or your estimate)
- **Priority label**: `priority/p0` / `priority/p1` / `priority/p2` / `priority/p3` (set if known; otherwise leave to the user)
- **Target repo label**: `repo/{repo-name}` for multi-repo workspaces

### 4.2 Update backend

**GitHub backend:**

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

#### 4.2a Mirror Status field to GitHub Project (optional)

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

**Local backend:**

```bash
yq -i '.labels -= ["status/needs-triage"] | .labels += ["status/ready", "{owner_label}", "{size_label}", "priority/p{priority}"]' "$item_file"
```

**Trello backend:**

Promotion = move card from `LIST_NEEDS_TRIAGE` to `LIST_READY_FOR_AGENT` on the card's home board. Validate the transition first.

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-transition.sh" \
  "needs_triage" "ready_for_agent" "$trello_statuses_json" \
  || { echo "transition check failed — aborting promote"; continue; }
```

Then the agent executes:

```
mcp__trello__set_active_board({ boardId: $card_board_id })
lists = mcp__trello__get_lists({})
ready_list_id = (find list where name == $LIST_READY_FOR_AGENT).id

mcp__trello__move_card({
  cardId: $card_id,
  listId: ready_list_id
})

# Apply size/priority labels via update_card_details (Trello labels are board-scoped strings):
mcp__trello__update_card_details({
  cardId: $card_id,
  labels: ["{size_label}", "priority/p{priority}"]   # combined with any existing labels — preserve "status/ready" + "{owner_label}" if the board uses status/owner labels too
})
```

### Approval cues (Trello-specific)

The "user confirmation" gate in Phase 1 step "Confirm? (yes / reject / keep / duplicate / skip)" works in two modes for Trello:

1. **Synchronous** — the user is at the keyboard and answers the prompt directly. Same as GitHub/local.
2. **Asynchronous** — the user moved the card themselves (e.g., dragged it from "Needs Triage" to "Ready") between sessions. When the skill loads a card, check its current list. If the card is in `LIST_READY_FOR_AGENT` already, treat it as approved and skip the prompt — proceed to label the card and update planning files.

Additionally, when reading a card's comments via `mcp__trello__get_card_comments`, look for natural-language approval cues from the most recent human comment, in priority order: `"yes"`, `"approve(d)"`, `"lgtm"`, `":+1:"`, `":thumbsup:"`, `"ship it"`, `"go"`, `"promote"`. Treat as confirmation. If a more recent comment from the human says `"hold"`, `"wait"`, `"not yet"`, `"reject"`, the skill must ask for explicit confirmation.

This implements the spec's "card-to-Ready move = approval" pattern (W2c) without losing the explicit-confirm mode for sit-down sessions.

### 4.3 Link to a parent epic (REQUIRED — every promoted item gets exactly one)

**Every item you promote must land under exactly one parent epic — no orphans.** A todo with no epic parent does not group under any epic in the project's "Sprint Plan" / group-by-Parent-issue view, which is the whole point of the board. So this is a required step, not an optional one. Do not promote an item to `status/ready` until it has an epic.

Determine the item's epic, in order of preference:

1. **Explicit reference** in the item body (e.g. "Part of Epic 1 (#236)").
2. **Infer from the open epics.** List them — `gh issue list --label epic --state open --repo "$gh_owner/$gh_repo"` — and match by area (memory work → the memory epic; a specific UI surface → that surface's epic; sync/reliability → the reliability epic; etc.). Per-surface UI work goes under that surface's epic, not a generic one.
3. **Ask** if still ambiguous: "Which epic does this belong under? {short list}". Pick before promoting.

**Creating a new epic (when none fits).** If the area genuinely has no epic yet, create one before linking — don't force the item under an ill-fitting parent. An epic is a **goal container**, so author it accordingly:

- **Labels: `epic` only.** Never give an epic a `status/*` label and never place it in a board status column. An epic carries no workflow status — its progress *is* the native sub-issue progress bar, and its membership *is* the sub-issue tree. (Lifecycle still applies: `/pm:reconcile` closes an epic once all its sub-issues close.)
- **Body = the goal, nothing else.** State the end-state and why it matters, written like a goal prompt you'd hand Claude Code — not a checklist of constituent items (that just drifts from the sub-issue tree, which is the real source of truth for membership). Use this shape:

  **Epic body template:**

  ```markdown
  ## Goal
  {The end-state we're driving toward, in one or two sentences.}

  ## Why
  {Why this matters — what's true once this is done.}
  ```

```bash
gh issue create \
  --title "{epic title}" \
  --body "{Goal/Why body from the template above}" \
  --label "epic" \
  --repo "$gh_owner/$gh_repo"
```

Capture the new epic's number to use as `{epic_number}` below.

**GitHub backend** — create the **native sub-issue relationship**; this is the canonical mechanism that drives epic grouping and the epic progress bar. Follow `references/github-sub-issues.md`, using `{epic_number}` as the parent and `{number}` as the child (GraphQL `addSubIssue`, with the comment-based fallback).

- An issue can have **only one parent**. If the child already has a different parent, `removeSubIssue` from the old parent first, then `addSubIssue` to the correct one — otherwise the add fails with a VALIDATION error.
- If `github.project_sync.enabled` AND the project has a custom **Epic** field, also set it (`gh project item-edit --id {item_id} --field-id {epic_field_id} --project-id {project_id} --text "#{epic_number} {epic_title}"`, or the `projects_write` `update_item_field_value` MCP call) so the native sub-issue tree and the group-by-Epic-field view agree.

**Local backend:**

```bash
yq -i '.parent_epic = {epic_number}' "$item_file"
```

**No-epic escape hatch.** If an item genuinely belongs to no epic (rare — e.g. a standalone strategy/positioning note or a pure competitor-watch item), do NOT leave it silently unparented. Add a `no-epic` label so it's a deliberate, auditable choice rather than an oversight, and `/pm:reconcile` can surface accidental orphans (todos that are neither under an epic nor labelled `no-epic`).

### 4.4 Update planning/todos.md

> When backend == trello, the row's `#{number}` is the card's Trello short id (e.g. `t-AbCdEfGh`); `{spec path or "—"}` is the card's `shortUrl`. Otherwise, the row format is identical.

If the project maintains the markdown backlog (`planning/todos.md` exists), add promoted items to the Ready section.

Read the current `planning/todos.md`. Find the `## Ready` section and the `### Sprint: Unassigned` subsection. Append a row for each promoted item:

```markdown
| #{number} | {title} | {size} | priority/p{priority} | status/ready ({owner_label}) | {spec path or "—"} | {TODAY} | — |
```

For `needs-info` items, do NOT add to Ready — they stay in triage. For items promoted with `owner/human`, add to Ready with status `status/ready` and the `owner/human` label (these still need code work, but a human should review the spec gaps first):

```markdown
| #{number} | {title} | {size} | priority/p{priority} | status/ready (owner/human) | {spec path or "—"} | {TODAY} | {failing criteria} |
```

---

## Phase 5: Summary

After all items are processed, print:

```
PM — Triage Complete
=====================
Items processed:          {total}
Rejected (out-of-scope):  {X}
Duplicates closed:        {Y}
Skipped:                  {Z}
Specced:                  {W}
Promoted to status/ready + owner/ai:    {A}
Promoted to status/ready + owner/human: {B}
Left as needs-info (status/needs-triage): {C}

{If GitHub: "Issues updated in {owner}/{repo}"}
{If local: "Items updated in {items_dir}"}

{If A > 0: "Next: Run /pm:sprint-dev to pick up status/ready + owner/ai items."}
{If B > 0: "{B} item(s) need human review before agent work."}
{If C > 0: "{C} item(s) need more information — re-run /pm:triage after adding details."}
```

---

## Error Handling

- **pulse-config.yaml missing**: Stop — run `/product-pulse:setup` or `/pm:setup`.
- **.pm/config.yml missing**: Stop — run `/pm:setup`.
- **No status/needs-triage items**: Exit cleanly with message. Not an error.
- **CONTEXT.md missing**: Warn, continue without domain context. Recommend running `/pm:setup`.
- **out-of-scope directory missing**: Warn, continue without rejection checking. Create the directory.
- **gh CLI unavailable or unauthenticated**: Stop for GitHub backend — install `gh` and run `gh auth login`.
- **Brainstorming or writing-plans skill unavailable**: Warn the user. Offer to write a minimal spec manually instead of invoking the skill. The triage pipeline should not hard-fail because a superpowers skill is missing.
- **Scorecard evaluator failure**: Fall back to manual scoring — present the 6-point checklist and ask the user to score each criterion.
- **GitHub sub-issue API unavailable**: Fall back to comment-based linking.
- **planning/todos.md missing**: Skip the backlog update step. Warn: `"planning/todos.md not found — skipping backlog row insertion. Run /pm:setup to create the backlog."`.
- **User stops mid-pipeline**: This is expected and fine. Items that haven't been processed remain as `status/needs-triage`. Print a partial summary of what was completed.
- **Item body is empty or malformed**: Flag it to the user during sorting. Recommend reject or keep with a note that it needs a description before speccing.
- **Trello card moved by user mid-skill**: If the skill loaded a card from `LIST_NEEDS_TRIAGE` and the user moved it to another list during the run, the move-to-target call from this skill will fail with "card already in list X". Surface the error, skip the item, and continue. Reconcile will catch up next run.
- **Approval cue ambiguous**: When neither a clear approval cue nor an explicit user response is available, ALWAYS ask. Do not infer.
