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
