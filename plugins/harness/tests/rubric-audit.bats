#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/rubric-audit.sh"
  PROJ="${BATS_TEST_TMPDIR}/projects/-Users-me-proj"
  mkdir -p "$PROJ/abc123/subagents"
  # Keep the real ~/.codex out of every test; Codex tests write fixtures here.
  export CODEX_HOME="${BATS_TEST_TMPDIR}/codex"
  CODEX_DIR="$CODEX_HOME/sessions/2026/09/23"
  mkdir -p "$CODEX_DIR"
}

# One Codex rollout line. kind payload-json
codex_line() {
  printf '{"timestamp":"%s","type":"%s","payload":%s}\n' "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)" "$1" "$2"
}

spawn_line() { # arguments-json
  local args
  args="$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')"
  codex_line response_item "{\"type\":\"function_call\",\"name\":\"spawn_agent\",\"arguments\":$args}"
}

write_codex_fixture() {
  {
    codex_line session_meta '{"id":"c1","source":"vscode"}'
    codex_line turn_context '{"model":"gpt-6-astra"}'
    spawn_line '{"task_name":"a","model":"gpt-5.6-sol","reasoning_effort":"high"}'
    spawn_line '{"task_name":"b","model":"gpt-5.6-terra","reasoning_effort":"high"}'
    spawn_line '{"task_name":"c","message":"no model"}'
    codex_line response_item '{"type":"function_call","name":"exec_command","arguments":"{}"}'
  } > "$CODEX_DIR/rollout-c1.jsonl"
  {
    codex_line session_meta '{"id":"c2","source":{"subagent":{"thread_spawn":{"depth":1}}}}'
    spawn_line '{"task_name":"nested","model":"gpt-5.6-luna"}'
  } > "$CODEX_DIR/rollout-c2.jsonl"
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
    tool_use_line Bash  '{"command":"\"$h/scripts/codex-dispatch.sh\" --operation review --model m"}'
    tool_use_line Bash  '{"command":"grep -n codex-dispatch.sh README.md"}'
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
  echo "$output" | grep -qE 'Codex handoffs: +3 \(codex exec/review Bash calls: 1, codex-dispatch.sh: 1, pm:codex-\* skills: 1\)'
  echo "$output" | grep -qE 'spawn_agent: +0 total'
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

@test "a transcript duplicated across project dirs is counted once" {
  write_fixture
  OTHER="${BATS_TEST_TMPDIR}/projects/-Users-me-moved-proj"
  mkdir -p "$OTHER"
  cp "$PROJ/abc123.jsonl" "$OTHER/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 session(s)"* ]] || return 1
  echo "$output" | grep -qE 'Agent dispatches: +3 total'
}

@test "entries with a timestamp older than --days are ignored even in a fresh file" {
  write_fixture
  printf '{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Agent","input":{"model":"haiku","prompt":"old"}}]}}\n' >> "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects" --days 7
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'haiku 0'
}

@test "a current timestamped entry is counted" {
  write_fixture
  now="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Agent","input":{"model":"opus","prompt":"new"}}]}}\n' "$now" >> "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects" --days 7
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'Agent dispatches: +4 total'
  echo "$output" | grep -qE 'opus 2'
}

@test "when a duplicated session was continued, the larger copy wins" {
  write_fixture
  OTHER="${BATS_TEST_TMPDIR}/projects/-Users-me-moved-proj"
  mkdir -p "$OTHER"
  cp "$PROJ/abc123.jsonl" "$OTHER/abc123.jsonl"
  tool_use_line Agent '{"model":"opus","prompt":"continued here"}' >> "$OTHER/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 session(s)"* ]] || return 1
  echo "$output" | grep -qE 'Agent dispatches: +4 total'
}

@test "a fresh file whose entries are all old is not a session" {
  printf '{"type":"assistant","timestamp":"2020-01-01T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"t","name":"Agent","input":{"model":"haiku","prompt":"old"}}]}}\n' > "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects" --days 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 session(s)"* ]] || return 1
}

@test "an UNSET Claude dispatch names the session model it inherited" {
  write_fixture
  printf '{"type":"assistant","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"tool_use","id":"t","name":"Agent","input":{"prompt":"p"}}]}}\n' >> "$PROJ/abc123.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/projects"
  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'UNSET: 1 \(inherited: claude-opus-5 1\)'
}

@test "Codex spawn_agent calls are tallied by model and effort; sub-agent threads skipped" {
  write_codex_fixture
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/nope"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Codex:             1 session(s)"* ]] || return 1
  echo "$output" | grep -qE 'spawn_agent: +3 total — model set: 2, UNSET: 1 \(inherited: gpt-6-astra 1\)'
  echo "$output" | grep -qE 'by model: +gpt-5.6-sol@high 1 · gpt-5.6-terra@high 1$'
  [[ "$output" != *"luna"* ]]
}

@test "Codex entries older than --days are ignored" {
  {
    codex_line session_meta '{"id":"c3","source":"cli"}'
    printf '{"timestamp":"2020-01-01T00:00:00.000Z","type":"response_item","payload":{"type":"function_call","name":"spawn_agent","arguments":"{}"}}\n'
  } > "$CODEX_DIR/rollout-c3.jsonl"
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/nope" --days 7
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'spawn_agent: +0 total'
}

@test "--codex-sessions overrides CODEX_HOME" {
  write_codex_fixture
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/nope" --codex-sessions "${BATS_TEST_TMPDIR}/elsewhere"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'spawn_agent: +0 total'
}

@test "missing projects dir reports 0 sessions, exit 0" {
  run "$SCRIPT" --projects "${BATS_TEST_TMPDIR}/nope"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 session(s)"* ]]
}
