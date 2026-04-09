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

## Setup

After installing, run the onboarding wizard:

```
/product-pulse:setup
```

This interviews you about your product, competitors, and strategic priorities, then scaffolds:

```
{research_dir}/
├── research-context.md       # Your product's identity and market position
├── research-sources.json     # Curated sources per research domain
├── deep-dives/               # Standalone research reports and evaluations
└── {YYYY-MM}/                # Month folders (created automatically)
    └── W{NN}/                # Week folders with daily reports + weekly briefs

todos/
├── backlog.md                # Unified backlog with all item statuses
├── WORKFLOW.md               # Lifecycle documentation and role guide
└── specs/
    └── _TEMPLATE.md          # Spec template for L/XL items
```

## Skills

### `/product-pulse:setup`

One-time onboarding. Interviews you, scaffolds files, seeds sources, creates the backlog and spec system.

### `/product-pulse:weekly-strategist`

Dispatches 5 analyst agents in parallel:
- **Market Scout** — Industry shifts, funding, regulation, tech trends
- **Competitor Tracker** — What competitors shipped or changed
- **Audience Analyst** — User signals, unmet needs, emerging segments
- **Growth Analyst** — Distribution channels, partnerships, content plays
- **Product Scout** — Feature gaps, new APIs, technical opportunities

Produces a strategy brief with:
- Week's theme and top 3 priorities
- Recommendations for which ideas to spec (max 5)
- Monitor alerts for approaching deadlines
- Backlog cleanup (dismissals, priority adjustments)

### `/product-pulse:daily-research`

Scans configured research domains for actionable intelligence. Filters findings through the weekly strategy brief so only strategically relevant items land in your backlog. Adds items as `idea` status only — never promotes beyond that. Caps at 5 new backlog items per day.

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

L/XL backlog items need a spec before promotion to Ready. Specs live at `todos/specs/{item-number}-{slug}.md` and include:

- **Goal** and **Context** — what and why
- **Code References with Base SHA** — enables freshness checking
- **Approach** and **Chunks** — how to implement, in what order
- **Acceptance Criteria** — what "done" looks like
- **Freshness Log** — tracks when specs were last validated

The template is scaffolded at `todos/specs/_TEMPLATE.md` during setup.

## Scheduling

Product Pulse works best with automated scheduling for the weekly and daily skills. Sprint-dev is always manual.

### Claude Code Scheduled Tasks

**Weekly Strategist** (Monday mornings):
- Task ID: `{project}-weekly-strategist`
- Schedule: Monday ~6:00 AM
- Prompt: `Run /product-pulse:weekly-strategist`

**Daily Research** (every morning):
- Task ID: `{project}-daily-research`
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
research/
├── 2026-04/
│   ├── W15/
│   │   ├── 2026-W15-strategy-brief.md
│   │   ├── 2026-W15-recommendations.md
│   │   ├── 2026-04-07-daily-research.md
│   │   └── 2026-04-08-daily-research.md
│   └── W16/
│       └── ...
├── 2026-05/
│   └── ...
├── research-context.md
└── research-sources.json

todos/
├── backlog.md
├── WORKFLOW.md
└── specs/
    ├── _TEMPLATE.md
    ├── 12-auth-revamp.md
    └── 15-api-v2.md
```

## Memory

Product Pulse saves findings and strategic decisions to Claude's memory system so context carries across sessions. It uses whatever memory mechanism is available — built-in project memory, or external tools if configured.

## License

MIT
