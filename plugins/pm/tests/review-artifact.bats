#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="$REPO_ROOT/plugins/pm/scripts/materialize-review-artifact.sh"
  TEST_ROOT="$(mktemp -d)"
  FIXTURE_REPO="$TEST_ROOT/repo"

  git init -q "$FIXTURE_REPO"
  git -C "$FIXTURE_REPO" config user.email "pm-tests@example.invalid"
  git -C "$FIXTURE_REPO" config user.name "PM Tests"
  printf 'before\n' > "$FIXTURE_REPO/value.txt"
  git -C "$FIXTURE_REPO" add value.txt
  git -C "$FIXTURE_REPO" commit -q -m "before"
  BASE_SHA="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
  printf 'after\n' > "$FIXTURE_REPO/value.txt"
  git -C "$FIXTURE_REPO" commit -q -am "after"
  HEAD_SHA="$(git -C "$FIXTURE_REPO" rev-parse HEAD)"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "matching retained review artifact is reused without overwrite" {
  run "$SCRIPT" "$FIXTURE_REPO" "$BASE_SHA" "$HEAD_SHA"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  artifact_rel="$(printf '%s\n' "$output" | sed -n 's/^artifact=//p')"
  artifact_abs="$FIXTURE_REPO/$artifact_rel"
  fixed_target="$(printf '%s\n' "$output" | sed -n 's/^fixed_target=//p')"
  [ -f "$artifact_abs" ] || return 1
  [[ "$output" == *"state=created"* ]] || return 1
  retained_inode="$(ls -id "$artifact_abs" | awk '{print $1}')"

  run "$SCRIPT" "$FIXTURE_REPO" "$BASE_SHA" "$HEAD_SHA"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  [[ "$output" == *"state=reused"* ]] || return 1
  [[ "$output" == *"artifact=$artifact_rel"* ]] || return 1
  [[ "$output" == *"fixed_target=$fixed_target"* ]] || return 1
  [ "$(ls -id "$artifact_abs" | awk '{print $1}')" = "$retained_inode" ] || return 1
  [ "$(find "$FIXTURE_REPO/.harness-review" -type f | wc -l | tr -d ' ')" -eq 1 ]
}

@test "mismatched retained review artifact blocks without overwrite" {
  run "$SCRIPT" "$FIXTURE_REPO" "$BASE_SHA" "$HEAD_SHA"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output" >&2; return 1; }
  artifact_rel="$(printf '%s\n' "$output" | sed -n 's/^artifact=//p')"
  artifact_abs="$FIXTURE_REPO/$artifact_rel"
  expected_digest="$(printf '%s\n' "$output" | sed -n 's/^fixed_target=snapshot:sha256://p')"
  printf 'retained conflict\n' > "$artifact_abs"
  conflict_digest="$(shasum -a 256 "$artifact_abs" | awk '{print $1}')"

  run "$SCRIPT" "$FIXTURE_REPO" "$BASE_SHA" "$HEAD_SHA"
  [ "$status" -eq 3 ] || { printf 'status=%s\n%s\n' "$status" "$output" >&2; return 1; }
  [[ "$output" == *"review artifact conflict: $artifact_rel"* ]] || return 1
  [[ "$output" == *"has digest $conflict_digest; expected $expected_digest"* ]] || return 1
  [ "$(sed -n '1p' "$artifact_abs")" = "retained conflict" ] || return 1
  [ "$(find "$FIXTURE_REPO/.harness-review" -type f | wc -l | tr -d ' ')" -eq 1 ]
}

@test "symlinked artifact directory is refused without outside writes" {
  outside_dir="$TEST_ROOT/outside-directory"
  mkdir "$outside_dir"
  ln -s "$outside_dir" "$FIXTURE_REPO/.harness-review"

  run "$SCRIPT" "$FIXTURE_REPO" "$BASE_SHA" "$HEAD_SHA"

  [ "$status" -eq 3 ] || { printf 'status=%s\n%s\n' "$status" "$output" >&2; return 1; }
  [[ "$output" == *".harness-review is not an in-worktree directory"* ]] || return 1
  [ -z "$(find "$outside_dir" -mindepth 1 -maxdepth 1 -print -quit)" ] || return 1
}

@test "raced destination symlink cannot create a hard link outside worktree" {
  race_bin="$TEST_ROOT/race-bin"
  outside_dir="$TEST_ROOT/outside-destination"
  mkdir "$race_bin" "$outside_dir"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'destination=""' \
    'for argument in "$@"; do destination="$argument"; done' \
    '/bin/ln -s "$RACE_OUTSIDE_DIR" "$destination"' \
    'exec /bin/ln "$@"' \
    > "$race_bin/ln"
  chmod +x "$race_bin/ln"

  run env PATH="$race_bin:$PATH" RACE_OUTSIDE_DIR="$outside_dir" \
    "$SCRIPT" "$FIXTURE_REPO" "$BASE_SHA" "$HEAD_SHA"

  failed=0
  if [ "$status" -ne 3 ]; then
    printf 'expected status 3, got %s\n%s\n' "$status" "$output" >&2
    failed=1
  fi
  if [[ "$output" == *"state=created"* ]]; then
    printf 'helper falsely reported creation:\n%s\n' "$output" >&2
    failed=1
  fi
  outside_entry="$(find "$outside_dir" -mindepth 1 -maxdepth 1 -print -quit)"
  if [ -n "$outside_entry" ]; then
    printf 'helper created an outside hard link: %s\n' "$outside_entry" >&2
    failed=1
  fi
  [ "$failed" -eq 0 ]
}
