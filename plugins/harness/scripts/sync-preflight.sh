#!/usr/bin/env bash
# Ingest the current remote branch before any sync writer runs.
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: sync-preflight.sh <agents-repo>" >&2; exit 2; }
repo="$1"

repo="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || {
  echo "SYNC_PREFLIGHT=failed: not a Git repository" >&2
  exit 1
}
git_dir="$(git -C "$repo" rev-parse --absolute-git-dir)"
state_path="$git_dir/harness-sync-expected-remote"
rm -f -- "$state_path"
branch="$(git -C "$repo" branch --show-current)"
[ -n "$branch" ] || { echo "SYNC_PREFLIGHT=failed: detached HEAD cannot sync" >&2; exit 1; }

remote="$(git -C "$repo" config --get "branch.$branch.remote" || true)"
merge_ref="$(git -C "$repo" config --get "branch.$branch.merge" || true)"
if [ -z "$remote" ]; then
  remote=origin
fi
if [ -z "$merge_ref" ]; then
  merge_ref="refs/heads/$branch"
fi
fetch_urls="$(git -C "$repo" remote get-url --all "$remote" 2>/dev/null)" || {
  echo "SYNC_PREFLIGHT=failed: no upstream or $remote remote" >&2
  exit 1
}
push_urls="$(git -C "$repo" remote get-url --all --push "$remote" 2>/dev/null)" || {
  echo "SYNC_PREFLIGHT=failed: could not resolve $remote push URL" >&2
  exit 1
}
if [ "$fetch_urls" != "$push_urls" ] || [[ "$fetch_urls" == *$'\n'* ]]; then
  echo "SYNC_PREFLIGHT=failed: distinct push URL is unsupported; make fetch and push endpoints identical, then rerun sync" >&2
  exit 1
fi

query_remote_sha() {
  local line
  line="$(git -C "$repo" ls-remote --heads "$remote" "$merge_ref")" || {
    echo "SYNC_PREFLIGHT=failed: could not query $remote" >&2
    return 1
  }
  printf '%s' "${line%%[[:space:]]*}"
}

persist_expected_remote() {
  local expected="$1" parent temporary
  parent="$(dirname "$state_path")"
  temporary="$(mktemp "$parent/.harness-sync-expected-remote.XXXXXX")"
  chmod 600 "$temporary"
  printf '%s\n%s\n%s\n%s\n' "$remote" "$merge_ref" "$expected" "$fetch_urls" > "$temporary"
  mv -f "$temporary" "$state_path"
}

remote_sha="$(query_remote_sha)" || exit 1
if [ -z "$remote_sha" ]; then
  confirmed_sha="$(query_remote_sha)" || exit 1
  [ -z "$confirmed_sha" ] || {
    echo "SYNC_PREFLIGHT=failed: remote moved during preflight; rerun sync" >&2
    exit 1
  }
  persist_expected_remote ABSENT
  echo "SYNC_PREFLIGHT=ready state=new-branch"
  exit 0
fi
remote_branch="${merge_ref#refs/heads/}"
tracking_ref="refs/remotes/$remote/$remote_branch"
local_sha="$(git -C "$repo" rev-parse HEAD)"

if [ -n "$(git -C "$repo" status --porcelain --untracked-files=all)" ]; then
  known_sha="$(git -C "$repo" rev-parse "$tracking_ref" 2>/dev/null || true)"
  if [ "$remote_sha" != "$known_sha" ] && [ "$remote_sha" != "$local_sha" ]; then
    echo "SYNC_PREFLIGHT=failed: remote moved while local work exists; commit or stash it, ingest the remote, then rerun sync" >&2
    exit 1
  fi
  if [ "$remote_sha" = "$local_sha" ] && [ "$remote_sha" != "$known_sha" ]; then
    git -C "$repo" fetch --no-tags "$remote" "$merge_ref:$tracking_ref"
    fetched_sha="$(git -C "$repo" rev-parse "$tracking_ref")"
    if [ "$fetched_sha" != "$remote_sha" ]; then
      echo "SYNC_PREFLIGHT=failed: remote moved during preflight; rerun sync" >&2
      exit 1
    fi
  fi
  if ! git -C "$repo" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
    echo "SYNC_PREFLIGHT=failed: remote has commits not present locally while local work exists; commit or stash it, ingest the remote, then rerun sync" >&2
    exit 1
  fi
  if ! git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
    git -C "$repo" branch --set-upstream-to="$remote/$remote_branch" "$branch" >/dev/null
  fi
  confirmed_sha="$(query_remote_sha)" || exit 1
  [ "$confirmed_sha" = "$remote_sha" ] || {
    echo "SYNC_PREFLIGHT=failed: remote moved during preflight; rerun sync" >&2
    exit 1
  }
  persist_expected_remote "$remote_sha"
  printf 'SYNC_PREFLIGHT=ready state=remote-unchanged remote=%s\n' "$remote_sha"
  exit 0
fi

git -C "$repo" fetch --no-tags "$remote" "$merge_ref:$tracking_ref"
fetched_sha="$(git -C "$repo" rev-parse "$tracking_ref")"
if [ "$fetched_sha" != "$remote_sha" ]; then
  echo "SYNC_PREFLIGHT=failed: remote moved during preflight; rerun sync" >&2
  exit 1
fi

state=current
if [ "$local_sha" = "$fetched_sha" ]; then
  :
elif git -C "$repo" merge-base --is-ancestor "$local_sha" "$fetched_sha"; then
  git -C "$repo" merge --ff-only "$tracking_ref"
  state=fast-forwarded
elif git -C "$repo" merge-base --is-ancestor "$fetched_sha" "$local_sha"; then
  state=local-ahead
else
  echo "SYNC_PREFLIGHT=failed: local and remote histories diverged; reconcile them, then rerun sync" >&2
  exit 1
fi

if ! git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  git -C "$repo" branch --set-upstream-to="$remote/$remote_branch" "$branch" >/dev/null
fi
confirmed_sha="$(query_remote_sha)" || exit 1
[ "$confirmed_sha" = "$remote_sha" ] || {
  echo "SYNC_PREFLIGHT=failed: remote moved during preflight; rerun sync" >&2
  exit 1
}
persist_expected_remote "$remote_sha"
printf 'SYNC_PREFLIGHT=ready state=%s remote=%s\n' "$state" "$remote_sha"
