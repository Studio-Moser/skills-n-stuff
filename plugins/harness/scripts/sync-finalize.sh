#!/usr/bin/env bash
# Stage and validate every repo write, then perform one commit/push transaction
# and prove the local tree matches the actual remote result.
set -euo pipefail

[ $# -eq 2 ] || { echo "usage: sync-finalize.sh <agents-repo> <commit-message>" >&2; exit 2; }
repo="$1"
message="$2"
scripts="$(cd "$(dirname "$0")" && pwd -P)"

repo="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "SYNC_STATE=failed: not a Git repository" >&2
  exit 1
}
[ -n "$message" ] || { echo "SYNC_STATE=failed: empty commit message" >&2; exit 2; }

git -C "$repo" add -A
git -C "$repo" diff --cached --check
"$scripts/portability-lint.sh" "$repo"
[ ! -e "$repo/mcp.manifest" ] || "$scripts/mcp-manifest.sh" --check "$repo/mcp.manifest"

python3 - "$repo" <<'PY'
from pathlib import PurePosixPath
import re
import subprocess
import sys

repo = sys.argv[1]

def git(*args: str) -> bytes:
    return subprocess.check_output(["git", "-C", repo, *args])

tracked = [
    item.decode("utf-8", "surrogateescape")
    for item in git("ls-files", "-z").split(b"\0")
    if item
]
local_state = []
for name in tracked:
    if (
        name in {".fleet-local.json", ".skill-lock.json"}
        or name == "claude/mcp.json"
        or name.endswith("/settings.local.json")
        or PurePosixPath(name).name in {"known_marketplaces.json", "installed_plugins.json"}
    ):
        local_state.append(name)
if local_state:
    for name in local_state:
        print(f"LOCAL_STATE_FINDING={name}", file=sys.stderr)
    print("SYNC_STATE=failed: staged local-state scan failed", file=sys.stderr)
    raise SystemExit(1)

patterns = (
    re.compile(rb"-----BEGIN (?:RSA |OPENSSH |EC |DSA |PGP )?PRIVATE KEY-----"),
    re.compile(
        rb"\b(?:ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|"
        rb"AKIA[A-Z0-9]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|"
        rb"sk-proj-[A-Za-z0-9_-]{10,}|sk-ant-[A-Za-z0-9_-]{10,})\b"
    ),
    re.compile(
        rb"(?im)\b(?:(?:(?:openai|anthropic|google|gemini|groq|openrouter|"
        rb"mistral|xai|cohere|perplexity)[_-]?)?api[_-]?(?:key|token)|"
        rb"access[_-]?token|auth[_-]?token|client[_-]?secret|password)\b"
        rb"[\"']?\s*[:=]\s*[\"']?(?!\$)[^\s\"',}]{16,}"
    ),
)
secret_paths = []
for name in tracked:
    try:
        blob = git("show", f":{name}")
    except subprocess.CalledProcessError:
        continue
    if any(pattern.search(blob) for pattern in patterns):
        secret_paths.append(name)
if secret_paths:
    for name in secret_paths:
        print(f"SECRET_FINDING={name}", file=sys.stderr)
    print("SYNC_STATE=failed: staged secret scan failed", file=sys.stderr)
    raise SystemExit(1)

print("STAGED_SCANS=portability,final-index-secret,local-state clean")
PY

git -C "$repo" diff --cached --stat
git -C "$repo" diff --cached --name-status

branch="$(git -C "$repo" branch --show-current)"
[ -n "$branch" ] || { echo "SYNC_STATE=failed: detached HEAD cannot sync" >&2; exit 1; }

remote="$(git -C "$repo" config --get "branch.$branch.remote" || true)"
merge_ref="$(git -C "$repo" config --get "branch.$branch.merge" || true)"
[ -n "$remote" ] || remote=origin
[ -n "$merge_ref" ] || merge_ref="refs/heads/$branch"
git -C "$repo" remote get-url "$remote" >/dev/null 2>&1 || {
  echo "SYNC_STATE=failed: no upstream or $remote remote" >&2
  exit 1
}

query_remote_sha() {
  local line
  line="$(git -C "$repo" ls-remote --heads "$remote" "$merge_ref")" || {
    echo "SYNC_STATE=failed: could not query $remote" >&2
    return 1
  }
  printf '%s' "${line%%[[:space:]]*}"
}

remote_branch="${merge_ref#refs/heads/}"
tracking_ref="refs/remotes/$remote/$remote_branch"
remote_before="$(query_remote_sha)" || exit 1
set_upstream=0
if [ -n "$remote_before" ]; then
  expected_remote="$(git -C "$repo" rev-parse "$tracking_ref" 2>/dev/null || true)"
  if [ -z "$expected_remote" ]; then
    echo "SYNC_STATE=failed: existing remote branch was not preflighted; rerun sync" >&2
    exit 1
  fi
  if [ "$remote_before" != "$expected_remote" ]; then
    echo "SYNC_STATE=failed: remote moved after preflight; rerun sync" >&2
    exit 1
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$remote_before" HEAD; then
    echo "SYNC_STATE=failed: local HEAD does not contain the preflighted remote; rerun sync" >&2
    exit 1
  fi
else
  set_upstream=1
fi

if ! git -C "$repo" diff --cached --quiet; then
  git -C "$repo" commit -m "$message"
fi

if [ -n "$(git -C "$repo" status --porcelain --untracked-files=all)" ]; then
  echo "SYNC_STATE=failed: worktree changed before push" >&2
  exit 1
fi

if [ "$set_upstream" -eq 1 ]; then
  git -C "$repo" push -u "$remote" "$branch:$merge_ref"
else
  git -C "$repo" push "$remote" "$branch:$merge_ref"
fi

if [ -n "$(git -C "$repo" status --porcelain --untracked-files=all)" ]; then
  echo "SYNC_STATE=failed: worktree changed during or after push" >&2
  exit 1
fi

local_sha="$(git -C "$repo" rev-parse HEAD)"
remote_sha="$(query_remote_sha)" || exit 1
if [ "$local_sha" != "$remote_sha" ]; then
  echo "SYNC_STATE=failed: remote moved during or after push" >&2
  exit 1
fi

printf 'SYNC_STATE=clean remote=%s\n' "$remote_sha"
