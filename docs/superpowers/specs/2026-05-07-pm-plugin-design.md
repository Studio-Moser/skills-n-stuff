# PM plugin + product-pulse restructuring

**Date:** 2026-05-07
**Status:** Design — pending implementation plan
**Affects:** `skills-n-stuff/plugins/pm` (new), `skills-n-stuff/plugins/product-pulse`, `skills-n-stuff/plugins/research-scout` (deprecated)

## Background

The `product-pulse` plugin grew organically to cover three concerns: intelligence gathering (daily-research, weekly-strategist), project management (backlog lifecycle, spec system), and execution (sprint-dev). These are different jobs. Intelligence gathering is automated and opinionated — the skill decides what to research and how to filter. Project management is interactive and human-gated — the user decides what to build and when. Mixing them in one plugin means the backlog management code is duplicated across three skills, the triage step (turning rough ideas into agent-ready specs) is entirely manual, and there's no integration with external issue trackers.

Meanwhile, `research-scout` is a standalone deep-dive research plugin that shares the same infrastructure concerns as product-pulse (output directories, git flow, memory, backlog integration) but maintains its own parallel config story. Every project that uses both plugins configures the same things twice.

This spec splits the system into two focused plugins:

- **product-pulse** — Intelligence gathering only. Daily scans, weekly strategy, deep-dive research (absorbing research-scout). Produces report files. No longer owns the backlog or sprint execution.
- **pm** — Project management. Owns the backlog lifecycle from ingestion through execution. Reads product-pulse reports, triages items, manages specs, handles sprint execution, syncs with GitHub Issues.

## Goals

1. Create a `pm` plugin that owns the full project management lifecycle: ingestion, triage, reconciliation, sprint execution.
2. Strip product-pulse down to pure intelligence — remove sprint-dev, remove backlog editing from daily/weekly skills.
3. Absorb research-scout into product-pulse as a fourth skill (`deep-dive`), eliminating a standalone plugin.
4. Add GitHub Issues integration as the primary backend, with local markdown as a fallback.
5. Automate the triage step: take rough ideas through spec-writing (brainstorming → writing-plans) and agent-ready scoring.
6. Handle deferred blockers — tasks spawned mid-sprint by AI agents that block the parent from shipping.
7. Add domain knowledge management: CONTEXT.md glossary, ADRs, out-of-scope rejection KB.
8. Multi-repo from day one, matching the Shelby workspace pattern (parent directory with N independent git repos).

## Non-Goals

1. Not building a Linear adapter in v1. GitHub Issues first; Linear when someone needs it.
2. Not building auto-scheduling or sprint planning AI. The user picks what to build.
3. Not building Kanban views or dashboards. Use GitHub Projects UI directly.
4. Not building notifications or webhooks.
5. Not changing the research cadence model (daily/weekly/deep-dive). Product-pulse's intelligence architecture is fine.
6. Not migrating existing consuming repos (Shelby-Strategy, TCL) in this spec — that's a separate follow-up after both plugins ship.

## Architecture

### Plugin separation

```
product-pulse (intelligence)          pm (project management)
├── setup                             ├── setup
├── daily-research                    ├── ingest
├── weekly-strategist                 ├── triage
└── deep-dive (was research-scout)    ├── reconcile
                                      └── sprint-dev (was in product-pulse)
```

Product-pulse produces files (reports, briefs, recommendations). PM reads those files and manages the work lifecycle. They share infrastructure config via `pulse-config.yaml`.

### Config story

Two config files, one shared:

**`pulse-config.yaml`** (shared infrastructure — already exists from product-pulse v0.2.0):
```yaml
project_id: shelby
repos:
  - name: Shelby-Strategy
    path: .
    role: primary
  - name: Shelby-MacOS
    path: ../Shelby-MacOS
default_branch: main
auto_merge: true
memory:
  connector: shelby
backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

PM reads `pulse-config.yaml` for `project_id`, `repos`, `default_branch`, `memory`, and `backlog` paths. If product-pulse isn't installed, PM:setup creates a minimal `pulse-config.yaml` itself so the shared infrastructure works standalone.

**`.pm/config.yml`** (PM-specific — new):
```yaml
# Issue tracker backend
backend: github  # github | local
github:
  # Owner and repo are inferred from the primary repo's git remote
  # unless overridden here:
  # owner: Studio-Moser
  # repo: Shelby-Strategy

# Where to find research reports for ingestion
# Relative to primary repo root
research_dirs:
  - Research
  - Research/deep-dives

# Triage settings
triage:
  stale_threshold_days: 30

# Domain knowledge paths (relative to workspace root or primary repo root)
context_md: CONTEXT.md
adr_dir: docs/adr
```

### Data flow

```
product-pulse:daily-research ──→ report files ──→ pm:ingest ──→ needs-triage items
product-pulse:weekly-strategist ──→ brief + recommendations ──→ pm:ingest
product-pulse:deep-dive ──→ deep-dive report ──→ pm:ingest
                                                      │
                                                      ▼
                                               pm:triage
                                          (spec, score, promote)
                                                      │
                                              ┌───────┴───────┐
                                              ▼               ▼
                                        ready-for-agent   .pm/out-of-scope/
                                              │
                                              ▼
                                        pm:sprint-dev
                                        (implement, PR)
                                              │
                                              ▼
                                        pm:reconcile
                                   (done, stale, blockers)
```

### Backend abstraction

```
Skills → BackendAdapter interface → GitHubAdapter (v1)
                                  → LocalAdapter (markdown files, offline/private)
```

**BackendAdapter interface** (what each adapter implements):
- `createItem(title, body, labels, parent?)` → item ID
- `updateItem(id, fields)`
- `listItems(filters)` → items
- `getItem(id)` → item
- `addSubItem(parent, child)`
- `listSubItems(parent)` → items
- `addLabel(id, label)`
- `closeItem(id)`
- `getProgress(parent)` → `{total, done, blocked}`

GitHub adapter uses `gh` CLI exclusively — no API tokens beyond existing `gh auth` needed. Sub-issues via `gh api` GraphQL (GitHub sub-issues are GA since March 2025, up to 8 levels deep, 100 children per parent).

Local adapter stores items as YAML files in `.pm/items/` for repos without external trackers.

### Item lifecycle

The lifecycle from product-pulse v0.2.0 carries forward with one addition — `needs-triage` as the entry point from ingestion:

```
needs-triage → [reject → .pm/out-of-scope/]
             → [spec it → specced]
             → [small enough → ready directly]
             → ready → in-progress → awaiting-pr → done
```

The existing `idea` status in `planning/ideas.md` maps to `needs-triage` in the issue tracker. When PM:ingest reads reports, it creates items with `needs-triage`. PM:triage processes them.

### Deferred blocker handling

AI agents frequently spawn sub-tasks during implementation rather than doing them inline. These need classification:

- **Blocking** — parent can't ship without this. Gets `blocker` label + linked as sub-issue of parent.
- **Independent** — related but separable. Goes to `needs-triage` as a new item.

PM:reconcile scans for items spawned during the current sprint (tagged `spawned-during-sprint` or linked as sub-issues of in-progress work) and classifies them. Blocking chains are reported: "Issue #42 is blocked by #55 and #56."

---

## PM Plugin Skills

### `/pm:setup`

**Run once per workspace.** Interactive onboarding that wires PM to a project.

**What it does:**
1. Detects workspace type: single-repo or multi-repo (multiple `.git` dirs under a parent)
2. Checks for existing `pulse-config.yaml` — if found, reads shared config from it. If not, interviews user for project basics and creates a minimal one.
3. Asks which issue tracker: GitHub Issues (default) or local markdown
4. For GitHub: infers owner/repo from primary repo's git remote, confirms with user
5. Creates `.pm/` directory in the primary repo:
   ```
   .pm/
     config.yml
     out-of-scope/
       README.md
   ```
6. Creates `CONTEXT.md` at workspace root (or primary repo root) — domain glossary with starter structure:
   ```markdown
   # Project Context

   Domain terms, canonical names, and concepts for this project.
   Agents read this before starting work. Updated during sprints
   when new terms are encountered.

   ## Terms

   | Term | Definition | Aliases to avoid |
   |------|-----------|-----------------|

   ## Relationships

   | Concept A | Relationship | Concept B |
   |-----------|-------------|-----------|

   ## Ambiguities

   | Term | Confusion risk | Resolution |
   |------|---------------|-----------|
   ```
7. Creates `docs/adr/` directory with ADR template
8. Sets up GitHub Issue labels and types if using GitHub backend:
   - Labels: `needs-triage`, `ready-for-agent`, `ready-for-human`, `blocker`, `spawned-during-sprint`, `epic`, size labels (S/M/L/XL)
   - Custom issue types (if org supports them): Epic, Story, Task
9. If `planning/` structure doesn't exist yet (no product-pulse), scaffolds it (same structure product-pulse setup creates)

### `/pm:ingest`

**Read research reports and promote action items to tracked issues.** The bridge between intelligence gathering and project management.

**What it does:**
1. Reads `.pm/config.yml` for `research_dirs`
2. Checks ingestion watermarks in `.pm/state.yml` (last-ingested timestamps per directory)
3. Scans configured research directories for new/updated reports since last ingestion:
   - Daily research reports (`*-daily-research.md`)
   - Weekly strategy briefs (`*-strategy-brief.md`) and recommendations (`*-recommendations.md`)
   - Deep-dive reports (from `deep-dives/`)
4. For each report, reads it fresh and extracts:
   - Action items, recommendations, opportunities
   - Source URLs and confidence ratings
   - Priority and sizing from the report
5. Diffs extracted items against:
   - Existing open issues (avoids duplicates)
   - Current codebase state across all repos (skips items already implemented)
   - `.pm/out-of-scope/` rejections (skips explicitly rejected ideas)
6. Creates new items with `needs-triage` label:
   - Source attribution (which report, which section, which date)
   - Initial sizing estimate from the report
   - Suggested parent epic (if one exists)
   - Raw context from the report for the triager
7. For the GitHub backend: creates GitHub Issues with `needs-triage` label
8. For local backend: creates YAML files in `.pm/items/`
9. Updates `.pm/state.yml` with new watermarks
10. Reports: X items found, Y already tracked, Z out-of-scope, W new issues created

**Key design choice:** Ingestion creates `needs-triage` items, never `ready-for-agent`. Every item must pass through triage. Stale AI recommendations don't auto-execute.

### `/pm:triage`

**The full pipeline from rough idea to agent-ready spec.** Not labeling — this is where raw input becomes real work.

**What it does:**

*Phase 1 — Sort:*
- Pulls all `needs-triage` items
- For each: is it clearly out of scope? → reject with `.pm/out-of-scope/{slug}.md`:
  ```markdown
  # {Feature/Concept Name}

  **Decided:** {date}
  **Status:** Rejected

  ## Decision
  {What was rejected and why}

  ## Reasoning
  {Trade-offs considered, why this doesn't fit}

  ## Prior requests
  - {date}: {source} — {context}
  ```
- Is it a duplicate of an existing issue? → link and close
- Does it target a specific repo? If not, classify which repo(s) it belongs to

*Phase 2 — Spec (for items that need it):*
- S-sized items can go directly to `ready-for-agent` if they have a clear description
- M/L/XL items: invokes spec creation flow using superpowers brainstorming → writing-plans skills
- Produces a spec with acceptance criteria, code references, negative constraints
- For GitHub backend: spec content goes in the issue body (structured with headers)
- For local backend: spec file at `planning/specs/{number}-{slug}.md`
- Reads `CONTEXT.md` for domain terminology and `.pm/out-of-scope/` for negative constraints

*Phase 3 — Score:*
- Evaluates each item against the agent-ready scorecard:
  1. ✅ Clear description (what, not how)
  2. ✅ Explicit acceptance criteria
  3. ✅ Linked code references with target repo
  4. ✅ Negative constraints (cross-refs `.pm/out-of-scope/`)
  5. ✅ Bounded scope (single deliverable, one repo)
  6. ✅ No open design questions
- Items that pass all 6 → `ready-for-agent` with priority + target repo label
- Items failing on questions → `ready-for-human` with specific questions listed
- Items missing context → `needs-info` (stays in triage pool)

*Phase 4 — Organize:*
- Assigns parent epic via sub-issues when hierarchy is clear
- Sets priority, size estimate
- Interactive throughout: presents each item with recommendation, user confirms/overrides

### `/pm:reconcile`

**Sync reality with the tracker.** Run after sprints, after merges, periodically.

**What it does:**

*Completion tracking:*
- Scans recent git history across ALL configured repos for commits/PRs that reference issue numbers
- Marks referenced issues as done (or prompts for confirmation)
- Checks epic rollup: if all children done → marks parent done
- For the `planning/` files: moves completed items from Ready to Done, archives items older than 7 days to `planning/archive/done-YYYY-QN.md`

*Stale detection:*
- Flags items untouched for configured threshold (default: 30 days)
- Suggests: re-triage, close, or demote priority

*Deferred blocker handling:*
- Scans for items spawned mid-sprint (tagged `spawned-during-sprint` or linked as sub-issues of in-progress work)
- Classifies each: **blocking** (parent can't ship without it) vs. **independent** (related but separable)
- Blocking items get `blocker` label + linked to parent via sub-issue
- Independent items go to `needs-triage`
- Reports blocking chains: "Issue #42 is blocked by #55 and #56"

*CONTEXT.md maintenance:*
- Scans recent commits and PRs for new domain terms
- Proposes additions to CONTEXT.md glossary (user confirms each)

*ADR creation:*
- If a recent commit/PR represents an architectural decision (hard to reverse + surprising without context + real trade-off), proposes creating an ADR
- User confirms before creation

*Reconciliation report:*
- X items completed since last reconcile
- Y items flagged stale
- Z deferred blockers classified
- Epic progress rollups (e.g., "Epic #10: 7/12 tasks done")
- W new domain terms proposed for CONTEXT.md

### `/pm:sprint-dev`

**Pick ready work and execute it.** Moved from product-pulse, enhanced with PM integration.

This skill inherits the full sprint-dev implementation from product-pulse v0.2.0 with the following changes:

*Config discovery:*
- Reads `.pm/config.yml` for backend type and PM-specific settings
- Reads `pulse-config.yaml` for `repos`, `project_id`, `memory`, `default_branch` (same as before)
- Reads `CONTEXT.md` for domain terminology before dispatching sub-agents
- Checks `.pm/out-of-scope/` to populate negative constraints for sub-agent prompts

*Item source:*
- Pulls `ready-for-agent` items from the configured backend (GitHub Issues or local)
- Falls back to `planning/todos.md` Ready section if no backend items exist (backward compat)
- Cross-references `planning/specs/` for specs (same freshness check as before)

*Execution:*
- Same Phase 0 (sync, reconcile, pull), Phase 1 (parse, filter, propose), Phase 2 (build approved PRs) as product-pulse sprint-dev
- Sub-agent prompts now include CONTEXT.md domain terms and out-of-scope constraints
- When sub-agents discover new work during implementation: creates `needs-triage` items (tagged `spawned-during-sprint`) instead of inline execution. Original task's definition of done stays fixed.

*Post-execution:*
- Updates issue status in the backend
- Comments on GitHub Issue with PR link and completion summary
- Updates parent epic progress

---

## Product-pulse Changes

### Skills modified

**`/product-pulse:daily-research`:**
- Remove all backlog editing (Phases 3.4, 3.5, 4 "Update the Backlog", 5.1 backlog edits)
- The skill produces report files only — no more writing to `planning/ideas.md` or `planning/todos.md`
- Remove the `backlog.active` and `backlog.ideas` config parsing from Phase 0 (no longer needed)
- Keep the report structure including the Action Items table — PM:ingest reads these

**`/product-pulse:weekly-strategist`:**
- Remove all backlog editing (Phase 3.3 move/dismiss operations, Phase 5.1 backlog edits)
- The skill produces brief + recommendations files only
- Keep the recommendations table structure — PM:ingest reads these
- Keep the "Recommended for speccing" output — PM:triage uses these as input

**`/product-pulse:setup`:**
- Remove `planning/` folder scaffolding (PM:setup handles that now)
- Keep research directory scaffolding (`research-context.md`, `research-sources.yaml`, `pulse-config.yaml`)
- Stop generating `backlog:` section in new `pulse-config.yaml` installs — PM:setup adds it. Existing configs that already have `backlog:` keep it (no breakage).
- Keep `deep-dives/` directory creation (for the new deep-dive skill)

### Skills added

**`/product-pulse:deep-dive`:**
- Absorbs research-scout's core logic (Phases 1-7: load prior research, understand resources, cross-reference, ecosystem research, project audit, compare, deliver report)
- Drops research-scout's own setup phase — uses `pulse-config.yaml` discovery instead
- Drops backlog integration (Phases 9) — PM:ingest handles that
- Drops standalone git/memory config — uses `pulse-config.yaml` `memory.connector` and PR-based flow
- Reports save to `{research_dir}/deep-dives/{slug}.md`
- Git output uses branch `deep-dive/{slug}` + PR + auto-merge (same pattern as daily/weekly)
- Keeps the `transcribe` skill integration for video analysis
- Keeps confidence ratings, source credibility, cross-reference analysis
- Keeps the report template from `references/report-template.md`

### Skills removed

**`/product-pulse:sprint-dev`** — moved to PM plugin.

### Plugin manifest changes

- Remove sprint-dev from skills list
- Add deep-dive to skills list
- Bump version to 0.3.0
- Update description: remove "interactive sprint development"
- Update keywords: add "deep-dive"
- Keep `userConfig.research_dir` as fallback hint

### README changes

- Update "three-cadence system" to "three-cadence intelligence system" (research only)
- Remove sprint-dev documentation
- Add deep-dive documentation
- Update lifecycle diagram to show product-pulse → PM handoff
- Note: "For project management (triage, sprint execution, issue tracking), install the `pm` plugin"

---

## Research-scout Deprecation

The research-scout plugin is deprecated. Its core functionality moves to `/product-pulse:deep-dive`.

**Migration path:**
- Users with research-scout installed: uninstall research-scout, install product-pulse (if not already), use `/product-pulse:deep-dive` instead of `/research-scout:research-scout`
- Existing deep-dive reports in `docs/research/` or similar: still readable by `/product-pulse:deep-dive` (it indexes them in Phase 1)
- `backlog_file` userConfig: no longer needed — PM:ingest handles backlog integration
- `use_shelby` userConfig: replaced by `memory.connector` in `pulse-config.yaml`

**Marketplace changes:**
- Mark research-scout as deprecated in `marketplace.json` (keep the entry but add `"deprecated": true, "successor": "product-pulse"`)
- Or remove entirely if the marketplace schema doesn't support deprecation flags

---

## Plugin Structure

```
plugins/pm/
├── .claude-plugin/
│   └── plugin.json
├── README.md
├── skills/
│   ├── setup/
│   │   └── SKILL.md
│   ├── ingest/
│   │   └── SKILL.md
│   ├── triage/
│   │   └── SKILL.md
│   ├── reconcile/
│   │   └── SKILL.md
│   └── sprint-dev/
│       └── SKILL.md
├── agents/
│   ├── ingestion-analyst.md     # subagent: reads reports, extracts items
│   └── scorecard-evaluator.md   # subagent: evaluates agent-ready criteria
└── templates/
    ├── context-md.md            # CONTEXT.md starter template
    ├── adr-template.md          # ADR template
    └── out-of-scope-entry.md    # .pm/out-of-scope/ entry template
```

### Plugin manifest

```json
{
  "name": "pm",
  "version": "0.1.0",
  "description": "Backend-agnostic project management for AI-native teams. Ingests research reports, triages and specs work items, manages sprint execution with sub-agents, syncs with GitHub Issues. Pairs with product-pulse for automated intelligence gathering.",
  "author": {
    "name": "Studio Moser",
    "url": "https://github.com/Studio-Moser"
  },
  "repository": "https://github.com/Studio-Moser/skills-n-stuff",
  "license": "MIT",
  "keywords": [
    "project-management",
    "github-issues",
    "triage",
    "sprint",
    "backlog",
    "issue-tracker",
    "multi-repo"
  ]
}
```

---

## Workspace Layout (after both plugins ship)

```
~/Projects/Shelby/                          # workspace root
├── CONTEXT.md                              # domain glossary (managed by PM)
├── docs/adr/                               # architecture decision records
├── Shelby-Strategy/                        # primary repo (has PM state)
│   ├── Research/
│   │   ├── pulse-config.yaml               # shared infrastructure config
│   │   ├── research-context.md             # product prose
│   │   ├── research-sources.yaml           # curated sources
│   │   ├── deep-dives/                     # deep-dive research reports
│   │   └── {YYYY-MM}/W{NN}/               # daily + weekly reports
│   ├── planning/
│   │   ├── todos.md                        # live work queue
│   │   ├── ideas.md                        # incoming ideas staging
│   │   ├── WORKFLOW.md                     # lifecycle docs
│   │   ├── archive/                        # done rows
│   │   └── specs/                          # item specs
│   └── .pm/
│       ├── config.yml                      # PM-specific config
│       ├── state.yml                       # ingestion watermarks
│       └── out-of-scope/                   # rejection KB
│           ├── README.md
│           └── {slug}.md                   # one per rejected concept
├── Shelby-MacOS/                           # target repo (implementation)
├── Shelby-MCP/                             # target repo
└── Shelby-Website/                         # target repo
```

---

## Risks

**Coordination between plugins.** PM depends on product-pulse report formats. If product-pulse changes its report structure, PM:ingest breaks. Mitigation: document the report contract (Action Items table format, recommendation table format) and version it. PM:ingest should be tolerant of missing sections.

**GitHub Issues rate limits.** Batch ingestion could hit API rate limits if many reports accumulated. Mitigation: `gh` CLI handles rate limiting with backoff. PM:ingest processes reports chronologically and can resume from watermarks.

**Sprint-dev migration.** Moving sprint-dev from product-pulse to PM means users who only have product-pulse lose sprint execution. Mitigation: document clearly that PM is the new home for sprint-dev. Product-pulse README says "install PM for sprint execution."

**Triage automation quality.** Automated spec-writing via brainstorming + writing-plans may produce specs that need human revision. Mitigation: triage is always interactive — the user confirms/overrides every promotion. The automation proposes; the human disposes.

**Product-pulse backlog removal.** Existing product-pulse users who rely on daily-research writing to `planning/ideas.md` will need PM:ingest to fill that gap. Mitigation: version the change (product-pulse 0.3.0 removes backlog editing). Document the migration: "install PM alongside product-pulse, run PM:ingest after research runs."

## Open Issues

- Whether `CONTEXT.md` should live at workspace root (accessible across all repos) or in the primary repo root. Workspace root is better for multi-repo but means it's outside any single git repo. For now: primary repo root if single-repo, workspace root if multi-repo (with a symlink or `.claude` include in each sub-repo).
- Whether PM:ingest should run automatically after daily-research/weekly-strategist (via a hook or scheduled task) or always be manually triggered. Starting with manual; can add a hook later.
- The exact GraphQL mutations needed for GitHub sub-issue management — the `gh sub-issue` CLI extension exists but may not be installed. May need to fall back to `gh api graphql` calls.
- Whether the `planning/` files should be kept in sync with GitHub Issues (bidirectional sync) or whether GitHub Issues becomes the source of truth and `planning/` files are deprecated. Starting with GitHub Issues as source of truth for items that have been ingested; `planning/` files remain for backward compatibility and for users without the GitHub backend.
