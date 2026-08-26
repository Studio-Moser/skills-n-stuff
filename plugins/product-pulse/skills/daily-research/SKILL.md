---
name: daily-research
description: >-
  Use when configured research domains need a daily source scan, strategic
  filtering, and a dated report for PM ingestion and publication.
allowed-tools: "Bash Read Write Edit Skill"
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
- **Error tolerant** — If a Harness request fails, note it and continue. If memory is unavailable, skip memory ops.
- **Harness boundary** — Invoke the named Harness skill through `Skill`; do not read Harness skill, reference, script, or rubric files, and do not perform Harness phases inside Product Pulse. Do not read or inspect the model rubric, and do not resolve a model, effort, provider, or executor. Do not repair an unresolved or blocked route inside Product Pulse; consume and report the typed Harness Result.

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

If `memory.connector` is set, define a recall intent for prior daily findings from
the last 7 days. Attach it to the Phase 2 Harness requests; Product Pulse does not
discover or call a memory provider. If Harness returns no enrichment, continue from
recent report files.

### 0.5 Build Dedup List

From recent reports and any bounded context Harness returns for the recall intent,
collect finding URLs and summaries. A finding is a duplicate if:
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

Include each domain's Always Check items (if any) in its Phase 2 request. The research worker must run **every** Always Check search term on **every** run, in addition to its 3-5 rotating terms.

---

## Phase 1: Load Sources

Read `{research_dir}/research-sources.yaml`. For each domain, rank sources by `qualityScore` descending. Sources without a score default to 50.

---

## Phase 2: Request Domain Scans

For each configured domain, invoke `harness:execute` with `operation: execute` and
`route: bulk`. Submit independent requests concurrently. Product Pulse chooses the
research question, sources, and acceptance rules; Harness owns concrete routing and
execution.

Replace every placeholder with that domain's actual content. The constraint block is
the complete instruction set for a fresh worker; never pass it a Product Pulse plugin
path and expect it to recover private instructions.

```yaml
operation: execute
route: bulk
outcome: Return at most 5 current, source-backed findings for one configured research domain
context:
  project: {project_id}
  mode: fresh
  state: {condensed product context, domain name, ranked sources and 3-5 rotated search terms, every Always Check item and search term, dedup list, and weekly strategic direction}
  files: [{repository-relative research-context.md, research-sources.yaml, and recent report paths}]
  memory:
    enabled: {memory.connector is not null}
    recall:
      - purpose: Avoid duplicating prior daily research from the last 7 days
        query: Daily research findings for {project_id} in the last 7 days
        limit: 20
    capture: []
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only paths named in context.files}]
  tools: [internet research, read-only source retrieval]
  approvals: []
constraints:
  - |
    Product Pulse daily domain researcher:
    Search the supplied ranked sources and rotated terms for changes relevant to the
    supplied product and weekly strategic direction. Run every Always Check search term
    on every scan with no rotation. Return max 5 findings. Every finding must contain
    title, URL, summary, impact, effort, confidence, and relevance. The URL must be a
    real source URL that you opened; do not fabricate or infer URLs.
  - |
    Assess source credibility from authority, directness, corroboration, publication or
    update date, and whether the claim is still current. Prefer primary sources. Mark
    uncertainty and never strengthen a source claim. Use the supplied dedup list and
    any Harness-provided recalled context to exclude the same URL or a same-domain
    finding with 3 or more shared significant keywords. Report checked sources and
    search terms even when no finding qualifies.
  - |
    Tag a qualifying watch-item finding as **ALWAYS-CHECK HIT** in its title and set
    impact to at least Medium. A hit must satisfy the supplied hit definition; do not
    fabricate an Always Check item or infer a hit from keyword overlap alone.
  - Do not modify files, publish reports, or choose follow-up work
verification:
  seam: Open every returned URL and compare the finding, date, credibility assessment, and required fields with the source and supplied domain packet
  expected: Every finding is current, relevant, non-duplicate, source-supported, complete, and within the 5-finding cap
```

Consume the exact Harness Result. Accept findings only from `status: accepted` with
`evidence.outcome: proven`, then reproduce the verification seam. A worker summary,
exit code, or inaccessible citation is not research proof. Log a failed, blocked, or
abandoned domain and continue with the remaining domains.

### Branch Manifest

Build the Branch Manifest before synthesis with one row for every configured domain.
Record branch identity, exact Harness `status`, evidence outcome, blockers, and elapsed
when available (`unavailable` otherwise). Only accepted/proven branches whose
verification seam Product Pulse reproduced may contribute content. Keep every other
expected branch in the manifest and exclude its claims.

---

## Phase 3: Synthesize

Invoke `harness:execute` with `operation: execute` and `route: taste` for one bounded
draft. Product Pulse remains the accepting workflow and writes the report only after
checking the returned Harness Result.

```yaml
operation: execute
route: taste
outcome: Produce a source-preserving daily research report draft from the accepted domain findings
context:
  project: {project_id}
  mode: fresh
  state: {complete branch manifest, accepted domain findings, weekly strategy, product context, Always Check definitions, and source-check records}
  files: [{repository-relative recent report paths used for deduplication and strategy}]
  memory:
    enabled: {memory.connector is not null}
    recall: []
    capture:
      - when: accepted
        type: note
        summary: Daily research {YYYY-MM-DD}: {N} findings across {M} domains
        content: {proven finding summary, action items, and source-performance update}
        topics: [product-pulse-daily-research, {project_id}-research]
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only paths named in context.files}]
  tools: [read-only inspection]
  approvals: []
constraints:
  - |
    Product Pulse daily synthesis:
    Extract every **ALWAYS-CHECK HIT** first; it bypasses ranking and the strategic
    filter, appears in Escalations and Action Items, and does not count against the
    5-item cap. Note any required Guide doc update. Deduplicate across domains by exact
    URL or 3 or more shared significant keywords without merging distinct claims.
  - |
    Rank remaining findings by impact and effort. Apply the weekly strategic filter:
    +2 for direct support of a top-3 priority, +1 for the weekly theme, +0 otherwise;
    always retain security, hard-deadline, and blocker findings. Select at most 5 normal
    action items by alignment and then impact/effort. Preserve every citation, caveat,
    confidence rating, and source credibility assessment; do not create a new claim.
  - |
    Return a complete draft with domain findings, Action Items, Source Performance,
    Noted, and Search Terms Used sections. Include the intended report path
    {week_dir}/{today}-daily-research.md. Do not write or publish files.
  - |
    Report coverage as expected, accepted/proven, failed, blocked, abandoned, and
    unproven. Count an accepted/unproven result as unproven, not accepted. Mark degraded
    coverage whenever accepted/proven is fewer than expected. Never describe a failed,
    blocked, abandoned, unproven, or missing branch as scanned, researched, or covered.
verification:
  seam: Trace every report claim and action item to one accepted domain finding and verify branch manifest totals, degraded-coverage disclosure, caps, deduplication, strategic scoring, citations, and report path
  expected: The draft is source-faithful, strategically ranked, complete, accurately discloses coverage, and ready for Product Pulse publication
```

Require `status: accepted` and `evidence.outcome: proven`, reproduce the seam, and
reject any draft that changes a citation, drops a required section, or invents a claim.

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
**Research Coverage**: {accepted}/{expected} accepted/proven; {failed} failed; {blocked} blocked; {abandoned} abandoned; {unproven} unproven{ — degraded coverage when accepted < expected}
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

Include each checked source's hit/miss result in the Phase 3 capture intent so
Harness can update optional project memory after the draft is proven.

---

## Phase 5: Persist & Commit

### 5.1 Confirm optional memory enrichment

The Phase 3 Harness request carries the domain capture intent. After Product Pulse
reproduces its proof, retain any returned Harness memory identifiers in the run
summary. If memory is disabled or unavailable, continue with the report and leave
those optional identifiers empty; do not call a provider directly.

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
Research Coverage: {accepted}/{expected} accepted/proven; {failed} failed; {blocked} blocked; {abandoned} abandoned; {unproven} unproven{ — degraded coverage when accepted < expected}
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
- **Harness request failure**: Note the failed domain and continue with others.
