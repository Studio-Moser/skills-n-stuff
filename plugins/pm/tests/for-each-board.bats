#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/for-each-board.sh"
  # Use multi-word list names matching the canonical fixture (config.yml).
  # This catches shell-quoting bugs that single-token stubs would miss.
  ONE_BOARD='[{"id":"B1","name":"Moby App","lists":{"needs_triage":"Needs Triage","ready_for_agent":"Ready","in_progress":"In Progress","review":"Review","done":"Done","needs_changes":"Needs Changes","blocked":"Blocked"},"approval_steps":["tech_lead"],"review_policy":"self","worker_instructions":"Follow CONTRIBUTING.md and the project ADR style."}]'
  TWO_BOARDS='[{"id":"B1","name":"Moby App","lists":{"needs_triage":"Needs Triage","ready_for_agent":"Ready","in_progress":"In Progress","review":"Review","done":"Done","needs_changes":"Needs Changes","blocked":"Blocked"},"approval_steps":["tech_lead"],"review_policy":"self","worker_instructions":"Follow CONTRIBUTING.md and the project ADR style."},{"id":"B2","name":"Moby Web","lists":{"needs_triage":"Needs Triage","ready_for_agent":"Ready","in_progress":"In Progress","review":"Review","done":"Done","needs_changes":"Needs Changes","blocked":"Blocked"},"approval_steps":["lead"],"review_policy":"judge","worker_instructions":"Be careful with frontend changes"}]'
}

@test "single board emits one block with seven LIST_ keys" {
  run "$SCRIPT" "$ONE_BOARD"
  [ "$status" -eq 0 ]
  # eval the output and assert the variables hold the FULL multi-word values.
  eval "$output"
  [ "$BOARD_ID" = "B1" ]
  [ "$BOARD_NAME" = "Moby App" ]
  [ "$LIST_NEEDS_TRIAGE" = "Needs Triage" ]
  [ "$LIST_READY_FOR_AGENT" = "Ready" ]
  [ "$LIST_IN_PROGRESS" = "In Progress" ]
  [ "$LIST_REVIEW" = "Review" ]
  [ "$LIST_DONE" = "Done" ]
  [ "$LIST_NEEDS_CHANGES" = "Needs Changes" ]
  [ "$LIST_BLOCKED" = "Blocked" ]
  [ "$REVIEW_POLICY" = "self" ]
  [ "$APPROVAL_STEPS" = "tech_lead" ]
  [ "$WORKER_INSTRUCTIONS" = "Follow CONTRIBUTING.md and the project ADR style." ]
}

@test "eval contract: multi-word values survive shell evaluation" {
  # Regression test for the eval-quoting bug. With unquoted output, eval would
  # treat the second word of "Needs Triage" as a command and leave LIST_*
  # empty. This test fails loudly if quoting regresses.
  run "$SCRIPT" "$ONE_BOARD"
  [ "$status" -eq 0 ]
  # No 'command not found' noise on stderr (run merges stderr into output).
  [[ "$output" != *"command not found"* ]]
  # Confirm eval succeeds in a fresh subshell with `set -e` and produces the
  # expected full-string values — matches how SKILL.md call sites consume it.
  result="$(bash -c "set -e; eval \"\$(\"$SCRIPT\" '$ONE_BOARD')\"; echo \"<\$LIST_NEEDS_TRIAGE>|<\$LIST_IN_PROGRESS>|<\$LIST_NEEDS_CHANGES>|<\$WORKER_INSTRUCTIONS>\"" 2>&1)"
  [ "$result" = "<Needs Triage>|<In Progress>|<Needs Changes>|<Follow CONTRIBUTING.md and the project ADR style.>" ]
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

@test "values containing single quotes survive eval" {
  # Defensive: if a list name or worker_instructions ever has a single quote.
  TRICKY='[{"id":"B1","name":"Tim'\''s Board","lists":{"needs_triage":"Needs Triage","ready_for_agent":"Ready","in_progress":"In Progress","review":"Review","done":"Done","needs_changes":"Needs Changes","blocked":"Blocked"},"approval_steps":[],"review_policy":"self","worker_instructions":"Run all the tests"}]'
  run "$SCRIPT" "$TRICKY"
  [ "$status" -eq 0 ]
  eval "$output"
  [ "$BOARD_NAME" = "Tim's Board" ]
  [ "$WORKER_INSTRUCTIONS" = "Run all the tests" ]
}

@test "empty array exits 0 with no output" {
  run "$SCRIPT" "[]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
