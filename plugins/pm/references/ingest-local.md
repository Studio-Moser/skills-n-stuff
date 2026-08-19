# Local Backend Procedures for /pm:ingest

Load this file only when the configured ingest backend is `local`. The main skill
owns extraction, shared filtering, the candidate body, and watermarks.

## Phase 3: Collect Existing Open Work

Resolve `local.items_dir`, defaulting to `.pm/items`, and read every YAML item that
is not terminal:

```bash
items_dir="$primary_repo_root/$(yq '.local.items_dir // ".pm/items"' "$pm_config")"
for item_file in "$items_dir"/*.yml; do
  [ -f "$item_file" ] || continue
  title="$(yq '.title' "$item_file")"
  body="$(yq '.body' "$item_file")"
done
```

Return each title and body to the shared similarity check in ingest Phase 3.

## Phase 4: Create the Candidate

Create the items directory if necessary. Allocate the next numeric identifier and
derive a lowercase slug from the neutral title:

```bash
mkdir -p "$items_dir"
last_num="$(ls "$items_dir" | grep -oE '^[0-9]+' | sort -n | tail -1)"
next_num=$(( ${last_num:-0} + 1 ))
slug="$(echo "{candidate title}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//' | cut -c1-60)"
item_file="$items_dir/${next_num}-${slug}.yml"
```

Write one YAML record:

```yaml
title: "{candidate title}"
body: |
  {candidate body, indented}
labels:
  - status/needs-triage
candidate:
  evidence: "{evidence}"
  proposed_outcome: "{proposed outcome}"
  rationale: "{rationale}"
  source:
    report: "{source.report}"
    section: "{source.section}"
  confidence: "{confidence}"
  target_repo: "{target repo}"
created_at: "{ISO 8601 timestamp}"
```

Do not write size or priority. Increment `next_num` for each later survivor.
Capture `item_file`. In the final summary, report `Items written to {items_dir}`.

## Errors

Create a missing items directory automatically. On an unreadable or unwritable
item file, print the path and error and stop without switching backends.
