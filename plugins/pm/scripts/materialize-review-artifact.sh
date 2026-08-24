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
worktree_root="$(cd -P "$worktree_root" && pwd -P)" || exit 1
base_sha="$(git -C "$worktree_root" rev-parse "${base_ref}^{commit}")" || exit 1
head_sha="$(git -C "$worktree_root" rev-parse "${head_ref}^{commit}")" || exit 1

artifact_dir_rel=".harness-review"
artifact_dir_abs="$worktree_root/$artifact_dir_rel"

artifact_directory_conflict() {
  printf 'review artifact conflict: %s is not an in-worktree directory\n' \
    "$artifact_dir_rel" >&2
  exit 3
}

validate_artifact_directory() {
  if [ -L "$artifact_dir_abs" ] || [ ! -d "$artifact_dir_abs" ]; then
    artifact_directory_conflict
  fi
  if ! artifact_dir_physical="$(cd -P "$artifact_dir_abs" 2>/dev/null && pwd -P)"; then
    artifact_directory_conflict
  fi
  [ "$artifact_dir_physical" = "$artifact_dir_abs" ] || artifact_directory_conflict
}

mkdir "$artifact_dir_abs" 2>/dev/null || validate_artifact_directory
validate_artifact_directory
cd -P "$artifact_dir_abs" || artifact_directory_conflict
[ "$(pwd -P)" = "$artifact_dir_abs" ] || artifact_directory_conflict

artifact_tmp_path="$(mktemp "./review.patch.XXXXXX")" || exit 1

cleanup_temp() {
  if [ -n "${artifact_tmp_path:-}" ]; then
    rm -f "$artifact_tmp_path"
  fi
  rmdir "$artifact_dir_abs" 2>/dev/null || true
}
trap cleanup_temp EXIT
trap 'exit 1' HUP INT TERM

git -C "$worktree_root" diff --binary --full-index "$base_sha" "$head_sha" > "$artifact_tmp_path" || exit 1
expected_digest="$(shasum -a 256 "$artifact_tmp_path" | awk '{print $1}')"
printf '%s\n' "$expected_digest" | grep -Eq '^[0-9a-f]{64}$' || exit 1

artifact_name="review-${expected_digest}.patch"
artifact_rel="$artifact_dir_rel/$artifact_name"
artifact_abs="$worktree_root/$artifact_rel"
artifact_path="./$artifact_name"
fixed_target="snapshot:sha256:${expected_digest}"

classify_existing() {
  if [ -L "$artifact_path" ] || { [ -e "$artifact_path" ] && [ ! -f "$artifact_path" ]; }; then
    printf 'review artifact conflict: %s is not a regular file; expected digest %s\n' \
      "$artifact_rel" "$expected_digest" >&2
    exit 3
  fi
  [ -f "$artifact_path" ] || return 1
  if ! existing_digest="$(shasum -a 256 "$artifact_path" | awk '{print $1}')"; then
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

verify_expected_artifact() {
  validate_artifact_directory
  if [ -L "$artifact_abs" ] || [ ! -f "$artifact_abs" ] || \
    [ -L "$artifact_path" ] || [ ! -f "$artifact_path" ] || \
    ! [ "$artifact_abs" -ef "$artifact_path" ]; then
    printf 'review artifact conflict: %s is not the expected in-worktree regular file\n' \
      "$artifact_rel" >&2
    exit 3
  fi
  if ! verified_digest="$(shasum -a 256 "$artifact_path" | awk '{print $1}')" || \
    [ "$verified_digest" != "$expected_digest" ]; then
    printf 'review artifact conflict: %s failed post-creation digest verification; expected %s\n' \
      "$artifact_rel" "$expected_digest" >&2
    exit 3
  fi
}

if classify_existing; then
  :
else
  existing_status=$?
  [ "$existing_status" -eq 1 ] || exit "$existing_status"
  if ln -n "$artifact_tmp_path" "$artifact_path" 2>/dev/null; then
    if [ -L "$artifact_path" ] || [ ! -f "$artifact_path" ] || \
      ! [ "$artifact_tmp_path" -ef "$artifact_path" ]; then
      printf 'review artifact conflict: %s was not created at the expected destination\n' \
        "$artifact_rel" >&2
      exit 3
    fi
    rm -f "$artifact_tmp_path"
    artifact_tmp_path=""
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

verify_expected_artifact
printf 'state=%s\nfixed_target=%s\nartifact=%s\n' \
  "$state" "$fixed_target" "$artifact_rel"
