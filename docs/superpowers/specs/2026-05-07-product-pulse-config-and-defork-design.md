# product-pulse: configurable plugin + de-fork consuming repos

**Date:** 2026-05-07
**Status:** Design — pending implementation plan
**Affects:** `skills-n-stuff/plugins/product-pulse`, `Shelby/Shelby-Strategy`, `The Crooked Line/docs`

## Background

The `product-pulse` plugin ships three skills (daily-research, weekly-strategist, sprint-dev) and five analyst agents. Two consuming repos — `Shelby-Strategy` and `The Crooked Line/docs` — each hold local forks of all eight files. The forks have drifted in lockstep across April–May 2026 (matching commits on both sides for things like the two-file backlog migration), and they share a set of bugs:

1. **Push-to-main silently fails under cloud-agent runs.** Phase 6 of weekly-strategist instructs `git push origin main`. Cloud-agent runners enforce branch isolation, so the work lands on `claude/<adjective>-<noun>-<id>` orphan branches with no PR. Four weekly briefs (W16–W19, Apr 13 – May 4) sat unmerged this way until a manual recovery on 2026-05-07.
2. **Path casing fragmentation.** The plugin source uses `research/` (lowercase). Shelby's repo uses `Research/` (capital). The forks inherited lowercase, but on case-insensitive macOS filesystems the existing capital directory was sometimes preserved and sometimes not, fragmenting the tree across runs.
3. **Local scheduled-task hook collision.** `.claude/hooks/scheduled-safety-gate.sh` defers `Write`, `Edit`, and `git push` under `CLAUDE_SCHEDULED=1`. Anything routed through the local scheduled-tasks runner halts mid-execution. The plugin's git instructions never accounted for this hook's existence.

The forks themselves were the underlying problem — every customization, including the buggy ones, lived in N copies. This spec eliminates the forks by making the plugin configuration-aware.

## Goals

1. Eliminate the local skill + agent forks in both consuming repos.
2. Make `product-pulse` generic enough that both products use the published plugin version.
3. Fix the two structural bugs: silent push-to-main failure, and path casing fragmentation.
4. Per-product configuration lives in the consuming repo, not in user-level Claude settings, so a teammate cloning the repo gets a working setup.

## Non-Goals

1. Not publishing the plugin to a public marketplace — it stays in `skills-n-stuff` for now.
2. Not changing the three-cadence model (daily-research / weekly-strategist / sprint-dev). The architecture is fine; only the configuration story changes.
3. Not migrating Shelby's memory connector usage. Both products keep using Shelby memory; the plugin makes that configurable rather than hardcoded.
4. Not building per-skill config — `pulse-config.yaml` is shared across all three skills.
5. Not rewriting `setup` to handle migration of existing installs — both existing installs are migrated by hand as part of this work.

## Architecture

The plugin becomes the single source of truth. Consuming repos hold two artifacts: prose context (`research-context.md`) and operational config (`pulse-config.yaml`). No skill or agent files in consuming repos.

```
skills-n-stuff/plugins/product-pulse/         (single source of truth)
├── .claude-plugin/plugin.json                (userConfig.research_dir → setup-only fallback)
├── skills/
│   ├── setup/SKILL.md                        (interviews + scaffolds both files)
│   ├── daily-research/SKILL.md               (generic, config-aware)
│   ├── weekly-strategist/SKILL.md            (generic, config-aware)
│   └── sprint-dev/SKILL.md                   (generic, config-aware)
└── agents/
    ├── market-scout.md                       (generic; reads product context at dispatch)
    ├── competitor-tracker.md
    ├── audience-analyst.md
    ├── growth-analyst.md
    └── product-scout.md

Shelby-Strategy/                              (consuming repo)
├── Research/
│   ├── research-context.md                   (PROSE: identity, competitors, audiences)
│   ├── pulse-config.yaml                     (NEW — operational config)
│   └── research-sources.yaml                 (converted from .json)
├── planning/                                 (renamed from todos/)
│   ├── todos.md                              (renamed from backlog.md)
│   ├── ideas.md                              (renamed from backlog-ideas.md)
│   ├── archive/
│   ├── specs/
│   └── ...
├── .claude/skills/                           (DELETED)
└── .claude/agents/                           (DELETED)

The Crooked Line/docs/                        (consuming repo)
├── research/
│   ├── research-context.md
│   ├── pulse-config.yaml
│   └── research-sources.yaml
├── planning/
│   ├── todos.md
│   └── ideas.md
├── .claude/skills/                           (DELETED)
└── .claude/agents/                           (DELETED)
```

### Data flow on a weekly-strategist run

1. Skill resolves the nearest `pulse-config.yaml` walking up from cwd. The file's parent directory is the research directory. Casing is implicit from where the file lives.
2. Skill loads `pulse-config.yaml` for operational config (repos to pull, memory connector, auto-merge setting, etc.).
3. Skill loads `research-context.md` from the same directory for product prose; passes it to all five dispatched analyst agents.
4. Agents execute. Skill synthesizes brief + recommendations.
5. Phase 6: skill creates branch `weekly-brief/W{NN}`, commits, pushes, opens PR via `gh pr create`. If `auto_merge: true` and the PR is mergeable, `gh pr merge --squash --delete-branch`.

### Skill ↔ config separation principle

- The skill defines *what* to do (load context, dispatch agents, write brief, open PR).
- Operational config defines *where* and *whom* (which repos, which memory connector, which directory).
- Product framing prose lives in `research-context.md` — neither in the skill nor in operational config.

## Configuration Schema

`pulse-config.yaml` lives in the directory where research output should be written. The skill discovers it by walking up from cwd.

```yaml
# Required
project_id: shelby                  # used for memory.project tagging and brief metadata

# Repos to operate on (length 1 = monorepo, length N = multi-repo)
# Paths are git-aware: `.` = the git repo containing this config file
# (discovered by walking up from the config file until .git is found).
# `../<name>` = a sibling git repo on the filesystem.
repos:
  - name: Shelby-Strategy
    path: .                          # the repo containing this config
    role: primary                    # exactly one entry must be 'primary'
  - name: Shelby-MCP
    path: ../Shelby-MCP
  - name: Shelby-MacOS
    path: ../Shelby-MacOS
  - name: Shelby-Website
    path: ../Shelby-Website

# Optional with defaults
default_branch: main                 # branch PRs target; default: main
auto_merge: true                     # auto-squash-merge if PR is mergeable; default: true

memory:
  connector: shelby                  # MCP tool-name prefix; null disables; default: shelby

backlog:
  active: planning/todos.md          # live work queue; default shown
  ideas: planning/ideas.md           # idea staging; default shown
  # archive convention `planning/archive/done-YYYY-QN.md` baked in (sprint-dev only)
```

### TCL example

```yaml
project_id: the-crooked-line

repos:
  - name: the-crooked-line
    path: .
    role: primary

memory:
  connector: shelby                  # TCL also uses Shelby memory cross-product
```

### Discovery rule

The plugin walks up from cwd until it finds `pulse-config.yaml`. That file's parent directory is the research directory. All week subdirectories (`{YYYY-MM}/W{NN}/`), brief files, and recommendations land there.

Conventions baked in (not configurable):

- Week structure: `{YYYY-MM}/W{NN}/`
- Brief filename: `{year}-W{NN}-strategy-brief.md`
- Recommendations filename: `{year}-W{NN}-recommendations.md`
- Sprint-dev archive path: `planning/archive/done-YYYY-QN.md`

## Skill Behavior Changes

The plugin's three skills are rewritten with the following changes vs. the current generic plugin source:

### 1. Config loading (Phase 0)

Skill walks up from cwd to find the nearest `pulse-config.yaml`. Loads it. Reads `research-context.md` from the same directory for prose. If no config file is found, falls back to the existing plugin `userConfig.research_dir` with a deprecation warning.

### 2. Multi-repo Phase 0 pull

Skill iterates `repos:` and runs `git checkout {default_branch} && git pull` in each. Single-element list is the degenerate case for monorepos — same code path.

### 3. PR-based output (Phase 6)

This fixes the W16-W19 silent-failure bug.

- Always: create branch (`weekly-brief/W{NN}` for weekly, `daily-research/{YYYY-MM-DD}` for daily), commit, push, `gh pr create`.
- If `auto_merge: true` AND PR is mergeable (no conflicts, no required reviews blocking), then `gh pr merge --squash --delete-branch`.
- If auto-merge fails or `auto_merge: false`, skill logs the PR URL and exits — human merges later.

This eliminates the cloud-agent push-to-main mismatch entirely. The skill no longer pretends it can push to `main`; it always uses the branch + PR flow, which works equally under interactive, scheduled, and cloud-agent execution contexts.

### 4. Memory ops (configurable)

Skill checks for tools matching `memory.connector` prefix at runtime. If found, captures thoughts with `project: {project_id}`. If not found or `memory.connector: null`, skips memory ops silently. No more hardcoded "Shelby memory Connector" references in the plugin source.

### 5. Casing

All references to the research directory in the skill use the discovered config-file parent directory (variable, not hardcoded `research/` or `Research/`). Whatever case the config file lives at is the case used everywhere. This eliminates the path-fragmentation bug.

### 6. Removed from plugin

What was in the forks but won't appear in the rewritten plugin:

- Scheduled-task name references (Phase 7 summary just calls it "weekly-strategist").
- Specific deep-dive doc references (those belong in `research-context.md`).
- Product framing prose (lives in `research-context.md`).
- Shelby's hardcoded 4-repo loop (replaced by `repos:` iteration).
- Agents' product-specific knowledge (read from passed-in product context at dispatch).

## Migration

### Step 1 — Plugin upgrade (skills-n-stuff repo)

1. Bump `product-pulse` version to `0.2.0`.
2. Rewrite `skills/{daily-research,weekly-strategist,sprint-dev}/SKILL.md` per the Skill Behavior Changes section.
3. Update `skills/setup/SKILL.md` to scaffold `pulse-config.yaml` + the `planning/` folder structure (and walk the user through the new schema).
4. Verify agents are truly generic — drop any baked-in product-specific framing.
5. Update `.claude-plugin/plugin.json`: `userConfig.research_dir` becomes a fallback hint for `setup` only; runtime resolution is from `pulse-config.yaml` discovery.
6. Document the schema in `plugins/product-pulse/README.md`.

### Step 2 — Migrate Shelby-Strategy

Done first because it's the harder case (multi-repo) and higher-stakes for the user.

1. Create `Research/pulse-config.yaml` with Shelby's repos list, `project_id: shelby`, `memory.connector: shelby`.
2. Convert `research/research-sources.json` → `research/research-sources.yaml` (~61 lines).
3. Rename `todos/` → `planning/`. Rename `backlog.md` → `todos.md`, `backlog-ideas.md` → `ideas.md`. Update internal cross-references in `WORKFLOW.md`, specs, archive paths.
4. Update `CLAUDE.md` to describe `planning/` instead of `todos/`.
5. Delete `.claude/skills/{daily-research,weekly-strategist,sprint-dev}/` and `.claude/agents/`.
6. Verify with manual runs of weekly-strategist and daily-research; confirm each produces a reviewable PR.
7. One PR per repo containing all the above.

### Step 3 — Migrate The Crooked Line/docs

Same pattern, simpler — single-repo.

1. Create `research/pulse-config.yaml` with single-repo list, `project_id: the-crooked-line`, `memory.connector: shelby`.
2. Convert `research/research-sources.json` → `.yaml` (~80 lines).
3. Rename `todos/` → `planning/` and rename files.
4. Delete `.claude/skills/` and `.claude/agents/`.
5. Verify with manual runs.
6. One PR.

### Step 4 — Cleanup

1. Audit `claude/lucid-cori-9tSnU` branch on TCL for unmerged content (parallels the W16–W19 audit done on Shelby), then delete.
2. Update the safety hook (`.claude/hooks/scheduled-safety-gate.sh`) to reflect the new flow: `git push` to a branch + `gh pr create` is the normal path. The hook should still defer destructive operations (`rm -rf`, `git reset --hard`) but allow normal PR-flow operations under `CLAUDE_SCHEDULED=1`.

## Risks

**Timing risk during migration.** Steps 2 and 3 each have a window where the repo is partially migrated. A scheduled run hitting the partial state would fail. Mitigation: do each migration in a single PR, merge during a window when no scheduled task is about to fire (the daily-research jobs run at 05:02 and 06:02), and verify with a manual run before merging. Worst case: a scheduled run lands on an in-progress migration and fails — recoverable, just re-run after the migration merges.

**Plugin version pinning.** When v0.2.0 of product-pulse ships, both repos auto-pick it up at the next plugin cache refresh. If migration of the consuming repos lags behind plugin upgrade, the new generic skills will run against the old `todos/backlog.md` paths and fail. Mitigation: order is Step 1 → Step 2 → Step 3 with verification at each stage.

**Auto-merge surprises.** If `auto_merge: true` is the default and the consuming repo has branch protection requiring reviews, auto-merge will silently fail and the PR will sit. Mitigation: skill logs the PR URL on auto-merge failure so the run isn't lost; user merges manually as fallback.

## Open Issues / Out of Scope

- Whether the `setup` skill should grow a "migrate-from-fork" mode for users who installed product-pulse before v0.2.0. YAGNI for now since the only two existing installs are being hand-migrated as part of this work.
- The auto-merge mergeability check in Phase 6 needs a small retry/poll loop if `gh pr create` returns before the PR is fully ready for merge — implementation detail to settle in the plan.
- Whether `backlog:` in the YAML schema should be renamed `planning:` for symmetry with the folder rename. Backlog is the *concept* (work pending), planning is the *folder* (where files live). Keeping `backlog:` for now; flag for revisit if it feels off during implementation.
