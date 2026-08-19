# GitHub Backend Setup for /pm:setup

Load this only when the user selects the GitHub Issues backend. It covers the
backend interview, Phase 3 config generation, and Phase 6 provisioning. Return
to the main skill between sections.

Load `references/setup-github-projects.md` only if the user wants an optional
GitHub Projects v2 board.

## Backend Interview

Read and parse the primary repo's HTTPS or SSH remote:

```bash
git remote get-url origin 2>/dev/null
```

Confirm the detected owner/repo.
- "I detected `{owner}/{repo}` from your git remote. Is that correct?"
- If the user has a multi-repo workspace, ask: "Should PM create issues in the primary repo only, or across all repos? (Default: primary repo only, with labels indicating target repo.)"

## Generate .pm/config.yml

Use these values in the backend-specific placeholder in the main skill's shared
config:

```yaml
backend: github

github:
  owner: {owner from git remote or interview}
  repo: {repo from git remote or interview}
  # For multi-repo workspaces, target repos receive issues with a repo label.
  # Uncomment and list target repos if PM should create issues across repos:
  # target_repos:
  #   - owner/repo-name
  # Optional GitHub Projects v2 mirroring is added only by its selected path.
  # When skipped, the `project_sync` block is intentionally absent
  # (which means "off"). See plugins/pm/schemas/pm-config.github.example.yml.
```

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

### Optional GitHub Project

Ask whether the user wants a GitHub Projects v2 board. If yes, load
`references/setup-github-projects.md` and follow it. If no, do not load that file
and keep label-only mode.

### Summary lines

Record the label count and repo. If the optional project path ran, include its
created/linked state, URL, status sync state, and added-item count. Otherwise
record `GitHub Project: skipped (label-only mode)`.

## Edge Cases

- **gh CLI not installed**: If the GitHub backend is selected but `gh` is not available, warn the user: "The `gh` CLI is required for the GitHub Issues backend. Install it with `brew install gh` and run `gh auth login`, then re-run `/pm:setup`." Fall back to local backend if the user prefers.

- **gh CLI not authenticated**: If `gh auth status` fails, prompt the user to run `gh auth login` first.

- **Private repos without gh access**: If `gh repo view` fails with a permissions error, note this and suggest the user check their `gh` authentication scopes.

- **No git remote**: GitHub setup is not viable until the user adds a remote or
  supplies an accessible owner/repo. Offer to return to backend selection.
