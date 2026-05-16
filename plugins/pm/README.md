# PM

A backlog lifecycle plugin for [Claude Code](https://code.claude.com). Takes raw research and ideas from ingestion through triage, speccing, sprint execution, and reconciliation -- backed by GitHub Issues or a local YAML tracker.

[![skills.sh](https://skills.sh/b/Studio-Moser/skills-n-stuff)](https://skills.sh/Studio-Moser/skills-n-stuff)

## What It Does

PM is a **five-skill pipeline** that manages the full lifecycle of work items, from discovery through delivery:

| Skill | Role | When | What |
|-------|------|------|------|
| `/pm:setup` | Scaffolder | Once per workspace | Detects workspace layout, wires GitHub Issues, creates `.pm/` config and domain knowledge files |
| `/pm:ingest` | Discoverer | After new research lands | Reads product-pulse reports, extracts actionable items, deduplicates, files `status/needs-triage` issues |
| `/pm:triage` | Classifier | When items need decisions | Sort (reject/dedup), spec (brainstorm + write plans), score (6-point checklist), promote |
| `/pm:sprint-dev` | Builder | When you're ready to ship | Picks ready items, groups into PRs, dispatches sub-agents with self-review and testing |
| `/pm:reconcile` | Janitor | After sprints or merges | Completion tracking, stale detection, blocker classification, CONTEXT.md and ADR proposals |

### The Flow

```
product-pulse                PM pipeline
─────────────                ───────────
daily-research ──reports──▸  /pm:ingest ──status/needs-triage──▸  /pm:triage
weekly-strategist ────────▸       │                                  │
deep-dives ───────────────▸       │              reject ◂────────────┤
                                  │              spec + score ───────┤
                                  │                                  │
                                  │            status/ready+owner/ai──▸  /pm:sprint-dev
                                  │                                       │
                                  │                              PRs ◂────┘
                                  │                               │
                                  └──────────────────────────▸  /pm:reconcile
                                                                  │
                                                     CONTEXT.md ◂─┤
                                                     ADRs ◂───────┤
                                                     close done ◂─┘
```

### Item Lifecycle

```
status/needs-triage → [reject → out-of-scope/]
                    → [spec → score → status/ready + owner/ai] → status/in-progress → status/in-review → status/done
```

- **Ingest** creates `status/needs-triage` items only -- never promotes beyond that
- **Triage** sorts, specs, scores, and promotes (or rejects) with your approval
- **Sprint-dev** moves items to `status/in-progress`, dispatches agents, creates PRs
- **Reconcile** detects merged PRs and closes done items automatically

## Prerequisites

**Required:**

```bash
# GitHub CLI — issue tracking, labels, PRs
brew install gh

# yq — YAML parsing for config files
brew install yq
```

**For the Trello backend (optional, in addition to yq):**

```bash
# jq — JSON processing for Trello config
brew install jq

# Trello API credentials
# Get a key at https://trello.com/app-key, then click "Token" on that page.
export TRELLO_API_KEY=...
export TRELLO_TOKEN=...
```

The `@delorenj/mcp-server-trello` server is fetched on demand by `npx -y` — no manual install required.

**Recommended:**

- [Product Pulse](../product-pulse/) -- provides the research reports that `/pm:ingest` reads. PM works without it (you can create `status/needs-triage` issues manually), but the two plugins are designed as a pair.

## Setup

Run the onboarding wizard once per workspace:

```
/pm:setup
```

This detects your workspace layout, interviews you about issue tracking preferences, and scaffolds:

```
.pm/
├── config.yml                # PM-specific config
├── out-of-scope/             # Rejection knowledge base
│   └── {slug}.md             # Why something was rejected (prevents re-filing)
└── state.yml                 # Ingestion watermarks and reconcile state

CONTEXT.md                    # Domain glossary — agents read this before working
docs/adr/
└── 0000-template.md          # Architecture Decision Record template
```

If `pulse-config.yaml` already exists (from Product Pulse setup), PM reads shared infrastructure from it. If not, setup creates a minimal one.

## Backends

PM supports three issue-tracking backends. Choose one in `/pm:setup`; switching later requires manual migration.

| Backend | Use when | What it stores | External deps |
|---|---|---|---|
| **GitHub Issues** (`github`) | You already use GitHub for code review and want issues alongside PRs | Issues, labels, sub-issues in your repo | `gh` CLI, `gh auth login` |
| **Trello** (`trello`) | Stakeholders work from a visual board, items are conversations not tickets, multi-board workspaces | Cards across one or more Trello boards with bidirectional status moves (e.g. done -> needs_changes -> in_progress) | `TRELLO_API_KEY`, `TRELLO_TOKEN`, `@delorenj/mcp-server-trello` (auto-fetched) |
| **Local markdown** (`local`) | Private/offline projects | YAML files in `.pm/items/` | none |

The Trello backend explicitly handles the moves Marv (moby_assistant) couldn't — `done -> needs_changes` and `needs_changes -> in_progress` are first-class via the `statuses` block in `.pm/config.yml`. See `plugins/pm/schemas/pm-config.trello.example.yml` for an annotated example.

Multi-board: Trello's `boards[]` array supports per-board `lists` mappings, `approval_steps`, `review_policy` (`self` / `judge` / `auto`), and `worker_instructions`. Cards stay on their home board; sprint-dev iterates every configured board on each pass.

## Configuration

PM uses two config files: a shared infrastructure file and a PM-specific file.

### Shared infrastructure: `pulse-config.yaml`

Lives in your research directory. Shared with Product Pulse. Provides project identity, repo layout, and memory config:

```yaml
project_id: my-product
repos:
  - name: my-product
    path: .
    role: primary
default_branch: main
memory:
  connector: shelby
backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

### PM-specific: `.pm/config.yml`

Lives in the primary repo root. Controls backend, research directories, and triage behavior:

```yaml
backend: github                 # github | local
github:
  owner: Studio-Moser           # GitHub org or user
  repo: Shelby-Strategy         # Primary repo for issues
research_dirs:                  # Where to look for product-pulse reports
  - Research
  - Research/deep-dives
triage:
  stale_threshold_days: 30      # Days before a status/in-progress item is flagged stale
context_md: CONTEXT.md          # Path to domain glossary (relative to repo root)
adr_dir: docs/adr               # Path to ADR directory
out_of_scope_dir: .pm/out-of-scope  # Rejection knowledge base
```

All paths are relative to the primary repo root.

## GitHub Issues Integration

PM uses GitHub Issues as its backend, with labels driving the workflow state machine.

### Labels

Setup creates these labels automatically via `gh label create`:

PM uses a namespaced label taxonomy split across **status**, **owner**, **priority**, **size**, and **flags**. Status and owner together describe an item's position in the pipeline; the rest are orthogonal.

| Label | Purpose |
|-------|---------|
| `status/needs-triage` | New issue awaiting classification |
| `status/ready` | Triaged, specced, scored -- ready to be picked up (pair with an `owner/*` label) |
| `status/in-progress` | Currently being worked on |
| `status/in-review` | PR open, awaiting merge |
| `status/done` | Shipped and closed |
| `owner/ai` | An AI agent (via `/pm:sprint-dev`) is the intended worker |
| `owner/human` | A human is the intended worker (judgment, design call, manual work) |
| `owner/operator` | Needs Tim's hands -- ops/manual steps (not automatable) |
| `priority/p0` | Drop-everything blocker |
| `priority/p1` | High priority, this sprint |
| `priority/p2` | Normal |
| `priority/p3` | Low / someday |
| `blocker` | Blocks other work -- escalate (urgency flag, orthogonal to status) |
| `spawned-during-sprint` | Filed by a sub-agent during sprint execution |
| `epic` | Groups related issues under a parent |
| `size/S` | Small: < 1 hour |
| `size/M` | Medium: 1--4 hours |
| `size/L` | Large: 4+ hours, needs spec |
| `size/XL` | Extra large: multi-day, needs spec + chunking |
| `sprint/*` | Optional sprint cohort tags (e.g. `sprint/2026-05-12`) -- documented for convention but not auto-set by the plugin |

### Sub-issues

Triage and reconcile use the GitHub sub-issues API to link child items to epics. If the API is unavailable (depends on your GitHub plan), they fall back to comment-based linking with `#N` references.

### Issue lifecycle via labels

Labels are the single source of truth for item state. Skills add and remove labels as items move through the pipeline -- you never need to manage labels manually.

## Domain Knowledge

PM maintains three types of domain knowledge that agents read before doing work:

### CONTEXT.md

A structured glossary at the repo root. Contains:

- **Terms** -- canonical names and definitions with aliases to avoid
- **Relationships** -- how concepts relate to each other
- **Ambiguities** -- terms that are easily confused, with resolutions

Reconcile proposes additions when it encounters new terms in merged PRs. Sprint-dev reads this before dispatching sub-agents so they use consistent terminology.

### Architecture Decision Records (ADRs)

Live in `docs/adr/`. Follow a standard template: Context, Decision, Consequences (positive, negative, neutral). Reconcile proposes new ADRs when it detects architectural shifts in merged code.

### Out-of-scope rejections

Live in `.pm/out-of-scope/`. Each file records what was rejected and why, plus a log of prior requests for the same thing. Ingest checks this directory before filing new items -- if a finding matches an existing rejection, it skips it. Triage adds new entries when you reject items.

This prevents the same idea from being re-filed every time a research report mentions it.

## Multi-repo

PM supports multi-repo workspaces where a primary repo holds planning artifacts and sibling repos hold implementation targets.

### The workspace pattern

```
~/Projects/my-product/
├── pulse-config.yaml           # Shared config (lists all repos)
├── CONTEXT.md                  # Domain glossary
├── docs/adr/                   # Architecture decisions
├── My-Product-Strategy/        # Primary — has .pm/, planning/, Research/
│   ├── .pm/config.yml
│   ├── planning/
│   └── Research/
├── My-Product-App/             # Target repo (receives PRs)
├── My-Product-API/             # Target repo
└── My-Product-Website/         # Target repo
```

### How it works

- **Issues live in the primary repo** by default, with labels indicating which target repo the work belongs to
- **Sprint-dev routes PRs** to the correct target repo based on the issue's code references
- **Reconcile scans git history** across all configured repos when detecting completions
- **Labels sync** across repos if you opt in during setup

Each spec's "Code References" section specifies the target repo, so sub-agents know where to work. The agent-ready scorecard enforces that each item targets a single repo (criterion 5: bounded scope).

## Pairing with Product Pulse

PM and Product Pulse are designed as a pair. Product Pulse handles intelligence -- PM handles execution.

| Concern | Product Pulse | PM |
|---------|--------------|-----|
| Research | Daily research, weekly strategy, deep-dives | -- |
| Discovery | Identifies ideas, adds to backlog | Ingests reports, files issues |
| Planning | Recommends items for speccing | Sorts, specs, scores, promotes |
| Execution | -- | Dispatches sub-agents, creates PRs |
| Maintenance | -- | Closes done items, flags stale work, proposes ADRs |
| Config | Owns `pulse-config.yaml` | Reads shared config, owns `.pm/config.yml` |

### Without Product Pulse

PM works standalone. Instead of running `/pm:ingest` to process research reports, create `status/needs-triage` issues manually in GitHub. The rest of the pipeline (triage, sprint-dev, reconcile) operates the same way.

### The combined flow

```
Mon     /product-pulse:weekly-strategist → strategy brief
Tue-Sun /product-pulse:daily-research    → daily reports
        /pm:ingest                       → status/needs-triage issues
        /pm:triage                       → reject, spec, score, promote
        /pm:sprint-dev                   → PRs
        /pm:reconcile                    → close done, flag stale, propose ADRs
Next Mon  cycle repeats
```

## Agent-Ready Scorecard

Before an item can be promoted to `status/ready` + `owner/ai`, triage scores it against a 6-point checklist:

1. **Clear description** -- states what, not how
2. **Explicit acceptance criteria** -- measurable conditions for done
3. **Linked code references** -- file paths with target repo specified
4. **Negative constraints** -- cross-references `.pm/out-of-scope/` for what NOT to do
5. **Bounded scope** -- single deliverable, one repo
6. **No open design questions** -- all ambiguity resolved before execution

Items that fail any criterion can be fixed inline during triage and re-scored. Items that pass all six are promoted to `status/ready` + `owner/ai`. Items with unfixable failures are promoted to `status/ready` + `owner/human` instead.

## License

MIT
