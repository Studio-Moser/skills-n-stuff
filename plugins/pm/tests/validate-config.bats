#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/validate-config.sh"
  FIX="$BATS_TEST_DIRNAME/fixtures"
}

@test "github fixture validates" {
  run "$SCRIPT" "$FIX/github/config.yml"
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

@test "missing file gives usage" {
  run "$SCRIPT" /tmp/does-not-exist-$$.yml
  [ "$status" -eq 2 ]
}
