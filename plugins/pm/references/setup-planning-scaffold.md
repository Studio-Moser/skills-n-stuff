# planning/ Scaffold for /pm:setup

Loaded by `skills/setup/SKILL.md` Phase 7 for every backend.

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

Read the template from `templates/spec-template.md`. Write to `{specs_dir}/_TEMPLATE.md` (`specs_dir` from `.pm/config.yml`, default `planning/specs`) (no placeholder substitution — agents copy this file and fill in placeholders when creating new specs).

#### Create planning/archive/

Create the empty directory. Sprint-dev creates quarterly files (e.g. `done-2026-Q2.md`) when archiving.

#### Update pulse-config.yaml

If `pulse-config.yaml` exists but lacks a `backlog:` section, append:

```yaml
backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
```
