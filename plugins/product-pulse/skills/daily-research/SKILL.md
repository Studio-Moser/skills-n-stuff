---
name: daily-research
description: >-
  Scans configured research domains, filters findings strategically, and writes a dated report for PM ingestion and publication. Use when the daily research scan is due.
allowed-tools: "Bash Read Write Edit Skill"
disable-model-invocation: true
---

# Product Pulse — Daily Research

Find what changed today across the product's configured research domains, filter it through the week's strategic direction, and produce an actionable report. Leave direction-setting to the weekly strategist: this scan gathers and surfaces evidence, and the weekly brief decides what it means.

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

Run § Discover Configuration in [Config_and_Publish.md](../../references/Config_and_Publish.md) with `save_report=true`. It sets `{research_dir}`, `{primary_repo_root}`, `default_branch`, `auto_merge`, `project_id`, and `memory_connector`, and stops when the config, a required tool, or the `gh` login is missing.

### 0.1 Read Product Context

Read `{research_dir}/research-context.md`. If missing, stop and tell the user to run `/product-pulse:setup`.

### 0.2 Pull Latest (all configured repos)

Run § Pull Latest in [Config_and_Publish.md](../../references/Config_and_Publish.md).

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

If the section is missing or empty, skip this phase. Don't invent items: each one records the user's decision about which facts are load-bearing.

Include each domain's Always Check items (if any) in its Phase 2 request. The packet requires every Always Check term on every run, beside the 3-5 rotating terms, because a watch item only helps if a change is caught the day it lands.

---

## Phase 1: Load Sources

Read `{research_dir}/research-sources.yaml`. For each domain, rank sources by `qualityScore` descending. Sources without a score default to 50.

---

## Phase 2: Request Domain Scans

For each configured domain, invoke `harness:delegate` with `operation: execute` and
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
For a returned result, record branch identity, exact Harness `status`, evidence outcome,
blockers, and elapsed when available (`unavailable` otherwise). When no Harness Result
exists, retain the expected identity. Record `status: unavailable (no result)` as a
Product Pulse manifest sentinel, not a Harness status; record evidence outcome
`unproven`, blocker `missing Harness Result`, and elapsed `unavailable`; count that row
as unproven for coverage and exclude its claims. Only accepted/proven branches whose
verification seam Product Pulse reproduced may contribute content. Keep every other
expected branch in the manifest and exclude its claims.

---

## Phase 3: Synthesize

Invoke `harness:delegate` with `operation: execute` and `route: taste` for one bounded
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
    5-item cap. When a hit's Reference names a Guide doc, note "Guide doc update
    required: {path}". Deduplicate across domains by exact URL or 3 or more shared
    significant keywords without merging distinct claims.
  - |
    Rank remaining findings by impact and effort: high impact/low effort, high/high,
    medium/low, then the rest. When a weekly brief exists, apply the strategic filter:
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
  seam: Trace every report claim and action item to one accepted domain finding and verify branch manifest totals, including no-result unproven classification, degraded-coverage disclosure, caps, deduplication, strategic scoring, citations, and report path
  expected: The draft is source-faithful, strategically ranked, complete, accurately discloses coverage, and ready for Product Pulse publication
```

Require `status: accepted` and `evidence.outcome: proven`, reproduce the seam, and
reject any draft that changes a citation, drops a required section, or invents a claim.

Before accepting, confirm the draft applied the packet's rules: Always Check hits
extracted first into Escalations, cross-domain deduplication, impact/effort ranking,
the strategic filter, and the 5-item Action Items cap.

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
**Escalations**: {N}

---

## Escalations (Always Check Hits)

{Omit this section when no Always Check item hit.}

### {Always Check ID} — {Topic}
- **Source**: [{source name}]({URL})
- **Change detected**: {what shifted vs the hit definition}
- **Guide doc update required**: {path, or "none"}
- **Action**: {what the user should do about this}

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

### 5.2 Publish

Run § Publish in [Config_and_Publish.md](../../references/Config_and_Publish.md) with:

- `branch="daily-research/{today}"`
- `publish_path="$research_dir"`
- `title="research: daily scan {today} — {N} findings across {M} domains"`
- `body="Daily research scan for {today}. {N} findings across {M} domains; {K} action items. Auto-generated by product-pulse daily-research."`

It opens the PR with `gh pr create` and queues a squash merge only when `auto_merge` is true.

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
