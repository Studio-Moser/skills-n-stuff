# product-pulse: configurable plugin + de-fork — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `product-pulse` plugin generic and configuration-aware via per-repo `pulse-config.yaml`, then eliminate the local skill + agent forks in `Shelby-Strategy` and `The Crooked Line/docs`. Fix the push-to-main bug (W16–W19 incident) and the path-casing fragmentation along the way.

**Architecture:** Plugin becomes the single source of truth for skills (daily-research, weekly-strategist, sprint-dev) and agents (5 analysts). Each consuming repo holds two artifacts in its research directory: prose context (`research-context.md`) and operational config (`pulse-config.yaml`). The plugin discovers `pulse-config.yaml` by walking up from cwd; the file's parent directory IS the research directory. Output flow always goes through a branch + PR with optional auto-merge.

**Tech Stack:** Markdown skill files (no compiled code), YAML config, Bash for file operations, `gh` CLI for PR flow. Verification is operational (manual skill runs against real config), not unit-tested.

**Spec:** [docs/superpowers/specs/2026-05-07-product-pulse-config-and-defork-design.md](../specs/2026-05-07-product-pulse-config-and-defork-design.md)

---

## File Structure

### Plugin (`/Users/timmoser/Projects/skills-n-stuff/`)

| File | Action |
|------|--------|
| `plugins/product-pulse/.claude-plugin/plugin.json` | Modify — bump version to 0.2.0, deprecate `userConfig.research_dir` |
| `plugins/product-pulse/skills/weekly-strategist/SKILL.md` | Rewrite — config discovery, multi-repo Phase 0, PR flow, configurable memory |
| `plugins/product-pulse/skills/daily-research/SKILL.md` | Rewrite — same shape adaptations |
| `plugins/product-pulse/skills/sprint-dev/SKILL.md` | Rewrite — same shape adaptations |
| `plugins/product-pulse/skills/setup/SKILL.md` | Rewrite — scaffold `pulse-config.yaml` and `planning/` folder |
| `plugins/product-pulse/agents/*.md` | Audit — likely no changes needed (already generic) |
| `plugins/product-pulse/README.md` | Modify — document `pulse-config.yaml` schema |

### Shelby-Strategy (`/Users/timmoser/Projects/Shelby/Shelby-Strategy/`)

| File | Action |
|------|--------|
| `Research/pulse-config.yaml` | Create — Shelby's operational config |
| `research/research-sources.yaml` | Create — converted from `.json` |
| `research/research-sources.json` | Delete after conversion |
| `todos/` (entire folder) | Rename → `planning/` |
| `planning/backlog.md` | Rename → `planning/todos.md` |
| `planning/backlog-ideas.md` | Rename → `planning/ideas.md` |
| `CLAUDE.md` | Modify — update folder/file references |
| `planning/WORKFLOW.md` | Modify — update file references |
| `.claude/skills/{daily-research,weekly-strategist,sprint-dev}/` | Delete |
| `.claude/agents/` | Delete |
| `.claude/hooks/scheduled-safety-gate.sh` | Modify — allow normal PR-flow under CLAUDE_SCHEDULED=1 |

### The Crooked Line (`/Users/timmoser/Projects/The Crooked Line/docs/`)

| File | Action |
|------|--------|
| `research/pulse-config.yaml` | Create — TCL's single-repo config |
| `research/research-sources.yaml` | Create — converted from `.json` |
| `research/research-sources.json` | Delete after conversion |
| `todos/` (entire folder) | Rename → `planning/` |
| `planning/backlog.md` | Rename → `planning/todos.md` (if exists) |
| `planning/backlog-ideas.md` | Rename → `planning/ideas.md` (if exists) |
| `CLAUDE.md` | Modify — update references |
| `.claude/skills/{daily-research,weekly-strategist,sprint-dev}/` | Delete |
| `.claude/agents/` | Delete |

### Cleanup

| File | Action |
|------|--------|
| TCL `origin/claude/lucid-cori-9tSnU` | Audit for unmerged content, then delete |

---

## Phase 1: Plugin Upgrade (skills-n-stuff)

This phase produces plugin v0.2.0. It must merge before any consuming repo migration can begin, because consuming-repo migrations rely on the v0.2.0 skills working correctly when the local forks are deleted.

### Task 1.1: Set up working branch

**Files:**
- Modify: `/Users/timmoser/Projects/skills-n-stuff/` (branch state)

- [ ] **Step 1: Create feature branch**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git checkout main
git pull origin main
git checkout -b feat/product-pulse-config-aware
```

- [ ] **Step 2: Verify clean state**

Run: `git status`
Expected: `On branch feat/product-pulse-config-aware`, working tree clean.

---

### Task 1.2: Bump plugin version and document config

**Files:**
- Modify: `plugins/product-pulse/.claude-plugin/plugin.json`

- [ ] **Step 1: Read current plugin.json**

Read: `/Users/timmoser/Projects/skills-n-stuff/plugins/product-pulse/.claude-plugin/plugin.json`

Confirm current version is `0.1.0` and `userConfig.research_dir` exists.

- [ ] **Step 2: Update plugin.json**

Edit the file. Bump `version` from `"0.1.0"` to `"0.2.0"`. Update the `userConfig.research_dir` description to indicate it's a fallback hint for setup only. The new content of `userConfig` should be:

```json
"userConfig": {
  "research_dir": {
    "description": "Fallback hint used by /product-pulse:setup if no pulse-config.yaml exists yet. Runtime resolution uses pulse-config.yaml discovery (walked up from cwd). Default: research",
    "sensitive": false
  }
}
```

- [ ] **Step 3: Commit**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/product-pulse/.claude-plugin/plugin.json
git commit -m "chore(product-pulse): bump to 0.2.0 and deprecate userConfig.research_dir"
```

---

### Task 1.3: Rewrite weekly-strategist SKILL.md

This is the largest single rewrite. The new skill must implement the changes documented in the spec's "Skill Behavior Changes" section. Use the existing plugin file (193 lines) as a starting point and apply each change.

**Files:**
- Modify: `plugins/product-pulse/skills/weekly-strategist/SKILL.md`

- [ ] **Step 1: Add Phase 0.0 — Config Discovery**

Insert this as the first subsection of Phase 0 (before existing 0.1):

````markdown
### 0.0 Discover Configuration

Walk up from cwd until you find `pulse-config.yaml`. That file's parent directory is the **research directory** (referred to below as `{research_dir}` — substitute its actual path). Load the YAML config; the rest of the skill uses values from it.

```bash
config_path=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  if [ -f "$dir/pulse-config.yaml" ]; then
    config_path="$dir/pulse-config.yaml"
    research_dir="$dir"
    break
  fi
  dir="$(dirname "$dir")"
done

if [ -z "$config_path" ]; then
  echo "No pulse-config.yaml found. Run /product-pulse:setup first." >&2
  exit 1
fi

echo "Using config: $config_path"
echo "Research dir: $research_dir"
```

Parse the YAML. Required fields: `project_id`, `repos`. Optional with defaults: `default_branch` (default `main`), `auto_merge` (default `true`), `memory.connector` (default `shelby`), `backlog.active` (default `planning/todos.md`), `backlog.ideas` (default `planning/ideas.md`).

Find the entry in `repos:` with `role: primary`; treat its `path` (resolved relative to the directory containing the primary repo's `.git`) as the **primary repo root** for all backlog and git operations. The research dir is `{primary_repo_root}/{relative path from primary repo root to research_dir}`.
````

- [ ] **Step 2: Replace Phase 0.2 — Multi-repo pull**

Replace the existing 0.2 (single `git pull`) with:

````markdown
### 0.2 Pull Latest (all configured repos)

Iterate `repos:` from `pulse-config.yaml`. For each repo, resolve its absolute path (relative to the primary repo's parent directory), then:

```bash
for repo in $(yq '.repos[].path' pulse-config.yaml); do
  abs="$(realpath "$primary_repo_root/$repo")"
  echo "=== Pulling $abs ==="
  cd "$abs" && git checkout "$default_branch" && git pull origin "$default_branch" || echo "pull failed for $abs"
done
```

If any pull fails, note it and continue. Single-element `repos:` is the monorepo case — same loop, one iteration.
````

- [ ] **Step 3: Replace product-context.md reference**

Find the line in Phase 0.1 referencing `{research_dir}/product-context.md` and change it to `{research_dir}/research-context.md`. The file was renamed across both consuming products (commit `8d53f79` in Shelby and `35760c5` in TCL).

- [ ] **Step 4: Replace research-tracker.md reference**

Find Phase 0.5 ("Read the Research Tracker") which reads `{research_dir}/research-tracker.md`. Replace with two-file backlog:

````markdown
### 0.5 Read the Backlog

Read both files configured in `pulse-config.yaml`:
- Active work: `{primary_repo_root}/{backlog.active}` (default `planning/todos.md`)
- Ideas staging: `{primary_repo_root}/{backlog.ideas}` (default `planning/ideas.md`)

From `todos.md`, parse: Roadmap, Ready (sprint subsections), Monitor, Manual, Done (last 7 days), Dismissed.
From `ideas.md`, parse: per-domain Ideas subsections plus an Expired / passed-deadline table.

Build a health snapshot: total open, items by priority/domain, items by target repo, oldest item age, items currently in flight (`awaiting-pr` / `in-progress`).

If either file is missing or malformed, skip that file's parsing and note it in the brief — do NOT auto-recreate the file.
````

- [ ] **Step 5: Replace Phase 0.6 — Memory ops**

Replace the generic memory section with config-driven check:

````markdown
### 0.6 Search Memory (if configured)

If `memory.connector` is set in `pulse-config.yaml` and not `null`, look for MCP tools whose names contain that prefix (e.g., `shelby` matches `mcp__shelby-memory__*`). If no matching tools are available, skip memory ops and continue.

When tools are available, search for prior weekly briefs and overnight worker results:

```
search_thoughts(query="weekly-strategist {project_id}", limit=10)
search_thoughts(query="{project_id}-daily-research", limit=20)
```

If `memory.connector: null`, skip this phase entirely.
````

- [ ] **Step 6: Replace Phase 5 — PR-based output**

This is the bug fix for the W16–W19 incident. Replace existing Phase 5 ("Update Tracker & Persist") with:

````markdown
## Phase 5: Update Backlog and Persist

### 5.1 Backlog edits

Edits go to the configured backlog files. In `{backlog.ideas}`:
- Remove rows being dismissed
- Remove rows being moved to Monitor
- Update priority levels where the week's analysis justifies a change
- Update the `Last updated:` date

In `{backlog.active}`:
- Append dismissed Ideas to the Dismissed table with reason and date
- Append watch-and-wait Ideas to the Monitor table with trigger/deadline
- Update priorities on Roadmap/Monitor rows where strategic context shifted
- Update `Last updated:` date

Do NOT add new Ideas (daily-research's job). Do NOT mark items as `ready` (human's job). Do NOT move items to Done (sprint-dev's job).

### 5.2 Save to memory (if configured)

If `memory.connector` is set, capture the brief summary:

```
capture_thought({
  content: "{full weekly brief summary with priorities, theme, and key decisions}",
  summary: "Weekly strategy W{NN}: {theme in <80 chars}",
  type: "decision",
  topics: ["weekly-strategist", "{project_id}-research", "{project_id}", "strategy"],
  source: "weekly-strategist-{YYYY}-W{NN}",
  project: "{project_id}",
  metadata: { ... }
})
```

### 5.3 Branch + commit + PR (always)

Inside the primary repo:

```bash
cd "$primary_repo_root"
branch="weekly-brief/W{NN}"
git checkout -b "$branch"
git add "$research_dir" "$backlog_active" "$backlog_ideas"
git commit -m "strategy: weekly brief W{NN} — {theme short}"
git push -u origin "$branch"
pr_url=$(gh pr create --base "$default_branch" --head "$branch" \
  --title "strategy: weekly brief W{NN} — {theme short}" \
  --body "Weekly strategy brief and recommendations for W{NN}. Auto-generated by product-pulse weekly-strategist." \
  | tail -n1)
echo "PR opened: $pr_url"
```

### 5.4 Auto-merge (if enabled and mergeable)

If `auto_merge: true` in config:

```bash
sleep 8  # let GitHub finalize mergeability check
gh pr merge "$pr_url" --squash --delete-branch --auto || \
  echo "Auto-merge declined; PR sits for human review at $pr_url"
```

`--auto` queues the merge if checks are still running. `--squash --delete-branch` keeps history tidy. If the merge is rejected (conflicts, branch protection, required reviews), the skill exits with the PR URL surfaced; the human merges manually.
````

- [ ] **Step 7: Update Phase 6 summary**

Find the Phase 6 summary block and add a line for the PR status:

```markdown
PR: {pr_url} ({merged | open})
```

- [ ] **Step 8: Update frontmatter description**

Update the `description:` field in frontmatter to remove the obsolete reference to "the focus list for sprint-dev" and replace with current behavior:

```yaml
description: >-
  Weekly strategic intelligence. Dispatches 5 analyst agents (Market Scout,
  Competitor Tracker, Audience Analyst, Growth Analyst, Product Scout), reads
  the last 7 daily reports, reviews the backlog, and produces a strategy brief
  + recommendations PR with the week's theme, top 3 priorities, and items
  recommended for speccing. Reads pulse-config.yaml from the nearest research
  directory. Run Monday mornings or whenever you need strategic direction.
  Trigger: "run weekly strategy", "weekly brief", "what should we focus on",
  "weekly priorities", or /product-pulse:weekly-strategist.
```

- [ ] **Step 9: Verify the rewritten skill reads cleanly end-to-end**

Read the entire rewritten file. Check:
- All `{research_dir}` placeholders are explained as "the directory containing pulse-config.yaml"
- All `{primary_repo_root}` placeholders are explained as "directory of primary repo's .git"
- No remaining references to `product-context.md` (should be `research-context.md`)
- No remaining references to `research-tracker.md` (should be the two backlog files)
- No remaining references to `git push origin main` (should be `weekly-brief/W{NN}` branch + PR)
- No hardcoded `Shelby` or `Crooked Line` references

- [ ] **Step 10: Commit**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/product-pulse/skills/weekly-strategist/SKILL.md
git commit -m "feat(weekly-strategist): config discovery, multi-repo, PR flow, configurable memory"
```

---

### Task 1.4: Rewrite daily-research SKILL.md

Same shape changes as weekly-strategist. The daily-research skill currently produces a daily report file and adds rows to the backlog ideas file. It needs:

**Files:**
- Modify: `plugins/product-pulse/skills/daily-research/SKILL.md`

- [ ] **Step 1: Read current file**

Read: `/Users/timmoser/Projects/skills-n-stuff/plugins/product-pulse/skills/daily-research/SKILL.md` (192 lines)

- [ ] **Step 2: Add Phase 0 config discovery**

Insert the same config-discovery block as Task 1.3 Step 1, adapted for daily-research's Phase 0.

- [ ] **Step 3: Replace tracker reference**

Find any `research-tracker.md` references and replace with `{backlog.ideas}` (daily-research writes to ideas, not the active backlog).

- [ ] **Step 4: Replace product-context.md → research-context.md**

Same find-and-replace as weekly-strategist Step 3.

- [ ] **Step 5: Replace push-to-main with branch + PR**

Find the git commit/push section. Replace with branch creation + PR + auto-merge, mirroring weekly-strategist Phase 5.3 + 5.4. Branch name: `daily-research/{YYYY-MM-DD}` (date-based, since daily reports are dated). Commit message: `research: daily report {YYYY-MM-DD}`.

- [ ] **Step 6: Add multi-repo pull**

If daily-research currently has a `git pull` step, replace with the same multi-repo iteration as weekly-strategist Task 1.3 Step 2. (Daily-research mostly reads, but pulling latest before reading is still useful when used as a Monday-morning sanity step.)

- [ ] **Step 7: Add memory config check**

If daily-research has memory ops, gate them on `memory.connector` per Task 1.3 Step 5.

- [ ] **Step 8: Update frontmatter description**

Mention `pulse-config.yaml` discovery and `/product-pulse:daily-research`.

- [ ] **Step 9: Verify end-to-end**

Read the rewritten file. Same verification checklist as Task 1.3 Step 9.

- [ ] **Step 10: Commit**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/product-pulse/skills/daily-research/SKILL.md
git commit -m "feat(daily-research): config discovery, multi-repo, PR flow, configurable memory"
```

---

### Task 1.5: Rewrite sprint-dev SKILL.md

Sprint-dev is the largest of the three (239 lines) — it implements backlog items and orchestrates sub-agents. It needs config awareness for backlog file locations and primary repo root.

**Files:**
- Modify: `plugins/product-pulse/skills/sprint-dev/SKILL.md`

- [ ] **Step 1: Read current file**

Read: `/Users/timmoser/Projects/skills-n-stuff/plugins/product-pulse/skills/sprint-dev/SKILL.md` (239 lines)

- [ ] **Step 2: Add Phase 0 config discovery**

Insert the same config-discovery block. Sprint-dev needs `{backlog.active}` and `{backlog.ideas}` paths from config plus `{primary_repo_root}` for the working directory.

- [ ] **Step 3: Replace backlog file references**

Find every reference to `todos/backlog.md` and `todos/backlog-ideas.md` (or `{research_dir}/backlog.md` etc.). Replace with `{backlog.active}` and `{backlog.ideas}` from config. Sprint-dev also references the archive path — update to `planning/archive/done-YYYY-QN.md` (baked-in convention per spec).

- [ ] **Step 4: Update repo selection for multi-repo target**

Sprint-dev dispatches sub-agents per target repo. Currently this is hardcoded for the single-repo case. Update to iterate `repos:` from config, group items by `target_repo` (column in backlog rows), and dispatch one sub-agent per target repo per PR group.

- [ ] **Step 5: Replace push-to-main**

Sprint-dev creates implementation PRs (separate from the daily/weekly PRs). The PR-creation logic should already exist; verify it pushes to a feature branch and uses `gh pr create`. Make `auto_merge: false` the default for implementation PRs (you want human review before merging code changes), regardless of the config's `auto_merge` setting — sprint-dev work is not the same as research output.

- [ ] **Step 6: Add memory config check**

Same as Task 1.3 Step 5.

- [ ] **Step 7: Update frontmatter description**

Mention `pulse-config.yaml` discovery.

- [ ] **Step 8: Verify end-to-end**

Read the rewritten file. Same verification checklist plus confirm sprint-dev does NOT auto-merge implementation PRs.

- [ ] **Step 9: Commit**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/product-pulse/skills/sprint-dev/SKILL.md
git commit -m "feat(sprint-dev): config discovery, multi-repo target dispatch, planning/ paths"
```

---

### Task 1.6: Rewrite setup SKILL.md

The setup skill currently scaffolds research directory + product-context.md. It needs to scaffold `pulse-config.yaml` and the new `planning/` folder structure.

**Files:**
- Modify: `plugins/product-pulse/skills/setup/SKILL.md`

- [ ] **Step 1: Read current file**

Read: `/Users/timmoser/Projects/skills-n-stuff/plugins/product-pulse/skills/setup/SKILL.md` (274 lines)

- [ ] **Step 2: Add config-generation step**

In Phase 2 ("Build Product Context"), after generating `research-context.md`, add a new step "Build Operational Config" that generates `pulse-config.yaml` from interview answers. Question batch additions:

- "What's your project_id?" (suggest a slug from product name)
- "Is this a monorepo or multi-repo?" (already asked) — produces `repos:` list shape
- "What's your default branch?" (default: main)
- "Auto-merge research PRs?" (default: yes)
- "Use Shelby memory connector for capturing thoughts?" (default: yes if user is Tim, else null)

Output the YAML to `{research_dir}/pulse-config.yaml`:

```yaml
project_id: {slug}

repos:
  - name: {primary_name}
    path: .
    role: primary
{additional_repos_if_multi_repo}

default_branch: {default_branch}
auto_merge: {auto_merge}

memory:
  connector: {memory_connector}

backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

- [ ] **Step 3: Replace product-context.md → research-context.md**

The setup skill currently produces `product-context.md`. Update it to produce `research-context.md` (the new convention).

- [ ] **Step 4: Add planning/ folder scaffold**

In the scaffold phase, create `planning/` directory with empty `todos.md` and `ideas.md` files plus an `archive/` subdirectory. Don't create `specs/` (only sprint-dev needs it; created on first spec).

- [ ] **Step 5: Drop research-tracker.md scaffold**

Remove any step that creates `research-tracker.md` — it's been replaced by the two-file backlog. Add a clear migration note in the skill that says "if you're migrating from an older product-pulse install, see the spec at docs/superpowers/specs/2026-05-07-product-pulse-config-and-defork-design.md".

- [ ] **Step 6: Update frontmatter description**

Mention scaffolding `pulse-config.yaml` and `planning/`.

- [ ] **Step 7: Commit**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/product-pulse/skills/setup/SKILL.md
git commit -m "feat(setup): scaffold pulse-config.yaml and planning/ folder; drop research-tracker"
```

---

### Task 1.7: Audit agents for product-specific drift

The plugin's generic agents should already be product-agnostic. Quick audit to confirm.

**Files:**
- Read-only audit, possibly Modify: `plugins/product-pulse/agents/*.md`

- [ ] **Step 1: Read all 5 agent files**

```bash
for f in /Users/timmoser/Projects/skills-n-stuff/plugins/product-pulse/agents/*.md; do
  echo "=== $f ==="
  cat "$f"
done
```

- [ ] **Step 2: Verify each agent reads product context at runtime**

Each agent should have a clear "read the product context provided" instruction and not bake in any specific industry, product name, or competitor list. If any agent has hardcoded specifics, replace with "read the product context to determine what market/segment/competitor set applies."

- [ ] **Step 3: Commit any fixes**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/product-pulse/agents/
git commit -m "chore(agents): remove product-specific drift from generic plugin agents"
```

If no changes needed, skip the commit.

---

### Task 1.8: Document the schema in plugin README

**Files:**
- Modify: `plugins/product-pulse/README.md`

- [ ] **Step 1: Add Configuration section to README**

Append (or insert near the top) a section that documents:
- The `pulse-config.yaml` schema (copy from the spec)
- Discovery rule (walked up from cwd)
- Each field with default value
- Two example configs (monorepo and multi-repo) — the Shelby and TCL examples from the spec are good

- [ ] **Step 2: Document migration from 0.1.0 → 0.2.0**

Add a "Migrating from 0.1.0" subsection that explains:
- `product-context.md` → `research-context.md` (rename)
- `research-tracker.md` → split into `planning/todos.md` + `planning/ideas.md`
- New required file: `pulse-config.yaml`
- Run `/product-pulse:setup` to regenerate from interview, OR see the spec for hand-migration steps

- [ ] **Step 3: Commit**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git add plugins/product-pulse/README.md
git commit -m "docs(product-pulse): document pulse-config.yaml schema and 0.1.0→0.2.0 migration"
```

---

### Task 1.9: Open and merge PR

**Files:**
- Branch: `feat/product-pulse-config-aware`

- [ ] **Step 1: Push branch**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git push -u origin feat/product-pulse-config-aware
```

- [ ] **Step 2: Create PR**

```bash
gh pr create --base main --title "feat(product-pulse): config-aware plugin (v0.2.0)" --body "$(cat <<'EOF'
## Summary
- Plugin discovers per-repo \`pulse-config.yaml\` (walks up from cwd) instead of relying on \`{research_dir}\` placeholder substitution
- Multi-repo support via \`repos:\` list (length-1 = monorepo)
- PR-based output flow with optional auto-merge replaces direct push-to-main (fixes the W16–W19 orphan-branch incident)
- Configurable memory connector (defaults to \`shelby\`, can be \`null\`)
- Two-file backlog (\`planning/todos.md\` + \`planning/ideas.md\`) replaces \`research-tracker.md\`
- \`product-context.md\` renamed to \`research-context.md\`
- README documents schema + 0.1.0→0.2.0 migration

## Test plan
- [ ] Read all rewritten SKILL.md files end-to-end; no Shelby/TCL hardcoded references
- [ ] Frontmatter \`description\` fields updated for all skills
- [ ] Agents audited; remain generic
- [ ] Manual test: run weekly-strategist against a sample \`pulse-config.yaml\` in a scratch directory; confirm config discovery works and a PR-shaped output is produced

## Spec
docs/superpowers/specs/2026-05-07-product-pulse-config-and-defork-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Verify PR**

Run: `gh pr view --web` (or read PR via `gh pr view`).

Spot-check the diff. If anything looks off, push fixes; otherwise proceed.

- [ ] **Step 4: Merge PR**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 5: Verify on main**

```bash
cd /Users/timmoser/Projects/skills-n-stuff
git checkout main
git pull origin main
git log -1 --stat
```

Expected: top commit is the squashed feature commit. Plugin v0.2.0 is now in main.

- [ ] **Step 6: Refresh plugin cache**

The plugin cache at `~/.claude/plugins/cache/studio-moser/product-pulse/` is keyed by version. To pick up `0.2.0`:

```bash
ls ~/.claude/plugins/cache/studio-moser/product-pulse/
# Expected: 0.1.0 (cached old version)
```

Trigger a refresh by reloading the marketplace. The exact mechanism depends on Claude Code's plugin system — typically `/plugin reload` or restarting the session. If the cache doesn't auto-update, manually copy the new version:

```bash
cp -R /Users/timmoser/Projects/skills-n-stuff/plugins/product-pulse \
     ~/.claude/plugins/cache/studio-moser/product-pulse/0.2.0
```

After refresh, verify:

```bash
ls ~/.claude/plugins/cache/studio-moser/product-pulse/
# Expected: 0.1.0 0.2.0 (or just 0.2.0 if auto-cleaned)
```

---

### Task 1.10: Smoke-test the new plugin in a scratch directory

Verify the plugin works before deleting any forks.

**Files:**
- Create temporary: `/tmp/pulse-smoke-test/` (will be deleted)

- [ ] **Step 1: Set up scratch test directory**

```bash
mkdir -p /tmp/pulse-smoke-test/research
cd /tmp/pulse-smoke-test
git init
echo "# Test Research Context" > research/research-context.md
cat > research/pulse-config.yaml <<'EOF'
project_id: smoke-test
repos:
  - name: smoke-test
    path: .
    role: primary
default_branch: main
auto_merge: false  # don't actually try to merge
memory:
  connector: null
backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
EOF
mkdir -p planning
touch planning/todos.md planning/ideas.md
git add -A
git commit -m "init smoke test"
```

- [ ] **Step 2: From inside the scratch dir, invoke weekly-strategist**

In Claude Code with cwd set to `/tmp/pulse-smoke-test`, invoke `/product-pulse:weekly-strategist` (or the skill name as exposed).

- [ ] **Step 3: Verify config discovery**

Confirm the skill reports something like:
```
Using config: /tmp/pulse-smoke-test/research/pulse-config.yaml
Research dir: /tmp/pulse-smoke-test/research
```

If it can't find the config, debug the discovery walker. If it finds the config but fails on missing daily reports / memory tools — that's expected (smoke test, not full e2e).

- [ ] **Step 4: Clean up**

```bash
rm -rf /tmp/pulse-smoke-test
```

If smoke test passes, plugin is ready. If it fails, fix the bug, push, and re-merge before proceeding to Phase 2.

---

## Phase 2: Migrate Shelby-Strategy

This phase eliminates the Shelby fork. It depends on Phase 1 being merged and the plugin cache containing v0.2.0.

### Task 2.1: Set up working branch in Shelby-Strategy

**Files:**
- Modify: `/Users/timmoser/Projects/Shelby/Shelby-Strategy/` (branch state)

- [ ] **Step 1: Create feature branch**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
git checkout main
git pull origin main
git checkout -b refactor/migrate-to-product-pulse-0.2
```

- [ ] **Step 2: Verify clean state**

Run: `git status`
Expected: clean tree, on the new branch.

---

### Task 2.2: Convert research-sources.json to YAML

**Files:**
- Create: `research/research-sources.yaml`
- Delete: `research/research-sources.json`

- [ ] **Step 1: Convert file using yq**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
yq -P 'sort_keys(..)' research/research-sources.json > research/research-sources.yaml
```

If `yq` isn't installed: `brew install yq`. If `yq -P` (pretty-print) doesn't preserve order well, use Python:

```bash
python3 -c "import json, yaml, sys; yaml.dump(json.load(open('research/research-sources.json')), sys.stdout, sort_keys=False, default_flow_style=False)" > research/research-sources.yaml
```

- [ ] **Step 2: Spot-check the conversion**

Read both files side by side. Confirm:
- All domains preserved
- All sources preserved with name/url/type/qualityScore
- `version` and `lastUpdated` fields preserved at top level

- [ ] **Step 3: Delete the .json file**

```bash
git rm research/research-sources.json
```

- [ ] **Step 4: Commit**

```bash
git add research/research-sources.yaml
git commit -m "refactor: convert research-sources.json to YAML"
```

---

### Task 2.3: Create Research/pulse-config.yaml

Note the casing — Shelby uses capital `Research/`. The new config file lives there because the file's location IS the research directory.

**Files:**
- Create: `Research/pulse-config.yaml`

- [ ] **Step 1: Verify Research/ casing**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
ls -la | grep -i research
```

Expected: `Research` (capital R) appears in output. `research/` (lowercase) may also appear — both directories exist due to the historic case fragmentation. The new config goes under capital `Research/`.

- [ ] **Step 2: Move research-sources.yaml under Research/ if it landed in lowercase**

If Task 2.2 wrote to `research/` (lowercase), move it:

```bash
git mv research/research-sources.yaml Research/research-sources.yaml 2>/dev/null || \
  mv research/research-sources.yaml Research/research-sources.yaml && \
  git add -A
```

Verify with `git status`.

- [ ] **Step 3: Move research-context.md under Research/ if needed**

```bash
ls -la research/research-context.md Research/research-context.md 2>&1
```

If only `research/research-context.md` exists (lowercase), move it:

```bash
git mv research/research-context.md Research/research-context.md 2>/dev/null || \
  mv research/research-context.md Research/research-context.md && \
  git add -A
```

- [ ] **Step 4: Create the pulse-config.yaml**

Write `Research/pulse-config.yaml`:

```yaml
project_id: shelby

repos:
  - name: Shelby-Strategy
    path: .
    role: primary
  - name: Shelby-MCP
    path: ../Shelby-MCP
  - name: Shelby-MacOS
    path: ../Shelby-MacOS
  - name: Shelby-Website
    path: ../Shelby-Website

default_branch: main
auto_merge: true

memory:
  connector: shelby

backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

- [ ] **Step 5: Commit**

```bash
git add Research/pulse-config.yaml
git commit -m "feat: add pulse-config.yaml for product-pulse 0.2.0"
```

---

### Task 2.4: Rename todos/ → planning/ and rename files

**Files:**
- Rename: `todos/` → `planning/`
- Rename: `planning/backlog.md` → `planning/todos.md`
- Rename: `planning/backlog-ideas.md` → `planning/ideas.md`

- [ ] **Step 1: Survey existing todos/ contents**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
ls -la todos/
```

Note all top-level files and subdirs (expected: `backlog.md`, `backlog-ideas.md`, `WORKFLOW.md`, `archive/`, `specs/`, `_archive/`, plus possibly some phase markdown files).

- [ ] **Step 2: Rename folder**

```bash
git mv todos planning
```

- [ ] **Step 3: Rename files inside planning/**

```bash
git mv planning/backlog.md planning/todos.md
git mv planning/backlog-ideas.md planning/ideas.md
```

- [ ] **Step 4: Verify**

```bash
ls -la planning/
git status
```

Expected: all old `todos/...` paths shown as renamed to `planning/...`. `backlog.md` shown as renamed to `todos.md`. `backlog-ideas.md` shown as renamed to `ideas.md`. Other contents (WORKFLOW.md, archive/, specs/, etc.) shown as renamed without content changes.

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: rename todos/ to planning/, backlog.md to todos.md, backlog-ideas.md to ideas.md"
```

---

### Task 2.5: Update internal cross-references

The folder rename breaks all internal references. Fix them.

**Files:**
- Modify: `CLAUDE.md`
- Modify: `planning/WORKFLOW.md`
- Modify: spec files in `planning/specs/` (if any reference the old paths)
- Modify: any file referencing `todos/` or `backlog.md` or `backlog-ideas.md`

- [ ] **Step 1: Find all references**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
grep -rn "todos/" --exclude-dir=.git --exclude-dir=planning/_archive --exclude-dir=planning/archive | grep -v "planning/todos\." | head -50
grep -rn "backlog.md\|backlog-ideas.md" --exclude-dir=.git --exclude-dir=planning/_archive --exclude-dir=planning/archive | head -50
```

(Excluding archives because old archived content can keep historical paths — those are a record, not active references.)

- [ ] **Step 2: Update CLAUDE.md**

Replace every `todos/` with `planning/`. Replace `backlog.md` with `todos.md` and `backlog-ideas.md` with `ideas.md` (in the context of describing the live work queue / idea staging — leave any historical references in archived discussions alone).

Spot-check the result for sentences that read awkwardly post-rename (e.g., "the todos/ folder" → "the planning/ folder").

- [ ] **Step 3: Update planning/WORKFLOW.md**

Same find-and-replace inside this file.

- [ ] **Step 4: Update planning/specs/_TEMPLATE.md and active specs**

If any spec references the old paths in code-references or freshness-tracking sections, update them.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: update cross-references to planning/ folder and todos.md/ideas.md filenames"
```

---

### Task 2.6: Delete forks of skills and agents

**Files:**
- Delete: `.claude/skills/{daily-research,weekly-strategist,sprint-dev}/`
- Delete: `.claude/agents/`

- [ ] **Step 1: Confirm what's there**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
ls -la .claude/skills/ .claude/agents/
```

- [ ] **Step 2: Delete forks**

```bash
git rm -r .claude/skills/daily-research .claude/skills/weekly-strategist .claude/skills/sprint-dev
git rm -r .claude/agents
```

Note: leave `.claude/skills/` directory itself if there are non-product-pulse skills inside. Check first:

```bash
ls .claude/skills/
```

If only the three product-pulse skills were there and the directory is now empty, you can either keep the empty directory or remove it — Claude Code is fine either way.

- [ ] **Step 3: Verify**

```bash
git status
```

Expected: shows the skill files and agent files as deleted.

- [ ] **Step 4: Commit**

```bash
git commit -m "refactor: delete local product-pulse skill and agent forks (now using plugin v0.2.0)"
```

---

### Task 2.7: Verification — run weekly-strategist manually

Critical step. Don't merge the PR until this passes.

**Files:**
- No changes — just running the skill

- [ ] **Step 1: Confirm plugin v0.2.0 is loaded**

In a fresh Claude Code session with cwd `/Users/timmoser/Projects/Shelby/Shelby-Strategy`, run:

```bash
ls ~/.claude/plugins/cache/studio-moser/product-pulse/
```

Expected: `0.2.0` exists (and is the version in use). If only `0.1.0` is present, refresh the plugin cache (Task 1.9 Step 6).

- [ ] **Step 2: Invoke weekly-strategist**

Type `run weekly strategy` (or invoke `/product-pulse:weekly-strategist` directly). The skill should:
1. Find `Research/pulse-config.yaml`
2. Pull all 4 Shelby repos
3. Read `Research/research-context.md`
4. Read last 7 daily reports + last weekly brief
5. Read `planning/todos.md` and `planning/ideas.md`
6. Search Shelby memory (since `memory.connector: shelby`)
7. Dispatch 5 analyst agents in parallel
8. Synthesize a brief
9. Open a PR (don't auto-merge during this verification — set `auto_merge: false` temporarily, OR manually halt before the PR step)

- [ ] **Step 3: Spot-check the output**

Confirm:
- Brief lands in `Research/{YYYY-MM}/W{NN}/{YYYY}-W{NN}-strategy-brief.md` (capital R)
- No fragmented `research/` (lowercase) directory created
- Backlog edits go to `planning/todos.md` and `planning/ideas.md`, not `todos/backlog.md`

- [ ] **Step 4: If verification fails, debug**

Common failure modes:
- Config discovery not finding pulse-config.yaml → check the discovery walker's start path
- yq/yaml parsing error → check pulse-config.yaml syntax
- Multi-repo pull failing → check repo paths resolve correctly relative to primary

Fix any plugin bugs in the skills-n-stuff repo, push, and re-test.

- [ ] **Step 5: Don't merge the test PR if it was auto-created**

If the verification accidentally auto-merged a test brief, that's fine — it's real output and you can keep it. Just make sure the next steps don't double-up.

---

### Task 2.8: Open and merge PR for Shelby migration

**Files:**
- Branch: `refactor/migrate-to-product-pulse-0.2`

- [ ] **Step 1: Push branch**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
git push -u origin refactor/migrate-to-product-pulse-0.2
```

- [ ] **Step 2: Create PR**

```bash
gh pr create --base main --title "refactor: migrate to product-pulse 0.2.0" --body "$(cat <<'EOF'
## Summary
- Add \`Research/pulse-config.yaml\` for the new config-aware plugin
- Convert \`research-sources.json\` to YAML
- Rename \`todos/\` → \`planning/\`, \`backlog.md\` → \`todos.md\`, \`backlog-ideas.md\` → \`ideas.md\`
- Delete local forks of product-pulse skills and agents (now using plugin v0.2.0 directly)
- Update CLAUDE.md, WORKFLOW.md, and other internal references to new paths

## Test plan
- [x] weekly-strategist runs end-to-end against new config (verified Task 2.7)
- [ ] daily-research runs successfully on next 06:02 schedule
- [ ] sprint-dev verified manually on next ready item

## Spec
skills-n-stuff/docs/superpowers/specs/2026-05-07-product-pulse-config-and-defork-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Merge PR (after spot-checking diff)**

```bash
gh pr view  # spot-check
gh pr merge --squash --delete-branch
```

- [ ] **Step 4: Watch the next scheduled daily-research run**

`shelby-daily-research` runs at 06:02. After the next run, verify:
- It produced a daily-research/{YYYY-MM-DD} branch + PR (not pushed to main)
- The PR auto-merged successfully (since `auto_merge: true`)
- Files landed in `Research/{YYYY-MM}/W{NN}/`

If the run fails, debug — likely config discovery from the runner's cwd or yq availability.

---

## Phase 3: Migrate The Crooked Line/docs

Same shape as Phase 2, simpler (single repo, no multi-repo loop).

### Task 3.1: Set up working branch in TCL/docs

- [ ] **Step 1: Create feature branch**

```bash
cd "/Users/timmoser/Projects/The Crooked Line/docs"
git checkout main
git pull origin main
git checkout -b refactor/migrate-to-product-pulse-0.2
```

- [ ] **Step 2: Verify clean state**

Run: `git status`. Expected: clean tree.

---

### Task 3.2: Convert research-sources.json to YAML

- [ ] **Step 1: Convert**

```bash
cd "/Users/timmoser/Projects/The Crooked Line/docs"
yq -P 'sort_keys(..)' research/research-sources.json > research/research-sources.yaml
```

(Or use the Python fallback from Task 2.2.)

- [ ] **Step 2: Spot-check**

Read both files. Confirm structure preserved.

- [ ] **Step 3: Delete .json**

```bash
git rm research/research-sources.json
```

- [ ] **Step 4: Commit**

```bash
git add research/research-sources.yaml
git commit -m "refactor: convert research-sources.json to YAML"
```

---

### Task 3.3: Create research/pulse-config.yaml

TCL uses lowercase `research/` (already confirmed). The config file lives there.

- [ ] **Step 1: Create the config**

Write `research/pulse-config.yaml`:

```yaml
project_id: the-crooked-line

repos:
  - name: the-crooked-line
    path: .
    role: primary

default_branch: main
auto_merge: true

memory:
  connector: shelby  # TCL writes to Shelby memory cross-product

backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```

- [ ] **Step 2: Commit**

```bash
git add research/pulse-config.yaml
git commit -m "feat: add pulse-config.yaml for product-pulse 0.2.0"
```

---

### Task 3.4: Rename todos/ → planning/ and rename files

Same as Task 2.4 — applied to TCL.

- [ ] **Step 1: Survey existing todos/ contents**

```bash
cd "/Users/timmoser/Projects/The Crooked Line/docs"
ls -la todos/
```

- [ ] **Step 2: Rename folder**

```bash
git mv todos planning
```

- [ ] **Step 3: Rename files inside if they exist**

```bash
[ -f planning/backlog.md ] && git mv planning/backlog.md planning/todos.md
[ -f planning/backlog-ideas.md ] && git mv planning/backlog-ideas.md planning/ideas.md
```

(TCL may not have the same exact file names as Shelby — adjust if the file inventory differs. The principle: `backlog*.md` → `todos.md`/`ideas.md`.)

- [ ] **Step 4: Verify**

```bash
ls -la planning/
git status
```

- [ ] **Step 5: Commit**

```bash
git commit -m "refactor: rename todos/ to planning/, backlog.md to todos.md, backlog-ideas.md to ideas.md"
```

---

### Task 3.5: Update internal cross-references

- [ ] **Step 1: Find references**

```bash
cd "/Users/timmoser/Projects/The Crooked Line/docs"
grep -rn "todos/" --exclude-dir=.git --exclude-dir=planning/_archive --exclude-dir=planning/archive 2>/dev/null | grep -v "planning/todos\." | head -50
grep -rn "backlog.md\|backlog-ideas.md" --exclude-dir=.git --exclude-dir=planning/_archive --exclude-dir=planning/archive 2>/dev/null | head -50
```

- [ ] **Step 2: Update CLAUDE.md**

Same find-and-replace as Shelby's CLAUDE.md.

- [ ] **Step 3: Update planning/WORKFLOW.md (if exists)**

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: update cross-references to planning/ folder and renamed files"
```

---

### Task 3.6: Delete forks of skills and agents

- [ ] **Step 1: Confirm what's there**

```bash
cd "/Users/timmoser/Projects/The Crooked Line/docs"
ls -la .claude/skills/ .claude/agents/
```

- [ ] **Step 2: Delete forks**

```bash
git rm -r .claude/skills/daily-research .claude/skills/weekly-strategist .claude/skills/sprint-dev
git rm -r .claude/agents
```

- [ ] **Step 3: Commit**

```bash
git commit -m "refactor: delete local product-pulse skill and agent forks (now using plugin v0.2.0)"
```

---

### Task 3.7: Verification — run weekly-strategist manually

- [ ] **Step 1: Confirm plugin v0.2.0 is loaded**

```bash
ls ~/.claude/plugins/cache/studio-moser/product-pulse/
```

Expected: `0.2.0` exists.

- [ ] **Step 2: Invoke weekly-strategist**

In a Claude Code session with cwd `/Users/timmoser/Projects/The Crooked Line/docs`, invoke `/product-pulse:weekly-strategist`. Verify it discovers `research/pulse-config.yaml` and runs end-to-end.

- [ ] **Step 3: Spot-check output**

Confirm output lands in `research/{YYYY-MM}/W{NN}/`.

---

### Task 3.8: Open and merge PR for TCL migration

- [ ] **Step 1: Push branch**

```bash
cd "/Users/timmoser/Projects/The Crooked Line/docs"
git push -u origin refactor/migrate-to-product-pulse-0.2
```

- [ ] **Step 2: Create PR**

```bash
gh pr create --base main --title "refactor: migrate to product-pulse 0.2.0" --body "$(cat <<'EOF'
## Summary
- Add \`research/pulse-config.yaml\` for the new config-aware plugin
- Convert \`research-sources.json\` to YAML
- Rename \`todos/\` → \`planning/\`, backlog files renamed
- Delete local forks of product-pulse skills and agents (now using plugin v0.2.0 directly)
- Update CLAUDE.md and other internal references to new paths

## Test plan
- [x] weekly-strategist runs end-to-end against new config (verified Task 3.7)
- [ ] daily-research runs on next 05:02 schedule

## Spec
skills-n-stuff/docs/superpowers/specs/2026-05-07-product-pulse-config-and-defork-design.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Merge PR**

```bash
gh pr view
gh pr merge --squash --delete-branch
```

- [ ] **Step 4: Watch the next scheduled tcl-daily-research run**

Runs at 05:02. Verify it produced a branch + PR and auto-merged.

---

## Phase 4: Cleanup

### Task 4.1: Audit and clean up TCL `claude/lucid-cori-9tSnU`

This branch is from a prior cloud-agent run that may have unmerged content (parallels the W16–W19 audit done on Shelby).

- [ ] **Step 1: Check whether the branch still exists**

```bash
cd "/Users/timmoser/Projects/The Crooked Line/docs"
git fetch --prune
git branch -r | grep claude
```

If `origin/claude/lucid-cori-9tSnU` is gone, skip the rest of this task.

- [ ] **Step 2: Compare branch content vs main**

```bash
git diff --stat main...origin/claude/lucid-cori-9tSnU
git log main..origin/claude/lucid-cori-9tSnU --oneline
```

- [ ] **Step 3: Check for unmerged files**

For each file added or modified on the branch:

```bash
for f in $(git diff --name-only main...origin/claude/lucid-cori-9tSnU); do
  if git cat-file -e main:"$f" 2>/dev/null; then
    if git diff --quiet origin/claude/lucid-cori-9tSnU main -- "$f"; then
      echo "  ✓ IDENTICAL on main: $f"
    else
      echo "  ~ DIFFERS on main: $f"
    fi
  else
    echo "  ✗ MISSING on main: $f"
  fi
done
```

- [ ] **Step 4: If files are missing, backfill them**

If any files are missing, decide whether to backfill them (same approach used for W16–W19 in Shelby earlier this session — `git show <branch>:<path> > <path>`, commit, push). If files are stale or already superseded, skip backfill.

- [ ] **Step 5: Delete the branch**

```bash
git push origin --delete claude/lucid-cori-9tSnU
git fetch --prune
```

---

### Task 4.2: Update Shelby's safety-gate hook

The hook currently defers `Write`, `Edit`, and `git push` under `CLAUDE_SCHEDULED=1`. The new flow uses `git push <branch>` and `gh pr create` as the normal path — those need to be allowed. Destructive operations (`rm -rf`, `git reset --hard`, `git clean -fdx`, `curl --data`) should still be deferred.

**Files:**
- Modify: `Shelby-Strategy/.claude/hooks/scheduled-safety-gate.sh`

- [ ] **Step 1: Read current hook**

Read: `/Users/timmoser/Projects/Shelby/Shelby-Strategy/.claude/hooks/scheduled-safety-gate.sh`

- [ ] **Step 2: Update Write/Edit handling**

Currently: defers ALL `Write` and `Edit` calls. New behavior: allow `Write` and `Edit` (skill needs them to produce briefs and update backlog files). Remove the unconditional defer for these tools.

Replace:

```bash
# Defer Write and Edit tool calls in scheduled context
if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ]; then
    echo "scheduled-safety-gate: deferring '$TOOL' in scheduled context — waiting for human approval" >&2
    exit 2
fi
```

with:

```bash
# Write and Edit are allowed in scheduled context — skills produce files normally.
# Destructive shell operations are still gated below.
```

- [ ] **Step 3: Update git push handling**

Currently: defers all `git push` (including normal feature-branch pushes). New behavior: allow `git push origin <branch>` (any branch) and `gh pr` operations; defer only `git push --force` and `git push origin main`/`master`.

Replace:

```bash
    # Defer git push (including force push)
    if printf '%s' "$COMMAND" | grep -qE 'git\s+push'; then
        echo "scheduled-safety-gate: deferring git push in scheduled context — waiting for human approval" >&2
        exit 2
    fi
```

with:

```bash
    # Defer force-push (history-rewriting) and direct push to protected branches
    if printf '%s' "$COMMAND" | grep -qE 'git\s+push.*(--force|--force-with-lease|-f\b)'; then
        echo "scheduled-safety-gate: deferring force-push in scheduled context — waiting for human approval" >&2
        exit 2
    fi
    if printf '%s' "$COMMAND" | grep -qE 'git\s+push\s+origin\s+(main|master)\b'; then
        echo "scheduled-safety-gate: deferring direct push to main/master in scheduled context — feature branch + PR is the expected flow" >&2
        exit 2
    fi
    # Normal feature-branch pushes (git push -u origin <branch>) are allowed.
```

- [ ] **Step 4: Verify other gates still in place**

Confirm `rm -rf`, `git reset --hard`, `git clean -fdx`, `curl --data` patterns are still deferred (those rules unchanged).

- [ ] **Step 5: Test the hook syntax**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
bash -n .claude/hooks/scheduled-safety-gate.sh
```

Expected: no output (syntax OK). If syntax errors, fix them.

- [ ] **Step 6: Smoke-test interactively**

```bash
# Should pass through (interactive — no CLAUDE_SCHEDULED set)
CLAUDE_TOOL_NAME=Write CLAUDE_TOOL_INPUT='{}' bash .claude/hooks/scheduled-safety-gate.sh
echo "exit: $?"  # Expected: 0

# Should defer (scheduled + force-push)
CLAUDE_SCHEDULED=1 CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT='git push --force origin main' bash .claude/hooks/scheduled-safety-gate.sh
echo "exit: $?"  # Expected: 2

# Should pass (scheduled + branch push)
CLAUDE_SCHEDULED=1 CLAUDE_TOOL_NAME=Bash CLAUDE_TOOL_INPUT='git push -u origin feat/foo' bash .claude/hooks/scheduled-safety-gate.sh
echo "exit: $?"  # Expected: 0

# Should pass (scheduled + Write)
CLAUDE_SCHEDULED=1 CLAUDE_TOOL_NAME=Write CLAUDE_TOOL_INPUT='{}' bash .claude/hooks/scheduled-safety-gate.sh
echo "exit: $?"  # Expected: 0
```

- [ ] **Step 7: Commit**

```bash
cd /Users/timmoser/Projects/Shelby/Shelby-Strategy
git checkout -b chore/safety-gate-allow-pr-flow
git add .claude/hooks/scheduled-safety-gate.sh
git commit -m "chore(hooks): allow Write/Edit and feature-branch pushes under CLAUDE_SCHEDULED=1

Defer only force-push and direct-to-main pushes plus existing destructive shell ops.
Normal product-pulse PR flow now works under scheduled execution."
git push -u origin chore/safety-gate-allow-pr-flow
gh pr create --base main --title "chore(hooks): align safety-gate with PR-flow" --body "Allows the new product-pulse 0.2.0 flow (feature branch + gh pr create) under CLAUDE_SCHEDULED=1, while still deferring destructive operations and direct pushes to main/master."
gh pr merge --squash --delete-branch
```

---

## Final Verification

After all four phases land:

- [ ] **Step 1: Confirm no remaining forks**

```bash
ls "/Users/timmoser/Projects/Shelby/Shelby-Strategy/.claude/skills/" 2>/dev/null
ls "/Users/timmoser/Projects/The Crooked Line/docs/.claude/skills/" 2>/dev/null
```

Both should be empty (or not exist).

- [ ] **Step 2: Confirm config files in both repos**

```bash
ls "/Users/timmoser/Projects/Shelby/Shelby-Strategy/Research/pulse-config.yaml"
ls "/Users/timmoser/Projects/The Crooked Line/docs/research/pulse-config.yaml"
```

- [ ] **Step 3: Confirm planning/ folders**

```bash
ls "/Users/timmoser/Projects/Shelby/Shelby-Strategy/planning/"
ls "/Users/timmoser/Projects/The Crooked Line/docs/planning/"
```

Both should contain `todos.md` and `ideas.md`.

- [ ] **Step 4: Watch a full week of automation**

Let `shelby-daily-research` and `tcl-daily-research` run on their schedules for at least 3 days. Verify each run produces a PR that auto-merges successfully. If any run fails, debug and patch.

- [ ] **Step 5: Run weekly-strategist on the next Monday**

Invoke manually (no current scheduled task). Confirm:
- Brief lands in correct directory
- PR is opened and auto-merges
- Memory thought is captured (Shelby memory)
- Both repos' next-Monday brief lands cleanly

- [ ] **Step 6: Update Shelby memory with completion thought**

Capture a thought summarizing the migration (so future Claude sessions know the de-fork is done):

```
capture_thought({
  summary: "product-pulse 0.2.0 de-fork complete; both Shelby and TCL use plugin directly",
  type: "decision",
  topics: ["product-pulse", "shelby-strategy", "the-crooked-line", "plugin-architecture"],
  ...
})
```

---

## Notes for the executor

- **Plugin cache refresh:** Claude Code's plugin cache needs to refresh between Phase 1 and Phase 2. If it doesn't pick up v0.2.0 automatically, see Task 1.9 Step 6 for the manual copy fallback.
- **Timing:** Phase 2 and Phase 3 each have a window where the consuming repo is mid-migration. If a scheduled task fires during that window, it will fail. Mitigation: do each migration during a quiet window (after 06:02 daily-research completes, before next day's run). Worst case: one failed run, recoverable on next schedule.
- **Auto-merge surprises:** If branch protection or required reviews are enabled on `main` in either repo, `gh pr merge --auto` will queue the merge until requirements are met. Verify branch protection settings before relying on auto-merge.
- **Reading the spec:** Each task here references the spec at `skills-n-stuff/docs/superpowers/specs/2026-05-07-product-pulse-config-and-defork-design.md` — read it for context on *why* each change exists.
