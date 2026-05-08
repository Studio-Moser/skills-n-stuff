# Product Pulse

A strategic intelligence plugin for [Claude Code](https://code.claude.com). Keeps your finger on the pulse of your market with automated research, weekly strategy briefs, and interactive sprint development.

## What It Does

Product Pulse is a **three-cadence system** that coordinates strategic thinking, daily intelligence, and focused implementation:

| Cadence | Skill | Role | When | What |
|---------|-------|------|------|------|
| **Weekly** | `/product-pulse:weekly-strategist` | Advisor | Monday mornings | 5 analyst agents scan the market, review backlog, recommend items for speccing |
| **Daily** | `/product-pulse:daily-research` | Intelligence | Every morning | Domain-specific research filtered through the weekly strategy, adds ideas to backlog |
| **On-demand** | `/product-pulse:sprint-dev` | Executor | When you're ready | Implements ready items with freshness checks, code review, and testing |

### The Flow

```
Monday     Weekly Strategist reviews backlog + recommends items for speccing
                    |
Tue-Sun    Daily Research gathers intel (filtered by weekly direction)
                    |
You        Spec recommended items, promote to Ready when satisfied
                    |
Anytime    Sprint Dev implements ready items (with your approval)
                    |
Next Mon   Weekly Strategist reads the week's research, adjusts course
```

### Item Lifecycle

```
idea → specced → ready → in-progress → awaiting-pr → done
```

- **Daily Research** discovers ideas (max 5/day)
- **Weekly Strategist** recommends which ideas to spec (never promotes directly)
- **You** write specs and promote items to Ready
- **Sprint Dev** implements Ready items, checks spec freshness first

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

planning/
├── todos.md                  # Live work queue (Roadmap, Ready, Monitor, Manual, Done, Dismissed)
├── ideas.md                  # Incoming ideas staging (per-domain Ideas + Expired)
├── WORKFLOW.md               # Lifecycle documentation and role guide
├── archive/                  # Done rows older than 7 days, partitioned by quarter
└── specs/
    └── _TEMPLATE.md          # Spec template for L/XL items
```

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
  connector: shelby              # MCP tool-name prefix (e.g. shelby matches mcp__shelby-memory__*)
                                 # set to null to disable memory ops; default: shelby

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

The weekly-strategist and daily-research skills pull all configured repos at the start of every run. Sprint-dev routes implementation items to the correct target repo based on the backlog row's `target_repo` column.

## Skills

### `/product-pulse:setup`

One-time onboarding. Interviews you, scaffolds files, seeds sources, creates the `pulse-config.yaml`, the `planning/` folder, and the spec system.

### `/product-pulse:weekly-strategist`

Dispatches 5 analyst agents in parallel:
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

### `/product-pulse:sprint-dev`

Interactive implementation tool. Reads the weekly recommendations, presents eligible Ready items grouped into proposed PRs, and waits for your approval.

**Freshness checks**: Before proposing work, sprint-dev diffs each spec's Code References against their Base SHA:
- **Green** — no changes, proceed normally
- **Yellow** — minor drift (<20 lines), proceed with notes
- **Red** — significant divergence, skip and flag for re-spec

Then dispatches sub-agents that:
1. Read the spec (L/XL items follow Chunks order)
2. Plan the implementation
3. Write code (TDD where applicable)
4. Self-review (security, quality, correctness, spec compliance)
5. Run tests and build
6. Create the PR

You control what gets built and when.

## The Spec System

L/XL backlog items need a spec before promotion to Ready. Specs live at `planning/specs/{item-number}-{slug}.md` and include:

- **Goal** and **Context** — what and why
- **Code References with Base SHA** — enables freshness checking
- **Approach** and **Chunks** — how to implement, in what order
- **Acceptance Criteria** — what "done" looks like
- **Freshness Log** — tracks when specs were last validated

The template is scaffolded at `planning/specs/_TEMPLATE.md` during setup.

## Scheduling

Product Pulse works best with automated scheduling for the weekly and daily skills. Sprint-dev is always manual.

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
/product-pulse:sprint-dev
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

If `memory.connector` is configured in `pulse-config.yaml` (default: `shelby`), Product Pulse saves findings and strategic decisions to a memory MCP server so context carries across sessions. The plugin looks for MCP tools whose names match the configured prefix (e.g., `shelby` matches `mcp__shelby-memory__*`). Set `memory.connector: null` to disable memory ops entirely.

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
