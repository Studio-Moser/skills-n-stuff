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
