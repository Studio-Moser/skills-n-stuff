#!/usr/bin/env bats

setup() {
  SCRIPTS="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  STATE="$XDG_STATE_HOME/studio-moser/harness/telemetry"
  mkdir -p "$HOME"
  RESULT='{"status":"blocked","route":{"requested":"bulk","model":"m","effort":"low","provider":"openai","executor":"codex","dispatch":"delegated"},"artifacts":{"files":[],"report":""},"evidence":{"fixed_target":"","checks":["a","b"],"outcome":"unproven"},"blockers":["missing executor at /Users/someone/.codex"]}'
}

@test "record-result appends one typed, redacted line per terminal result" {
  run "$SCRIPTS/telemetry.py" record-result --result "$RESULT" --attempted '[{"candidate":"gpt@low","reason":"quota"}]' --operation execute --consumer pm:dev-task
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "recorded"'* ]] || return 1
  run python3 - "$STATE" <<'PY'
import json, pathlib, sys
files = list(pathlib.Path(sys.argv[1]).glob("Results-*.jsonl"))
assert len(files) == 1, files
lines = files[0].read_text().splitlines()
assert len(lines) == 1, lines
record = json.loads(lines[0])
assert record["status"] == "blocked" and record["outcome"] == "unproven"
assert record["route"]["executor"] == "codex" and record["checks"] == 2
assert record["operation"] == "execute" and record["consumer"] == "pm:dev-task"
assert record["attempted"] == [{"candidate": "gpt@low", "reason": "quota"}]
assert record["blockers"] == ["missing executor at ~/.codex"], record["blockers"]
assert {"id", "ts", "host"} <= set(record)
assert "/Users/" not in lines[0]
PY
  [ "$status" -eq 0 ]
}

@test "record-result rejects a result missing contract fields and writes nothing" {
  run "$SCRIPTS/telemetry.py" record-result --result '{"status":"done","route":{}}'
  [ "$status" -eq 2 ]
  [[ "$output" == *'"status": "invalid"'* ]] || return 1
  [ ! -e "$STATE" ] || [ -z "$(ls -A "$STATE")" ]
}

@test "publish merges by id, is idempotent, and never drops published history" {
  repo="$BATS_TEST_TMPDIR/agents"
  mkdir -p "$repo"
  "$SCRIPTS/telemetry.py" record-result --result "$RESULT" >/dev/null
  "$SCRIPTS/telemetry.py" record-result --result "$RESULT" >/dev/null
  run "$SCRIPTS/telemetry.py" publish --repo "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"added": 2'* ]] || return 1
  run "$SCRIPTS/telemetry.py" publish --repo "$repo"
  [[ "$output" == *'"added": 0'* ]] || return 1

  # A reinstalled machine with the same host name starts with empty local state.
  rm -rf "$STATE"
  "$SCRIPTS/telemetry.py" record-result --result "$RESULT" >/dev/null
  run "$SCRIPTS/telemetry.py" publish --repo "$repo"
  [[ "$output" == *'"added": 1'* ]] || return 1
  [ "$(cat "$repo"/telemetry/*/Results-*.jsonl | wc -l | tr -d ' ')" -eq 3 ]
}
