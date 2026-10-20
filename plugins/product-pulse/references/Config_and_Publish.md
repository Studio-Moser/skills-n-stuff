# Config and Publish

Shared procedure for `daily-research`, `weekly-strategist`, and `deep-dive`. Each
skill says which sections to run and supplies its own branch, path, and messages.

## Discover Configuration

Walk up from cwd, checking each directory for `pulse-config.yaml` directly and in
common research-dir subdirs (`research/`, `Research/`, `docs/research/`). The first
match wins; that file's parent directory is the **research directory**
(`{research_dir}`).

Set `save_report=true` when the run writes files and opens a PR (daily, weekly, and
the deep-dive saved path); set it to `false` on the deep-dive chat path. Only a
publishing run stops for a missing config or a missing `gh` login, and it stops
before research rather than after it.

```bash
save_report=true   # false only on the deep-dive chat path
config_path=""
research_dir=""
dir="$PWD"
while [ "$dir" != "/" ]; do
  for sub in "" "research/" "Research/" "docs/research/"; do
    candidate="$dir/${sub}pulse-config.yaml"
    if [ -f "$candidate" ]; then
      config_path="$candidate"
      research_dir="$(cd "$(dirname "$candidate")" && pwd)"
      break 2
    fi
  done
  dir="$(dirname "$dir")"
done

if [ -z "$config_path" ]; then
  if [ "$save_report" = true ]; then
    echo "No pulse-config.yaml found. Run /product-pulse:setup first." >&2
    exit 1
  fi
  echo "No pulse-config.yaml found; continuing in chat without a research directory."
else
  # Required tools: stop before pulling if any is missing.
  for tool in git yq realpath; do
    command -v "$tool" >/dev/null || { echo "Missing required tool: $tool" >&2; exit 1; }
  done

  primary_repo_root="$(cd "$research_dir" && git rev-parse --show-toplevel)"
  default_branch="$(yq '.default_branch // "main"' "$config_path")"
  auto_merge="$(yq '.auto_merge // false' "$config_path")"
  project_id="$(yq '.project_id' "$config_path")"
  memory_connector="$(yq '.memory.connector // "shelby"' "$config_path")"

  echo "Using config: $config_path"
  echo "Research dir: $research_dir"
fi

if [ "$save_report" = true ]; then
  command -v gh >/dev/null || { echo "Missing required tool: gh" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "GitHub CLI is not signed in. Run: gh auth login" >&2; exit 1; }
fi
```

Required fields: `project_id`, `repos`. Optional with defaults: `default_branch`
(`main`), `auto_merge` (`false`), `memory.connector` (`shelby`; `null` disables memory).

The **primary repo root** (`{primary_repo_root}`) is the git top-level of the research
directory; git operations run there. Every `repos[].path` resolves relative to it:
`path: .` is the primary repo and `path: ../{name}` is a sibling repo.

## Pull Latest

Pull the default branch of every configured repo:

```bash
for repo_path in $(yq '.repos[].path' "$config_path"); do
  abs="$(realpath "$primary_repo_root/$repo_path")"
  echo "=== Pulling $abs ==="
  cd "$abs" && git checkout "$default_branch" && git pull origin "$default_branch" || echo "pull failed for $abs"
done
```

If a pull fails, note it and continue. A single-element `repos:` is the monorepo case.

## Publish

Run only when `save_report=true`. The calling skill supplies `branch`, `publish_path`,
`title`, and `body`.

```bash
cd "$primary_repo_root"
git checkout -b "$branch" 2>/dev/null || git checkout "$branch"  # reuse the branch on a same-day rerun
git add "$publish_path"
git commit -m "$title"
git push -u origin "$branch"
# A same-day rerun reuses the open PR; the push above already updated it.
pr_url=$(gh pr view "$branch" --json url,state --jq 'select(.state == "OPEN") | .url' 2>/dev/null)
if [ -z "$pr_url" ]; then
  pr_url=$(gh pr create --base "$default_branch" --head "$branch" \
    --title "$title" --body "$body" | tail -n1)
fi
echo "PR: $pr_url"

if [ "$auto_merge" = true ]; then
  sleep 8  # let GitHub finalize the mergeability check
  gh pr merge "$pr_url" --squash --delete-branch --auto || \
    echo "Auto-merge declined; PR sits for human review at $pr_url"
fi
```

`--auto` queues the merge while checks run. If branch protection or required reviews
block it, the PR waits for human review and the run ends cleanly with the PR URL.
