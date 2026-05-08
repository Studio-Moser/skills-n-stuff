#!/usr/bin/env bash
# discover-config.sh — Pre-resolves all PM + pulse config values.
# Called via !`...` shell injection in SKILL.md files so Claude receives
# pre-resolved values instead of executing the walk-up loop itself.
#
# Usage: discover-config.sh
# Output: key=value pairs that the skill can reference directly.

set -euo pipefail

# ── Find pulse-config.yaml ──────────────────────────────────────────
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
  echo "ERROR: No pulse-config.yaml found. Run /product-pulse:setup or /pm:setup first."
  exit 0  # exit 0 so shell injection doesn't abort skill load
fi

# ── Parse pulse-config.yaml ─────────────────────────────────────────
primary_repo_root="$(cd "$research_dir" && git rev-parse --show-toplevel 2>/dev/null || echo "$research_dir")"
project_id="$(yq '.project_id // "unknown"' "$config_path" 2>/dev/null || echo "unknown")"
default_branch="$(yq '.default_branch // "main"' "$config_path" 2>/dev/null || echo "main")"
auto_merge="$(yq '.auto_merge // true' "$config_path" 2>/dev/null || echo "true")"
memory_connector="$(yq '.memory.connector // "shelby"' "$config_path" 2>/dev/null || echo "shelby")"
backlog_active="$(yq '.backlog.active // "planning/todos.md"' "$config_path" 2>/dev/null || echo "planning/todos.md")"
backlog_ideas="$(yq '.backlog.ideas // "planning/ideas.md"' "$config_path" 2>/dev/null || echo "planning/ideas.md")"

# ── Parse .pm/config.yml ────────────────────────────────────────────
pm_config="$primary_repo_root/.pm/config.yml"
if [ ! -f "$pm_config" ]; then
  echo "ERROR: No .pm/config.yml found at $pm_config. Run /pm:setup first."
  exit 0
fi

backend="$(yq '.backend // "github"' "$pm_config" 2>/dev/null || echo "github")"
context_md="$(yq '.context_md // "CONTEXT.md"' "$pm_config" 2>/dev/null || echo "CONTEXT.md")"
adr_dir="$(yq '.adr_dir // "docs/adr"' "$pm_config" 2>/dev/null || echo "docs/adr")"
oos_dir="$(yq '.out_of_scope_dir // ".pm/out-of-scope"' "$pm_config" 2>/dev/null || echo ".pm/out-of-scope")"
stale_threshold="$(yq '.triage.stale_threshold_days // 30' "$pm_config" 2>/dev/null || echo "30")"

# ── Backend-specific extraction ─────────────────────────────────────
gh_owner=""
gh_repo=""
trello_webhook_url=""
trello_boards_json="[]"
trello_statuses_json="{}"

case "$backend" in
  github)
    gh_owner="$(yq '.github.owner // ""' "$pm_config" 2>/dev/null || echo "")"
    gh_repo="$(yq '.github.repo  // ""' "$pm_config" 2>/dev/null || echo "")"
    ;;
  trello)
    trello_webhook_url="$(yq '.trello.webhook_url // ""' "$pm_config" 2>/dev/null || echo "")"
    trello_boards_json="$(yq -o=json -I=0 '.trello.boards // []' "$pm_config" 2>/dev/null || echo "[]")"
    trello_statuses_json="$(yq -o=json -I=0 '.trello.statuses // {}' "$pm_config" 2>/dev/null || echo "{}")"
    ;;
  local)
    : # nothing to add
    ;;
esac

# Research directories
research_dirs_raw="$(yq '.research_dirs[]' "$pm_config" 2>/dev/null || echo "")"
if [ -z "$research_dirs_raw" ]; then
  research_dirs="$research_dir"
else
  resolved=""
  while IFS= read -r rd; do
    [ -z "$rd" ] && continue
    if [[ "$rd" = /* ]]; then
      resolved="${resolved:+$resolved:}$rd"
    else
      resolved="${resolved:+$resolved:}$primary_repo_root/$rd"
    fi
  done <<< "$research_dirs_raw"
  research_dirs="$resolved"
fi

# State file
state_file="$primary_repo_root/.pm/state.yml"

# Repos from pulse-config
repos_yaml="$(yq -o=json '.repos' "$config_path" 2>/dev/null || echo "[]")"

# ── Output ──────────────────────────────────────────────────────────
cat <<CONF
config_path=$config_path
research_dir=$research_dir
primary_repo_root=$primary_repo_root
project_id=$project_id
default_branch=$default_branch
auto_merge=$auto_merge
memory_connector=$memory_connector
backlog_active=$primary_repo_root/$backlog_active
backlog_ideas=$primary_repo_root/$backlog_ideas
pm_config=$pm_config
backend=$backend
context_md=$primary_repo_root/$context_md
adr_dir=$primary_repo_root/$adr_dir
oos_dir=$primary_repo_root/$oos_dir
stale_threshold_days=$stale_threshold
gh_owner=$gh_owner
gh_repo=$gh_repo
trello_webhook_url=$trello_webhook_url
trello_boards_json=$trello_boards_json
trello_statuses_json=$trello_statuses_json
research_dirs=$research_dirs
state_file=$state_file
repos_json=$repos_yaml
CONF
