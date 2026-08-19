#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/rubric-audit.sh"
  PROJ="${BATS_TEST_TMPDIR}/projects/-Users-me-proj"
  mkdir -p "$PROJ/abc123/subagents"
}

# One transcript line: an assistant message carrying one tool_use block.
tool_use_line() { # name json-input
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"%s","input":%s}]}}\n' "$1" "$2"
}

write_fixture() {
  {
    printf '{"type":"queue-operation","operation":"x"}\n'
    printf '{"type":"user","message":{"role":"user","content":"hi"}}\n'
    tool_use_line Agent '{"subagent_type":"general-purpose","model":"sonnet","prompt":"p"}'
    tool_use_line Agent '{"subagent_type":"general-purpose","model":"fable","prompt":"p"}'
    tool_use_line Task  '{"subagent_type":"Explore","model":"opus","prompt":"p"}'
    tool_use_line Bash  '{"command":"codex exec -C /x -s workspace-write - < p.md > r.md"}'
    tool_use_line Bash  '{"command":"echo not-a-codex-call"}'
    tool_use_line Skill '{"skill":"pm:codex-review","args":""}'
    tool_use_line Skill '{"skill":"superpowers:brainstorming"}'
  } > "$PROJ/abc123.jsonl"
  # A sub-agent transcript that must NOT be counted as a dispatch.
  tool_use_line Agent '{"model":"haiku","prompt":"nested"}' > "$PROJ/abc123/subagents/agent-1.jsonl"
}

@test "clean fixture: totals, by-model line, handoffs, exit 0" {
  write_fixture
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 session(s)"* ]] || return 1
  echo "$output" | grep -qE 'Agent dispatches: +3 total — model set: 3, UNSET: 0'
  echo "$output" | grep -qE 'by model: +fable 1 · opus 1 · sonnet 1 · haiku 0'
  echo "$output" | grep -qE 'Codex handoffs: +2 \(codex exec/review Bash calls: 1, pm:codex-\* skills: 1\)'
}

@test "sub-agent transcripts are excluded from dispatch counts" {
  write_fixture
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'by model: +fable 1 · opus 1 · sonnet 1 · haiku 0'
  [[ "$output" != *"haiku 1"* ]]
}

@test "an UNSET model is counted and exits 1" {
  write_fixture
  tool_use_line Agent '{"subagent_type":"general-purpose","prompt":"no model"}' >> "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'Agent dispatches: +4 total — model set: 3, UNSET: 1'
}

@test "a haiku dispatch exits 1" {
  write_fixture
  tool_use_line Agent '{"model":"haiku","prompt":"p"}' >> "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'haiku 1'
}

@test "files older than --days are ignored" {
  write_fixture
  touch -t 202001010000 "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects" --days 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 session(s)"* ]] || return 1
  echo "$output" | grep -qE 'Agent dispatches: +0 total'
}

@test "missing projects dir reports 0 sessions, exit 0" {
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/nope"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 session(s)"* ]]
}
