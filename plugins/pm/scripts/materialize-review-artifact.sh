#!/usr/bin/env bash
# Materialize one immutable review patch and safely reuse an exact retained copy.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 WORKTREE BASE_COMMIT HEAD_COMMIT" >&2
  exit 2
fi

worktree="$1"
base_ref="$2"
head_ref="$3"
worktree_root="$(git -C "$worktree" rev-parse --show-toplevel)" || exit 1
base_sha="$(git -C "$worktree_root" rev-parse "${base_ref}^{commit}")" || exit 1
head_sha="$(git -C "$worktree_root" rev-parse "${head_ref}^{commit}")" || exit 1

artifact_dir_rel=".harness-review"
artifact_dir_abs="$worktree_root/$artifact_dir_rel"
mkdir -p "$artifact_dir_abs" || exit 1
artifact_tmp_abs="$(mktemp "$artifact_dir_abs/review.patch.XXXXXX")" || exit 1

cleanup_temp() {
  if [ -n "${artifact_tmp_abs:-}" ]; then
    rm -f "$artifact_tmp_abs"
  fi
  rmdir "$artifact_dir_abs" 2>/dev/null || true
}
trap cleanup_temp EXIT
trap 'exit 1' HUP INT TERM

git -C "$worktree_root" diff --binary --full-index "$base_sha" "$head_sha" > "$artifact_tmp_abs" || exit 1
expected_digest="$(shasum -a 256 "$artifact_tmp_abs" | awk '{print $1}')"
printf '%s\n' "$expected_digest" | grep -Eq '^[0-9a-f]{64}$' || exit 1

artifact_rel="$artifact_dir_rel/review-${expected_digest}.patch"
artifact_abs="$worktree_root/$artifact_rel"
fixed_target="snapshot:sha256:${expected_digest}"

classify_existing() {
  if [ -L "$artifact_abs" ] || { [ -e "$artifact_abs" ] && [ ! -f "$artifact_abs" ]; }; then
    printf 'review artifact conflict: %s is not a regular file; expected digest %s\n' \
      "$artifact_rel" "$expected_digest" >&2
    exit 3
  fi
  [ -f "$artifact_abs" ] || return 1
  if ! existing_digest="$(shasum -a 256 "$artifact_abs" | awk '{print $1}')"; then
    printf 'review artifact conflict: cannot hash %s; expected digest %s\n' \
      "$artifact_rel" "$expected_digest" >&2
    exit 3
  fi
  if [ "$existing_digest" != "$expected_digest" ]; then
    printf 'review artifact conflict: %s has digest %s; expected %s\n' \
      "$artifact_rel" "$existing_digest" "$expected_digest" >&2
    exit 3
  fi
  state="reused"
}

if classify_existing; then
  :
else
  existing_status=$?
  [ "$existing_status" -eq 1 ] || exit "$existing_status"
  if ln "$artifact_tmp_abs" "$artifact_abs" 2>/dev/null; then
    rm -f "$artifact_tmp_abs"
    artifact_tmp_abs=""
    state="created"
  elif classify_existing; then
    :
  else
    raced_status=$?
    [ "$raced_status" -ne 1 ] && exit "$raced_status"
    printf 'could not create review artifact without overwrite: %s\n' "$artifact_rel" >&2
    exit 1
  fi
fi

printf 'state=%s\nfixed_target=%s\nartifact=%s\n' \
  "$state" "$fixed_target" "$artifact_rel"
