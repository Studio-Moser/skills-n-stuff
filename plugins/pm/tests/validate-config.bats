#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-config.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
}

@test "github fixture validates" {
  run "$SCRIPT" "$FIX/github/config.yml"
  [ "$status" -eq 0 ]
}

@test "github fixture with optional project_sync block validates" {
  run "$SCRIPT" "$FIX/github/config.with-project-sync.yml"
  [ "$status" -eq 0 ]
}

@test "valid trello fixture validates" {
  run "$SCRIPT" "$FIX/trello/config.yml"
  [ "$status" -eq 0 ]
}

@test "trello fixture missing 'done' list is rejected" {
  run "$SCRIPT" "$FIX/trello/config.invalid-missing-list.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing required list key: done"* ]]
}

@test "trello fixture without done -> needs_changes back-edge is rejected" {
  run "$SCRIPT" "$FIX/trello/config.invalid-no-back-edge.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"done -> needs_changes"* ]]
}

@test "trello fixture with empty boards array surfaces friendly error (no yq crash)" {
  # `run` merges stdout+stderr so we can assert on both.
  run "$SCRIPT" "$FIX/trello/config.empty-boards.yml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"trello.boards must have at least one entry"* ]] || return 1
  # Must NOT leak yq's cryptic message.
  [[ "$output" != *"out of range"* ]] || return 1
  [[ "$output" != *"Error: index"* ]]
}

@test "missing file gives usage" {
  run "$SCRIPT" /tmp/does-not-exist-$$.yml
  [ "$status" -eq 2 ]
}
