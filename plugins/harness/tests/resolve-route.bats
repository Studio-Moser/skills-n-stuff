#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/resolve-route.py"
  RUBRIC="${BATS_TEST_TMPDIR}/rubric.yml"
  STATE="${BATS_TEST_TMPDIR}/provider-health.json"
  write_rubric
}

write_rubric() {
  cat > "$RUBRIC" <<'YAML'
models:
  - name: claude-fable-5
    effort: high
    provider: anthropic
    taste: 10
  - name: gpt-5.6-sol
    effort: high
    provider: openai
    via: codex
    taste: 9
routing:
  default: gpt-5.6-sol@high
  taste: claude-fable-5@high
  independent: claude-fable-5@high
  taste_min: 9
fallbacks:
  taste: [gpt-5.6-sol@high]
YAML
}

assert_result() {
  local program="$1"
  RESULT_JSON="$output" python3 - "$program" <<'PY'
import json
import os
import sys

result = json.loads(os.environ["RESULT_JSON"])
assert eval(sys.argv[1], {"result": result}), result
PY
}

assert_state() {
  local program="$1"
  STATE_PATH="$STATE" python3 - "$program" <<'PY'
import json
import os
import sys

with open(os.environ["STATE_PATH"], encoding="utf-8") as handle:
    state = json.load(handle)
assert eval(sys.argv[1], {"state": state}), state
PY
}

@test "matching provider uses native even when the row declares via" {
  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route default --native-provider openai --executors "" \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  assert_result '(
      result["status"], result["resolution"], result["candidate"], result["executor"]
  ) == ("resolved", "primary", "gpt-5.6-sol@high", "native")'
}

@test "native mismatch selects the ordered cross-provider fallback" {
  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider openai --executors codex \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  assert_result '(
      result["status"], result["candidate"], result["provider"],
      result["executor"], result["reason"]
  ) == ("fallback", "gpt-5.6-sol@high", "openai", "native", "missing_executor")'
}

@test "callable non-native via executor resolves selection" {
  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route default --native-provider anthropic --executors codex \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  assert_result '(
      result["status"], result["candidate"], result["provider"], result["executor"]
  ) == ("resolved", "gpt-5.6-sol@high", "openai", "codex")'
}

@test "validate recognizes a callable non-native via executor" {
  run "$SCRIPT" validate --rubric "$RUBRIC" \
    --native-provider anthropic --executors codex
  [ "$status" -eq 0 ]
  assert_result 'result == {"status": "valid"}'
}

@test "taste fallback below the configured minimum blocks selection" {
  sed -i '' 's/taste: 9/taste: 8/' "$RUBRIC"

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider openai --executors codex \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "taste" in result["blockers"][0]'
}

@test "independent route rejects every supplied authoring provider" {
  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route independent --native-provider anthropic --executors codex \
    --authoring-providers anthropic --now 2026-08-25T12:00:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "authoring provider" in result["blockers"][0]'
}

@test "validate rejects a chain that repeats its primary provider" {
  sed -i '' 's/gpt-5.6-sol@high]/claude-fable-5@high]/' "$RUBRIC"

  run "$SCRIPT" validate --rubric "$RUBRIC" \
    --native-provider anthropic --executors codex
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "duplicate provider" in result["blockers"][0]'
}

@test "malformed fallback chains block instead of selecting the primary" {
  sed -i '' 's/taste: \[gpt-5.6-sol@high\]/taste: gpt-5.6-sol@high/' "$RUBRIC"

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route default --native-provider openai --executors codex \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "fallbacks.taste" in result["blockers"][0]'
}

@test "unresolved fallback rows block validation" {
  sed -i '' 's/gpt-5.6-sol@high]/missing-model@high]/' "$RUBRIC"

  run "$SCRIPT" validate --rubric "$RUBRIC" \
    --native-provider openai --executors codex
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "missing-model@high" in result["blockers"][0]'
}

@test "exhausted candidates block without retrying an attempted provider" {
  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route default --native-provider openai --executors codex \
    --attempted gpt-5.6-sol@high --now 2026-08-25T12:00:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and result["attempted"] == ["gpt-5.6-sol@high"]'
}

@test "legacy routing fallback never authorizes automatic selection" {
  sed -i '' '/fallbacks:/,$d' "$RUBRIC"
  cat >> "$RUBRIC" <<'YAML'
  fallback: gpt-5.6-sol@high
YAML

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider openai --executors "" \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and result["attempted"] == []'
}

@test "single-provider rubric without fallbacks validates" {
  cat > "$RUBRIC" <<'YAML'
models:
  - name: gpt-5.6-sol
    effort: high
    provider: openai
    via: codex
    taste: 9
routing:
  default: gpt-5.6-sol@high
YAML

  run "$SCRIPT" validate --rubric "$RUBRIC" \
    --native-provider openai --executors ""
  [ "$status" -eq 0 ]
  assert_result 'result == {"status": "valid"}'
}

@test "malformed attempted candidates are argument errors before rubric loading" {
  run "$SCRIPT" select --rubric "${BATS_TEST_TMPDIR}/missing.yml" \
    --route default --native-provider openai --executors "" --attempted invalid
  [ "$status" -eq 2 ]
  assert_result 'result["status"] == "error" and "invalid model-effort" in result["blockers"][0]'
}

@test "quota defaults to 24 hours, skips selection, and success clears the endpoint" {
  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason quota \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  [[ "$output" == *'"unavailable_until":"2026-08-26T12:00:00Z"'* ]] || return 1

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider anthropic --executors codex \
    --now 2026-08-25T12:01:00Z
  [ "$status" -eq 0 ]
  assert_result '(
      result["resolution"], result["candidate"], result["reason"]
  ) == ("fallback", "gpt-5.6-sol@high", "quota")'

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider anthropic --executors codex \
    --attempted claude-fable-5@high --now 2026-08-25T12:02:00Z
  [ "$status" -eq 0 ]
  assert_result 'result["resolution"] == "fallback" and result["reason"] == "quota"'

  run "$SCRIPT" record-success --state "$STATE" \
    --provider anthropic --executor native --now 2026-08-26T12:00:01Z
  [ "$status" -eq 0 ]
  assert_state '"anthropic|native" not in state["circuits"]'
}

@test "quota uses a supplied future reset timestamp" {
  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason quota \
    --retry-at 2026-08-25T18:30:00Z --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  assert_result 'result["unavailable_until"] == "2026-08-25T18:30:00Z"'
  assert_state 'state["circuits"]["anthropic|native"]["unavailable_until"] == "2026-08-25T18:30:00Z"'
}

@test "authentication defaults to a 24 hour cooldown" {
  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason authentication \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  assert_result 'result["unavailable_until"] == "2026-08-26T12:00:00Z"'
}

@test "rate limit and outage cooldowns advance and cap at 24 hours" {
  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason rate_limit \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  assert_result '(
      result["failure_count"], result["unavailable_until"]
  ) == (1, "2026-08-25T12:15:00Z")'

  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason provider_unavailable \
    --now 2026-08-25T12:01:00Z
  [ "$status" -eq 0 ]
  assert_result '(
      result["failure_count"], result["unavailable_until"]
  ) == (1, "2026-08-25T12:16:00Z")'

  local expected
  for expected in \
    '2|2026-08-25T13:02:00Z|2026-08-25T12:02:00Z' \
    '3|2026-08-25T18:03:00Z|2026-08-25T12:03:00Z' \
    '4|2026-08-26T12:04:00Z|2026-08-25T12:04:00Z' \
    '5|2026-08-26T12:05:00Z|2026-08-25T12:05:00Z'
  do
    IFS='|' read -r count unavailable now <<< "$expected"
    run "$SCRIPT" record-failure --state "$STATE" \
      --provider anthropic --executor native --reason provider_unavailable \
      --now "$now"
    [ "$status" -eq 0 ]
    RESULT_JSON="$output" EXPECTED_COUNT="$count" EXPECTED_UNAVAILABLE="$unavailable" python3 - <<'PY'
import json
import os

result = json.loads(os.environ["RESULT_JSON"])
assert result["failure_count"] == int(os.environ["EXPECTED_COUNT"]), result
assert result["unavailable_until"] == os.environ["EXPECTED_UNAVAILABLE"], result
PY
  done
}

@test "exactly one concurrent selector claims an expired probe" {
  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason rate_limit \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]

  export SCRIPT RUBRIC STATE
  run bash -c '
    "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
      --route taste --native-provider anthropic --executors codex \
      --now 2026-08-25T12:15:00Z > "${STATE}.one" &
    first=$!
    "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
      --route taste --native-provider anthropic --executors codex \
      --now 2026-08-25T12:15:00Z > "${STATE}.two" &
    second=$!
    wait "$first" && wait "$second"
  '
  [ "$status" -eq 0 ]

  STATE_PATH="$STATE" python3 - <<'PY'
import json
import os

path = os.environ["STATE_PATH"]
with open(f"{path}.one", encoding="utf-8") as handle:
    first = json.load(handle)
with open(f"{path}.two", encoding="utf-8") as handle:
    second = json.load(handle)
results = [first, second]
probes = [result for result in results if result.get("probe") is True]
fallbacks = [result for result in results if result["resolution"] == "fallback"]
assert len(probes) == 1, results
assert probes[0]["candidate"] == "claude-fable-5@high", results
assert len(fallbacks) == 1 and fallbacks[0]["reason"] == "rate_limit", results
PY
}

@test "probe lease can only be reclaimed after 15 minutes" {
  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason rate_limit \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider anthropic --executors codex \
    --now 2026-08-25T12:15:00Z
  [ "$status" -eq 0 ]
  assert_result 'result["candidate"] == "claude-fable-5@high" and result["probe"] is True'

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider anthropic --executors codex \
    --now 2026-08-25T12:29:59Z
  [ "$status" -eq 0 ]
  assert_result 'result["resolution"] == "fallback" and result["reason"] == "rate_limit"'

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider anthropic --executors codex \
    --now 2026-08-25T12:30:00Z
  [ "$status" -eq 0 ]
  assert_result 'result["candidate"] == "claude-fable-5@high" and result["probe"] is True'
}

@test "circuit state is written with mode 0600" {
  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason quota \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]

  STATE_PATH="$STATE" python3 - <<'PY'
import os
import stat

mode = stat.S_IMODE(os.stat(os.environ["STATE_PATH"]).st_mode)
assert mode == 0o600, oct(mode)
PY
}

@test "default state path is lazy until circuit state is needed" {
  local state_root="${BATS_TEST_TMPDIR}/xdg-state"

  run env XDG_STATE_HOME="$state_root" "$SCRIPT" select --rubric "$RUBRIC" \
    --route default --native-provider openai --executors codex \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  [ ! -e "$state_root" ]

  run env XDG_STATE_HOME="$state_root" "$SCRIPT" record-failure \
    --provider anthropic --executor native --reason quota \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 0 ]
  [ -e "$state_root/studio-moser/harness/provider-health.json" ]
}

@test "empty XDG state home falls back to HOME without repo-local state" {
  local temporary_home="${BATS_TEST_TMPDIR}/home"
  local working_directory="${BATS_TEST_TMPDIR}/working"
  mkdir -p "$temporary_home" "$working_directory"
  export SCRIPT RUBRIC temporary_home working_directory

  run bash -c '
    cd "$working_directory"
    XDG_STATE_HOME="" HOME="$temporary_home" "$SCRIPT" select \
      --rubric "$RUBRIC" --route default --native-provider openai \
      --executors codex --now 2026-08-25T12:00:00Z
  '
  [ "$status" -eq 0 ]
  [ ! -e "$temporary_home/.local/state" ]
  [ ! -e "$working_directory/studio-moser" ]

  run bash -c '
    cd "$working_directory"
    XDG_STATE_HOME="" HOME="$temporary_home" "$SCRIPT" record-failure \
      --provider anthropic --executor native --reason quota \
      --now 2026-08-25T12:00:00Z
  '
  [ "$status" -eq 0 ]
  [ -e "$temporary_home/.local/state/studio-moser/harness/provider-health.json" ]
  [ ! -e "$working_directory/studio-moser" ]
}

@test "malformed state blocks selection and recording without overwrite" {
  cat > "$STATE" <<'JSON'
{"version":1,"circuits":[]}
JSON
  cp "$STATE" "${STATE}.original"

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider anthropic --executors codex \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "state" in result["blockers"][0]'
  cmp "$STATE" "${STATE}.original"

  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason quota \
    --now 2026-08-25T12:00:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "state" in result["blockers"][0]'
  cmp "$STATE" "${STATE}.original"
}

@test "unhashable malformed reason blocks without overwrite" {
  cat > "$STATE" <<'JSON'
{"version":1,"circuits":{"anthropic|native":{"state":"open","reason":[],"failure_count":1,"last_failure_at":"2026-08-25T12:00:00Z","unavailable_until":"2026-08-26T12:00:00Z","probe_claimed_at":null}}}
JSON
  cp "$STATE" "${STATE}.original"

  run "$SCRIPT" select --rubric "$RUBRIC" --state "$STATE" \
    --route taste --native-provider anthropic --executors codex \
    --now 2026-08-25T12:01:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "state" in result["blockers"][0]'
  cmp "$STATE" "${STATE}.original"

  run "$SCRIPT" record-failure --state "$STATE" \
    --provider anthropic --executor native --reason quota \
    --now 2026-08-25T12:01:00Z
  [ "$status" -eq 4 ]
  assert_result 'result["status"] == "blocked" and "state" in result["blockers"][0]'
  cmp "$STATE" "${STATE}.original"
}
