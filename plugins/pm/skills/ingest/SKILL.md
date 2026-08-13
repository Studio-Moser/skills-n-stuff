---
name: ingest
description: >-
  Read research reports from product-pulse (daily, weekly, deep-dive) and
  create status/needs-triage items in the configured issue tracker. Diffs against
  existing issues, current codebase, and out-of-scope rejections to avoid
  duplicates. Uses ingestion watermarks to process only new reports.
  Trigger: "ingest research", "process reports", "import findings",
  or /pm:ingest. Do NOT use for classifying/speccing/scoring items
  (that's /pm:triage) or syncing completed work (that's /pm:reconcile) —
  ingest only turns research reports into status/needs-triage items.
effort: low
allowed-tools: "Bash Read Write Edit Agent"
---

# PM — Ingest

You are the research-to-backlog bridge. Your job is to read product-pulse reports, extract actionable items, deduplicate them against existing issues and the codebase, and create `status/needs-triage` items in the configured issue tracker.

You are NOT the triage agent — that's `/pm:triage`. You discover and file; others classify and prioritize.

---

## Ground Rules

- **Ingest creates `status/needs-triage` items ONLY.** Never `status/ready`. Every item must pass through triage before execution. Stale AI recommendations do not auto-execute.
- **One item per finding.** Do not combine multiple report items into a single issue.
- **Source attribution always.** Every created item links back to the report and section it came from.
- **Error tolerant.** If one report fails to parse, log it and continue with others.
- **No fabrication.** Only extract items that exist in the reports. Do not editorialize or invent action items.
- **Idempotent.** Running ingest twice with the same watermark produces zero new items.

---

## Phase 0: Discover Config

### 0.0 Pre-resolved Configuration

All config values are pre-resolved at skill load time. If you see `ERROR:` in the output below, stop and tell the user.

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/discover-config.sh`
```

Parse the key=value pairs above. The `research_dirs` value is colon-separated (split on `:`). The `repos_json` value is a JSON array of repo objects.

If `state_file` does not exist yet, create it:

```bash
if [ ! -f "$state_file" ]; then
  cat > "$state_file" << 'EOF'
# Ingestion watermarks — updated by /pm:ingest
last_ingested: {}
last_reconcile: null
EOF
fi
```

The scan watermark is a dedicated file touched ONLY by ingest — `state_file`'s mtime cannot serve, because `/pm:reconcile` also writes `state_file`, and every reconcile would silently mark all reports since the last ingest as already processed:

```bash
watermark_file="$(dirname "$state_file")/ingest-watermark"
if [ ! -f "$watermark_file" ]; then
  if [ -f "$state_file" ]; then
    touch -r "$state_file" "$watermark_file"   # migration: inherit the old shared watermark once
  else
    touch -t 197001010000 "$watermark_file"    # true first run: every report is new
  fi
fi
```

The watermark is machine-local state (its only meaning is its mtime), so keep it out of git — a fresh checkout would reset it:

```bash
gitignore_file="$(dirname "$state_file")/.gitignore"
grep -qs '^ingest-watermark$' "$gitignore_file" || echo 'ingest-watermark' >> "$gitignore_file"
```

To deliberately re-ingest a window (e.g. after reports were missed), back-date it: `touch -t YYYYMMDDhhmm "$watermark_file"` — Phase 3's dedup absorbs anything already filed.

---

### 0.1 Pull Latest

Iterate repos from `pulse-config.yaml`, pull the default branch for each:

```bash
for repo_path in $(yq '.repos[].path' "$config_path"); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  echo "=== Pulling $abs ==="
  cd "$abs" && git checkout "$default_branch" && git pull origin "$default_branch" || echo "pull failed for $abs"
done
```

If any pull fails, note it and continue — stale data is better than a full stop.

---

## Phase 1: Scan for New Reports

For each directory in `research_dirs`, find report files newer than the ingest watermark file.

```bash
new_reports=()
for rd in "${research_dirs[@]}"; do
  [ ! -d "$rd" ] && echo "Warning: $rd does not exist, skipping." && continue

  while IFS= read -r f; do
    [ -n "$f" ] && new_reports+=("$f")
  done < <(
    find "$rd" -name "*-daily-research.md" -newer "$watermark_file" 2>/dev/null
    find "$rd" -name "*-strategy-brief.md" -newer "$watermark_file" 2>/dev/null
    find "$rd" -name "*-recommendations.md" -newer "$watermark_file" 2>/dev/null
    find "$rd/deep-dives" -name "*.md" -newer "$watermark_file" 2>/dev/null
  )
done
```

Caveat to keep in mind (not a blocker): mtimes come from git checkout/pull time, not authorship, so a fresh clone can over-report old files as new — Phase 3's dedup filters those out. Under-reporting only happens if something other than ingest touches `$watermark_file`; nothing should.

If no new reports are found, print `"No new reports since last ingestion."` and exit cleanly.

Otherwise print `"Found ${#new_reports[@]} new report(s) to process."` and continue.

---

## Phase 2: Extract Action Items

For each new report, determine its type from the filename and dispatch the **ingestion-analyst** sub-agent.

### Classify report type

| Filename pattern | Report type |
|-----------------|-------------|
| `*-daily-research.md` | `daily-research` |
| `*-strategy-brief.md` | `weekly-brief` |
| `*-recommendations.md` | `weekly-recommendations` |
| `deep-dives/*.md` | `deep-dive` |

### Dispatch sub-agents

**CRITICAL**: Dispatch all report analysts in a single message as parallel Agent tool calls.

For each report, read `plugins/pm/agents/ingestion-analyst.md` and use its content as the system prompt for an Agent tool call. Report extraction is clear-spec bulk work: pass `model` explicitly, set to `routing.bulk` from the rubric (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`). Omitting `model` inherits the session model and burns a frontier tier on mechanical extraction. Provide in the user prompt:

- The full text of the report (read the file)
- The report type (from classification above)
- The product context (condensed from `{research_dir}/research-context.md` if it exists, otherwise from `pulse-config.yaml`)

Each sub-agent returns a list of items with: **title**, **description**, **source_report**, **source_section**, **suggested_size** (S/M/L/XL), **suggested_priority** (P0-P3), **confidence** (High/Medium/Low), **target_repo**.

Collect all extracted items into a single list. Track per-report counts for the summary. If a sub-agent fails, log the error and continue with remaining reports.

---

## Phase 3: Dedup and Filter

For each extracted item, run three checks. An item is skipped if ANY check matches.

### 3.1 Check against existing open issues

**GitHub backend:**

```bash
existing_issues=$(gh issue list \
  --state open \
  --json title,body,labels \
  --limit 200 \
  --repo "{owner}/{repo}")
# Dedup against any open issue still in the pipeline (status/needs-triage,
# status/ready, status/in-progress, status/in-review). Filter client-side
# from the labels field if needed.
```

**Local backend:**

```bash
for item_file in "$primary_repo_root/.pm/items/"*.yml; do
  [ -f "$item_file" ] || continue
  title="$(yq '.title' "$item_file")"
  body="$(yq '.body' "$item_file")"
done
```

**Trello backend:**

Iterate boards. For each board, set active and read cards from each non-rejected list (`needs_triage`, `ready_for_agent`, `in_progress`, `review`, `needs_changes`, `blocked`). The `done` list is excluded — done items are valid dedup-misses (they may be reborn).

```bash
pm="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/pm/*/ 2>/dev/null | sort -V | tail -1)}"; pm="${pm%/}"
echo "$trello_boards_json" | jq -c '.[]' | while read -r board_json; do
  eval "$("$pm/scripts/for-each-board.sh" "[$board_json]")"
  # MCP tool call (the agent executes this — shell can't call MCP):
  # mcp__trello__set_active_board({ boardId: $BOARD_ID })
  # all_lists = mcp__trello__get_lists({})
  # For each required list (except done), find its id and:
  #   cards = mcp__trello__get_cards_by_list_id({ listId: $LIST_ID })
  # Collect (title, description, board_id, card_id) into existing_cards.
done
```

Compare each extracted ingestion item against `existing_cards` using the same > 80% significant-word similarity rule. Mark duplicates: `"duplicate of existing card on board {board_name}: {card_title}"`.

An item is a **duplicate** if its title or description shares > 80% significant-word overlap with an existing issue. Significant words are 3+ characters, excluding stop words ("the", "a", "and", "for", "to", "in", "of", "is"). Similarity = `(shared words) / (min(words_in_A, words_in_B))`. Mark duplicates: `"duplicate of existing issue: {matching title}"`.

### 3.2 Check against out-of-scope rejections

```bash
oos_dir="$primary_repo_root/$(yq '.out_of_scope_dir // ".pm/out-of-scope"' "$pm_config")"
```

Read each `.md` file in the out-of-scope directory (skip `README.md`). An item is **out-of-scope** if its title or description shares > 60% significant-word overlap with a rejection's feature name or decision text. Lower threshold than dedup (60% vs 80%) to aggressively catch previously-rejected concepts. Mark: `"matches out-of-scope rejection: {slug}"`.

### 3.3 Check against current codebase

For items suggesting a specific implementation, search configured repos:

```bash
for repo_path in $(yq '.repos[].path' "$config_path"); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  grep -r --include="*.swift" --include="*.ts" --include="*.py" --include="*.js" \
    --include="*.rb" --include="*.go" --include="*.rs" --include="*.java" \
    -l "$search_term" "$abs/Sources" "$abs/src" "$abs/lib" "$abs/app" 2>/dev/null
done
```

An item is **already implemented** if 2+ key terms from the title appear together in the same source file AND the surrounding context confirms the feature. Do not skip items simply because a keyword appears — the context must match the item's intent. Mark: `"appears already implemented in {file path}"`.

### Filter summary

Partition items into: **survivors** (passed all checks), **duplicates**, **out_of_scope**, **already_implemented**.

---

## Phase 4: Create Items

For each surviving item, create a `status/needs-triage` item in the configured backend.

### Issue body template

Use this template for the body of every created item:

```markdown
## Description

{description from the extracted item}

## Source

- **Report**: `{source_report}`
- **Section**: {source_section}
- **Confidence**: {confidence}
- **Suggested priority**: {suggested_priority}
- **Target repo**: {target_repo}

## Context

This item was automatically extracted from a product-pulse research report
by `/pm:ingest`. It requires triage before any work begins.

Run `/pm:triage` to classify, size, and prioritize this item.

---
*Ingested on {DATE} from `{source_report}`*
```

### GitHub backend

For each surviving item:

```bash
gh issue create \
  --title "{title}" \
  --body "{body from template above}" \
  --label "status/needs-triage,size/{suggested_size}" \
  --repo "{owner}/{repo}"
```

If `target_repo` is known and differs from the primary repo, add a label for the target:

```bash
gh issue create \
  --title "{title}" \
  --body "{body from template above}" \
  --label "status/needs-triage,size/{suggested_size},repo/{target_repo_name}" \
  --repo "{owner}/{repo}"
```

Capture the created issue number and URL for the summary.

### Local backend

```bash
items_dir="$primary_repo_root/$(yq '.local.items_dir // ".pm/items"' "$pm_config")"
mkdir -p "$items_dir"
last_num=$(ls "$items_dir" | grep -oE '^[0-9]+' | sort -n | tail -1)
next_num=$(( ${last_num:-0} + 1 ))

slug=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
item_file="$items_dir/${next_num}-${slug}.yml"
```

Write the YAML item file:

```yaml
# Item #{next_num}: {title}
# Created by /pm:ingest on {DATE}

title: "{title}"
body: |
  ## Description

  {description}

  ## Source

  - **Report**: `{source_report}`
  - **Section**: {source_section}
  - **Confidence**: {confidence}
  - **Suggested priority**: {suggested_priority}
  - **Target repo**: {target_repo}

  ## Context

  This item was automatically extracted from a product-pulse research report
  by `/pm:ingest`. It requires triage before any work begins.
labels:
  - status/needs-triage
  - "size/{suggested_size}"
source:
  report: "{source_report}"
  section: "{source_section}"
  confidence: "{confidence}"
  suggested_priority: "{suggested_priority}"
  target_repo: "{target_repo}"
created_at: "{ISO 8601 timestamp}"
```

Increment `next_num` for the next item.

### Trello backend

Cards are created on the **first** configured board's `needs_triage` list. Multi-board fan-out (creating one card per relevant board) is not in scope for ingest — triage handles routing to the right board.

For each surviving item:

```bash
pm="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/pm/*/ 2>/dev/null | sort -V | tail -1)}"; pm="${pm%/}"
# Resolve the first board and its needs_triage list id once per skill run.
first_board_json="$(echo "$trello_boards_json" | jq -c '.[0]')"
eval "$("$pm/scripts/for-each-board.sh" "[$first_board_json]")"
```

Then call (the agent executes these MCP tools — see `plugins/pm/scripts/trello-ops.md`):

```
mcp__trello__set_active_board({ boardId: $BOARD_ID })
lists = mcp__trello__get_lists({})
list_id_needs_triage = (find list where name == $LIST_NEEDS_TRIAGE).id

card = mcp__trello__add_card_to_list({
  listId: list_id_needs_triage,
  name:   "{title}",
  desc:   "{body from template above}",
  labels: ["status/needs-triage", "size/{suggested_size}"]
})

# Source attribution comment (separate from desc so future edits don't lose it):
mcp__trello__add_comment({
  cardId: card.id,
  text: "Ingested by /pm:ingest from `{source_report}` on {DATE}. Confidence: {confidence}. Suggested priority: {suggested_priority}."
})
```

Capture `card.id` and `card.shortUrl` for the summary. The card title is the item title; the description follows the same Markdown template as GitHub.

---

## Phase 5: Update Watermarks

After all items are created (or skipped), update the state file to record the ingestion timestamp.

```bash
touch "$watermark_file"  # THE scan watermark (used by find -newer). Do NOT rely on $state_file's mtime — reconcile writes that file too.
```

Also write structured watermark data for auditability:

```yaml
# Ingestion watermarks — updated by /pm:ingest
last_ingested:
  timestamp: "{ISO 8601 timestamp of this run}"
  reports_processed:
    - "{relative path to report 1}"
    - "{relative path to report 2}"
  items_created: {count}
last_reconcile: {preserve existing value or null}
```

Read the existing `last_reconcile` value before overwriting so it is preserved.

---

## Phase 6: Summary

Print:

```
PM — Ingest Complete
=====================
Reports scanned:       {X}
Items extracted:       {Y}
Duplicates skipped:    {Z} (matched existing issues)
Out-of-scope skipped:  {W} (matched rejection KB)
Already implemented:   {V} (found in codebase)
New items created:     {U}

Backend: {github or local}
{If GitHub: "Issues created in {owner}/{repo}"}
{If local: "Items written to {items_dir}"}
{If Trello: "Cards created on board {first_board_name} ({first_board_id}) in list \"{LIST_NEEDS_TRIAGE}\""}

Next: Run /pm:triage to classify and prioritize the new items.
```

If zero items were created, note: `"All extracted items were duplicates, out-of-scope, or already implemented. Watermarks updated."`

---

## Error Handling

- **pulse-config.yaml missing**: Stop — run `/product-pulse:setup` or `/pm:setup`.
- **.pm/config.yml missing**: Stop — run `/pm:setup`.
- **Research directory missing**: Warn, skip that directory, continue with others.
- **Report unreadable/malformed**: Log filename and error, skip, continue. Note in summary.
- **gh CLI unavailable or unauthenticated**: Stop — install `gh` and run `gh auth login`.
- **Sub-agent failure**: Log and continue. Partial results are valid.
- **No research_dirs configured**: Fall back to `research_dir` from `pulse-config.yaml`.
- **State file missing**: Create with empty watermarks (first-run behavior).
- **Watermark file missing**: Initialize from `state_file`'s mtime if it exists (migration), else epoch (first run). Never fall back to using `state_file`'s mtime directly for the scan.
- **Items directory missing (local)**: Create automatically.
- **Git pull fails**: Note and continue. Watermarks catch duplicates on next run.
- **Trello MCP tool call failure (rate limit, auth)**: Stop the run. Print the error verbatim. Resume after fixing credentials (`/pm:setup` re-validates) or after the rate limit window passes.
- **`trello_boards_json=[]`**: Stop — config has no boards. Run `/pm:setup`.
