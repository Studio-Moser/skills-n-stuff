# Triage — Local Backend Detail

Backend-specific procedure blocks for `/pm:triage`, split out of `triage/SKILL.md` so GitHub/Trello users don't have to read past them. Only relevant when `backend == local`; skip this whole file otherwise. Variables (`$items_dir`, `$item_file`, `{number}`, etc.) are the same ones resolved earlier in the SKILL.md flow — read this file in-session and continue where you left off.

## Phase 0.2: Pull Needs-Triage Items — Local

```bash
items_dir="$primary_repo_root/$(yq '.local.items_dir // ".pm/items"' "$pm_config")"
triage_items=()
for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  labels="$(yq '.labels[]' "$item_file" 2>/dev/null)"
  echo "$labels" | grep -q "status/needs-triage" && triage_items+=("$item_file")
done
```

## Phase 0.3: Load Existing Open Items (dedup pool) — Local

Same loop over `$items_dir/*.yml` as above, skipping files whose labels include `status/needs-triage`.

## Phase 1: Process rejections — Local

Write the same `oos_file` markdown (this is backend-agnostic; see SKILL.md), then update the item's YAML file — replace `status/needs-triage` in labels with `rejected`, add `closed_at` timestamp:

```bash
yq -i '.labels -= ["status/needs-triage"] | .labels += ["rejected"] | .closed_at = "{ISO 8601 timestamp}"' "$item_file"
```

## Phase 1: Process duplicates — Local

```bash
yq -i '.labels -= ["status/needs-triage"] | .labels += ["duplicate"] | .duplicate_of = {duplicate_number} | .closed_at = "{ISO 8601 timestamp}"' "$item_file"
```

## Phase 2, Step 2b.1: Create XL epic and children — Local

Run only after the user approves the displayed XL split. The current item's numeric
prefix is the epic identifier. Convert that item to an epic-only goal container:

```bash
epic_number=$(basename "$item_file" | sed -E 's/^([0-9]+)-.*/\1/')
yq -i '.labels = ["epic"] | .body = "{confirmed Goal/Why body}" | del(.spec)' "$item_file"

last_num=$(ls "$items_dir" | grep -oE '^[0-9]+' | sort -n | tail -1)
next_num=$(( ${last_num:-0} + 1 ))
xl_child_ids=()
```

For each confirmed child, in blocker-first order, derive `child_file` from `next_num`
using the Phase 2 Step 2c slug rule:

```bash
slug=$(echo "{child title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
child_file="$items_dir/${next_num}-${slug}.yml"
```

Write this existing local-item shape; `blockers` contains earlier child numbers from
`xl_child_ids`, or an empty list:

```yaml
title: "{child title}"
body: |
  {child summary}
labels:
  - status/needs-triage
  - "size/{child_size}"
parent_epic: {epic_number}
blockers: [{earlier child numbers}]
created_at: "{ISO 8601 timestamp}"
```

After writing each `$child_file`, return its identifier to the shared flow and advance
the counter:

```bash
xl_child_ids+=("$next_num")
# xl-phase3-selection:start
phase3_items=()
for candidate in "${triage_items[@]}"; do
  [ "$candidate" = "$item_file" ] || phase3_items+=("$candidate")
done
phase3_items+=("$child_file")
triage_items=("${phase3_items[@]}")
# xl-phase3-selection:end
next_num=$((next_num + 1))
```

This replaces the original XL parent in `triage_items` with its children. The resulting
array is the Phase 3 carry-forward collection; the epic item is absent.

## Phase 2, Step 2c: Write spec to backend — Local

Write the spec to `planning/specs/{number}-{slug}.md`:

```bash
specs_dir="$primary_repo_root/planning/specs"
mkdir -p "$specs_dir"

slug=$(echo "{title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)
spec_file="$specs_dir/${number}-${slug}.md"
```

Use the canonical spec content from `references/triage-spec-flow.md` (§ Step 2c), but
wrap it in a spec header (matching `planning/specs/_TEMPLATE.md`): add `# Spec: {title}`
plus frontmatter fields (Backlog #, Size, Priority, Created, Status: draft) before the
`## Goal` section.

Also update the local item's YAML to reference the spec:

```bash
yq -i ".spec = \"planning/specs/${number}-${slug}.md\"" "$item_file"
```

## Phase 4.2: Update backend (promote) — Local

```bash
yq -i '.labels -= ["status/needs-triage"] | .labels += ["status/ready", "{owner_label}", "{size_label}", "priority/p{priority}"]' "$item_file"
```

## Phase 4.3: Link to a parent epic — Local

Listing open epics (for the "infer from open epics" step) — same iteration pattern as Phase 0.2, filtering for the `epic` label instead:

```bash
for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  yq '.labels[]' "$item_file" 2>/dev/null | grep -q "^epic$" && echo "$item_file"
done
```

Linking the promoted item to its epic:

```bash
yq -i '.parent_epic = {epic_number}' "$item_file"
```

There is no local-backend equivalent of GitHub's native sub-issue relationship or progress bar — `parent_epic` on the child item is the sole source of epic membership for this backend.
