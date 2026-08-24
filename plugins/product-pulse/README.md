# Product Pulse

A strategic intelligence plugin that keeps your finger on the pulse of your market with automated research, weekly strategy briefs, and deep-dive analysis.

> **Required control plane:** install and configure Harness first:
> `/plugin install harness@studio-moser`, then `/harness:setup`. Product Pulse
> sends routing, execution, review, and optional memory intent through Harness.
>
> **For project management** (triage, sprint execution, issue tracking), install
> Product Pulse and then the `pm` plugin:
> `/plugin install product-pulse@studio-moser` followed by
> `/plugin install pm@studio-moser`.

## What It Does

Product Pulse is a **three-cadence intelligence system** that coordinates strategic thinking, daily intelligence, and on-demand deep research:

| Cadence | Skill | Role | When | What |
|---------|-------|------|------|------|
| **Weekly** | `/product-pulse:weekly-strategist` | Advisor | Monday mornings | 5 analyst packets scan the market, review evidence, and recommend items for speccing |
| **Daily** | `/product-pulse:daily-research` | Intelligence | Every morning | Domain-specific research filtered through the weekly strategy, adds ideas to backlog |
| **On-demand** | `/product-pulse:deep-dive` | Analyst | When you need depth | Deep-dive research on specific resources — videos, articles, repos, docs |

### The Flow

```
Monday     Weekly Strategist reviews research + sets direction
                    |
Tue-Sun    Daily Research gathers intel (filtered by weekly direction)
                    |
Anytime    Deep Dive researches specific resources in depth
                    |
PM Plugin  /pm:ingest reads reports → /pm:triage specs items → /pm:sprint-dev builds
```

### Item Lifecycle

```
Product-pulse discovers → PM ingests → PM triages → PM builds
```

- **Daily Research** discovers ideas (max 5/day)
- **Weekly Strategist** recommends which ideas to spec (never promotes directly)

### Harness Boundary

Product Pulse owns research questions, source selection, credibility checks, citations, project comparison, synthesis, and report publication. It submits provider-neutral semantic requests and accepts only evidence-bearing results. Harness owns concrete routing, execution, and evidence mechanics.

Harness also owns the [universal project rules](../harness/references/house-rules.md);
Product Pulse does not duplicate those control-plane instructions.

## Prerequisites

Product Pulse skills shell out to `yq` to parse `pulse-config.yaml` at runtime. Install it before running any skill:

```bash
# macOS
brew install yq

# Linux
sudo snap install yq    # or use your distro's package manager
```

`gh` (GitHub CLI) is also required for the PR-based output flow used by `weekly-strategist` and `daily-research`. Install with `brew install gh` or follow [cli.github.com](https://cli.github.com).

## Setup

After installing, run the onboarding wizard:

```
/product-pulse:setup
```

This interviews you about your product, competitors, and strategic priorities, then scaffolds:

```
{research_dir}/
├── pulse-config.yaml         # Operational config (NEW in 0.2.0)
├── research-context.md       # Your product's identity and market position
├── research-sources.yaml     # Curated sources per research domain
├── deep-dives/               # Standalone research reports and evaluations
└── {YYYY-MM}/                # Month folders (created automatically by skills)
    └── W{NN}/                # Week folders with daily reports + weekly briefs

```

> **Project management**: For backlog tracking, triage, and sprint execution, install the [PM plugin](/plugins/pm/README.md) (`/plugin install pm@studio-moser`).

## Configuration

Operational config lives in `pulse-config.yaml`, placed in your research directory. The plugin walks up from your current working directory to find it — that file's parent IS the research directory. Casing is implicit from where the file lives (so `Research/pulse-config.yaml` and `research/pulse-config.yaml` both work, and outputs use the matching casing).

### Schema

```yaml
# Required
project_id: my-product           # used for memory tagging and brief metadata; lowercase-hyphenated

# Repos to operate on (length 1 = monorepo, length N = multi-repo)
# Paths are git-aware: `.` = the git repo containing this config file.
# `../<name>` = a sibling git repo on the filesystem.
repos:
  - name: my-product
    path: .
    role: primary                # exactly one entry must be 'primary'
  # If multi-repo, add entries:
  # - name: my-product-mobile
  #   path: ../my-product-mobile

# Optional with defaults
default_branch: main             # branch PRs target; default: main
auto_merge: true                 # auto-squash-merge research PRs if mergeable; default: true

memory:
  connector: shelby              # optional provider handled through Harness canonical scope
                                 # set to null to disable memory enrichment; default: shelby

backlog:
  active: planning/todos.md      # live work queue (relative to primary repo root); default shown
  ideas: planning/ideas.md       # idea staging (relative to primary repo root); default shown
```

### Multi-repo example

```yaml
project_id: shelby

repos:
  - name: Shelby-Strategy
    path: .
    role: primary
  - name: Shelby-MCP
    path: ../Shelby-MCP
  - name: Shelby-MacOS
    path: ../Shelby-MacOS
  - name: Shelby-Website
    path: ../Shelby-Website

default_branch: main
auto_merge: true

memory:
  connector: shelby

backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

The weekly-strategist and daily-research skills pull all configured repos at the start of every run.

## Skills

### `/product-pulse:setup`

One-time onboarding. Interviews you, scaffolds files, seeds sources, and creates the `pulse-config.yaml`.

### `/product-pulse:weekly-strategist`

Submits 5 independent `bulk` analyst requests through Harness:
- **Market Scout** — Industry shifts, funding, regulation, tech trends
- **Competitor Tracker** — What competitors shipped or changed
- **Audience Analyst** — User signals, unmet needs, emerging segments
- **Growth Analyst** — Distribution channels, partnerships, content plays
- **Product Scout** — Feature gaps, new APIs, technical opportunities

Produces a strategy brief PR (auto-mergeable when `auto_merge: true`) with:
- Week's theme and top 3 priorities
- Recommendations for which ideas to spec (max 5)
- Monitor alerts for approaching deadlines
- Backlog cleanup (dismissals, priority adjustments)

### `/product-pulse:daily-research`

Scans configured research domains for actionable intelligence. Filters findings through the weekly strategy brief so only strategically relevant items land in your backlog. Adds items as `idea` status only — never promotes beyond that. Caps at 5 new backlog items per day. Outputs go through a daily PR.

### `/product-pulse:deep-dive`

On-demand deep-dive research on specific external resources. Use when you need thorough analysis of a video, article, repo, or documentation page.

**When to use**: You explicitly ask for research or analysis on a specific resource — "research this repo", "analyze this article", "what does this video cover?"

**How it works**:
1. Transcribes videos (YouTube captions or audio)
2. Reads and extracts key content from articles and docs
3. Analyzes repos for architecture, patterns, and relevance
4. Compares findings to your project context
5. Produces a structured research report

**Output**: Report delivered in chat and saved to `{research_dir}/deep-dives/` as a dated markdown file. Creates a PR when configured.

## Scheduling

Product Pulse works best with automated scheduling for the weekly and daily skills. Deep-dive is always on-demand.

Use your `project_id` from `pulse-config.yaml` as the prefix for scheduled task IDs so memory tagging stays consistent across runs.

### Claude Code Scheduled Tasks

**Weekly Strategist** (Monday mornings):
- Task ID: `{project_id}-weekly-strategist`
- Schedule: Monday ~6:00 AM
- Prompt: `Run /product-pulse:weekly-strategist`

**Daily Research** (every morning):
- Task ID: `{project_id}-daily-research`
- Schedule: Daily ~8:00 AM
- Prompt: `Run /product-pulse:daily-research`

### Without Scheduling

Run any skill manually at any time:
```
/product-pulse:weekly-strategist
/product-pulse:daily-research
/product-pulse:deep-dive
```

## File Organization

Reports are organized by month and week — each week folder contains the strategy brief, recommendations, and all daily reports for that week:

```
{research_dir}/
├── pulse-config.yaml
├── research-context.md
├── research-sources.yaml
├── deep-dives/
├── 2026-04/
│   ├── W15/
│   │   ├── 2026-W15-strategy-brief.md
│   │   ├── 2026-W15-recommendations.md
│   │   ├── 2026-04-07-daily-research.md
│   │   └── 2026-04-08-daily-research.md
│   └── W16/
│       └── ...
└── 2026-05/
    └── ...

planning/
├── todos.md
├── ideas.md
├── WORKFLOW.md
├── archive/
│   └── done-2026-Q2.md
└── specs/
    ├── _TEMPLATE.md
    ├── 12-auth-revamp.md
    └── 15-api-v2.md
```

## Memory

If `memory.connector` is configured in `pulse-config.yaml` (default: `shelby`),
Product Pulse includes optional recall and capture intent in its Harness requests.
Harness resolves canonical project scope and any available provider; Product Pulse
never calls the provider directly. Set `memory.connector: null` to disable memory
enrichment entirely. Provider absence does not block file-based research.

## Migrating from 0.1.0

If your project was set up with a previous version of this plugin, hand-migrate as follows:

1. Rename `todos/` → `planning/`
2. Rename `planning/backlog.md` → `planning/todos.md`
3. Rename `planning/backlog-ideas.md` → `planning/ideas.md`
4. Convert `research/research-sources.json` → `research/research-sources.yaml` (use `yq -P 'sort_keys(..)' research-sources.json > research-sources.yaml` or equivalent)
5. Create `pulse-config.yaml` in your research directory using the schema above. Pull values from any "Configuration" section that may have existed in `research-context.md`, then remove that section (config now lives in `pulse-config.yaml`).
6. Update any internal cross-references in `CLAUDE.md`, `WORKFLOW.md`, or specs to use the new paths.
7. Re-run `/product-pulse:setup` if you want a guided walkthrough — it will detect existing files and offer to merge.

## License

MIT
