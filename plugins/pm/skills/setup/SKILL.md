---
name: setup
description: >-
  Onboard PM to a new project. Detects workspace type (single-repo or multi-repo),
  wires up issue tracker backend (GitHub Issues or local), creates .pm/ config
  directory, CONTEXT.md glossary, ADR template, out-of-scope rejection KB, and a
  model-selection rubric that the dev/sprint skills route sub-agents by.
  If product-pulse is installed, reads shared config from pulse-config.yaml.
  Run once per workspace. Trigger: "setup pm", "initialize project management",
  "configure issue tracking", or /pm:setup.
disable-model-invocation: true
effort: medium
allowed-tools: "Bash Read Write Edit"
---

# PM — Setup

You are the onboarding wizard for **PM**, a backend-agnostic project management system for AI-native teams. Your job is to detect the workspace layout, interview the user about their issue tracking preferences and domain knowledge, then scaffold everything needed for the ingest, triage, reconcile, and sprint-dev skills to operate.

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

### Step 1c: Detect existing GitHub remote

For the primary repo, extract the GitHub owner and repo name:

```bash
git remote get-url origin 2>/dev/null
```

Parse the owner/repo from HTTPS (`https://github.com/OWNER/REPO.git`) or SSH (`git@github.com:OWNER/REPO.git`) format. Store these as defaults for the GitHub backend configuration.

### Step 1d: Check for existing .pm/ directory

If `.pm/config.yml` already exists, warn the user:

"Found existing PM configuration at `{path}/.pm/config.yml`. Do you want to reconfigure from scratch, or keep the existing setup?"

If they want to keep it, exit early with a summary of what's already configured.

---

## Phase 2: Interview

Gather PM configuration by asking the user directly. Ask in focused batches — don't overwhelm with everything at once.

### Batch 1: Issue Tracker Backend

Ask these together:

1. **Which issue tracker backend do you want?**
   - **GitHub Issues** (default) — uses `gh` CLI to create issues, labels, and sub-issues in your GitHub repo. Best when you already use GitHub for code review.
   - **Trello** — uses the Trello MCP server (`@delorenj/mcp-server-trello`) to manage cards across one or more boards. Best when stakeholders prefer a visual board, when items represent ongoing conversations rather than discrete tickets, or when you want to mix non-engineering work into the same backlog.
   - **Local markdown** — stores items as YAML files in `.pm/items/`. No external dependencies. Good for private projects or offline workflows.

2. **If GitHub Issues**: **(backend step)** — follow your loaded `references/setup-github.md` (§ Batch 1: GitHub owner/repo confirm).

3. **If Trello**: continue to Batch 1.5.

4. **If local**: nothing further; skip to Batch 2.

5. **If multi-repo and no pulse-config.yaml**: Ask which repo is primary (holds `.pm/`, `planning/`, issue tracking state) and list the other repos with a brief description of each.

**Backend dispatch.** PM uses one backend per project. Once the backend is chosen, load ONLY `references/setup-<backend>.md` (`setup-github.md`, `setup-trello.md`, or `setup-local.md`) and follow its steps wherever a phase below is marked **(backend step)**. Ignore the other backends' files entirely.

### Batch 1.5: Trello Setup (only when backend == trello)

**(backend step)** — follow your loaded `references/setup-trello.md` (§ Batch 1.5: Trello Setup), then return here. Skip entirely for GitHub/local.

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
   - `shelby` (default — looks for tools matching `mcp__shelby-memory__*`)
   - `null` (skip memory operations entirely)
   - Any other prefix matching your memory MCP's tool names

### Batch 5: Model-Routing Rubric

`pm:sprint-dev` and `pm:dev-task` route each sub-agent to a model by task altitude — a cheaper capable model for clear-spec mechanical work, the strongest model for ambiguous or taste-sensitive work. That routing reads a **model-selection rubric** from this developer's **user-global** store (one file per dev, shared across every repo they touch — resolved via `"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh"`), not from this repo's `CLAUDE.md`/`AGENTS.md`. This batch just makes sure the dev has one; Phase 4.5 does the actual creation/refresh.

1. **Check whether it exists:**

   ```bash
   "$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh" --check
   ```

   - `set` → tell the user: `"Found your model rubric at {path} — sprint-dev and dev-task will route by it."` Offer a refresh only if its `reviewed:` date is **>14 days** old, or it lists a model you can see has been superseded. Otherwise, nothing more to do here.
   - `unset` → note that Phase 4.5 will walk them through creating one. Don't duplicate its creation steps here — just flag intent to opt in and move on.

   Remember this `set`/`unset` result — Phase 4.5 reuses it instead of re-running the check.

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

**(backend step)** — GitHub and local: follow your loaded `references/setup-<backend>.md` (§ Generate .pm/config.yml). Trello: see the next section.

### Generate .pm/config.yml — Trello backend

If the backend is `trello`, write this body (replace `{...}` from interview answers; copy the canonical example from `plugins/pm/schemas/pm-config.trello.example.yml` for any field the user did not customize):

```yaml
# PM Configuration
# Generated by /pm:setup on {DATE}

backend: trello

context_md: CONTEXT.md
adr_dir: docs/adr
out_of_scope_dir: .pm/out-of-scope

research_dirs:
  - {first research dir, e.g. Research}

triage:
  stale_threshold_days: {threshold from interview, default 30}

trello:
  webhook_url: "{webhook URL from Batch 1.5 step 6, or empty string}"

  boards:
    {for each selected board, emit:}
    - id: "{board id}"
      name: "{board name}"
      lists:
        needs_triage:    "{user-confirmed name}"
        ready_for_agent: "{user-confirmed name}"
        in_progress:     "{user-confirmed name}"
        review:          "{user-confirmed name}"
        done:            "{user-confirmed name}"
        needs_changes:   "{user-confirmed name}"
        blocked:         "{user-confirmed name}"
      approval_steps: [{from interview}]
      review_policy: "{from interview, default self}"
      worker_instructions: "{from interview, default empty}"

  statuses:
    needs_triage:    [ready_for_agent, rejected]
    ready_for_agent: [in_progress]
    in_progress:     [review, blocked, needs_changes]
    review:          [done, needs_changes]
    done:            [needs_changes]
    needs_changes:   [in_progress]
    blocked:         [in_progress, cancelled]
```

After writing, validate immediately:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/validate-config.sh" "$primary_repo_root/.pm/config.yml"
```

If validation fails, surface the errors and stop — do not proceed to Phase 6T.

### Generate .pm/state.yml

This file tracks ingestion watermarks. Start empty — the ingest skill populates it:

```yaml
# Ingestion watermarks — updated by /pm:ingest
last_ingested: {}
last_reconcile: null
```

### Generate .pm/out-of-scope/README.md

Read the template from `templates/oos-readme.md` (relative to this skill's plugin directory at `plugins/pm/`). Write it to `.pm/out-of-scope/README.md`.

### Create or update pulse-config.yaml (if it doesn't exist)

If Phase 1 did not find a `pulse-config.yaml`, create a minimal one in the primary repo root:

```yaml
project_id: {slug from interview}

repos:
  - name: {primary repo name}
    path: .
    role: primary
  # Multi-repo: add sibling repos here
  # - name: {repo-name}
  #   path: ../{repo-name}

default_branch: {branch from interview, default main}

memory:
  connector: {connector from interview, default shelby}

backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

If `pulse-config.yaml` already exists but lacks a `backlog:` section, append the `backlog:` block to it.

---

## Phase 4: Create CONTEXT.md

Read the template from `templates/context-md.md` (relative to this skill's plugin directory at `plugins/pm/`).

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

## Phase 4.4: Stamp the Studio Moser baseline block

Every repo — regardless of who works on it — gets the same managed baseline block in its `AGENTS.md`: house-rules essentials + the model-routing reminder that points a plugin-less dev's agent at the public setup walkthrough. This is what reaches developers who never install PM.

1. Resolve the target per the "Where the baseline block goes" rule (`references/model-orchestration.md`): `AGENTS.md` if it exists, or if neither `AGENTS.md` nor `CLAUDE.md` exists; `CLAUDE.md` directly only when it's the sole file present.

```bash
if [ -f "$primary_repo_root/AGENTS.md" ]; then
  TARGET="$primary_repo_root/AGENTS.md"
elif [ -f "$primary_repo_root/CLAUDE.md" ]; then
  TARGET="$primary_repo_root/CLAUDE.md"
else
  TARGET="$primary_repo_root/AGENTS.md"
fi
```

   If `$TARGET` is `AGENTS.md`, make sure `CLAUDE.md` imports it: if `CLAUDE.md` exists but has no `@AGENTS.md` line, add one; if `CLAUDE.md` doesn't exist, create a minimal one containing just `@AGENTS.md`.

2. Fetch the current block body from the canonical source (fall back to the copy bundled in the plugin if offline):

```bash
BODY="$(mktemp)"
curl -fsS "https://raw.githubusercontent.com/Studio-Moser/skills-n-stuff/main/studio-baseline/AGENTS_Baseline.md" -o "$BODY" \
  || cp "$CLAUDE_PLUGIN_ROOT/../../studio-baseline/AGENTS_Baseline.md" "$BODY" 2>/dev/null \
  || { echo "could not obtain baseline body"; }
```

3. Stamp it (idempotent — safe to re-run; never clobbers the repo's own content) — but only if the fetch actually produced a body. An empty `$BODY` means both the fetch and the bundled fallback failed; stamping it would wipe out any existing block instead of preserving it, so skip the stamp and say so:

```bash
if [ ! -s "$BODY" ]; then
  echo "Could not obtain the baseline block (offline, and no bundled copy found). Skipping the baseline stamp — re-run /pm:setup with network access or a full plugin checkout."
else
  "$CLAUDE_PLUGIN_ROOT/scripts/stamp-baseline.sh" "$TARGET" "$BODY"
fi
```

4. If the stamp ran, tell the user the block was stamped/refreshed and that it's committed with the rest of setup, so every teammate inherits it on clone.

---

## Phase 4.5: Establish the Model-Selection Rubric

The rubric is **per developer, user-global** — one file at `$("$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh")` (`${XDG_CONFIG_HOME:-$HOME/.config}/studio-moser/model-rubric.yml`), shared across every repo this dev touches — NOT written into the repo's `AGENTS.md`. The repo only carries the *reminder* to load it (stamped in Phase 4.4).

1. **Reuse Batch 5's check.** Batch 5 of the interview already ran `rubric-path.sh --check` for this pass — don't re-invoke it. Using that `set`/`unset` result:

- `set` → tell the user their rubric is in place; offer a refresh if its `reviewed:` date is **>14 days** old or it lists a superseded model. A refresh re-pulls Artificial Analysis for cost + intelligence and keeps the dev's taste scores + capabilities. Done.
- `unset` → walk them through creating one (next step).

2. **Create the rubric** by following the canonical walkthrough at `studio-baseline/Rubric_Setup.md` (read it from `$CLAUDE_PLUGIN_ROOT/../../studio-baseline/Rubric_Setup.md`, or fetch the raw URL): discover the current lineup **preferring the Artificial Analysis API** (`"$CLAUDE_PLUGIN_ROOT/scripts/fetch-model-data.sh"` when `ARTIFICIAL_ANALYSIS_API_KEY` is set → pricing → cost, coding/agentic index → intelligence; else vendor docs / judgment), score on cost/intelligence/taste for **this dev's** ecosystem, capture `capabilities` (e.g. `codex`), show the table for tweaks, then write the YAML to the path from `rubric-path.sh`. Stamp today's date in `reviewed:`. Stay inside the dev's own ecosystem — propose only models from families/CLIs they confirmed; add a cross-vendor tier (e.g. Codex/gpt-5.5) only if they confirm they have that CLI.

3. **Migrate any legacy in-repo rubric.** If a prior setup wrote a "Picking the right models" section into this repo's `AGENTS.md`/`CLAUDE.md`, move its scores into the user-global rubric (if the dev confirms they're theirs) and delete that section from the repo file — the rubric no longer lives in the repo. Leave the Phase 4.4 baseline reminder in place.

---

## Phase 5: Create ADR Directory

If the user opted in to ADRs (default: yes), create the directory and seed the template.

### Create directory

```bash
mkdir -p "{primary_repo_root}/docs/adr"
```

### Copy ADR template

Read the template from `templates/adr-template.md` (relative to this skill's plugin directory at `plugins/pm/`). Write it to:

```
{primary_repo_root}/docs/adr/0000-template.md
```

The template file serves as both documentation and a copy source. When agents create new ADRs, they copy this file and fill in the placeholders.

Print: "Created ADR directory at `docs/adr/` with template `0000-template.md`."

---

## Phase 6G: Set Up GitHub Labels (skip if backend != github)

**(backend step)** — follow your loaded `references/setup-github.md` (§ Phase 6G: Set Up GitHub Labels).

---

## Phase 6T: Set Up Trello Lists, Labels & Webhook (skip if backend != trello)

**(backend step)** — follow your loaded `references/setup-trello.md` (§ Phase 6T: Set Up Trello Lists, Labels & Webhook) to create lists, labels, and register the webhook. Skip for GitHub/local.

---

## Phase 6P: GitHub Project (optional, skip if backend != github)

The optional Projects v2 visualization layer is detailed in `references/setup-github-projects.md` — create/link a project, mirror status labels to a Status field. Skip if you don't want a project board; the label-based workflow is fully functional without it.

---

## Phase 7: Scaffold planning/ Directory

Check whether `planning/` already exists in the primary repo root (Product Pulse setup creates this directory).

### If planning/ already exists

Print: "Found existing `planning/` directory — skipping scaffold. PM will use the existing backlog files."

Verify these files exist and warn if any are missing:
- `planning/todos.md`
- `planning/ideas.md`
- `planning/WORKFLOW.md`
- `planning/archive/`
- `planning/specs/_TEMPLATE.md`

### If planning/ does not exist

Create the same structure that Product Pulse setup creates. This ensures PM works standalone without requiring Product Pulse.

```
planning/
├── todos.md          # Live work queue
├── ideas.md          # Incoming ideas staging
├── WORKFLOW.md       # Lifecycle documentation
├── archive/          # Done rows older than 7 days
└── specs/
    └── _TEMPLATE.md  # Spec template for ready items
```

#### Generate planning/todos.md

Read the template from `templates/todos-md.md` (relative to this skill's plugin directory at `plugins/pm/`). Replace `{project name or project_id}` with the actual project identifier and `{DATE}` with today's date. Write to `{planning_dir}/todos.md`.

#### Generate planning/ideas.md

Read the template from `templates/ideas-md.md`. Apply the same placeholder substitutions. Write to `{planning_dir}/ideas.md`.

#### Generate planning/WORKFLOW.md

Read the template from `templates/workflow-md.md`. Write to `{planning_dir}/WORKFLOW.md` (no placeholder substitution needed — this is reference documentation).

#### Generate planning/specs/_TEMPLATE.md

Read the template from `templates/spec-template.md`. Write to `{planning_dir}/specs/_TEMPLATE.md` (no placeholder substitution — agents copy this file and fill in placeholders when creating new specs).

#### Create planning/archive/

Create the empty directory. Sprint-dev creates quarterly files (e.g. `done-2026-Q2.md`) when archiving.

#### Update pulse-config.yaml

If `pulse-config.yaml` exists but lacks a `backlog:` section, append:

```yaml
backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

---

## Phase 8: Print Summary

After all scaffolding is complete, print a summary of everything created and next steps.

```
PM — Setup Complete
====================

Project: {project_id}
Backend: {github or local}
Workspace: {single-repo or multi-repo ({N} repos)}
Primary repo: {repo name} ({path})

Files created:
  .pm/config.yml              — PM configuration
  .pm/state.yml               — ingestion watermarks (empty)
  .pm/out-of-scope/README.md  — rejection KB documentation
  CONTEXT.md                  — domain glossary ({N} terms seeded)
  docs/adr/0000-template.md   — ADR template
  {planning files if created}

Model rubric: {created at {user-global rubric-path.sh path} | found existing at {user-global rubric-path.sh path} | skipped}
  {if created/found:} sprint-dev and dev-task route sub-agents by it.

{If GitHub backend:}
GitHub labels created: {N} labels in {owner}/{repo}
  status/needs-triage, status/ready, status/in-progress, status/in-review, status/done,
  owner/ai, owner/human, owner/operator,
  priority/p0, priority/p1, priority/p2, priority/p3,
  blocker, spawned-during-sprint, epic, size/S, size/M, size/L, size/XL

{If Phase 6P created or linked a project:}
GitHub Project: {created | linked}
  URL:                {project URL}
  Number:             {N}
  Status field sync:  {enabled | disabled}
  Items added:        {N (Path A only — omit for Path B)}
  Next: see README "GitHub Project integration" for one-time workflow/view setup.

{If Phase 6P was skipped or MCP not available:}
GitHub Project: skipped (label-only mode)

{If Trello backend:}
Trello configuration:
  Boards configured:   {N}
  Lists created:       {created} (of {total} required)
  Lists already existed: {existing}
  Webhook registered:  {yes / no / failed: {reason}}
  Validate any time:   "$CLAUDE_PLUGIN_ROOT/scripts/validate-config.sh" .pm/config.yml

--- Next Steps ---

1. Review generated config:
   - .pm/config.yml — backend settings, research dirs, triage thresholds
   - CONTEXT.md — add domain terms as they come up
   - pulse-config.yaml — shared infra config (repos, branches, memory)

2. Populate the backlog:
   - If you have research reports: run /pm:ingest
   - To add items manually: run /pm:triage
   - To add items via GitHub: create issues with the "status/needs-triage" label

3. Triage and prioritize:
   - /pm:triage — classify, size, and prioritize backlog items

4. Start building:
   - /pm:sprint-dev — pick up ready items and execute

5. Keep things in sync:
   - /pm:reconcile — sync GitHub Issues with local backlog state
```

Adjust the summary based on what was actually created — omit sections for skipped phases (e.g., no GitHub labels if backend is local, no planning files if they already existed).

---

## Edge Cases

- **Files already exist**: Always ask before overwriting. For `.pm/config.yml`, offer to show a diff of what would change. For `CONTEXT.md`, offer to merge new seed terms into the existing file.

- **No git remote**: If `git remote get-url origin` fails, the GitHub backend isn't viable. Default to local backend, or ask the user to add a remote first.

- **GitHub CLI edge cases** (not installed, not authenticated, private repo access): **(backend step)** — see `references/setup-github.md` (§ Edge Cases).

- **Multi-repo with no pulse-config.yaml**: Interview must capture all repo names, paths, and roles. Create the full `pulse-config.yaml` with the repos list.

- **Product Pulse already set up**: Common case. Read everything you can from `pulse-config.yaml` and skip redundant questions. The `planning/` directory likely exists already — just verify its contents.

- **User wants to change backend later**: Note that switching from local to GitHub (or vice versa) requires re-running `/pm:setup` and migrating existing items. The setup skill doesn't handle migration — that's a manual process.

- **Existing CONTEXT.md at a different path**: If `.pm/config.yml` points `context_md` at a non-default path, respect it. Don't create a second copy.

- **No research reports**: That's fine. Set `research_dirs` to an empty list and skip the ingest recommendation in next steps. The user can add research directories later by editing `.pm/config.yml`.

- **Model rubric location**: The rubric is always the single user-global store file (`"$CLAUDE_PLUGIN_ROOT/scripts/rubric-path.sh"`) — there's no repo-local copy to offer or reconcile. The repo itself only carries the Phase 4.4 baseline reminder block, which points a dev's agent at that store; it never holds the rubric's contents.

- **Unknown ecosystem**: If you genuinely can't tell which model family you belong to, don't guess model names — ask the user which assistant/CLI they run this project with and rank the models they name.
