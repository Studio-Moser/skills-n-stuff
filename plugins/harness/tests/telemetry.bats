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

@test "record-review appends one typed line per reviewer and defaults missing counts to zero" {
  run "$SCRIPTS/telemetry.py" record-review --consumer pm:dev-task --target '#504 at /Users/someone/x' --model astra --provider openai --round 1 --limit 2 --findings '{"fixed":2,"unique":1}' --diff-lines 40
  [ "$status" -eq 0 ]
  [[ "$output" == *'"status": "recorded"'* ]] || return 1
  run python3 - "$STATE" <<'PY'
import json, pathlib, sys
files = list(pathlib.Path(sys.argv[1]).glob("Review_Rounds-*.jsonl"))
assert len(files) == 1, files
record = json.loads(files[0].read_text())
assert record["round"] == 1 and record["limit"] == 2 and record["extension_approved"] is False
assert record["findings"] == {"fixed": 2, "disputed": 0, "declined": 0, "open": 0, "unique": 1, "regraded": 0}
assert record["diff_lines"] == 40 and record["model"] == "astra" and record["provider"] == "openai"
assert record["target"] == "#504 at ~/x", record["target"]
assert not list(pathlib.Path(sys.argv[1]).glob("Results-*.jsonl")), "review rounds must not touch Results"
PY
  [ "$status" -eq 0 ]
}

@test "record-review rejects prose, bad counts, and combined reviewers and writes nothing" {
  base=(--consumer c --target t --provider p --limit 2)
  for bad in '{"notes":1}' '{"fixed":-1}' '{"fixed":true}' '{"fixed":"2"}' '[1]' 'nope'; do
    run "$SCRIPTS/telemetry.py" record-review "${base[@]}" --model m --round 0 --diff-lines 1 --findings "$bad"
    [ "$status" -eq 2 ] || { echo "accepted findings: $bad"; return 1; }
  done
  run "$SCRIPTS/telemetry.py" record-review "${base[@]}" --model 'a+b' --round 0 --diff-lines 1 --findings '{}'
  [ "$status" -eq 2 ]
  run "$SCRIPTS/telemetry.py" record-review "${base[@]}" --model m --round -1 --diff-lines 1 --findings '{}'
  [ "$status" -eq 2 ]
  run "$SCRIPTS/telemetry.py" record-review "${base[@]}" --model m --round 0 --diff-lines -1 --findings '{}'
  [ "$status" -eq 2 ]
  run "$SCRIPTS/telemetry.py" record-review --consumer c --target ' ' --provider p --limit 2 --model m --round 0 --diff-lines 1 --findings '{}'
  [ "$status" -eq 2 ]
  [ ! -e "$STATE" ] || [ -z "$(ls -A "$STATE")" ]
}

@test "record-result rejects a combined model or provider and writes nothing" {
  combined="${RESULT/\"model\":\"m\"/\"model\":\"a+b\"}"
  run "$SCRIPTS/telemetry.py" record-result --result "$combined"
  [ "$status" -eq 2 ]
  combined="${RESULT/\"provider\":\"openai\"/\"provider\":\"anthropic+openai\"}"
  run "$SCRIPTS/telemetry.py" record-result --result "$combined"
  [ "$status" -eq 2 ]
  [ ! -e "$STATE" ] || [ -z "$(ls -A "$STATE")" ]
}

@test "publish carries review rounds to the agents repository" {
  repo="$BATS_TEST_TMPDIR/agents"
  mkdir -p "$repo"
  "$SCRIPTS/telemetry.py" record-review --consumer c --target t --model m --provider p --round 0 --limit 2 --findings '{}' --diff-lines 1 >/dev/null
  run "$SCRIPTS/telemetry.py" publish --repo "$repo"
  [[ "$output" == *'"added": 1'* ]] || return 1
  ls "$repo"/telemetry/*/Review_Rounds-*.jsonl
}
