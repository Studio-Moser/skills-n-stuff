---
name: setup
description: >-
  Configures PM's issue-tracker backend for a workspace. Use when PM is not yet configured or the user asks to reconfigure it.
disable-model-invocation: true
effort: medium
allowed-tools: "Bash Read Write Edit ToolSearch Skill"
---

# PM — Setup

You are the onboarding wizard for **PM**, a backend-agnostic project management system for AI-native teams. Your job is to detect the workspace layout, interview the user about their issue tracking preferences and domain knowledge, then scaffold everything needed for the ingest, triage, reconcile, sprint-dev, and project review workflows to operate.

**PM pairs with Product Pulse.** Product Pulse handles intelligence gathering (daily research, weekly strategy, deep-dives). PM handles the backlog lifecycle from ingestion through execution. They share infrastructure config via `pulse-config.yaml`.

**Run once per workspace.** If `.pm/config.yml` already exists, ask before overwriting. If individual files exist, offer to merge rather than clobber.

---

## Phase 1: Detect Workspace

Before interviewing the user, gather what you can automatically.

### Step 1a: Check for pulse-config.yaml

Walk up from the current working directory looking for `pulse-config.yaml`. This is the shared infrastructure config that Product Pulse creates during its setup.

**If found**, read these fields from it:

- `project_id` — the project slug (e.g. `shelby`)
- `repos` — list of repos with `name`, `path`, `role` (one has `role: primary`)
- `default_branch` — branch name (e.g. `main`)
- `memory` — memory connector config
- `backlog` — paths to `active` and `ideas` files

Print: "Found existing pulse-config.yaml at `{path}`. Reading shared config..."

Store the primary repo path — this is where `.pm/` will live.

**If not found**, note that you'll need to create a minimal `pulse-config.yaml` during Phase 3. Continue to the interview.

### Step 1b: Detect workspace type

Determine if this is a single-repo or multi-repo workspace:

1. Run `git rev-parse --show-toplevel` to find the current repo root.
2. Check the parent directory for sibling `.git` directories:
   ```bash
   ls -d "$(dirname "$(git rev-parse --show-toplevel)")"/*/.git 2>/dev/null | wc -l
   ```
3. If more than one `.git` directory exists at the same level, this is likely a multi-repo workspace.

For multi-repo workspaces, identify which repo is primary:
- If `pulse-config.yaml` exists, use the repo with `role: primary`.
- Otherwise, the repo the user is currently in is assumed primary. Confirm in the interview.

### Step 1c: Check for existing .pm/ directory

If `.pm/config.yml` already exists, warn the user:

"Found existing PM configuration at `{path}/.pm/config.yml`. Do you want to reconfigure from scratch, or keep the existing setup?"

If they want to keep it, run Step 1d before any keep-existing early exit and set
`keep_existing_pm: true`. After Harness returns accepted status with proven evidence,
preserve `.pm/config.yml` and every
existing scaffold unchanged, skip Phases 2–7, continue through Phase 7.5 so the review
system can be installed or refreshed, then print the Phase 8 summary. Otherwise use
Step 1d's unconfigured stop message. Keeping PM configuration is not an early exit from
review-system setup.

### Step 1d: Check Harness

Confirm the installed skill surface exposes `harness:delegate` and `harness:setup`.
This is only an availability check;
available skill names do not establish configuration.

Invoke `harness:setup` with `mode: status`. This is Harness's read-only configured-
status seam. Consume its exact Harness Result and continue only when it returns both
`status: accepted` and `evidence.outcome: proven`. Do not reinterpret an empty blocker
list, installed skill, or successful command exit as configuration proof.

If any required skill is unavailable, the status invocation fails, or the returned
result is not accepted with proven evidence, stop before PM scaffolding and say:

```text
Harness is not configured. Run /harness:setup, then rerun /pm:setup.
```

This is a dependency check, not Harness setup. PM must not inspect or create Harness
routing configuration, discover execution runtimes, or restate Harness setup
mechanics, because Harness owns that configuration and a second writer would drift
from it. Point only to `/harness:setup`. Retain the accepted result as the proof used
by the Phase 8 summary; never infer or default the displayed status, because only
Harness can prove it is configured.

---

## Phase 2: Interview

Gather PM configuration by asking the user directly. Ask in focused batches — don't overwhelm with everything at once.

### Batch 1: Issue Tracker Backend

Ask these together:

1. **Which issue tracker backend do you want?**
   - **GitHub Issues** (default) — uses `gh` CLI to create issues, labels, and sub-issues in your GitHub repo. Best when you already use GitHub for code review.
   - **Trello** — uses the Trello MCP server (`@delorenj/mcp-server-trello`) to manage cards across one or more boards. Best when stakeholders prefer a visual board, when items represent ongoing conversations rather than discrete tickets, or when you want to mix non-engineering work into the same backlog.
   - **Local markdown** — stores items as YAML files in `.pm/items/`. No external dependencies. Good for private projects or offline workflows.

2. **If multi-repo and no pulse-config.yaml**: Ask which repo is primary (holds `.pm/`, `planning/`, issue tracking state) and list the other repos with a brief description of each.

**Backend dispatch.** PM uses one backend per project. Once the user chooses it,
load exactly one file: `references/setup-${backend}.md`. Do not load another
setup backend reference. Follow the loaded file wherever this skill marks a
**backend step**.

3. **Backend interview**: **(backend step)** — follow the loaded reference's
interview section, then return here.

### Batch 2: Domain Knowledge

1. **Does this project have established domain terminology that agents should know?**
   - Explain: "We'll create a CONTEXT.md glossary that agents read before starting work. It captures canonical term definitions, relationships between concepts, and ambiguous terms to watch out for. This prevents agents from using wrong names or misunderstanding your domain."
   - If yes: "Give me 3-5 key terms to seed the glossary with. For each term, provide the definition and any aliases agents should avoid."
   - If no: "No problem — we'll create an empty template. You can populate it as terms come up during sprints."

2. **Do you want an Architecture Decision Records (ADR) directory?** (default: yes)
   - Explain: "ADRs document significant technical decisions with their context, rationale, and consequences. Agents create ADRs when they make architectural choices during sprint work."

### Batch 3: Research Integration

1. **Do you have product-pulse research reports?** If yes, where do they live?
   - Default: `Research` directory in the primary repo root, or the `research_dir` from `pulse-config.yaml` if it exists.
   - "The ingest skill will scan these directories for actionable findings."
   - Allow multiple directories (e.g. `Research` and `Research/deep-dives`).

2. **Stale threshold**: "How many days before an untouched item is flagged as stale?" (default: 30)

### Batch 4: Project Identity (only if no pulse-config.yaml)

Skip this batch if `pulse-config.yaml` already provided these values.

1. **What's your project_id slug?** (suggested: `{lowercased-hyphenated-repo-name}`)
   - "This slug is used to tag memory entries and as a prefix for scheduled tasks."
2. **Which git branch is your default?** (default: `main`)
3. **Memory connector?** Options:
   - `shelby` (default — Harness resolves the optional provider and canonical project scope)
   - `null` (skip memory operations entirely)
   - Another provider identifier already supported by the configured Harness

### Batch 5: Branch rules

Skip a repo whose `pulse-config.yaml` entry already has both keys. For each other
repo, `git fetch --prune` it, then ask together:

1. **Which branch does merged work land in?** (`base_branch`; default: the repo's
   GitHub default branch from `gh repo view --json defaultBranchRef`, else
   `default_branch`)
2. **Which branches must never be deleted?** (`protected_branches`; suggest existing
   remote branches matching `main|master|develop|dev|staging|stage|production|prod|live|release*`)

`/pm:tidy-up` reads these to decide what is merged and what to keep.

---

## Phase 3: Scaffold .pm/ Directory

Create the `.pm/` directory at the primary repo root. This is the PM-specific config directory — separate from `pulse-config.yaml` which is shared infrastructure.

### Directory structure

```
{primary_repo_root}/
└── .pm/
    ├── config.yml          # PM-specific configuration
    ├── state.yml           # Ingestion watermarks
    └── out-of-scope/
        └── README.md       # Explains the rejection KB pattern
```

### Generate .pm/config.yml

Start with the shared fields below. Replace the backend placeholder by following
the loaded reference's `Generate .pm/config.yml` section. Do not inspect another
backend's example or reference.

```yaml
# PM Configuration
# Generated by /pm:setup on {DATE}

{backend selection and configuration from the loaded reference}

context_md: CONTEXT.md
adr_dir: docs/adr
specs_dir: planning/specs
out_of_scope_dir: .pm/out-of-scope

research_dirs:
  - {first research dir, e.g. Research}

triage:
  stale_threshold_days: {threshold from interview, default 30}
```

After writing the complete file, validate it:

```bash
pm="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/pm/*/ 2>/dev/null | sort -V | tail -1)}"; pm="${pm%/}"
"$pm/scripts/validate-config.sh" "$primary_repo_root/.pm/config.yml"
```

If validation fails, surface the errors and stop before backend provisioning.

### Generate .pm/state.yml

This file tracks ingestion watermarks. Start empty — the ingest skill populates it:

```yaml
# Ingestion watermarks — updated by /pm:ingest
last_ingested: {}
last_reconcile: null
```

### Generate .pm/out-of-scope/README.md

Read `$pm/templates/oos-readme.md` and write it to `.pm/out-of-scope/README.md`.

### Create or update pulse-config.yaml (if it doesn't exist)

If Phase 1 did not find a `pulse-config.yaml`, create a minimal one in the primary repo root:

```yaml
project_id: {slug from interview}

repos:
  - name: {primary repo name}
    path: .
    role: primary
    base_branch: {branch from Batch 5}
    protected_branches: [{branches from Batch 5}]
  # Multi-repo: add sibling repos here
  # - name: {repo-name}
  #   path: ../{repo-name}
  #   base_branch: {branch from Batch 5}
  #   protected_branches: [{branches from Batch 5}]

default_branch: {branch from interview, default main}

memory:
  connector: {connector from interview, default shelby}

backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

If `pulse-config.yaml` already exists but lacks a `backlog:` section, append the `backlog:` block to it.

If it already exists, add Batch 5's `base_branch` and `protected_branches` to each
answered repo entry (for example `yq -i '(.repos[] | select(.name == "{name}")).base_branch = "{branch}"'`).
Leave every other key unchanged.

---

## Phase 4: Create CONTEXT.md

Read the template from `$pm/templates/context-md.md`.

**Placement:**
- **Single-repo**: Write to `{primary_repo_root}/CONTEXT.md`
- **Multi-repo**: Write to `{workspace_root}/CONTEXT.md` (the parent directory containing all repos)

If the user provided seed terms in Batch 2 of the interview, populate the Terms table:

```markdown
## Terms

| Term | Definition | Aliases to avoid |
|------|-----------|-----------------|
| {term 1} | {definition 1} | {aliases 1} |
| {term 2} | {definition 2} | {aliases 2} |
| {term 3} | {definition 3} | {aliases 3} |
```

If the user did not provide seed terms, write the template as-is with empty tables.

After writing, print: "Created CONTEXT.md at `{path}`. Agents will read this before starting work."

---

## Phases 4.4–4.5: Harness Baseline and Plugin Updates

Load `references/setup-baseline-and-updates.md` and follow it: stamp the managed
Harness baseline block from `plugins/harness/templates/AGENTS_Baseline.md` into the
repo's instruction file, then report whether the `studio-moser` marketplace is
registered and auto-updating. Carry its plugin-update line into the Phase 8 summary.

---

## Phase 5: Create ADR Directory

If the user opted in to ADRs (default: yes), create the directory and seed the template.

### Create directory

```bash
mkdir -p "{primary_repo_root}/docs/adr"
```

### Copy ADR template

Read the template from `$pm/templates/adr-template.md`. Write it to:

```
{primary_repo_root}/docs/adr/0000-template.md
```

The template file serves as both documentation and a copy source. When agents create new ADRs, they copy this file and fill in the placeholders.

Print: "Created ADR directory at `docs/adr/` with template `0000-template.md`."

---

## Phase 6: Backend Provisioning

**(backend step)** — follow the provisioning section in the one loaded backend
reference. Record its results for Phase 8. A backend may have no provisioning
work.

---

## Phase 7: Scaffold planning/ Directory

Load `references/setup-planning-scaffold.md` and follow it: keep an existing
`planning/` directory and warn about missing backlog files, or create the same
structure Product Pulse setup creates so PM works standalone.

---

## Phase 7.5: Install the Review System

Load `references/setup-review-system.md` and follow it for every configured repository.
This phase is independent of the issue-tracker backend: every repository receives the
managed `REVIEW.md` contract, while GitHub-hosted repositories may also receive the PR
template, verification workflow, CODEOWNERS mappings, and approved merge rules.

Local documentation may be created or refreshed without remote enforcement. Never
guess verification commands, owners, or GitHub settings, and never mutate a ruleset
without the reference's combined preview and explicit approval.

---

## Phase 8: Print Summary

After all scaffolding is complete, print a summary of everything created and next steps.

```
PM — Setup Complete
====================

Project: {project_id}
Backend: {github | trello | local}
Workspace: {single-repo or multi-repo ({N} repos)}
Primary repo: {repo name} ({path})

Files created:
  .pm/config.yml              — PM configuration
  .pm/state.yml               — ingestion watermarks (empty)
  .pm/out-of-scope/README.md  — rejection KB documentation
  CONTEXT.md                  — domain glossary ({N} terms seeded)
  docs/adr/0000-template.md   — ADR template
  REVIEW.md                   — managed review baseline plus project-owned policy
  {GitHub PR/workflow/CODEOWNERS files if created}
  {planning files if created}

Harness: configured for provider-neutral execution and review (verified by Harness)
Plugin updates: {studio-moser auto-updating | auto-update OFF — enable via /plugin → Marketplaces | marketplace missing}

Backend provisioning:
  {summary lines required by the selected backend reference}

Review system:
  {summary lines required by setup-review-system.md for each repository}

--- Next Steps ---

1. Review generated config:
   - .pm/config.yml — backend settings, research dirs, triage thresholds
   - CONTEXT.md — add domain terms as they come up
   - pulse-config.yaml — shared infra config (repos, branches, memory)
   - REVIEW.md — add project failure modes, sensitive paths, checks, and exclusions

2. Populate the backlog:
   - If you have research reports: run /pm:ingest
   - To add items manually: run /pm:triage or use the configured backend

3. Triage and prioritize:
   - /pm:triage — classify, size, and prioritize backlog items

4. Start building:
   - /pm:sprint-dev — pick up ready items and execute

5. Keep things in sync:
   - /pm:reconcile — sync the configured tracker with local backlog state
```

Adjust the summary based on what was actually created and omit skipped phases.

---

## Edge Cases

- **Files already exist**: Ask before overwriting, because these files often hold hand-edited project knowledge. For `.pm/config.yml`, offer to show a diff of what would change. For `CONTEXT.md`, offer to merge new seed terms into the existing file.

- **Backend-specific failures**: **(backend step)** — follow the errors section in
  the loaded backend reference.

- **Multi-repo with no pulse-config.yaml**: Interview must capture all repo names, paths, and roles. Create the full `pulse-config.yaml` with the repos list.

- **Product Pulse already set up**: Common case. Read everything you can from `pulse-config.yaml` and skip redundant questions. The `planning/` directory likely exists already — just verify its contents.

- **User wants to change backend later**: Re-run `/pm:setup` and migrate existing
  items manually; setup does not migrate tracker state.

- **Existing CONTEXT.md at a different path**: If `.pm/config.yml` points `context_md` at a non-default path, respect it. Don't create a second copy.

- **No research reports**: That's fine. Set `research_dirs` to an empty list and skip the ingest recommendation in next steps. The user can add research directories later by editing `.pm/config.yml`.
