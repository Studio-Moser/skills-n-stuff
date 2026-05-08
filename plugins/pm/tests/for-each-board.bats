#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/for-each-board.sh"
  ONE_BOARD='[{"id":"B1","name":"App","lists":{"needs_triage":"NT","ready_for_agent":"R","in_progress":"IP","review":"RV","done":"D","needs_changes":"NC","blocked":"BL"},"approval_steps":[],"review_policy":"self","worker_instructions":""}]'
  TWO_BOARDS='[{"id":"B1","name":"App","lists":{"needs_triage":"NT","ready_for_agent":"R","in_progress":"IP","review":"RV","done":"D","needs_changes":"NC","blocked":"BL"},"approval_steps":[],"review_policy":"self","worker_instructions":""},{"id":"B2","name":"Web","lists":{"needs_triage":"NT2","ready_for_agent":"R2","in_progress":"IP2","review":"RV2","done":"D2","needs_changes":"NC2","blocked":"BL2"},"approval_steps":["lead"],"review_policy":"judge","worker_instructions":"Be careful"}]'
}

@test "single board emits one block with seven LIST_ keys" {
  run "$SCRIPT" "$ONE_BOARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"BOARD_ID=B1"* ]]
  [[ "$output" == *"BOARD_NAME=App"* ]]
  [[ "$output" == *"LIST_NEEDS_TRIAGE=NT"* ]]
  [[ "$output" == *"LIST_READY_FOR_AGENT=R"* ]]
  [[ "$output" == *"LIST_IN_PROGRESS=IP"* ]]
  [[ "$output" == *"LIST_REVIEW=RV"* ]]
  [[ "$output" == *"LIST_DONE=D"* ]]
  [[ "$output" == *"LIST_NEEDS_CHANGES=NC"* ]]
  [[ "$output" == *"LIST_BLOCKED=BL"* ]]
  [[ "$output" == *"REVIEW_POLICY=self"* ]]
}

@test "two boards emit two blocks separated by ---" {
  run "$SCRIPT" "$TWO_BOARDS"
  [ "$status" -eq 0 ]
  blocks="$(echo "$output" | grep -c '^---$')"
  [ "$blocks" -eq 1 ]   # one separator between two blocks
  [[ "$output" == *"BOARD_ID=B1"* ]]
  [[ "$output" == *"BOARD_ID=B2"* ]]
  [[ "$output" == *"REVIEW_POLICY=judge"* ]]
}

@test "empty array exits 0 with no output" {
  run "$SCRIPT" "[]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
