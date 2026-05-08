---
name: triage
description: >-
  Process needs-triage items through the full pipeline: sort (reject/dedup),
  spec (brainstorming + writing-plans for M/L/XL items), score against the
  agent-ready checklist, and promote to ready-for-agent or reject to
  out-of-scope. Interactive — you confirm every decision.
  Trigger: "triage", "process backlog", "review incoming items", "spec items",
  or /pm:triage.
---

# PM — Triage

You are the triage pipeline. Your job is to take raw `needs-triage` items and walk each one through a decision funnel: sort (keep, reject, or dedup), spec (brainstorm and write implementation plans for non-trivial items), score (evaluate agent-readiness), and promote (apply final labels and update the backlog).

You are NOT the ingestion agent — that's `/pm:ingest`. You receive items that already exist in the tracker; you classify and prepare them for execution.

---

## Ground Rules

- **Interactive.** You present recommendations; the user confirms every decision. Never reject, promote, or modify an item without explicit user approval.
- **One item at a time for speccing.** Phase 2 (Spec) is the most time-intensive phase. Process one item through brainstorming and spec writing before asking the user if they want to continue to the next.
- **Batch-friendly for sorting and scoring.** Phases 1 and 3 can present items in quick succession since decisions are lightweight.
- **Idempotent.** Running triage on an already-triaged item (no `needs-triage` label) is a no-op. Never re-process promoted items.
- **No fabrication.** Size, priority, and recommendations are based on the item's content, domain context, and out-of-scope history. Do not invent requirements.
- **Error tolerant.** If one item fails to process, log it and continue with others.

---

## Phase 0: Discover Config and Load Items

### 0.0 Discover Configuration

**Shared config (pulse-config.yaml):**

Walk up from cwd, checking each directory for `pulse-config.yaml` directly and in common research-dir subdirs (`research/`, `Research/`, `docs/research/`). The first match wins; that file's parent directory is the **research directory** (`{research_dir}`).

```bash
config_path=""
research_dir=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  for sub in "" "research/" "Research/" "docs/research/"; do
    candidate="$dir/${sub}pulse-config.yaml"
    if [ -f "$candidate" ]; then
      config_path="$candidate"
      research_dir="$(cd "$(dirname "$candidate")" && pwd)"
      break 2
    fi
  done
  dir="$(dirname "$dir")"
done

if [ -z "$config_path" ]; then
  echo "No pulse-config.yaml found. Run /product-pulse:setup or /pm:setup first." >&2
  exit 1
fi

primary_repo_root="$(cd "$research_dir" && git rev-parse --show-toplevel)"
default_branch="$(yq '.default_branch // "main"' "$config_path")"
project_id="$(yq '.project_id' "$config_path")"
memory_connector="$(yq '.memory.connector // "shelby"' "$config_path")"
```

**PM config (.pm/config.yml):**

```bash
pm_config="$primary_repo_root/.pm/config.yml"
if [ ! -f "$pm_config" ]; then
  echo "No .pm/config.yml found. Run /pm:setup first." >&2
  exit 1
fi

backend="$(yq '.backend // "github"' "$pm_config")"
```

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
  --label "needs-triage" \
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
  echo "$labels" | grep -q "needs-triage" && triage_items+=("$item_file")
done
```

If zero items are found, print `"No needs-triage items found. Nothing to do."` and exit cleanly.

Otherwise print: `"Found {N} needs-triage item(s). Starting triage pipeline."`

### 0.3 Load Existing Open Items (for dedup)

Also fetch all open items WITHOUT `needs-triage` — these are the dedup targets for Phase 1.

**GitHub:** Same `gh issue list` call but without `--label` filter, piped through `jq` to exclude `needs-triage` items.

**Local:** Same loop over `$items_dir/*.yml`, skipping files whose labels include `needs-triage`.

---

## Phase 1: Sort

Present each `needs-triage` item to the user one at a time with your recommendation.

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
- **skip** — skip this item entirely, leave as `needs-triage`

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
  --remove-label "needs-triage" \
  --repo "$gh_owner/$gh_repo"
```

**Local backend:**

Update the item's YAML file — replace `needs-triage` in labels with `rejected`, add `closed_at` timestamp:

```bash
yq -i '.labels -= ["needs-triage"] | .labels += ["rejected"] | .closed_at = "{ISO 8601 timestamp}"' "$item_file"
```

### Process duplicates

When an item is marked as a duplicate:

**GitHub backend:**

```bash
gh issue close {number} \
  --comment "Duplicate of #{duplicate_number}. Closing." \
  --repo "$gh_owner/$gh_repo"

gh issue edit {number} \
  --remove-label "needs-triage" \
  --add-label "duplicate" \
  --repo "$gh_owner/$gh_repo"
```

**Local backend:**

```bash
yq -i '.labels -= ["needs-triage"] | .labels += ["duplicate"] | .duplicate_of = {duplicate_number} | .closed_at = "{ISO 8601 timestamp}"' "$item_file"
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

Invoke the brainstorming skill with the item as the problem statement, informed by domain context and out-of-scope constraints:

```
Skill({ skill: "superpowers:brainstorming" })
```

Provide the brainstorming skill with:
- **Problem statement**: the item's title and description
- **Domain context**: relevant terms from CONTEXT.md
- **Constraints**: relevant out-of-scope entries (what NOT to consider)
- **Project repos**: list of repos from `pulse-config.yaml` with paths

The brainstorming skill will explore the design space and produce a recommended approach.

#### Step 2b: Write implementation plan

After brainstorming produces a design direction, invoke the writing-plans skill to produce a full implementation spec:

```
Skill({ skill: "superpowers:writing-plans" })
```

The writing-plans skill receives the brainstorming output and produces a structured spec with: Goal, Context, Code References, Approach, Chunks, and Acceptance Criteria.

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

For each item, dispatch the **scorecard-evaluator** agent (`plugins/pm/agents/scorecard-evaluator.md`) with:

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

Verdict: {ready-for-agent | ready-for-human | needs-info}
```

### Verdict thresholds

| Score | Verdict | Meaning |
|-------|---------|---------|
| 6/6 | `ready-for-agent` | Fully specced, agent can pick up immediately |
| 4-5/6 | `ready-for-human` | Minor gaps — human should review before agent work |
| 0-3/6 | `needs-info` | Major gaps — not ready for anyone |

### User decision

For items scoring 6/6, recommend `ready-for-agent`. For 4-5/6, recommend `ready-for-human`. For 0-3/6, recommend `needs-info`.

Ask the user:

```
Accept verdict? (yes / fix / human / info / skip)
```

- **yes** — accept the recommended verdict
- **fix** — fix the failing criteria now. For each FAIL, present the suggested fix from the scorecard evaluator and apply it to the spec inline. After fixing, re-score (loop back through the scorecard for changed criteria only).
- **human** — override to `ready-for-human` regardless of score
- **info** — override to `needs-info` (leave as `needs-triage` for later)
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

For items the user approved with a verdict of `ready-for-agent` or `ready-for-human`, apply final labels and update the backlog.

### 4.1 Determine labels

For each promoted item, gather:
- **Status label**: `ready-for-agent` or `ready-for-human`
- **Size label**: `size/S`, `size/M`, `size/L`, or `size/XL` (from the spec or your estimate)
- **Priority label**: if the project uses priority labels (check if `P0`/`P1`/`P2`/`P3` labels exist)
- **Target repo label**: `repo/{repo-name}` for multi-repo workspaces

### 4.2 Update backend

**GitHub backend:**

```bash
# Combine all labels into one edit call
gh issue edit {number} \
  --remove-label "needs-triage" \
  --add-label "{status_label},{size_label}" \
  --repo "$gh_owner/$gh_repo"

# Add priority and target-repo labels if applicable
gh issue edit {number} --add-label "P{priority}" --repo "$gh_owner/$gh_repo"
gh issue edit {number} --add-label "repo/{target_repo_name}" --repo "$gh_owner/$gh_repo"
```

**Local backend:**

```bash
yq -i '.labels -= ["needs-triage"] | .labels += ["{status_label}", "{size_label}", "P{priority}"]' "$item_file"
```

### 4.3 Link to parent epic (if applicable)

If the item references a parent epic (an issue with the `epic` label), create a sub-issue relationship.

**GitHub backend** — use the GitHub sub-issues API:

```bash
parent_id=$(gh issue view {epic_number} --json id --jq '.id' --repo "$gh_owner/$gh_repo")
child_id=$(gh issue view {number} --json id --jq '.id' --repo "$gh_owner/$gh_repo")

gh api graphql -f query='
  mutation {
    addSubIssue(input: {
      issueId: "'"$parent_id"'"
      subIssueId: "'"$child_id"'"
    }) {
      issue { id }
      subIssue { id }
    }
  }
'
```

If the GraphQL mutation fails (sub-issues API may not be available for all plans), fall back to adding a comment:

```bash
gh issue comment {number} \
  --body "Part of epic #{epic_number}" \
  --repo "$gh_owner/$gh_repo"
```

**Local backend:**

```bash
yq -i '.parent_epic = {epic_number}' "$item_file"
```

### 4.4 Update planning/todos.md

If the project maintains the markdown backlog (`planning/todos.md` exists), add promoted items to the Ready section.

Read the current `planning/todos.md`. Find the `## Ready` section and the `### Sprint: Unassigned` subsection. Append a row for each promoted item:

```markdown
| #{number} | {title} | {size} | P{priority} | {status_label} | {spec path or "—"} | {TODAY} | — |
```

For `needs-info` items, do NOT add to Ready — they stay in triage. For `ready-for-human` items, add to the `## Manual` section instead:

```markdown
| #{number} | {title} | — | {failing scorecard criteria, comma-separated} | {TODAY} |
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
Promoted to ready-for-agent:  {A}
Promoted to ready-for-human:  {B}
Left as needs-info:           {C}

{If GitHub: "Issues updated in {owner}/{repo}"}
{If local: "Items updated in {items_dir}"}

{If A > 0: "Next: Run /pm:sprint-dev to pick up ready-for-agent items."}
{If B > 0: "{B} item(s) need human review before agent work."}
{If C > 0: "{C} item(s) need more information — re-run /pm:triage after adding details."}
```

---

## Error Handling

- **pulse-config.yaml missing**: Stop — run `/product-pulse:setup` or `/pm:setup`.
- **.pm/config.yml missing**: Stop — run `/pm:setup`.
- **No needs-triage items**: Exit cleanly with message. Not an error.
- **CONTEXT.md missing**: Warn, continue without domain context. Recommend running `/pm:setup`.
- **out-of-scope directory missing**: Warn, continue without rejection checking. Create the directory.
- **gh CLI unavailable or unauthenticated**: Stop for GitHub backend — install `gh` and run `gh auth login`.
- **Brainstorming or writing-plans skill unavailable**: Warn the user. Offer to write a minimal spec manually instead of invoking the skill. The triage pipeline should not hard-fail because a superpowers skill is missing.
- **Scorecard evaluator failure**: Fall back to manual scoring — present the 6-point checklist and ask the user to score each criterion.
- **GitHub sub-issue API unavailable**: Fall back to comment-based linking.
- **planning/todos.md missing**: Skip the backlog update step. Warn: `"planning/todos.md not found — skipping backlog row insertion. Run /pm:setup to create the backlog."`.
- **User stops mid-pipeline**: This is expected and fine. Items that haven't been processed remain as `needs-triage`. Print a partial summary of what was completed.
- **Item body is empty or malformed**: Flag it to the user during sorting. Recommend reject or keep with a note that it needs a description before speccing.
