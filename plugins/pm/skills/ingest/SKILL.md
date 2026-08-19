---
name: ingest
description: >-
  Use when new Product Pulse daily, weekly, or deep-dive reports need importing into
  the configured issue tracker. Do not use to triage existing candidates or reconcile
  completed work.
effort: low
allowed-tools: "Bash Read Write Edit Agent"
---

# PM — Ingest

Turn new Product Pulse findings into candidate backlog items. Preserve what the
source established separately from what it recommends. Triage decides what to
build, its size, and its priority.

## Ground Rules

- Create `status/needs-triage` items only. Never assign ready status, size, or priority.
- Treat every proposed outcome as a proposal, not a commitment.
- Keep one source finding per item and preserve its report and section.
- Do not fabricate, combine, or strengthen source claims.
- Continue past an unreadable report or failed analyst and report the failure.
- A repeated run with the same watermark creates no duplicate items.

## Phase 0: Discover Config and Select the Backend

All config values are pre-resolved at skill load time. If the output below
contains `ERROR:`, stop and tell the user.

```
!`${CLAUDE_PLUGIN_ROOT}/scripts/discover-config.sh`
```

Parse the key/value pairs. Split the colon-separated `research_dirs` value and
parse `repos_json` as an array.

Read `backend`, then load exactly one backend procedure:
`references/ingest-${backend}.md`. Do not load any other ingest backend
reference. Keep it available for the existing-item read in Phase 3 and candidate
creation in Phase 4.

If `state_file` does not exist, create it:

```yaml
# Ingestion watermarks — updated by /pm:ingest
last_ingested: {}
last_reconcile: null
```

Use a dedicated scan watermark because reconcile also writes `state_file`:

```bash
watermark_file="$(dirname "$state_file")/ingest-watermark"
if [ ! -f "$watermark_file" ]; then
  if [ -f "$state_file" ]; then
    touch -r "$state_file" "$watermark_file"
  else
    touch -t 197001010000 "$watermark_file"
  fi
fi

gitignore_file="$(dirname "$state_file")/.gitignore"
grep -qs '^ingest-watermark$' "$gitignore_file" || echo 'ingest-watermark' >> "$gitignore_file"
```

The migration inherits the old state-file time once. A true first run uses the
epoch. To replay a window, back-date `watermark_file`; dedup handles items that
were already filed.

Pull each configured repo's default branch. Note a failure and continue:

```bash
for repo_path in $(yq '.repos[].path' "$config_path"); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  echo "=== Pulling $abs ==="
  cd "$abs" && git checkout "$default_branch" && git pull origin "$default_branch" || echo "pull failed for $abs"
done
```

## Phase 1: Scan for New Reports

Find supported reports newer than the ingest watermark:

```bash
new_reports=()
for rd in "${research_dirs[@]}"; do
  [ ! -d "$rd" ] && echo "Warning: $rd does not exist, skipping." && continue

  while IFS= read -r report_file; do
    [ -n "$report_file" ] && new_reports+=("$report_file")
  done < <(
    find "$rd" -name "*-daily-research.md" -newer "$watermark_file" 2>/dev/null
    find "$rd" -name "*-strategy-brief.md" -newer "$watermark_file" 2>/dev/null
    find "$rd" -name "*-recommendations.md" -newer "$watermark_file" 2>/dev/null
    find "$rd/deep-dives" -name "*.md" -newer "$watermark_file" 2>/dev/null
  )
done
```

Git checkout times can make a fresh clone over-report old files. Dedup absorbs
that case. If no reports are new, print `No new reports since last ingestion.`
and exit cleanly.

## Phase 2: Extract Candidate Items

| Filename | Type |
|---|---|
| `*-daily-research.md` | `daily-research` |
| `*-strategy-brief.md` | `weekly-brief` |
| `*-recommendations.md` | `weekly-recommendations` |
| `deep-dives/*.md` | `deep-dive` |

Read `plugins/pm/agents/ingestion-analyst.md` and dispatch all report analysts
in one message as parallel Agent calls. This is clear-spec bulk work: use
`routing.bulk` from `${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`
through `references/model-orchestration.md`, passing model and effort explicitly.

Each analyst receives the full report, its type, and condensed product context
from the nearest `research-context.md` or `pulse-config.yaml`. Every returned item
contains:

- `evidence`: what the source actually reports
- `proposed outcome`: the source's candidate result or follow-up
- `rationale`: why that proposal follows from the evidence
- `source`: report filename and section
- `confidence`: High, Medium, or Low
- `target repo`: best-supported repo, or `unknown`

Collect all items and per-report counts. Log a failed analyst and continue.

## Phase 3: Dedup and Filter

Skip an item when any check matches.

### 3.1 Existing open work

Follow Phase 3 in the selected backend reference to collect every non-terminal
item's title and body. Compare each candidate against that collection.

Two items match when their title or body has more than 80% significant-word
overlap. Significant words have at least three characters and exclude `the`,
`a`, `and`, `for`, `to`, `in`, `of`, and `is`. Similarity is shared words divided
by the smaller word count. Record `duplicate of existing item: {title}`.

### 3.2 Out-of-scope decisions

```bash
oos_dir="$primary_repo_root/$(yq '.out_of_scope_dir // ".pm/out-of-scope"' "$pm_config")"
```

Read each Markdown file except `README.md`. More than 60% significant-word
overlap with a rejected feature or decision is out of scope. Record
`matches out-of-scope rejection: {slug}`.

### 3.3 Current code

For a candidate that implies a concrete implementation, search configured repos:

```bash
for repo_path in $(yq '.repos[].path' "$config_path"); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  grep -r --include="*.swift" --include="*.ts" --include="*.py" --include="*.js" \
    --include="*.rb" --include="*.go" --include="*.rs" --include="*.java" \
    -l "$search_term" "$abs/Sources" "$abs/src" "$abs/lib" "$abs/app" 2>/dev/null
done
```

Mark an item implemented only when at least two key terms appear in one source
file and surrounding code confirms the same behavior. A keyword alone is not
proof. Record `appears already implemented in {file path}`.

Partition the result into survivors, duplicates, out-of-scope items, and already
implemented items.

## Phase 4: Create Needs-Triage Items

For each survivor, derive a short neutral title from `proposed outcome` and build:

```markdown
## Evidence

{evidence}

## Proposed outcome

{proposed outcome}

## Rationale

{rationale}

## Source

- **Report**: `{source.report}`
- **Section**: {source.section}
- **Confidence**: {confidence}
- **Target repo**: {target repo}

## Context

This candidate was extracted by `/pm:ingest`. Its proposed outcome is not an
approved commitment. Run `/pm:triage` to verify, classify, size, and prioritize it.

---
*Ingested on {DATE} from `{source.report}`*
```

Follow Phase 4 in the selected backend reference. Assign only
`status/needs-triage`; preserve every candidate field in the body or backend
record. Capture the created identifier and URL or path for the summary.

## Phase 5: Update Watermarks

After all candidates are created or skipped:

```bash
touch "$watermark_file"
```

Rewrite `state_file` with the run timestamp, processed report paths, and created
count while preserving its existing `last_reconcile` value:

```yaml
# Ingestion watermarks — updated by /pm:ingest
last_ingested:
  timestamp: "{ISO 8601 timestamp}"
  reports_processed:
    - "{relative report path}"
  items_created: {count}
last_reconcile: {preserved value or null}
```

## Phase 6: Summary

Print report, extraction, skip-category, and creation counts; the configured
backend; and the destination recorded by the selected reference. End with
`Next: Run /pm:triage to verify, classify, and prioritize the new items.`

If nothing was created, explain that every extracted item was a duplicate,
out-of-scope, or already implemented, and confirm that watermarks were updated.

## Shared Error Handling

- Missing `pulse-config.yaml` or `.pm/config.yml`: stop and direct the user to
  Product Pulse setup or `/pm:setup`.
- Missing research directory: warn and continue.
- Unreadable report or failed analyst: log and continue with partial results.
- Empty `research_dirs`: fall back to `research_dir` from `pulse-config.yaml`.
- Failed repo pull: note and continue.
- Missing state or watermark: initialize it as described in Phase 0.
- Backend read, authentication, or create failure: follow the selected reference;
  do not switch backends during the run.
