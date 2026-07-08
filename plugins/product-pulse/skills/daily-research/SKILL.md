---
name: daily-research
description: >-
  Daily research automation. Scans configured domains for actionable
  intelligence, filters through the weekly strategy brief for relevance,
  and produces a dated research report with action items for PM ingestion.
  Opens an auto-mergeable PR. Reads pulse-config.yaml from the nearest
  research directory. Trigger: "run daily research", "research scan",
  "what's new", "check for updates", or /product-pulse:daily-research.
  Also triggered by scheduled tasks.
---

# Product Pulse — Daily Research

You are the daily research scanner. Your job is to find what changed today across the product's configured research domains, filter it through the week's strategic direction, and produce an actionable report.

You are NOT a strategist — that's the weekly skill. You gather intel and surface findings. Keep it focused.

---

## Ground Rules

- **Max 5 findings per domain.** Quality over quantity.
- **Max 5 action items in the report's Action Items table.** Prioritize by strategic alignment.
- **Search term rotation** — Pick 3-5 terms per domain per run. Rotate so you don't search the same phrases daily. Append current month/year for recency.
- **Always Check items run every scan (no rotation)** — see Phase 0.6 below. These are user-configured architectural watch items that must be searched on every run regardless of rotation. Any hit is flagged `**ALWAYS-CHECK HIT**` and surfaced in a dedicated Escalations section at the top of the report.
- **Quiet days** — If 3+ domains return zero findings, use condensed format.
- **No fabricated URLs** — Every finding must have a real, verifiable source.
- **Error tolerant** — If a sub-agent fails, note it and continue. If memory is unavailable, skip memory ops.

---

## Phase 0: Load Context

### 0.0 Discover Configuration

Walk up from cwd, checking each directory for `pulse-config.yaml` directly and in common research-dir subdirs (`research/`, `Research/`, `docs/research/`). The first match wins; that file's parent directory is the **research directory** (`{research_dir}`). Load the YAML config; the rest of the skill uses values from it.

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
  echo "No pulse-config.yaml found. Run /product-pulse:setup first." >&2
  exit 1
fi

primary_repo_root="$(cd "$research_dir" && git rev-parse --show-toplevel)"

default_branch="$(yq '.default_branch // "main"' "$config_path")"
auto_merge="$(yq '.auto_merge // true' "$config_path")"
project_id="$(yq '.project_id' "$config_path")"
memory_connector="$(yq '.memory.connector // "shelby"' "$config_path")"

echo "Using config: $config_path"
echo "Research dir: $research_dir"
```

Parse the YAML. Required fields: `project_id`, `repos`. Optional with defaults: `default_branch` (default `main`), `auto_merge` (default `true`), `memory.connector` (default `shelby`; set to `null` to disable).

Find the entry in `repos:` with `role: primary`. Its filesystem location (resolved relative to the directory containing pulse-config.yaml's parent) is the **primary repo root** (`{primary_repo_root}`) for git operations.

### 0.1 Read Product Context

Read `{research_dir}/research-context.md`. If missing, stop and tell the user to run `/product-pulse:setup`.

### 0.2 Pull Latest (all configured repos)

Iterate `repos:` from `pulse-config.yaml`. For each repo, resolve its absolute path relative to `{primary_repo_root}`'s parent directory, then pull the default branch:

```bash
for repo_path in $(yq '.repos[].path' pulse-config.yaml); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  echo "=== Pulling $abs ==="
  cd "$abs" && git checkout "$default_branch" && git pull origin "$default_branch" || echo "pull failed for $abs"
done
```

If any pull fails, note it and continue. Single-element `repos:` is the monorepo case — same loop, one iteration.

### 0.3 Read the Weekly Strategy Brief

Find the most recent `*-strategy-brief.md` in `{research_dir}/` (search recursively through year/month folders). Extract:
- This week's theme and top 3 priorities
- Recommendations from the corresponding `*-recommendations.md`

If no weekly brief exists, all findings are treated as potentially relevant (no strategic filter).

### 0.4 Context Recovery (if memory configured)

If `memory.connector` is set, search for prior daily research findings (last 7 days) to avoid duplicates.

### 0.5 Build Dedup List

From memory and recent reports, collect finding URLs and summaries. A finding is a duplicate if:
- Same URL as a previous finding, OR
- 3+ shared significant keywords with a previous finding in the same domain

### 0.6 Load Always Check Items

Parse the `## Always Check` section of `{research_dir}/research-context.md`. This section (if present) contains a list of persistent watch items the user has flagged as architecturally load-bearing. Each item has:

- **ID** (e.g., AC-1)
- **Topic** — short name
- **Domain** — which research domain owns it
- **Reference** — optional path to a Guide doc that captures the current known state
- **Hit definition** — what counts as a meaningful change
- **Search terms** — terms that must run every scan, no rotation

If the section is missing or empty, skip this phase — the user hasn't configured Always Check items yet. Do NOT fabricate items.

When dispatching sub-agents in Phase 2, pass each domain's Always Check items (if any) alongside its regular search terms. The sub-agent must run **every** Always Check search term on **every** run, in addition to its 3-5 rotating terms.

---

## Phase 1: Load Sources

Read `{research_dir}/research-sources.yaml`. For each domain, rank sources by `qualityScore` descending. Sources without a score default to 50.

---

## Phase 2: Dispatch Domain Sub-Agents

**CRITICAL**: All domain agents MUST be dispatched in a single message as parallel Agent tool calls.

For each domain defined in the product context and research-sources.yaml, dispatch a sub-agent with:
- The product context (condensed)
- The domain's sources and search terms
- The domain's **Always Check items** (from Phase 0.6, if any) — with clear instructions that every Always Check search term must run on every scan, no rotation
- The dedup list
- The weekly strategic direction (if available)
- Instructions to find max 5 findings, each with: title, URL, summary, impact (H/M/L), effort (H/M/L), confidence (H/M/L), and relevance to the product
- Instructions that any Always Check hit must be tagged `**ALWAYS-CHECK HIT**` in the Title field and returned with Impact at least "medium" regardless of normal scoring

Each sub-agent uses WebSearch and WebFetch to scan its sources and search terms. YouTube MCP tools should be used for YouTube sources if available.

**Model routing.** Domain scanners are bulk, clear-spec fan-out — dispatch them on a cheap, capable model (pass `model` on each Agent call), following the project's model-selection rubric if its `AGENTS.md`/`CLAUDE.md` defines one. Reserve a stronger model for the synthesis and strategic filter in Phase 3.

---

## Phase 3: Synthesize

### 3.0 Extract Always Check Hits

Before deduping or ranking, separate out any findings tagged `**ALWAYS-CHECK HIT**`. These bypass the normal ranking and strategic filter — they always surface at the top of the report in a dedicated **Escalations** section and always appear in the Action Items table (they don't count against the 5-item cap, since they're triggered by pre-approved watch items). If an Always Check hit references a Guide doc in its Reference field, note "Guide doc update required: {path}" so the user knows to refresh it.

### 3.1 Deduplicate Across Domains

Remove cross-domain duplicates (same URL or 3+ shared keywords).

### 3.2 Rank All Findings

Sort by:
1. High impact + Low effort (quick wins)
2. High impact + High effort (strategic)
3. Medium impact + Low effort (easy pickups)
4. Lower priority combinations

### 3.3 Apply Strategic Filter

If a weekly brief exists, score each finding:
- **+2** if it directly supports a top 3 priority
- **+1** if it's in a domain related to the week's theme
- **+0** if unrelated
- **Always include** P0-level findings regardless (security, hard deadlines, blockers)

Take the top 5 by alignment score, then by impact/effort ratio. Only these appear in the report's Action Items table.

---

## Phase 4: Write Output

### Determine paths

```
month = current month (YYYY-MM)
week = current ISO week (WNN)
today = current date (YYYY-MM-DD)
week_dir = {research_dir}/{month}/W{NN}/
```

Create the directory if it doesn't exist. Daily reports live alongside the weekly brief for that week.

### Write Daily Report

Write to `{week_dir}/{today}-daily-research.md`. Structure:

```markdown
# Daily Research — {today}

**Product**: {product name}
**Weekly theme**: {theme or "No weekly brief"}
**Domains scanned**: {N}
**Findings**: {N} total, {N} action items

---

## {Domain 1 Name}

### Finding: {title}
- **Source**: [{source name}]({URL})
- **Summary**: {2-3 sentences}
- **Impact**: {H/M/L} | **Effort**: {H/M/L} | **Confidence**: {H/M/L}
- **Relevance**: {why this matters to the product}

...

## Action Items

| # | Item | Size | Priority | Domain | Source | Confidence |
|---|------|------|----------|--------|--------|------------|

## Source Performance

| Source | Domain | Checked | Hit? |
|--------|--------|---------|------|

## Noted

{findings that were interesting but didn't make the top 5 cut}

## Search Terms Used

{list per domain, for rotation tracking}
```

### Update Source Quality

For each source checked, update quality tracking in memory (hit/miss ratio).

---

## Phase 5: Persist & Commit

### 5.1 Save to memory (if configured)

If `memory.connector` is set, capture a summary of today's findings. Tool names match the connector prefix:

```
capture_thought({
  content: "{summary of findings and domains scanned}",
  summary: "Daily research {YYYY-MM-DD}: {N} findings across {M} domains",
  type: "note",
  topics: ["product-pulse-daily-research", "{project_id}-research"],
  source: "daily-research-{YYYY-MM-DD}",
  project: "{project_id}",
  metadata: { date: "{YYYY-MM-DD}", domains: {M}, findings: {N}, action_items: {K} }
})
```

If `memory.connector: null` or no matching tools are found, skip this phase.

### 5.2 Branch + commit + PR (always)

Inside the primary repo:

```bash
cd "$primary_repo_root"
branch="daily-research/{YYYY-MM-DD}"
git checkout -b "$branch"
git add "$research_dir"
git commit -m "research: daily scan {today} — {N} findings across {M} domains"
git push -u origin "$branch"
pr_url=$(gh pr create --base "$default_branch" --head "$branch" \
  --title "research: daily scan {today} — {N} findings across {M} domains" \
  --body "Daily research scan for {today}. {N} findings across {M} domains; {K} action items. Auto-generated by product-pulse daily-research." \
  | tail -n1)
echo "PR opened: $pr_url"
```

### 5.3 Auto-merge (if enabled and mergeable)

If `auto_merge: true` in config:

```bash
sleep 8  # let GitHub finalize mergeability check
gh pr merge "$pr_url" --squash --delete-branch --auto || \
  echo "Auto-merge declined; PR sits for human review at $pr_url"
```

`--auto` queues the merge if checks are still running. If branch protection or required reviews block the merge, the PR sits for human review and the skill exits cleanly with the PR URL surfaced.

---

## Phase 6: Summary

```
Product Pulse — Daily Research ({today})
==========================================
Domains scanned: {N}
Findings: {N} total
Action items: {N} in report
Noted: {N}
Sources checked: {N} ({N} hits, {N} misses)
PR: {pr_url} ({merged | open})
```

---

## Error Handling

- **Research context missing**: Stop and tell the user to run `/product-pulse:setup`.
- **Memory unavailable**: Continue without memory context — rely on file-based data.
- **Sub-agent failure**: Note the failed domain and continue with others.
