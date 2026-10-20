---
name: weekly-strategist
description: >-
  Turns the last 7 daily reports and current market evidence into a weekly strategy brief with exactly three priorities and recommendations for PM ingestion. Use when the weekly strategy brief is due.
allowed-tools: "Bash Read Write Edit Skill"
disable-model-invocation: true
---

# Product Pulse — Weekly Strategist

Step back from the daily scans and answer: **"What should we focus on this week and why?"** Read the week's research, understand the market, and set direction. Recommend only, and never promote, dismiss, or edit backlog items: PM:ingest reads the recommendations file and PM:triage owns the backlog.

---

## Ground Rules

- **Brevity over comprehensiveness** — The brief should be readable in 5 minutes. Each analyst produces max 500 words.
- **Opinionated** — Make recommendations. Say "do X" not "you could do X or Y."
- **Error tolerant** — If a Harness request fails, continue with the other research packets. If no daily reports exist, use web research. If memory is unavailable, use file-based data.
- **Harness boundary** — Invoke the named Harness skill through `Skill`; do not read Harness skill, reference, script, or rubric files, and do not perform Harness phases inside Product Pulse. Do not read or inspect the model rubric, and do not resolve a model, effort, provider, or executor. Do not repair an unresolved or blocked route inside Product Pulse; consume and report the typed Harness Result.

---

## Phase 0: Load Context

### 0.0 Discover Configuration

Run § Discover Configuration in [Config_and_Publish.md](../../references/Config_and_Publish.md) with `save_report=true`. It sets `{research_dir}`, `{primary_repo_root}`, `default_branch`, `auto_merge`, `project_id`, and `memory_connector`, and stops when the config, a required tool, or the `gh` login is missing.

### 0.1 Read Product Context

Read `{research_dir}/research-context.md` to understand the product, competitors, audiences, and domains. This is your foundation — every recommendation must be relevant to this product.

If the file doesn't exist, stop and tell the user to run `/product-pulse:setup` first.

### 0.2 Pull Latest (all configured repos)

Run § Pull Latest in [Config_and_Publish.md](../../references/Config_and_Publish.md).

### 0.3 Read Last Weekly Brief

```bash
find {research_dir}/ -name "*-strategy-brief.md" 2>/dev/null | sort -r | head -1
```

Read it to understand last week's direction.

### 0.4 Read Last 7 Daily Reports

```bash
find {research_dir}/ -name "*-daily-research.md" 2>/dev/null | sort -r | head -7
```

Extract:
- Recurring themes across multiple days
- High-impact findings
- Cross-domain patterns
- Trend lines (increasing frequency or urgency)

### 0.5 Search Memory (if configured)

If `memory.connector` is set in `pulse-config.yaml` (not `null`), define recall
intents for prior weekly decisions and recent daily-research outcomes. Attach them
to each Phase 1 Harness request. Product Pulse does not discover or call a memory
provider; when Harness returns no enrichment, continue from repository reports.

### 0.6 Build Context Package

Compile a ~1000-word context package summarizing product status, market context, and last week's direction. This gets passed to every analyst.

---

## Phase 1: Request Five Analyst Briefs

Invoke `harness:delegate` five times with `operation: execute` and `route: bulk`, once
for each named analyst role. Submit independent requests concurrently. Product Pulse
chooses the questions, source standards, and analyst constraints; Harness owns concrete
routing and execution.

Use the packet below for each role. Include the entire role catalog in every request so
a fresh worker can apply the selected role without opening a Product Pulse plugin path.

```yaml
operation: execute
route: bulk
outcome: Return one source-backed weekly analyst brief of at most 500 words for the selected Product Pulse role
context:
  project: {project_id}
  mode: fresh
  state: {selected role, full context package, last 7 daily-report patterns, previous weekly direction, configured sources, and current date}
  files: [{repository-relative research context and accepted daily report paths}]
  memory:
    enabled: {memory.connector is not null}
    recall:
      - purpose: Recover prior weekly strategy decisions
        query: Weekly strategist decisions for {project_id}
        limit: 10
      - purpose: Recover recent daily-research outcomes
        query: Daily research outcomes for {project_id}
        limit: 20
    capture: []
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only paths named in context.files}]
  tools: [internet research, read-only source retrieval]
  approvals: []
constraints:
  - |
    Shared Product Pulse analyst rules:
    Adapt every query to this product and the selected role. Prefer developments from
    the last 7 days, append the current month and year to at least one search, and open
    every cited source URL. Assess source credibility from authority, directness,
    corroboration, publication or update date, and currentness. Prefer primary sources;
    do not fabricate URLs or strengthen claims. Return max 500 words, explain the
    product-specific "so what," give one recommended action, and say plainly when no
    significant evidence exists.
  - |
    Role catalog — apply only the selected role:
    Market Scout: investigate industry shifts, new entrants, funding, acquisitions,
    shutdowns, regulation, technology changes, and emerging trends. Return Key
    Findings, Implications for the product, and Recommended Action.
    Competitor Tracker: inspect each named competitor's releases, changelogs, official
    posts, pricing, positioning, hiring signals, and public repository activity. Focus
    on landscape-changing actions. Return Competitor Activity, Competitive Landscape
    Shift, and Recommended Action; name quiet competitors without padding.
    Audience Analyst: investigate recent complaints, requests, discussions, unmet needs,
    and emerging segments. Focus on pain points rather than demographics. Return
    Audience Signals, Emerging Segments, and Recommended Action.
    Growth Analyst: investigate specific distribution channels, partnerships,
    integrations, search demand, content angles, communities, directories, and
    marketplaces appropriate to the product stage. Rank concrete opportunities by
    impact and effort. Return Growth Opportunities and Top Recommendation.
    Product Scout: investigate evidence-backed feature gaps, documented APIs and data
    sources, technical capabilities, UX patterns, integrations, and user requests.
    Include value and small/medium/large effort. Return Product Opportunities and Top
    Recommendation; hypothetical APIs do not qualify.
  - Do not modify files, publish reports, or choose the weekly priorities
verification:
  seam: Open every source URL and compare each claim, date, credibility assessment, role requirement, and recommendation with the source and supplied product context
  expected: The selected role brief is current, source-supported, product-specific, complete, and at most 500 words
```

Consume the exact Harness Result. Accept a brief only from `status: accepted` with
`evidence.outcome: proven`, then reproduce the verification seam. Log failed, blocked,
or abandoned roles and continue. Do not take a single analyst claim at face value:
corroborate any claim that could drive a top-three priority.

---

## Phase 2: Adjudicate Evidence and Synthesize Strategy

When accepted sources remain contradictory or a high-impact claim is not adequately
corroborated, materialize the disputed claim, full citations, credibility assessments,
and source excerpts as one immutable snapshot digest before requesting a strategy draft.
Invoke `harness:delegate` with `operation: review` and `route: review`; do not silently
pick a winner or let contested evidence reach synthesis first.

```yaml
operation: review
route: review
outcome: Adjudicate one contradictory or insufficiently corroborated high-impact research claim before strategy synthesis
context:
  project: {project_id}
  mode: fresh
  state: {disputed claim, full source excerpts, publication dates, prior corroboration attempts, and product impact}
  files: [{read-only repository-relative immutable claim packet when materialized as a file}]
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only immutable claim packet and cited evidence}]
  tools: [read-only source retrieval and inspection]
  approvals: []
constraints:
  - Compare the contradictory evidence without strengthening either position
  - Assess source credibility, freshness, authority, directness, and corroboration
  - Verify all citations and identify what remains unknown
  - Report whether the high-impact claim is supported, refuted, or unresolved; do not edit files
verification:
  seam: Reopen every citation and reproduce the credibility comparison against the immutable claim packet
  expected: The adjudication names the best-supported position and all unresolved uncertainty with no fabricated claim
  fixed_target: {immutable digest of the contradictory or high-impact claim packet and cited evidence}
```

Only use an adjudication with `status: accepted`, matching `evidence.fixed_target`,
and `evidence.outcome: proven`. Otherwise keep the conflict visible and exclude it from
priority-setting.

### Branch Manifest

Build the Branch Manifest before synthesis with one row for the five analyst roles plus
every required adjudication. For a returned result, record branch identity, exact Harness
`status`, evidence outcome, blockers, and elapsed when available (`unavailable`
otherwise). When no Harness Result exists, retain the expected identity. Record
`status: unavailable (no result)` as a Product Pulse manifest sentinel, not a Harness
status; record evidence outcome `unproven`, blocker `missing Harness Result`, and elapsed
`unavailable`; count that row as unproven for coverage and exclude its claims. Only
accepted/proven branches whose verification seam Product Pulse reproduced may contribute
content. Keep every other expected branch in the manifest and exclude its claims.

After every required adjudication is accepted or explicitly excluded, invoke
`harness:delegate` with `operation: execute` and `route: taste` for the strategy draft.
Product Pulse remains the accepting workflow and writes the files only after validating
the returned Harness Result.

```yaml
operation: execute
route: taste
outcome: Produce a concise weekly strategy brief and recommendations draft grounded in accepted research and adjudications
context:
  project: {project_id}
  mode: fresh
  state: {complete branch manifest, accepted analyst briefs, accepted adjudications, excluded unresolved claims, last 7 daily reports, previous weekly direction, product context, configured repos, and corroboration notes}
  files: [{repository-relative accepted daily reports and prior strategy brief}]
  memory:
    enabled: {memory.connector is not null}
    recall: []
    capture:
      - when: accepted
        type: decision
        summary: Weekly strategy W{NN}: {theme in fewer than 80 characters}
        content: {proven theme, exactly three priorities, and key decisions}
        topics: [weekly-strategist, {project_id}-research, {project_id}, strategy]
authority:
  working_directory: {absolute primary repository root}
  allowed_paths: [{read-only paths named in context.files}]
  tools: [read-only inspection]
  approvals: []
constraints:
  - |
    Product Pulse weekly strategist:
    Identify one product-specific weekly theme. Set exactly 3 priorities; each must be
    achievable in one week, tied to evidence, identify the affected repo, and include a
    clear done definition. Only corroborated claims or accepted adjudications may drive
    a priority; exclude unresolved contested claims and preserve source citations,
    credibility caveats, dates, and confidence.
  - |
    Produce an opinionated strategy brief readable in 5 minutes plus recommendations:
    at most 5 Suggested for Speccing items with rationale, served priority, and size;
    Monitor Alerts; Quick Wins; Roadmap Notes; and 1-3 opportunities the daily scans
    might miss (cross-domain plays, timing-sensitive moves, audience expansion).
    Recommend only—do not promote, dismiss, or modify backlog items.
  - |
    Include the intended report paths {week_dir}/{YYYY}-W{NN}-strategy-brief.md and
    {week_dir}/{YYYY}-W{NN}-recommendations.md. Do not write or publish files.
  - |
    Report coverage as expected, accepted/proven, failed, blocked, abandoned, and
    unproven. Count an accepted/unproven result as unproven, not accepted. Mark degraded
    coverage whenever accepted/proven is fewer than expected. Never describe a failed,
    blocked, abandoned, unproven, or missing branch as scanned, researched, or covered.
verification:
  seam: Trace every theme, priority, alert, and recommendation to accepted cited evidence or adjudication and verify branch manifest totals, including no-result unproven classification, degraded-coverage disclosure, excluded claims, exact priority count, report sections, brevity, and report paths
  expected: The strategy brief and recommendations are evidence-grounded, decisive, complete, accurately disclose coverage, and ready for Product Pulse publication
```

Require `status: accepted` and `evidence.outcome: proven`, then reproduce the seam.

Before accepting, confirm the draft has one product-specific theme, exactly 3
evidence-tied priorities, and every recommendations section the packet requires.

---

## Phase 3: Write Output

### Determine paths

```
month = current month (YYYY-MM)
week = current ISO week (WNN)
week_dir = {research_dir}/{month}/W{NN}/
```

Create the directory if it doesn't exist.

### Write Strategy Brief

Write to `{week_dir}/{YYYY}-W{NN}-strategy-brief.md` using the template in `references/strategy-brief-template.md`.
Add this line immediately below the title: `Research Coverage: {accepted}/{expected}
accepted/proven; {failed} failed; {blocked} blocked; {abandoned} abandoned; {unproven}
unproven{ — degraded coverage when accepted < expected}`.

### Write Recommendations

Write to `{week_dir}/{YYYY}-W{NN}-recommendations.md` using the template in `references/recommendations-template.md`.

---

## Phase 4: Persist

### 4.1 Confirm optional memory enrichment

The Phase 2 taste request carries the weekly capture intent. After Product Pulse
reproduces its proof, retain any returned Harness memory identifiers in the run
summary. If memory is disabled or unavailable, continue with the brief and leave
those optional identifiers empty; do not call a provider directly.

### 4.2 Publish

Run § Publish in [Config_and_Publish.md](../../references/Config_and_Publish.md) with:

- `branch="weekly-brief/W{NN}"`
- `publish_path="$research_dir"`
- `title="strategy: weekly brief W{NN} — {theme short}"`
- `body="Weekly strategy brief and recommendations for W{NN}. Auto-generated by product-pulse weekly-strategist."`

It opens the PR with `gh pr create` and queues a squash merge only when `auto_merge` is true.

---

## Phase 5: Summary

```
Product Pulse — Weekly Strategy W{NN}
=======================================
Theme: {theme}
Priorities: {p1} | {p2} | {p3}
Research Coverage: {accepted}/{expected} accepted/proven; {failed} failed; {blocked} blocked; {abandoned} abandoned; {unproven} unproven{ — degraded coverage when accepted < expected}
Recommended for speccing: {N} items
Monitor alerts: {N}
Opportunities: {N} identified
PR: {pr_url} ({merged | open})
```
