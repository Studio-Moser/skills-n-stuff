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

2. **If GitHub Issues**: Confirm the owner/repo detected from the git remote.
   - "I detected `{owner}/{repo}` from your git remote. Is that correct?"
   - If the user has a multi-repo workspace, ask: "Should PM create issues in the primary repo only, or across all repos? (Default: primary repo only, with labels indicating target repo.)"

3. **If Trello**: continue to Batch 1.5.

4. **If local**: nothing further; skip to Batch 2.

5. **If multi-repo and no pulse-config.yaml**: Ask which repo is primary (holds `.pm/`, `planning/`, issue tracking state) and list the other repos with a brief description of each.

### Batch 1.5: Trello Setup (only when backend == trello)

Ask these in sequence. Each step uses an MCP tool; do not proceed past a failed call.

1. **Authenticate.** Confirm `TRELLO_API_KEY` and `TRELLO_TOKEN` are exported in the user's shell. If either is missing:

   "I need a Trello API key and token. Get them at https://trello.com/app-key (key) and the 'Token' link on that page. Add to your shell profile:

   ```bash
   export TRELLO_API_KEY=...
   export TRELLO_TOKEN=...
   ```

   Then re-run /pm:setup."

   Stop the wizard if either is missing.

2. **List boards.** Call:

   ```
   mcp__trello__list_boards({})
   ```

   Present the result as a numbered menu:

   ```
   Available Trello boards:
     [1] Moby App        — id abc123def456
     [2] Moby Website    — id xyz789...
     [3] Personal        — id ...
   ```

3. **Pick boards.** Ask: "Which board(s) should PM manage? Comma-separated numbers, or 'all'."

   Capture the chosen board(s) into `selected_boards`.

4. **For each selected board**, ask the per-board questions:

   ```
   For board "{name}" (id {id}):
   - Approval steps (comma-separated, e.g. "tech_lead,product"; blank = none):
   - Review policy (self | judge | auto, default self):
   - Worker instructions (one paragraph, blank to skip):
   ```

5. **List names.** For each selected board, call:

   ```
   mcp__trello__set_active_board({ boardId: $BOARD_ID })
   mcp__trello__get_lists({})
   ```

   Compare the existing list names against the seven required keys (`needs_triage`, `ready_for_agent`, `in_progress`, `review`, `done`, `needs_changes`, `blocked`). For each match found, propose the existing name as the value. For each missing name, ask the user what name to use (suggest the title-case default e.g. "Needs Triage", "Ready", etc.) — these go into `boards[i].lists`. Lists that don't yet exist will be created in Phase 6T.

6. **Webhook URL.** Ask: "What URL should Trello send card events to? (Leave blank to skip — events won't reach Shelby until you fill this in. Example: https://shelby.example.com/webhooks/trello.)"

   Store as `trello.webhook_url`.

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

`pm:sprint-dev` and `pm:dev-task` route each sub-agent to a model by task altitude — a cheaper capable model for clear-spec mechanical work, the strongest model for ambiguous or taste-sensitive work. That routing reads a **model-selection rubric** from the project's `CLAUDE.md`/`AGENTS.md` or the user's global agent config. This batch makes sure one exists.

1. **Look for an existing rubric** — a "Picking the right models" (or similar model-routing) section, checked in this order:
   - the primary repo's `CLAUDE.md`, then `AGENTS.md`;
   - the user's global agent config for whatever assistant is running this skill (e.g. `~/.claude/CLAUDE.md` for Claude Code, `~/.codex/AGENTS.md` for Codex).

   **If found:** print `"Found a model rubric in {path} — sprint-dev and dev-task will route by it."`, confirm the user wants to keep it, record the path, and skip to Batch 5's end (Phase 4.5 becomes a no-op). **But first check its freshness:** if the rubric carries a "reviewed {date}" stamp that's more than ~90 days old, or it lists a model you can see has been superseded, say so and offer to refresh it (re-runs the Phase 4.5 discovery + rescore, then restamps the date). Refreshing updates in place — it never duplicates the section.

   **If not found:** offer to co-create one:

   > "No model-routing rubric found. Want me to add one? It tells the dev/sprint skills which model to hand each task to, so you're not paying top-tier rates for boilerplate. I'll propose defaults for the models in *this* assistant's own ecosystem — you adjust."

2. **If the user opts in, gather two things** (defaults in Phase 4.5 do the rest):
   - **Axes to rank on** — default **cost, intelligence, taste** (intelligence = hardest problem handled unsupervised; taste = UI/UX, code quality, API/SDK design, copy). Accept edits.
   - **Where it lives** — default the primary repo's `CLAUDE.md` (travels with the repo, applies for teammates); alternative is the user's global agent config (applies to every project).

   **Stay inside your own ecosystem.** You — the assistant reading this skill — know which model family you are. Propose only models from that family and its native subagent/workflow mechanism; do **not** assume the user has another vendor's CLI (a Claude host does not reach for OpenAI Codex/gpt-5.5, and vice versa). Add a cross-vendor worker tier **only if the user says they have that CLI/subscription wired up.**

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

Build from interview answers. This file controls how PM skills behave:

```yaml
# PM Configuration
# Generated by /pm:setup on {DATE}

# Issue tracker backend: github | local
backend: {github or local}

# GitHub backend settings (only used when backend: github)
github:
  owner: {owner from git remote or interview}
  repo: {repo from git remote or interview}
  # For multi-repo workspaces, target repos receive issues with a repo label.
  # Uncomment and list target repos if PM should create issues across repos:
  # target_repos:
  #   - owner/repo-name
  # Optional GitHub Projects v2 mirroring is written by Phase 6P, not here.
  # If Phase 6P is skipped, the `project_sync` block is intentionally absent
  # (which means "off"). See plugins/pm/schemas/pm-config.github.example.yml.

# Where to find research reports for ingestion
# Paths relative to primary repo root
research_dirs:
  - {first research dir, e.g. Research}
  # - {additional dirs if provided}

# Triage settings
triage:
  stale_threshold_days: {threshold from interview, default 30}

# Domain knowledge paths (relative to primary repo root)
context_md: CONTEXT.md
adr_dir: docs/adr

# Out-of-scope rejection knowledge base
out_of_scope_dir: .pm/out-of-scope
```

If the backend is `local`, omit the `github:` section entirely and add:

```yaml
# Local backend settings
local:
  items_dir: .pm/items
```

And create the `.pm/items/` directory.

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

## Phase 4.5: Establish the Model-Selection Rubric

**Skip entirely** if Batch 5 found an existing rubric (just carry its path into the Phase 8 summary) or the user declined to create one.

Otherwise, draft a rubric for **this assistant's own ecosystem only** (per Batch 5) and write it to the location the user chose (default: primary repo `CLAUDE.md`).

**Discover the current lineup first — don't trust your training-cutoff memory of model names.** Model families turn over; the model you remember as "Sonnet" may be renamed or replaced by setup time. Before drafting, look up what's actually current *right now* for your own ecosystem, if a web tool is available:
- **Names + cost** — your own vendor's current models/pricing docs are authoritative. Use the models that exist today; if one you remember is gone, use its stated replacement.
- **Relative standing (intelligence, taste)** — cross-check against a live model-comparison source rather than guessing. Good general references (use whatever's reachable, treat as inputs not gospel): Artificial Analysis (`artificialanalysis.ai`) for an intelligence index + pricing, LMArena (`lmarena.ai`) for human-preference ranking (a decent proxy for taste), and the Aider polyglot leaderboard (`aider.chat/docs/leaderboards`) for coding specifically. Taste is subjective — lean on judgment, use benchmarks only to sanity-check.
- **No web access?** Fall back to your own knowledge, draft the rubric, and add a visible `(drafted offline — verify model names are current)` note so the user knows to check.

Then give each model a starting score on the user's chosen axes and a short "how to apply" block. Structure:

```markdown
## Picking the right models for workflows and subagents

Higher = better. Intelligence = hardest problem handled unsupervised. Taste = UI/UX, code quality, API/SDK design, copy.

| model | cost | intelligence | taste |
|-------|------|--------------|-------|
| {cheapest capable coder in your family} | … | … | … |
| {balanced mid-tier}                     | … | … | … |
| {most capable}                          | … | … | … |

How to apply:
- Defaults, not limits — escalate to a stronger model without asking if output misses the bar; judge the output, not the price.
- Bulk/mechanical, clear-spec work (implementation, migrations, data/log digging) → the cheapest capable model.
- User-facing work (UI, copy, API/SDK design) → needs taste ≥ {threshold, e.g. 7}.
- Reviews of plans/implementations → a strong model, optionally a second independent one for another perspective.
- Keep reasoning effort matched to difficulty; don't default to the top effort tier.
- {Your family}'s models are dispatched via the {Agent/Workflow model parameter, or your host's equivalent}.
- Every implementation sub-agent or workflow prompt carries: reuse existing code, stdlib/platform first, shortest working diff, no speculative abstractions, root cause over symptom.

_Rubric reviewed {today's date}, sources: {what you checked — vendor docs / benchmark / offline}. Re-assess when a newer model in your family ships or after ~90 days, whichever comes first: re-check the lineup and rescore, then update this date._
```

If, and only if, the user confirmed they also run another assistant/CLI, append a short note naming that cross-vendor worker tier and how it's invoked — nothing they didn't confirm.

**Before writing:** show the drafted table and let the user tweak the numbers or model choices. **Never clobber** — if the target file exists, append the section (or merge into an existing models section); if it doesn't, create it. After writing, print the path and note that sprint-dev/dev-task will now route by it.

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

**Skip this phase unless backend is `github`.**

Use the `gh` CLI to create PM labels in the primary repo. These labels are used by triage, sprint-dev, and reconcile skills to track issue lifecycle state.

### Create labels

```bash
for label in \
  "status/needs-triage:d4c5f9" \
  "status/ready:0e8a16" \
  "status/in-progress:1d76db" \
  "status/in-review:0052cc" \
  "status/done:6f42c1" \
  "owner/ai:c5def5" \
  "owner/human:fbca04" \
  "owner/operator:f9d0c4" \
  "priority/p0:b60205" \
  "priority/p1:d93f0b" \
  "priority/p2:fbca04" \
  "priority/p3:c5def5" \
  "blocker:d93f0b" \
  "spawned-during-sprint:c2e0c6" \
  "epic:5319e7" \
  "size/S:e6e6e6" \
  "size/M:e6e6e6" \
  "size/L:e6e6e6" \
  "size/XL:e6e6e6"; do
  name="${label%:*}"
  color="${label##*:}"
  gh label create "$name" --color "$color" --force 2>/dev/null || true
done
```

### Label descriptions

The taxonomy is namespaced: an item's pipeline position is described by a `status/*` label plus an `owner/*` label. `priority/*`, `size/*`, and flags like `blocker` are orthogonal.

| Label | Color | Purpose |
|-------|-------|---------|
| `status/needs-triage` | `#d4c5f9` (lavender) | New issue awaiting triage classification |
| `status/ready` | `#0e8a16` (green) | Triaged and specced — ready to be picked up (pair with an `owner/*` label) |
| `status/in-progress` | `#1d76db` (blue) | Currently being worked on |
| `status/in-review` | `#0052cc` (dark blue) | PR open, awaiting merge |
| `status/done` | `#6f42c1` (purple) | Shipped and closed |
| `owner/ai` | `#c5def5` (light blue) | An AI agent is the intended worker |
| `owner/human` | `#fbca04` (yellow) | A human is the intended worker |
| `owner/operator` | `#f9d0c4` (peach) | Needs Tim's hands — ops/manual steps |
| `priority/p0` | `#b60205` (dark red) | Drop-everything blocker |
| `priority/p1` | `#d93f0b` (red) | High priority, this sprint |
| `priority/p2` | `#fbca04` (yellow) | Normal |
| `priority/p3` | `#c5def5` (light blue) | Low / someday |
| `blocker` | `#d93f0b` (red) | Blocks other work — escalate (urgency flag, orthogonal to status) |
| `spawned-during-sprint` | `#c2e0c6` (light green) | Created by an agent during sprint execution |
| `epic` | `#5319e7` (purple) | Goal container — groups related issues as the group-by-Parent rows. Carries no `status/*` label and no board status column; its body is a Goal/Why statement, not an item checklist (see `/pm:triage` Phase 4.3) |
| `size/S` | `#e6e6e6` (gray) | Small: < 1 hour |
| `size/M` | `#e6e6e6` (gray) | Medium: 1-4 hours |
| `size/L` | `#e6e6e6` (gray) | Large: 4+ hours, needs spec |
| `size/XL` | `#e6e6e6` (gray) | Extra large: multi-day, needs spec + chunking |

**Note on `sprint/*`**: optional sprint cohort labels (e.g. `sprint/2026-05-12`) are a convention the plugin documents but doesn't auto-create. Add them by hand or via your own automation when you start a sprint.

### Multi-repo label sync

If the user has a multi-repo workspace and chose to track issues across repos, offer to create the same labels in each target repo:

"Should I create these labels in your other repos too? ({list of target repos})"

If yes, run the same `gh label create` loop for each target repo, using `--repo {owner}/{repo-name}`.

Print the results — how many labels were created vs. already existed.

---

## Phase 6T: Set Up Trello Lists, Labels & Webhook (skip if backend != trello)

Skip this entire phase if `backend != trello`.

### 6T.1 For each board, create missing lists

For each `boards[i]` in the freshly-written config, call:

```
mcp__trello__set_active_board({ boardId: $BOARD_ID })
existing = mcp__trello__get_lists({})
```

For each of the seven required list names from `boards[i].lists`, if the name is not in `existing`, call:

```
mcp__trello__add_list_to_board({ name: $LIST_NAME })
```

Track which lists were created (for the summary) vs already existed.

### 6T.2 Validate board access

After list creation, call `mcp__trello__get_active_board_info({})` and confirm the response. If it errors with "board not found" or auth failure, instruct the user to verify their token's read/write scopes for the board and stop.

### 6T.3 Register webhook (idempotent)

If `trello.webhook_url` is non-empty, register a webhook for the board.

**This step is idempotent.** Trello's `POST /1/webhooks` does NOT dedupe by `(idModel, callbackURL)` — re-running `/pm:setup` would otherwise create one duplicate webhook per board per run, and your receiver would see N copies of every event. Always list-then-create:

**Step 1 — List existing webhooks for this token (once, outside the per-board loop):**

```bash
existing_webhooks_json="$(curl -fsS \
  "https://api.trello.com/1/tokens/$TRELLO_TOKEN/webhooks?key=$TRELLO_API_KEY&token=$TRELLO_TOKEN")"
```

The response is a JSON array of webhook objects, each with at least `id`, `idModel`, `callbackURL`, and `active`.

**Step 2 — Per board, check whether a matching webhook already exists:**

A webhook is considered a match when `idModel == $BOARD_ID` AND `callbackURL == $webhook_url` (active OR inactive — re-using inactive webhooks avoids hitting Trello's per-token webhook cap).

```bash
match="$(echo "$existing_webhooks_json" \
  | jq -c --arg board "$BOARD_ID" --arg url "$webhook_url" \
      '.[] | select(.idModel == $board and .callbackURL == $url)' \
  | head -n1)"
```

**Step 3 — Create only if no match:**

```bash
if [ -n "$match" ]; then
  echo "skipped webhook for $BOARD_NAME (already registered: id=$(echo "$match" | jq -r .id))"
  skipped=$((skipped + 1))
else
  curl -fsS -X POST "https://api.trello.com/1/webhooks/" \
    -d "key=$TRELLO_API_KEY" \
    -d "token=$TRELLO_TOKEN" \
    -d "callbackURL=$webhook_url" \
    -d "idModel=$BOARD_ID" \
    -d "description=Shelby PM webhook for $BOARD_NAME" \
    && created=$((created + 1)) \
    || echo "warning: webhook registration failed for $BOARD_NAME (board id $BOARD_ID). Re-run /pm:setup once the webhook URL is reachable."
fi
```

**Step 4 — After the loop, report:**

```
Webhooks: created $created new; skipped $skipped (already registered).
```

Trello does a HEAD request against `callbackURL` before accepting a new webhook — if the URL is not reachable yet (the receiving route is owned by Shelby's W1e workstream), POST returns an error. That is expected; the warning above tells the user how to retry. The card-as-conversation flow only activates once the webhook is live, but all other PM operations work today using direct MCP calls. Re-running `/pm:setup` after the URL is live will create only the missing webhooks (idempotent).

If `trello.webhook_url` is empty, skip this step and emit:

```
note: no webhook_url configured — Shelby will not receive Trello events.
      Run /pm:setup again after deploying the webhook ingress (W1e) to register.
```

### 6T.4 Summary line for Phase 8

Record for the final summary:
- Boards configured: $N
- Lists created (vs already existed): $created / $existing
- Webhook registered: yes / no / failed (with reason)

---

## Phase 6P: GitHub Project (optional, skip if backend != github)

**Skip this phase unless `backend == github`.** Trello and local backends have their own visualization stories.

This phase is OPTIONAL. The plugin's label-based workflow works perfectly without it. The Project is a downstream visualization layer that mirrors `status/*` labels to a Projects v2 Status field — useful when you want a board/table UI with custom fields, but not required for any skill to function.

### 6P.1 Ask the user

Print:

```
Would you like a GitHub Project (Projects v2) to visualize this backlog
alongside labels? Labels remain the source of truth — the project just
makes the work browsable in a board/table UI with custom fields and
timelines.

  1. Create new project (recommended for first-time setup)
  2. Link an existing project I already created
  3. Skip — I'll add this later

Choice [1/2/3]:
```

If **3 (skip)**: do not write a `project_sync` section to `.pm/config.yml`. Print "Skipped — re-run /pm:setup any time to add a project." and continue to Phase 7.

If **1 or 2**: continue to 6P.2.

### 6P.2 Check MCP availability

Try to load the github MCP tool via ToolSearch:

```
ToolSearch query: "select:mcp__github__projects_write"
```

If the tool does NOT load successfully, print:

```
GitHub Projects integration requires the github MCP server. To enable it:

  1. Install the plugin:
       /plugin install github@claude-plugins-official
  2. Add a Personal Access Token to your ~/.claude/settings.json env
     section (scopes: repo, project, read:org):
       "env": {
         "GITHUB_PERSONAL_ACCESS_TOKEN": "ghp_..."
       }
  3. Reload Claude Code.
  4. Re-run /pm:setup to configure the project.

Setup will continue now WITHOUT project sync — your label-based workflow
is fully functional.
```

Do not write a `project_sync` section. Continue to Phase 7.

If the tool loads: continue.

### 6P.3 Path A — Create new project (choice 1)

1. Ask: `"Project title? [default: {gh_owner} — Backlog]"`
2. Ask: `"Make it private? [Y/n]"` — default yes.
3. Call `mcp__github__projects_write` with method `create_project`, passing `owner` (from `github.owner` in config), `title`, and the privacy flag. The response includes the project's `number` and `node_id` — store both.
4. Add custom fields. Call `mcp__github__projects_write` with the appropriate "add field" method for each:
   - `Target date` — type `DATE`
   - `Epic` — type `TEXT`
   (Status is already a default field on every Projects v2 project — do not create a second one.)
5. Link target repos. For each repo in `github.target_repos` (plus `github.owner/github.repo` if not already in that list), call `projects_write` with the "link repository" method.
6. Bulk-add open issues. For each linked repo:
   ```bash
   gh issue list --repo "{owner}/{repo}" --state open \
     --json url,number,labels --limit 1000
   ```
   For each issue returned, call `mcp__github__projects_write` with the "add item" method, passing the issue's URL or node ID. Capture each item's project item ID for the Status assignment in step 8.
7. Configure the Status field options. Call `mcp__github__projects_list` with method `list_project_fields` (or equivalent) to find the existing Status field ID. Then call `projects_write` to set the Status field options, in order, to:
   1. `Needs Triage`
   2. `Ready`
   3. `In Progress`
   4. `In Review`
   5. `Blocked`
   6. `Done`

   Capture each option's ID (you need these for step 8).
8. Set initial Status per item. For each added item, inspect the issue's labels (from the `gh issue list` output) to find its current `status/*` label. Map to the Status option from the table:
   | Label | Status option |
   |-------|---------------|
   | `status/needs-triage` | Needs Triage |
   | `status/ready` | Ready |
   | `status/in-progress` | In Progress |
   | `status/in-review` | In Review |
   | `status/done` | Done |
   | (none / `blocker`) | (leave unset, or Blocked if `blocker` label present) |

   Call `mcp__github__projects_write` with the "update item field value" method to set Status. Batch when the MCP supports it.

9. Persist to `.pm/config.yml` under `github.project_sync`:
   ```yaml
   github:
     owner: {existing}
     repo: {existing}
     project_sync:
       enabled: true
       project_number: {number from step 3}
       project_owner: {gh_owner}
       project_owner_type: org  # or "user" — match the owner type
       project_node_id: "{node_id from step 3}"
       status_field_sync: true
       status_field_id: "{Status field ID from step 7}"
       status_map:
         status/needs-triage: "Needs Triage"
         status/ready:        "Ready"
         status/in-progress:  "In Progress"
         status/in-review:    "In Review"
         status/blocked:      "Blocked"
         status/done:         "Done"
   ```
10. Print the manual playbook reminder:
    ```
    Project created — https://github.com/{type-prefix}/{owner}/projects/{number}

    A few things the MCP can't fully automate. See the
    "GitHub Project integration" section of the plugin README for the
    one-time UI steps:

      - Built-in workflows (auto-add issues, auto-archive done)
      - Custom views (Board by Status, Table by sprint, P0 filter, etc.)

    These take about 5 minutes in the project's web UI.
    ```

### 6P.4 Path B — Link existing project (choice 2)

1. Ask: `"Project number? (e.g. for https://github.com/orgs/Foo/projects/2 enter 2)"`
2. Ask: `"Is this an org-owned or user-owned project? [org/user]"` (default org).
3. Call `mcp__github__projects_get` passing `owner` and `number`. If the call fails (not found, no permission), print the error and ask if the user wants to retry or skip. On skip, write no `project_sync` section and continue.
4. Call `mcp__github__projects_list` with method `list_project_fields` to read the Status field's current options. Compare against the canonical set: `Needs Triage`, `Ready`, `In Progress`, `In Review`, `Blocked`, `Done`.

   If they don't match, ask:
   ```
   The Status field on this project has options [{list}] which don't match
   pm's conventions [Needs Triage, Ready, In Progress, In Review, Blocked, Done].

   Update them? [Y/n]

     Y — pm will set the Status options to match. SAFE on a new project,
         CAREFUL on an existing one: items already assigned to obsolete
         options will be reset.
     n — leave the existing options. PM will skip status mirroring
         (status_field_sync will be set to false).
   ```

   If Y: call `projects_write` to set the options. Capture field ID and option IDs.
   If n: still capture field ID; set `status_field_sync: false`.

5. Persist to `.pm/config.yml` under `github.project_sync` with the values gathered. Use `status_field_sync: false` when the user chose `n` above.

### 6P.5 Closing summary contribution

Record for Phase 8's summary:
- Project: created / linked / skipped
- Project URL (if applicable)
- Status field sync: enabled / disabled
- Items added (if Path A): N

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

Model rubric: {created at {path} | found existing at {path} | skipped}
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

- **gh CLI not installed**: If the GitHub backend is selected but `gh` is not available, warn the user: "The `gh` CLI is required for the GitHub Issues backend. Install it with `brew install gh` and run `gh auth login`, then re-run `/pm:setup`." Fall back to local backend if the user prefers.

- **gh CLI not authenticated**: If `gh auth status` fails, prompt the user to run `gh auth login` first.

- **Multi-repo with no pulse-config.yaml**: Interview must capture all repo names, paths, and roles. Create the full `pulse-config.yaml` with the repos list.

- **Product Pulse already set up**: Common case. Read everything you can from `pulse-config.yaml` and skip redundant questions. The `planning/` directory likely exists already — just verify its contents.

- **User wants to change backend later**: Note that switching from local to GitHub (or vice versa) requires re-running `/pm:setup` and migrating existing items. The setup skill doesn't handle migration — that's a manual process.

- **Existing CONTEXT.md at a different path**: If `.pm/config.yml` points `context_md` at a non-default path, respect it. Don't create a second copy.

- **No research reports**: That's fine. Set `research_dirs` to an empty list and skip the ingest recommendation in next steps. The user can add research directories later by editing `.pm/config.yml`.

- **Private repos without gh access**: If `gh repo view` fails with a permissions error, note this and suggest the user check their `gh` authentication scopes.

- **Model rubric already in global config**: If the only rubric found is in the user's global agent config (not the repo), that's fine — the routing skills still see it, since the global config loads into the agent's context. Offer (don't force) a project-local copy so teammates on the repo get the same routing.

- **Unknown ecosystem**: If you genuinely can't tell which model family you belong to, don't guess model names — ask the user which assistant/CLI they run this project with and rank the models they name.
