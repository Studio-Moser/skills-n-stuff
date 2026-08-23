# Independent Product Pulse and PM Setup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure Product Pulse and GitHub-backed PM independently in `skills-n-stuff` and `agents`, with each repository owning and auto-merging its own research PRs.

**Architecture:** Each repository receives a standalone `docs/research/pulse-config.yaml` whose sole repo is `.` and a standalone `.pm/config.yml` targeting that repository's GitHub Issues. Product Pulse reports, PM state, planning files, ADRs, context, labels, commits, and PRs remain isolated by repository.

**Tech Stack:** YAML, Markdown, Git, GitHub CLI, Product Pulse 0.4.0, PM 0.18.0

**Spec:** `docs/superpowers/specs/2026-08-22-independent-product-pulse-setup-design.md`

## Global Constraints

- Use `docs/research/` as the research directory in both repositories.
- Use `main`, `auto_merge: true`, and `memory.connector: shelby`.
- Use GitHub Issues in each local repository, label-only mode, a 30-day stale threshold, ADRs, and an empty glossary template.
- Do not add cross-repository paths or targets.
- Do not add literal `/Users/<name>` paths to `agents`.
- Preserve every pre-existing file and user change.

---

### Task 1: Configure skills-n-stuff

**Files:**
- Create: `docs/research/pulse-config.yaml`
- Create: `docs/research/research-context.md`
- Create: `docs/research/research-sources.yaml`
- Create: `docs/research/deep-dives/.gitkeep`
- Create: `.pm/config.yml`
- Create: `.pm/state.yml`
- Create: `.pm/out-of-scope/README.md`
- Create: `CONTEXT.md`
- Create: `docs/adr/0000-template.md`
- Create: `planning/todos.md`
- Create: `planning/ideas.md`
- Create: `planning/WORKFLOW.md`
- Create: `planning/archive/.gitkeep`
- Create: `planning/specs/_TEMPLATE.md`
- Create or modify: `AGENTS.md`
- Create or modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `Studio-Moser/skills-n-stuff`, the repository README, Product Pulse setup schema, PM templates, and PM baseline stamp script.
- Produces: project ID `skills-n-stuff`, research directory `docs/research`, GitHub backend `Studio-Moser/skills-n-stuff`, and backlog paths `planning/todos.md` and `planning/ideas.md`.

- [ ] **Step 1: Verify the isolated baseline and GitHub target**

Run:

```bash
git status --short
git remote get-url origin
gh repo view Studio-Moser/skills-n-stuff --json nameWithOwner,defaultBranchRef,isPrivate
```

Expected: clean except the committed spec/plan history; remote is `Studio-Moser/skills-n-stuff`; default branch is `main`.

- [ ] **Step 2: Create the Product Pulse files**

Create `docs/research/pulse-config.yaml` with one repo (`name: skills-n-stuff`, `path: .`, `role: primary`), `main`, auto-merge, Shelby memory, and the two planning backlog paths. Create `research-context.md` for the mature public Studio Moser plugin and skill collection with domains for agent-tool ecosystems, skill/plugin standards, research and PM workflows, distribution/interoperability, and technical/security changes. Leave `Always Check` as `_(none yet)_`.

Create `research-sources.yaml` with verified authoritative sources including:

- `https://agentskills.io/specification`
- `https://developers.openai.com/`
- `https://docs.anthropic.com/en/docs/claude-code/cli-usage`
- `https://modelcontextprotocol.io/specification/2026-07-28`
- `https://docs.github.com/en/actions/reference/security/secure-use`

Use search terms scoped to portable skills, Claude Code plugins, Codex agent workflows, MCP changes, GitHub supply-chain security, and AI-native product-research tooling. Add `docs/research/deep-dives/.gitkeep` so the empty directory is tracked.

- [ ] **Step 3: Create and validate PM configuration**

Create `.pm/config.yml` with `backend: github`, owner `Studio-Moser`, repo `skills-n-stuff`, `context_md: CONTEXT.md`, `adr_dir: docs/adr`, `out_of_scope_dir: .pm/out-of-scope`, `research_dirs: [docs/research]`, and `triage.stale_threshold_days: 30`. Copy the PM 0.18.0 templates into `.pm/state.yml`, `.pm/out-of-scope/README.md`, `CONTEXT.md`, `docs/adr/0000-template.md`, and `planning/`; substitute project ID `skills-n-stuff` and date `2026-08-22` where required.

Run:

```bash
/Users/timmoser/.codex/plugins/cache/studio-moser/pm/0.18.0/scripts/validate-config.sh .pm/config.yml
```

Expected: configuration valid.

- [ ] **Step 4: Stamp the managed baseline**

Fetch `studio-baseline/AGENTS_Baseline.md`, target root `AGENTS.md`, and run PM's idempotent `stamp-baseline.sh`. Ensure root `CLAUDE.md` contains exactly the required `@AGENTS.md` import plus any pre-existing content.

- [ ] **Step 5: Provision GitHub labels**

Create or refresh the 19 standard PM labels in `Studio-Moser/skills-n-stuff`: five `status/*`, three `owner/*`, four `priority/*`, four `size/*`, `blocker`, `spawned-during-sprint`, and `epic`. Use the names, colors, and descriptions from `references/setup-github.md`.

- [ ] **Step 6: Verify and commit**

Run:

```bash
git check-ignore -v docs/research/pulse-config.yaml docs/research/research-context.md .pm/config.yml CONTEXT.md || true
git diff --check
yq -e '.project_id == "skills-n-stuff" and .repos == [{"name":"skills-n-stuff","path":".","role":"primary"}] and .default_branch == "main" and .auto_merge == true and .memory.connector == "shelby"' docs/research/pulse-config.yaml
/Users/timmoser/.codex/plugins/cache/studio-moser/pm/0.18.0/scripts/validate-config.sh .pm/config.yml
git status --short
```

Expected: no generated path is ignored, no whitespace errors, both configs validate, and only intended setup files are changed.

Commit:

```bash
git add AGENTS.md CLAUDE.md CONTEXT.md .pm docs/adr docs/research planning docs/superpowers/plans/2026-08-22-independent-product-pulse-pm-setup.md
git commit -m "chore: configure Product Pulse and PM"
```

---

### Task 2: Configure agents

**Files:**
- Create: `docs/research/pulse-config.yaml`
- Create: `docs/research/research-context.md`
- Create: `docs/research/research-sources.yaml`
- Create: `docs/research/deep-dives/.gitkeep`
- Create: `.pm/config.yml`
- Create: `.pm/state.yml`
- Create: `.pm/out-of-scope/README.md`
- Create: `CONTEXT.md`
- Create: `docs/adr/0000-template.md`
- Create: `planning/todos.md`
- Create: `planning/ideas.md`
- Create: `planning/WORKFLOW.md`
- Create: `planning/archive/.gitkeep`
- Create: `planning/specs/_TEMPLATE.md`
- Create or modify: `AGENTS.md`
- Create or modify: `CLAUDE.md`

**Interfaces:**
- Consumes: `Studio-Moser/agents`, its README, Product Pulse setup schema, PM templates, and PM baseline stamp script.
- Produces: project ID `agents`, research directory `docs/research`, GitHub backend `Studio-Moser/agents`, and backlog paths `planning/todos.md` and `planning/ideas.md`.

- [ ] **Step 1: Verify the isolated baseline and GitHub target**

Run:

```bash
git status --short
git remote get-url origin
gh repo view Studio-Moser/agents --json nameWithOwner,defaultBranchRef,isPrivate
```

Expected: clean; remote is `Studio-Moser/agents`; default branch is `main`; repository is private.

- [ ] **Step 2: Create the Product Pulse files**

Create `docs/research/pulse-config.yaml` with one repo (`name: agents`, `path: .`, `role: primary`), `main`, auto-merge, Shelby memory, and the two planning backlog paths. Create `research-context.md` for the mature private per-developer agent-configuration system with domains for cross-tool portability, instruction and skill quality, configuration security, machine synchronization, and operational reliability. Leave `Always Check` as `_(none yet)_`.

Create `research-sources.yaml` with the same authoritative foundation as Task 1, but search terms scoped to AGENTS.md and CLAUDE.md behavior, portable skill installation, hook and settings changes, secret-safe synchronization, model routing, and multi-machine configuration drift. Add `docs/research/deep-dives/.gitkeep`.

- [ ] **Step 3: Create and validate PM configuration**

Create `.pm/config.yml` with `backend: github`, owner `Studio-Moser`, repo `agents`, and the same local paths and defaults as Task 1. Copy the PM templates, substituting project ID `agents` and date `2026-08-22` where required.

Run the PM validator and expect a valid configuration.

- [ ] **Step 4: Stamp the managed baseline**

Stamp root `AGENTS.md` and create root `CLAUDE.md` importing it. Confirm no new file contains `/Users/`; `$HOME` is permitted where a home-relative path is necessary.

- [ ] **Step 5: Provision GitHub labels**

Create or refresh the standard 19 PM labels in `Studio-Moser/agents`, using the canonical names, colors, and descriptions.

- [ ] **Step 6: Verify and commit**

Run the same ignore, whitespace, YAML, and PM validation checks as Task 1, replacing project/repo with `agents`, then run:

```bash
rg -n '/Users/' AGENTS.md CLAUDE.md CONTEXT.md .pm docs/research planning && exit 1 || true
```

Expected: no literal user path, and only intended setup files changed.

Commit:

```bash
git add AGENTS.md CLAUDE.md CONTEXT.md .pm docs/adr docs/research planning
git commit -m "chore: configure Product Pulse and PM"
```

---

### Task 3: Review, publish, and enable GitHub delivery

**Files:**
- Review: both setup branches in full

**Interfaces:**
- Consumes: the two verified setup commits and provisioned GitHub labels.
- Produces: one pull request per repository, each targeting `main` with auto-merge queued when permitted.

- [ ] **Step 1: Run final cross-repository verification**

Verify both branches are clean, both PM configs validate, both Product Pulse configs contain exactly one local repo, all 19 labels exist in each GitHub repository, and `skills-n-stuff`'s unavailable Bats runner is reported without claiming its tests passed.

- [ ] **Step 2: Review both diffs**

Review each full `origin/main...HEAD` diff for scope, secrets, cross-repository paths, malformed YAML, incorrect GitHub targets, and unintended changes. Fix and recommit any finding before publishing.

- [ ] **Step 3: Push and open pull requests**

Push `setup/product-pulse-pm` from each worktree and open one PR per repository titled `chore: configure Product Pulse and PM`. Each PR body must summarize independent Product Pulse output, GitHub-backed PM, generated files, config validation, label provisioning, and the missing local Bats runner where applicable.

- [ ] **Step 4: Queue auto-merge**

Run `gh pr merge --squash --delete-branch --auto` for each PR. If repository policy declines auto-merge, leave the PR open and report its URL and exact blocker.
