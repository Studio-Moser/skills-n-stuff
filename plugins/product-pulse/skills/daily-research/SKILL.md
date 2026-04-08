---
name: daily-research
description: >-
  Daily research automation. Scans configured domains for actionable
  intelligence, filters through the weekly strategy brief for relevance,
  and caps tracker additions at 5/day. Produces a dated research report
  and updates the tracker. Trigger: "run daily research", "research scan",
  "what's new", "check for updates", or /product-pulse:daily-research.
  Also triggered by scheduled tasks.
---

# Product Pulse — Daily Research

You are the daily research scanner. Your job is to find what changed today across the product's configured research domains, filter it through the week's strategic direction, and produce an actionable report.

You are NOT a strategist — that's the weekly skill. You gather intel and surface findings. Keep it focused.

---

## Ground Rules

- **Max 5 findings per domain.** Quality over quantity.
- **Max 5 new tracker items per day.** Prioritize by strategic alignment.
- **Search term rotation** — Pick 3-5 terms per domain per run. Rotate so you don't search the same phrases daily. Append current month/year for recency.
- **Quiet days** — If 3+ domains return zero findings, use condensed format.
- **No fabricated URLs** — Every finding must have a real, verifiable source.
- **Error tolerant** — If a sub-agent fails, note it and continue. If memory is unavailable, skip memory ops.

---

## Phase 0: Load Context

### 0.1 Read Product Context

Read `{research_dir}/product-context.md`. If missing, stop and tell the user to run `/product-pulse:setup`.

### 0.2 Pull Latest

```bash
git pull origin main 2>/dev/null || true
```

### 0.3 Read the Weekly Strategy Brief

Find the most recent `*-strategy-brief.md` in `{research_dir}/weekly/` (search recursively through year/month folders). Extract:
- This week's theme and top 3 priorities
- Focus items from the corresponding `*-focus.md`

If no weekly brief exists, all findings are treated as potentially relevant (no strategic filter).

### 0.4 Context Recovery

Search memory for prior daily research findings (last 7 days). Read the tracker for open items.

### 0.5 Build Dedup List

From memory and recent reports, collect finding URLs and summaries. A finding is a duplicate if:
- Same URL as a previous finding, OR
- 3+ shared significant keywords with a previous finding in the same domain

---

## Phase 1: Load Sources

Read `{research_dir}/research-sources.json`. For each domain, rank sources by `qualityScore` descending. Sources without a score default to 50.

---

## Phase 2: Dispatch Domain Sub-Agents

**CRITICAL**: All domain agents MUST be dispatched in a single message as parallel Agent tool calls.

For each domain defined in the product context and research-sources.json, dispatch a sub-agent with:
- The product context (condensed)
- The domain's sources and search terms
- The dedup list
- The weekly strategic direction (if available)
- Instructions to find max 5 findings, each with: title, URL, summary, impact (H/M/L), effort (H/M/L), confidence (H/M/L), and relevance to the product

Each sub-agent uses WebSearch and WebFetch to scan its sources and search terms. YouTube MCP tools should be used for YouTube sources if available.

---

## Phase 3: Synthesize

### 3.1 Deduplicate Across Domains

Remove cross-domain duplicates (same URL or 3+ shared keywords).

### 3.2 Rank All Findings

Sort by:
1. High impact + Low effort (quick wins)
2. High impact + High effort (strategic)
3. Medium impact + Low effort (easy pickups)
4. Lower priority combinations

### 3.3 Apply Strategic Filter for Tracker

If a weekly brief exists, score each finding:
- **+2** if it directly supports a top 3 priority
- **+1** if it's in a domain related to the week's theme
- **+0** if unrelated
- **Always include** P0-level findings regardless (security, hard deadlines, blockers)

Take the top 5 by alignment score, then by impact/effort ratio. Only these go into the tracker. All others stay in the report as "Noted."

---

## Phase 4: Write Output

### Determine paths

```
year = current year (YYYY)
month = current month (MM)
today = current date (YYYY-MM-DD)
report_dir = {research_dir}/daily/{year}/{month}/
```

Create the directory if it doesn't exist.

### Write Daily Report

Write to `{report_dir}/{today}-daily-research.md`. Structure:

```markdown
# Daily Research — {today}

**Product**: {product name}
**Weekly theme**: {theme or "No weekly brief"}
**Domains scanned**: {N}
**Findings**: {N} total, {N} added to tracker

---

## {Domain 1 Name}

### Finding: {title}
- **Source**: [{source name}]({URL})
- **Summary**: {2-3 sentences}
- **Impact**: {H/M/L} | **Effort**: {H/M/L} | **Confidence**: {H/M/L}
- **Relevance**: {why this matters to the product}
- **Status**: {Added to tracker | Noted}

...

## Source Performance

| Source | Domain | Checked | Hit? |
|--------|--------|---------|------|

## Noted (Not Added to Tracker)

{findings that were interesting but didn't make the top 5 cut}

## Search Terms Used

{list per domain, for rotation tracking}
```

### Update Tracker

Add up to 5 new items to the Open Items table. Each gets: item number (sequential), description, domain, impact, effort, ease, priority, found date, report link.

### Update Source Quality

For each source checked, update quality tracking in memory (hit/miss ratio).

---

## Phase 5: Persist & Commit

- Save findings to memory with topic `product-pulse-daily-research`
- Git commit and push if in a repo:
  ```bash
  git add {research_dir}/ && git commit -m "research: daily scan {today} — {N} findings across {M} domains" && git push origin HEAD
  ```

---

## Phase 6: Summary

```
Product Pulse — Daily Research ({today})
==========================================
Domains scanned: {N}
Findings: {N} total
Tracker additions: {N} (max 5)
Noted (not added): {N}
Sources checked: {N} ({N} hits, {N} misses)
```
