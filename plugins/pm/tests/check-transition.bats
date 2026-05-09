#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/check-transition.sh"
  STATUSES_JSON='{
    "needs_triage":    ["ready_for_agent","rejected"],
    "ready_for_agent": ["in_progress"],
    "in_progress":     ["review","blocked","needs_changes"],
    "review":          ["done","needs_changes"],
    "done":            ["needs_changes"],
    "needs_changes":   ["in_progress"],
    "blocked":         ["in_progress","cancelled"]
  }'
}

@test "forward move: ready_for_agent -> in_progress is valid" {
  run "$SCRIPT" ready_for_agent in_progress "$STATUSES_JSON"
  [ "$status" -eq 0 ]
}

@test "backward move: done -> needs_changes is valid" {
  run "$SCRIPT" done needs_changes "$STATUSES_JSON"
  [ "$status" -eq 0 ]
}

@test "backward chain: needs_changes -> in_progress is valid" {
  run "$SCRIPT" needs_changes in_progress "$STATUSES_JSON"
  [ "$status" -eq 0 ]
}

@test "invalid: done -> in_progress is rejected" {
  run "$SCRIPT" done in_progress "$STATUSES_JSON"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid transition"* ]]
}

@test "unknown from-status fails with helpful message" {
  run "$SCRIPT" frobnicate done "$STATUSES_JSON"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown status: frobnicate"* ]]
}

@test "missing args fails with usage" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}
