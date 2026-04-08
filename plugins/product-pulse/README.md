# Product Pulse

A strategic intelligence plugin for [Claude Code](https://code.claude.com). Keeps your finger on the pulse of your market with automated research, weekly strategy briefs, and interactive sprint development.

## What It Does

Product Pulse is a **three-cadence system** that coordinates strategic thinking, daily intelligence, and focused implementation:

| Cadence | Skill | When | What |
|---------|-------|------|------|
| **Weekly** | `/product-pulse:weekly-strategist` | Monday mornings | 5 analyst agents scan the market, triage your backlog, set the week's direction |
| **Daily** | `/product-pulse:daily-research` | Every morning | Domain-specific research filtered through the weekly strategy |
| **On-demand** | `/product-pulse:sprint-dev` | When you're ready | Interactive implementation of tracker items with code review and testing |

### The Flow

```
Monday     Weekly Strategist sets direction + triages tracker
                    |
Tue-Sun    Daily Research gathers intel (filtered by weekly direction)
                    |
Anytime    Sprint Dev implements focused items (with your approval)
                    |
Next Mon   Weekly Strategist reads the week's research, adjusts course
```

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
├── research-tracker.md       # Action item backlog
├── deep-dives/               # Standalone research reports and evaluations
└── {YYYY-MM}/                # Month folders (created automatically)
    └── W{NN}/                # Week folders with daily reports + weekly briefs

```

## Skills

### `/product-pulse:setup`

One-time onboarding. Interviews you, scaffolds files, seeds sources.

### `/product-pulse:weekly-strategist`

Dispatches 5 analyst agents in parallel:
- **Market Scout** — Industry shifts, funding, regulation, tech trends
- **Competitor Tracker** — What competitors shipped or changed
- **Audience Analyst** — User signals, unmet needs, emerging segments
- **Growth Analyst** — Distribution channels, partnerships, content plays
- **Product Scout** — Feature gaps, new APIs, technical opportunities

Produces a strategy brief with:
- Week's theme and top 3 priorities
- Tracker triage (This Week / Backlog / Dismiss)
- Opportunities the daily scans might miss

### `/product-pulse:daily-research`

Scans configured research domains for actionable intelligence. Filters findings through the weekly strategy brief so only strategically relevant items land in your tracker. Caps at 5 new tracker items per day to prevent backlog bloat.

### `/product-pulse:sprint-dev`

Interactive implementation tool. Reads the weekly focus list, presents eligible items grouped into proposed PRs, and waits for your approval. Then dispatches sub-agents that:
1. Understand the item (reads research report context)
2. Plan the implementation
3. Write code (TDD where applicable)
4. Self-review (security, quality, correctness)
5. Run tests and build
6. Create the PR

You control what gets built and when.

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

Reports are organized by month and week — each week folder contains the strategy brief, focus list, and all daily reports for that week:

```
research/
├── 2026-04/
│   ├── W15/
│   │   ├── 2026-W15-strategy-brief.md
│   │   ├── 2026-W15-focus.md
│   │   ├── 2026-04-07-daily-research.md
│   │   └── 2026-04-08-daily-research.md
│   └── W16/
│       └── ...
├── 2026-05/
│   └── ...
├── research-context.md
├── research-sources.json
└── research-tracker.md
```

## Memory

Product Pulse saves findings and strategic decisions to Claude's memory system so context carries across sessions. It uses whatever memory mechanism is available — built-in project memory, or external tools if configured.

## License

MIT
