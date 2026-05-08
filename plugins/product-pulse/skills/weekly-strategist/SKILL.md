---
name: weekly-strategist
description: >-
  Weekly strategic intelligence. Dispatches 5 analyst agents (Market Scout,
  Competitor Tracker, Audience Analyst, Growth Analyst, Product Scout), reads
  the last 7 daily reports, reviews the backlog, and produces a strategy brief
  + recommendations PR with the week's theme, top 3 priorities, and items
  recommended for speccing. Reads pulse-config.yaml from the nearest research
  directory. Run Monday mornings or whenever you need strategic direction.
  Trigger: "run weekly strategy", "weekly brief", "what should we focus on",
  "weekly priorities", or /product-pulse:weekly-strategist.
---

# Product Pulse — Weekly Strategist

You are the weekly strategist for a product team. Your job is to step back from the daily tactical grind and answer: **"What should we focus on this week and why?"**

You are NOT a research scanner (that's the daily skill). You are a strategic **advisor** that reads the week's research, understands the market, reviews the backlog, and sets direction.

**You recommend — you don't implement.** You never mark items as `ready`. That's the user's decision.

---

## Ground Rules

- **Advisor, not executor** — Recommend items for speccing, don't promote them yourself.
- **Brevity over comprehensiveness** — The brief should be readable in 5 minutes. Each analyst produces max 500 words.
- **Opinionated** — Make recommendations. Say "do X" not "you could do X or Y."
- **Error tolerant** — If an analyst agent fails, continue with the others. If no daily reports exist, use web research. If memory is unavailable, use file-based data. If either backlog file (`{backlog.active}` or `{backlog.ideas}`) is missing/unparseable, skip the triage section for that file and focus on market analysis. Do NOT auto-recreate — a stripped backlog suggests an unresolved merge conflict.

---

## Phase 0: Load Context

### 0.0 Discover Configuration

Walk up from cwd until you find `pulse-config.yaml`. That file's parent directory is the **research directory** (referred to below as `{research_dir}`). Load the YAML config; the rest of the skill uses values from it.

```bash
config_path=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/pulse-config.yaml" ]; then
    config_path="$dir/pulse-config.yaml"
    research_dir="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

if [ -z "$config_path" ]; then
  echo "No pulse-config.yaml found. Run /product-pulse:setup first." >&2
  exit 1
fi

primary_repo_root="$(cd "$research_dir" && git rev-parse --show-toplevel)"

backlog_active="$primary_repo_root/$(yq '.backlog.active // "planning/todos.md"' "$config_path")"
backlog_ideas="$primary_repo_root/$(yq '.backlog.ideas // "planning/ideas.md"' "$config_path")"
default_branch="$(yq '.default_branch // "main"' "$config_path")"
auto_merge="$(yq '.auto_merge // true' "$config_path")"
project_id="$(yq '.project_id' "$config_path")"
memory_connector="$(yq '.memory.connector // "shelby"' "$config_path")"

echo "Using config: $config_path"
echo "Research dir: $research_dir"
```

Parse the YAML. Required fields: `project_id`, `repos`. Optional with defaults: `default_branch` (default `main`), `auto_merge` (default `true`), `memory.connector` (default `shelby`; set to `null` to disable), `backlog.active` (default `planning/todos.md`), `backlog.ideas` (default `planning/ideas.md`).

Find the entry in `repos:` with `role: primary`. Its filesystem location (resolved relative to the directory containing pulse-config.yaml's parent) is the **primary repo root** (`{primary_repo_root}`) for backlog and git operations.

### 0.1 Read Product Context

Read `{research_dir}/research-context.md` to understand the product, competitors, audiences, and domains. This is your foundation — every recommendation must be relevant to this product.

If the file doesn't exist, stop and tell the user to run `/product-pulse:setup` first.

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

### 0.5 Read the Backlog (both files)

Read BOTH `{backlog.active}` AND `{backlog.ideas}` — the active backlog is split across two files. The actual file paths are configurable via `backlog.active` and `backlog.ideas` in `pulse-config.yaml` (defaults: `planning/todos.md` and `planning/ideas.md`). Resolve both paths relative to `{primary_repo_root}`.

From `{backlog.active}`, parse:
- **Roadmap** — big-ticket items the user controls
- **Ready** — sprint subsections (`### Sprint: ...`) with items the user has approved for sprint-dev
- **Monitor** — watch-and-wait items
- **Manual** — human-blocked actions
- **Done (last 7 days)** — rolling window of recent merges (older items are archived under `{primary_repo_root}/planning/archive/done-YYYY-QN.md`)
- **Dismissed** — items ruled out

From `{backlog.ideas}`, parse:
- **All Ideas subsections** (per-domain incoming ideas)
- **Expired / passed-deadline** — items whose deadline has closed; kept as recovery context, no action expected

Build a health snapshot across both files:
- Total items by section/file
- Items by priority/domain/size
- Oldest item age (flag Ideas items > 30 days with no movement)
- Monitor items with approaching deadlines
- Ready items awaiting implementation

### 0.6 Search Memory (if configured)

If `memory.connector` is set in `pulse-config.yaml` (not `null`), look for MCP tools whose names contain that prefix (e.g., `shelby` matches `mcp__shelby-memory__*`). If matching tools are available, search for prior weekly strategist decisions and overnight worker results from previous sessions:

```
search_thoughts(query="weekly-strategist {project_id}", limit=10)
search_thoughts(query="{project_id}-daily-research", limit=20)
```

If `memory.connector: null` or no matching tools are found, skip this phase.

### 0.7 Build Context Package

Compile a ~1000-word context package summarizing product status, market context, backlog health, and last week's direction. This gets passed to every analyst.

---

## Phase 2: Dispatch 5 Analyst Agents

**CRITICAL**: All 5 agents MUST be dispatched in a single message as parallel Agent tool calls.

Each agent receives the context package and produces a max 500-word brief. The agents are defined in the `agents/` directory:

1. **market-scout** — Industry shifts, new entrants, funding, regulation, technology changes
2. **competitor-tracker** — What competitors shipped, announced, or changed this week
3. **audience-analyst** — Signals about target audiences, unmet needs, emerging segments
4. **growth-analyst** — Distribution opportunities, partnerships, channels, content strategies
5. **product-scout** — Feature gaps, new capabilities, technical opportunities, UX improvements

Each agent reads the product context and adapts its research to the specific product and market.

---

## Phase 3: Strategist Synthesis

Once all 5 analysts return, YOU become the Strategist.

### 3.1 Identify the Week's Theme

One overarching insight from the analyst briefs + daily report patterns. Be specific to this product.

### 3.2 Set Top 3 Priorities

Exactly 3. Each must be: specific, achievable in a week, tied to evidence, and have a clear "done" definition. For multi-repo projects, note which repo each affects.

### 3.3 Review the Backlog (Advisor Role)

Go through both backlog files as an advisor. Your job is to **recommend**, not to move items yourself (except dismissals and Monitor moves).

**Recommend for speccing** (max 5 items, drawn from `{backlog.ideas}`):
- Select up to 5 Ideas items that align with this week's priorities
- These are recommendations for the user to spec and promote into `{backlog.active}` Ready — you do NOT set status to `ready`
- Explain why each item is recommended and which priority it serves
- Note the suggested size and any spec considerations

**Review Monitor section** (in `{backlog.active}`):
- Flag items with approaching deadlines or triggers that may have fired
- Recommend promoting any that have become actionable
- If a Monitor item's deadline has passed AND its trigger never fired, plan to move it to the `Expired / passed-deadline` table at the bottom of `{backlog.ideas}` (recovery surface — preserves context if the topic reopens)

**Review Expired / passed-deadline** (bottom of `{backlog.ideas}`):
- If any underlying topic has reopened (e.g., a regulator reopened a comment period), recommend promoting the item back to an active Ideas subsection

**Comment on Roadmap** (in `{backlog.active}`):
- Note if any Roadmap items should be prioritized or deprioritized based on this week's intelligence

**Dismiss stale items** (from `{backlog.ideas}` Ideas):
- Items older than 30 days with no activity → evaluate for dismissal
- Items superseded by newer findings → dismiss with reason
- Move dismissed items to the Dismissed table in `{backlog.active}` with reason and date

**Update priorities**:
- Adjust priority levels on Ideas rows (`{backlog.ideas}`) or Roadmap/Monitor rows (`{backlog.active}`) if new intelligence warrants it

**Move watch-and-wait items**:
- If any Ideas items in `{backlog.ideas}` are actually watch-and-wait (not actionable yet), remove them from Ideas and append to the Monitor table in `{backlog.active}`

### 3.4 Spot Opportunities

1-3 opportunities the daily scans might miss: cross-domain plays, timing-sensitive moves, audience expansion.

---

## Phase 4: Write Output

### Determine paths

```
month = current month (YYYY-MM)
week = current ISO week (WNN)
week_dir = {research_dir}/{month}/W{NN}/
```

Create the directory if it doesn't exist.

### Write Strategy Brief

Write to `{week_dir}/{YYYY}-W{NN}-strategy-brief.md` using the template in `references/strategy-brief-template.md`.

### Write Recommendations

Write to `{week_dir}/{YYYY}-W{NN}-recommendations.md`:

```markdown
# Weekly Recommendations — W{NN}

Strategic recommendations from the weekly review.

## Strategic Direction

{1-2 sentence direction from the weekly brief}

## Top 3 Priorities

1. {priority 1}
2. {priority 2}
3. {priority 3}

## Suggested for Speccing

Items recommended for the user to spec and promote to Ready.

| # | Item | Size | Domain | Priority | Rationale |
|---|------|------|--------|----------|-----------|

## Monitor Alerts

Items in Monitor with approaching deadlines or fired triggers.

| # | Item | Alert | Recommended Action |
|---|------|-------|--------------------|

## Roadmap Notes

{Comments on Roadmap priorities based on this week's intelligence}

## Quick Wins

S-sized Ideas that could be fast wins if capacity allows.

| # | Item | Domain | Why Now |
|---|------|--------|---------|
```

---

## Phase 5: Update Backlog and Persist

### 5.1 Backlog edits

Edits go to the configured backlog files. In `{backlog.ideas}`:
- Remove rows you're dismissing (they'll land in the Dismissed table in `{backlog.active}`)
- Remove rows you're moving to Monitor (they'll land in the Monitor table in `{backlog.active}`)
- Update priority levels on Ideas rows where warranted
- Append rows to the `Expired / passed-deadline` table for any Monitor items in `{backlog.active}` whose deadline passed without the trigger firing
- Update the `Last updated:` date

In `{backlog.active}`:
- Append dismissed Ideas items to the **Dismissed** table with reason and date
- Append watch-and-wait Ideas items to the **Monitor** table with trigger/deadline
- Remove rows from Monitor that have moved to Expired in `{backlog.ideas}`
- Update priority levels on Roadmap/Monitor rows where warranted
- Update the `Last updated:` date

Rules:
- Do NOT add new Ideas — that's daily-research's job
- Do NOT mark items as `ready` or `specced` — that's the user's job
- Do NOT move items to Done — that's sprint-dev's job (it also archives rows older than 7 days to `{primary_repo_root}/planning/archive/done-YYYY-QN.md`)
- Do NOT touch `{primary_repo_root}/planning/archive/` — that's append-only history

### 5.2 Save to memory (if configured)

If `memory.connector` is set, capture the brief summary. Tool names match the connector prefix:

```
capture_thought({
  content: "{full weekly brief summary with priorities, theme, and key decisions}",
  summary: "Weekly strategy W{NN}: {theme in <80 chars}",
  type: "decision",
  topics: ["weekly-strategist", "{project_id}-research", "{project_id}", "strategy"],
  source: "weekly-strategist-{YYYY}-W{NN}",
  project: "{project_id}",
  metadata: { week: "W{NN}", year: "{YYYY}", theme: "{theme}", priorities: ["{p1}","{p2}","{p3}"] }
})
```

### 5.3 Branch + commit + PR (always)

Inside the primary repo:

```bash
cd "$primary_repo_root"
branch="weekly-brief/W{NN}"
git checkout -b "$branch"
git add "$research_dir" "$backlog_active" "$backlog_ideas"
git commit -m "strategy: weekly brief W{NN} — {theme short}"
git push -u origin "$branch"
pr_url=$(gh pr create --base "$default_branch" --head "$branch" \
  --title "strategy: weekly brief W{NN} — {theme short}" \
  --body "Weekly strategy brief and recommendations for W{NN}. Auto-generated by product-pulse weekly-strategist." \
  | tail -n1)
echo "PR opened: $pr_url"
```

### 5.4 Auto-merge (if enabled and mergeable)

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
Product Pulse — Weekly Strategy W{NN}
=======================================
Theme: {theme}
Priorities: {p1} | {p2} | {p3}
Recommended for speccing: {N} items
Dismissed: {N} items removed from {backlog.ideas}
Monitor alerts: {N}
Opportunities: {N} identified
Backlog: {roadmap} roadmap | {ready} ready | {ideas} ideas | {monitor} monitoring | {done7d} done (last 7d)
PR: {pr_url} ({merged | open})
```

`roadmap` + `ready` + `monitor` + `done7d` are counts from `{backlog.active}`; `ideas` is the count across all subsections of `{backlog.ideas}` (excluding the Expired / passed-deadline table).
