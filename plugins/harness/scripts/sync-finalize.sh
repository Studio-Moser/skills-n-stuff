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

branch="$(git -C "$repo" branch --show-current)"
[ -n "$branch" ] || { echo "SYNC_STATE=failed: detached HEAD cannot sync" >&2; exit 1; }

remote="$(git -C "$repo" config --get "branch.$branch.remote" || true)"
merge_ref="$(git -C "$repo" config --get "branch.$branch.merge" || true)"
[ -n "$remote" ] || remote=origin
[ -n "$merge_ref" ] || merge_ref="refs/heads/$branch"
fetch_urls="$(git -C "$repo" remote get-url --all "$remote" 2>/dev/null)" || {
  echo "SYNC_STATE=failed: no upstream or $remote remote" >&2
  exit 1
}
push_urls="$(git -C "$repo" remote get-url --all --push "$remote" 2>/dev/null)" || {
  echo "SYNC_STATE=failed: could not resolve $remote push URL" >&2
  exit 1
}
if [ "$fetch_urls" != "$push_urls" ] || [[ "$fetch_urls" == *$'\n'* ]]; then
  echo "SYNC_STATE=failed: distinct push URL is unsupported; make fetch and push endpoints identical, then rerun sync" >&2
  exit 1
fi

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
        rb"sk-proj-[A-Za-z0-9_-]{10,}|sk-ant-[A-Za-z0-9_-]{10,}|"
        rb"AIza[A-Za-z0-9_-]{20,}|gsk_[A-Za-z0-9_-]{20,})\b"
    ),
    re.compile(
        rb"(?im)\b(?:(?:(?:openai|anthropic|azure[_-]?openai|deepseek|google|"
        rb"gemini|groq|openrouter|mistral|xai|cohere|perplexity)[_-]?)?"
        rb"api[_-]?(?:key|token)|"
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

git_dir="$(git -C "$repo" rev-parse --absolute-git-dir)"
state_path="$git_dir/harness-sync-expected-remote"
[ -f "$state_path" ] || {
  echo "SYNC_STATE=failed: remote was not preflighted; rerun sync" >&2
  exit 1
}
if ! {
  IFS= read -r expected_remote
  IFS= read -r expected_merge_ref
  IFS= read -r expected_sha
  ! IFS= read -r extra
} < "$state_path"; then
  echo "SYNC_STATE=failed: invalid preflight state; rerun sync" >&2
  exit 1
fi
if [ "$expected_remote" != "$remote" ] || [ "$expected_merge_ref" != "$merge_ref" ]; then
  echo "SYNC_STATE=failed: branch or remote changed after preflight; rerun sync" >&2
  exit 1
fi
case "$expected_sha" in
  ABSENT) ;;
  *[!0-9a-f]*|'')
    echo "SYNC_STATE=failed: invalid preflight state; rerun sync" >&2
    exit 1
    ;;
esac
if [ "$expected_sha" != ABSENT ] && [ "${#expected_sha}" -ne 40 ] && [ "${#expected_sha}" -ne 64 ]; then
  echo "SYNC_STATE=failed: invalid preflight state; rerun sync" >&2
  exit 1
fi

query_remote_sha() {
  local line
  line="$(git -C "$repo" ls-remote --heads "$remote" "$merge_ref")" || {
    echo "SYNC_STATE=failed: could not query $remote" >&2
    return 1
  }
  printf '%s' "${line%%[[:space:]]*}"
}

remote_before="$(query_remote_sha)" || exit 1
set_upstream=0
if [ "$expected_sha" = ABSENT ]; then
  if [ -n "$remote_before" ]; then
    echo "SYNC_STATE=failed: remote moved after preflight; rerun sync" >&2
    exit 1
  fi
  set_upstream=1
else
  if [ "$remote_before" != "$expected_sha" ]; then
    echo "SYNC_STATE=failed: remote moved after preflight; rerun sync" >&2
    exit 1
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$expected_sha" HEAD; then
    echo "SYNC_STATE=failed: local HEAD does not contain the preflighted remote; rerun sync" >&2
    exit 1
  fi
fi

if ! git -C "$repo" diff --cached --quiet; then
  git -C "$repo" commit -m "$message"
fi

if [ -n "$(git -C "$repo" status --porcelain --untracked-files=all)" ]; then
  echo "SYNC_STATE=failed: worktree changed before push" >&2
  exit 1
fi

if [ "$expected_sha" = ABSENT ]; then
  lease="--force-with-lease=$merge_ref:"
else
  lease="--force-with-lease=$merge_ref:$expected_sha"
fi
if [ "$set_upstream" -eq 1 ]; then
  push=(git -C "$repo" push -u "$lease" "$remote" "$branch:$merge_ref")
else
  push=(git -C "$repo" push "$lease" "$remote" "$branch:$merge_ref")
fi
if ! "${push[@]}"; then
  echo "SYNC_STATE=failed: remote compare-and-swap rejected; rerun sync" >&2
  exit 1
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

rm -f -- "$state_path"
printf 'SYNC_STATE=clean remote=%s\n' "$remote_sha"
