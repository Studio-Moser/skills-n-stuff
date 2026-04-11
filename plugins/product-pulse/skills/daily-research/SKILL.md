---
name: daily-research
description: >-
  Daily research automation. Scans configured domains for actionable
  intelligence, filters through the weekly strategy brief for relevance,
  and adds new ideas to todos/backlog.md (max 5/day). Produces a dated
  research report. Trigger: "run daily research", "research scan",
  "what's new", "check for updates", or /product-pulse:daily-research.
  Also triggered by scheduled tasks.
---

# Product Pulse — Daily Research

You are the daily research scanner. Your job is to find what changed today across the product's configured research domains, filter it through the week's strategic direction, and produce an actionable report.

You are NOT a strategist — that's the weekly skill. You gather intel and surface findings. Keep it focused.

---

## Ground Rules

- **Max 5 findings per domain.** Quality over quantity.
- **Max 5 new backlog items per day.** Prioritize by strategic alignment.
- **Research adds items as `idea` status ONLY** — never `ready` or beyond. You discover; others promote.
- **Search term rotation** — Pick 3-5 terms per domain per run. Rotate so you don't search the same phrases daily. Append current month/year for recency.
- **Always Check items run every scan (no rotation)** — see Phase 0.6 below. These are user-configured architectural watch items that must be searched on every run regardless of rotation. Any hit is flagged `**ALWAYS-CHECK HIT**` and surfaced in a dedicated Escalations section at the top of the report.
- **Quiet days** — If 3+ domains return zero findings, use condensed format.
- **No fabricated URLs** — Every finding must have a real, verifiable source.
- **Error tolerant** — If a sub-agent fails, note it and continue. If memory is unavailable, skip memory ops.

---

## Phase 0: Load Context

### 0.1 Read Product Context

Read `{research_dir}/research-context.md`. If missing, stop and tell the user to run `/product-pulse:setup`.

Extract the **Git branch** from the Configuration section (default: `main` if not specified). Use this as `{branch}` for all git operations.

### 0.2 Pull Latest

```bash
git pull origin main 2>/dev/null || true
```

### 0.3 Read the Weekly Strategy Brief

Find the most recent `*-strategy-brief.md` in `{research_dir}/` (search recursively through year/month folders). Extract:
- This week's theme and top 3 priorities
- Recommendations from the corresponding `*-recommendations.md`

If no weekly brief exists, all findings are treated as potentially relevant (no strategic filter).

### 0.4 Context Recovery

Search memory for prior daily research findings (last 7 days). Read the backlog for current items.

Read `todos/backlog.md`. Parse all sections: Roadmap, Ready, Ideas (all subsections), Awaiting PR, Monitor, Manual, Dismissed.

### 0.5 Build Dedup List

From memory and recent reports, collect finding URLs and summaries. A finding is a duplicate if:
- Same URL as a previous finding, OR
- 3+ shared significant keywords with a previous finding in the same domain

Also check against existing backlog items to avoid adding duplicates.

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

Read `{research_dir}/research-sources.json`. For each domain, rank sources by `qualityScore` descending. Sources without a score default to 50.

---

## Phase 2: Dispatch Domain Sub-Agents

**CRITICAL**: All domain agents MUST be dispatched in a single message as parallel Agent tool calls.

For each domain defined in the product context and research-sources.json, dispatch a sub-agent with:
- The product context (condensed)
- The domain's sources and search terms
- The domain's **Always Check items** (from Phase 0.6, if any) — with clear instructions that every Always Check search term must run on every scan, no rotation
- The dedup list
- The weekly strategic direction (if available)
- Instructions to find max 5 findings, each with: title, URL, summary, impact (H/M/L), effort (H/M/L), confidence (H/M/L), and relevance to the product
- Instructions that any Always Check hit must be tagged `**ALWAYS-CHECK HIT**` in the Title field and returned with Impact at least "medium" regardless of normal scoring

Each sub-agent uses WebSearch and WebFetch to scan its sources and search terms. YouTube MCP tools should be used for YouTube sources if available.

---

## Phase 3: Synthesize

### 3.0 Extract Always Check Hits

Before deduping or ranking, separate out any findings tagged `**ALWAYS-CHECK HIT**`. These bypass the normal ranking and strategic filter — they always surface at the top of the report in a dedicated **Escalations** section and are always added to the backlog (they don't count against the 5-item daily cap, since they're triggered by pre-approved watch items). If an Always Check hit references a Guide doc in its Reference field, note "Guide doc update required: {path}" so the user knows to refresh it.

### 3.1 Deduplicate Across Domains

Remove cross-domain duplicates (same URL or 3+ shared keywords).

### 3.2 Rank All Findings

Sort by:
1. High impact + Low effort (quick wins)
2. High impact + High effort (strategic)
3. Medium impact + Low effort (easy pickups)
4. Lower priority combinations

### 3.3 Apply Strategic Filter for Backlog

If a weekly brief exists, score each finding:
- **+2** if it directly supports a top 3 priority
- **+1** if it's in a domain related to the week's theme
- **+0** if unrelated
- **Always include** P0-level findings regardless (security, hard deadlines, blockers)

Take the top 5 by alignment score, then by impact/effort ratio. Only these go into the backlog. All others stay in the report as "Noted."

### 3.4 Classify for Backlog Placement

For each of the top 5 findings:
- **Actionable items** → Ideas subsection (matching domain)
- **Watch-and-wait items** (not actionable yet, depends on external trigger or timeline) → Monitor table

### 3.5 Map to Backlog Format

- **Size**: Map Effort to Size — Easy → S, Medium → M, Hard → L
- **Source**: Always `research`
- **Found**: Today's date

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
**Findings**: {N} total, {N} added to backlog

---

## {Domain 1 Name}

### Finding: {title}
- **Source**: [{source name}]({URL})
- **Summary**: {2-3 sentences}
- **Impact**: {H/M/L} | **Effort**: {H/M/L} | **Confidence**: {H/M/L}
- **Relevance**: {why this matters to the product}
- **Status**: {Added to backlog | Noted}

...

## Source Performance

| Source | Domain | Checked | Hit? |
|--------|--------|---------|------|

## Noted (Not Added to Backlog)

{findings that were interesting but didn't make the top 5 cut}

## Search Terms Used

{list per domain, for rotation tracking}
```

### Update the Backlog

Read `todos/backlog.md` and add new items:

- **Actionable items** → Add rows to the matching domain subsection under Ideas:
  `| # | Item | Size | Priority | Source | Found |`
- **Watch-and-wait items** → Add rows to the Monitor table:
  `| # | Item | Trigger | Deadline | Found |`

Item numbers are sequential across the entire backlog (continue from the highest existing number).

**Never** add items to Roadmap, Ready, or any other section. Research creates `idea` and `monitor` entries only.

### Update Source Quality

For each source checked, update quality tracking in memory (hit/miss ratio).

---

## Phase 5: Persist & Commit

- Save findings to memory with topic `product-pulse-daily-research`
- Git commit and push if in a repo:
  ```bash
  git checkout {branch} && git add {research_dir}/ todos/backlog.md && git commit -m "research: daily scan {today} — {N} findings across {M} domains" && git push origin {branch}
  ```

---

## Phase 6: Summary

```
Product Pulse — Daily Research ({today})
==========================================
Domains scanned: {N}
Findings: {N} total
Backlog additions: {N} (max 5)
Noted (not added): {N}
Sources checked: {N} ({N} hits, {N} misses)
```

---

## Error Handling

- **Backlog file missing**: Stop and tell the user to run `/product-pulse:setup`.
- **Research context missing**: Stop and tell the user to run `/product-pulse:setup`.
- **Memory unavailable**: Continue without memory context — rely on file-based data.
- **Sub-agent failure**: Note the failed domain and continue with others.
