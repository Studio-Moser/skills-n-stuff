# PM

A backlog lifecycle plugin for [Claude Code](https://code.claude.com). Takes raw research and ideas from ingestion through triage, speccing, sprint execution, and reconciliation -- backed by GitHub Issues or a local YAML tracker.

[![skills.sh](https://skills.sh/b/Studio-Moser/skills-n-stuff)](https://skills.sh/Studio-Moser/skills-n-stuff)

## What It Does

PM is a **six-skill pipeline** that manages the full lifecycle of work items, from discovery through delivery:

| Skill | Role | When | What |
|-------|------|------|------|
| `/pm:setup` | Scaffolder | Once per workspace | Detects the workspace, loads only the selected backend reference, creates PM config and domain files, and stamps the shared agent baseline |
| `/pm:ingest` | Discoverer | After new research lands | Separates source evidence from proposed outcomes, deduplicates candidates, and files `status/needs-triage` items through the selected backend |
| `/pm:triage` | Classifier | When items need decisions | Verifies claims before design, prepares independently verifiable delivery slices, splits XL work under goal epics, scores, and promotes |
| `/pm:sprint-dev` | Builder | When you're ready to ship | Selects the unblocked frontier, treats shared-file overlap as scheduling collisions, and dispatches approved slices with named proof |
| `/pm:dev-task` | Pair-programmer | Implementing one focused change | Guides one approved delivery slice through implementation, evidence-backed review, and PR creation; works with or without `/pm:setup` |
| `/pm:reconcile` | Janitor | After sprints or merges | Completion tracking, stale detection, blocker classification, CONTEXT.md and ADR proposals |

### Two build modes

- **`/pm:sprint-dev`** — *work the backlog.* Selects unblocked ready slices, schedules collisions, then dispatches the approved PR set. Needs `/pm:setup` + a tracker.
- **`/pm:dev-task`** — *walk me through this one task.* Interactive and foreground, with approval gates around one bounded change. Works in any repo, no setup required.

Both defer to the shared `house-rules` skill for conventions.
New to the team workflow? See [How we do dev tasks](docs/how-we-do-dev-tasks.md).

### Readiness and proof

Two canonical references govern PM's shared decisions:

- [`references/work-readiness.md`](references/work-readiness.md) owns verified claims, testing seams, delivery slices, blockers, the unblocked frontier, and scheduling collisions.
- [`references/review-proof.md`](references/review-proof.md) owns the fixed review target, applicable review axes, evidence levels, and approval conditions.

Skills load those references only at the branch where their rules apply. This README describes the resulting behavior; the references own the definitions.

### Harness execution

PM is a workflow consumer of the [Harness contract](../harness/references/harness-contract.md).
It sends complete provider-neutral requests to `harness:execute` and
`harness:review`, selecting only the semantic route: `bulk` for clear-spec
mechanical work and scorecards, `quick` only for latency-sensitive steps, `taste`
for user-facing design/copy/API work, `review` for ordinary fixed-target review, and
explicitly approved `independent` for an adversarial fresh-context review.

PM supplies readiness, delivery-slice Outcomes, Blockers, Testing Seams, tracker and PR
constraints, plus the Quality, Spec Fidelity, and Blast Radius review axes. Harness
owns concrete routing, execution authority, fixed-target evidence, and the returned
Harness Result. PM reproduces the named proof before marking a delivery slice complete.

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
- **Triage** verifies reported behavior before design, prepares delivery slices, scores, and promotes (or rejects) with your approval
- **Sprint-dev** moves approved frontier items to `status/in-progress`, dispatches agents, and creates PRs
- **Reconcile** detects merged PRs and closes done items automatically

## Prerequisites

**Required:**

- [Harness](../harness/) configured through `/harness:setup` for provider-neutral
  execution and review. `/pm:setup` checks this dependency but does not configure it.

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
After backend selection, setup loads exactly the selected backend reference; GitHub, local, and Trello procedures are not loaded together.

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
| `epic` | Goal container grouping related issues -- carries no `status/*` label; body is a Goal/Why statement, not a checklist |
| `size/S` | Small: < 1 hour |
| `size/M` | Medium: 1--4 hours |
| `size/L` | Large: 4+ hours, needs spec |
| `size/XL` | Extra large: multi-day, needs spec + chunking |
| `sprint/*` | Optional sprint cohort tags (e.g. `sprint/2026-05-12`) -- documented for convention but not auto-set by the plugin |

### Sub-issues

Triage and reconcile use the GitHub sub-issues API to link child items to epics. If the API is unavailable (depends on your GitHub plan), they fall back to comment-based linking with `#N` references.

### Issue lifecycle via labels

Labels are the single source of truth for item state. Skills add and remove labels as items move through the pipeline -- you never need to manage labels manually.

## GitHub Project integration (optional)

PM can OPTIONALLY mirror your backlog into a [GitHub Projects v2](https://docs.github.com/en/issues/planning-and-tracking-with-projects) board. **Labels remain canonical** — the project is a downstream visualization that mirrors the `status/*` label set to a Project Status field. The plugin works perfectly without this; turn it on when you want a board/table UI with custom fields, timelines, and aggregated views across repos.

### What it gives you

- One board that shows every open backlog item, with a Status column matching the `status/*` taxonomy
- Custom fields (`Target date`, `Epic`) that GitHub Issues alone don't offer
- Multi-repo aggregation in a single view
- Saved views: Board by Status, Table by sprint label, P0 filter, triage queue, AI workspace, etc.

### Prerequisites

1. **Install the github MCP plugin** (Claude marketplace):

   ```
   /plugin install github@claude-plugins-official
   ```

2. **Generate a Personal Access Token** at https://github.com/settings/tokens. Required scopes:
   - `repo` — read issues
   - `project` — read/write Projects v2
   - `read:org` — needed for org-owned projects

3. **Add the token to `~/.claude/settings.json`** under the env section:

   ```json
   {
     "env": {
       "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_..."
     }
   }
   ```

4. **Reload Claude Code** (or restart the CLI) so the env var is picked up by the MCP server.

### What `/pm:setup` automates

When you opt in to the project step during `/pm:setup` Phase 6P (offered only when `backend: github`), the wizard:

- Creates a new Project (or links an existing one)
- Adds custom fields: `Target date` (DATE), `Epic` (TEXT)
- Links each repo in `target_repos`
- Bulk-adds every open issue from those repos as a project item
- Sets the Status field options to: `Needs Triage`, `Ready`, `In Progress`, `In Review`, `Blocked`, `Done`
- Sets each item's initial Status based on its current `status/*` label
- Writes the `github.project_sync` block to `.pm/config.yml`

### What you still do by hand

The MCP can't fully drive GitHub's Project UI. After setup, spend ~5 minutes in the project's web UI to:

#### 1. Enable built-in workflows

Project settings → Workflows. Turn on:

- **Auto-add to project** — choose your target repos so new issues land on the board automatically. Use a filter like `is:issue is:open` to skip PRs.
- **Item added to project** — set Status to `Needs Triage` (matches the default `status/needs-triage` label that `/pm:ingest` applies).
- **Item closed** — set Status to `Done`.
- **Pull request linked / merged** — these handle the `Ready → In Progress` and `In Review → Done` transitions automatically when a PR references the issue. This is the reason `/pm:sprint-dev` makes no MCP calls — GitHub does the right thing on its own.

#### 2. Create useful views

The default Board view comes free. Add these as saved views (click "+ New view"):

| View | Type | Filter / group |
|------|------|----------------|
| Board by Status | Board | Group by Status |
| Triage queue | Table | Filter `Status:"Needs Triage"`, sort by Created |
| AI workspace | Board | Filter `label:owner/ai`, group by Status |
| Operator tasks | Table | Filter `label:owner/operator`, group by Status |
| P0 / blockers | Table | Filter `label:priority/p0 OR label:blocker` |
| Current sprint | Board | Filter `label:sprint/{current}`, group by Status |
| Roadmap | Roadmap | Date field: `Target date`, group by Epic |

Adjust to taste — the views are personal and don't affect any plugin behavior.

### Day-to-day behavior

Once configured, `/pm:triage` and `/pm:reconcile` mirror `status/*` label changes to the Project's Status field automatically. The mirror is non-blocking — if the MCP server is unavailable for any reason, the label change still succeeds and the skill prints a one-time warning per session.

### Disabling sync

Either delete the `project_sync` block from `.pm/config.yml` or set `enabled: false`. The plugin reverts to label-only mode immediately.

### Config schema

```yaml
github:
  owner: Studio-Moser
  repo:  Shelby-Strategy
  project_sync:                 # entire block is optional
    enabled: true               # set to false to pause without deleting the block
    project_number: 2           # number from the project URL: /projects/{N}
    project_owner: Studio-Moser # org login or user login
    project_owner_type: org     # or "user"
    project_node_id: PVT_...    # cached GraphQL node id
    status_field_sync: true     # mirror status/* labels onto the Status field
    status_field_id: PVTSSF_... # cached field id
    status_map:
      status/needs-triage: "Needs Triage"
      status/ready:        "Ready"
      status/in-progress:  "In Progress"
      status/in-review:    "In Review"
      status/blocked:      "Blocked"
      status/done:         "Done"
```

See `plugins/pm/schemas/pm-config.github.example.yml` for the annotated reference.

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

Before promotion, triage applies the canonical checklist in [`references/triage-scorecard.md`](references/triage-scorecard.md) and the completion conditions from `work-readiness.md`. A numeric score cannot bypass a failed readiness gate. Fixable gaps can be corrected and re-scored; unresolved blockers or controlling hypotheses remain `status/needs-triage`.

## License

MIT
