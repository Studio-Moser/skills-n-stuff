#!/usr/bin/env bats

setup() {
  SCRIPT="${HARNESS_SETUP_RESULT:-${BATS_TEST_DIRNAME}/../scripts/setup-result.py}"
  FIXTURE="$BATS_TEST_TMPDIR/setup-result"
  mkdir -p "$FIXTURE"
  SYNC="$FIXTURE/sync.json"
  RUBRIC="$FIXTURE/rubric.json"
  TOOLS="$FIXTURE/tools.json"
  ADVISAUR="$FIXTURE/advisaur.json"
  printf '%s\n' '{"initial":{"status":"accepted","checks":["sync initial"]},"final":{"status":"accepted","checks":["sync final"]},"files":["agents/config"]}' > "$SYNC"
  printf '%s\n' '{"status":"accepted","current":true,"reconciled":true,"changed":false,"checks":["rubric capabilities reconciled"],"files":["config/studio-moser/model-rubric.yml"]}' > "$RUBRIC"
}

run_setup_result() {
  run "$SCRIPT" \
    --sync-result "$SYNC" \
    --rubric-result "$RUBRIC" \
    --tool-names "$TOOLS" \
    "$@" \
    --model setup-model \
    --effort medium \
    --provider native \
    --executor current-runtime \
    --fixed-target config-snapshot \
    --proof proven
}

assert_complete_result() {
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert list(r) == ["status", "route", "artifacts", "evidence", "blockers"]
assert list(r["route"]) == [
    "requested", "model", "effort", "provider", "executor", "dispatch",
]
assert list(r["artifacts"]) == ["files", "report"]
assert list(r["evidence"]) == ["fixed_target", "checks", "outcome"]
assert r["route"] == {
    "requested": "default", "model": "setup-model", "effort": "medium",
    "provider": "native", "executor": "current-runtime", "dispatch": "direct",
}
PY
}

@test "Advisaur-present fixture contributes checks without adding result fields" {
  printf '%s\n' '["mcp__advisaur_memory__get_brief","mcp__advisaur_memory__log_run"]' > "$TOOLS"
  printf '%s\n' '{"status":"accepted","project_id":"project-id","run_id":"run-id","checkpoint_ids":["checkpoint-id"],"checks":["Advisaur run logged"]}' > "$ADVISAUR"

  run_setup_result --advisaur-result "$ADVISAUR"

  [ "$status" -eq 0 ]
  assert_complete_result
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "accepted"
assert r["evidence"]["outcome"] == "proven"
assert any("Advisaur run logged" in check for check in r["evidence"]["checks"])
assert r["blockers"] == []
PY
}

@test "tool names from an install under the old Shelby name still count" {
  printf '%s\n' '["mcp__shelby_memory__get_brief"]' > "$TOOLS"
  printf '%s\n' '{"status":"failed","error":"unavailable"}' > "$ADVISAUR"
  run_setup_result --advisaur-result "$ADVISAUR"
  [ "$status" -eq 0 ]
  grep -q 'Advisaur enrichment failed' <<<"$output"
}

@test "Advisaur-absent fixture completes without result metadata" {
  printf '%s\n' '["bash","read","edit"]' > "$TOOLS"

  run_setup_result

  [ "$status" -eq 0 ]
  assert_complete_result
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "accepted"
assert r["blockers"] == []
PY
}

@test "Advisaur failure remains non-blocking and cannot add result fields" {
  printf '%s\n' '["mcp__advisaur_memory__get_brief"]' > "$TOOLS"
  printf '%s\n' '{"status":"failed","error":"Advisaur unavailable","project_id":"invented","run_id":"invented","checkpoint_ids":["invented"]}' > "$ADVISAUR"

  run_setup_result --advisaur-result "$ADVISAUR"

  [ "$status" -eq 0 ]
  assert_complete_result
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "accepted"
assert any("Advisaur enrichment failed" in check for check in r["evidence"]["checks"])
assert r["blockers"] == []
PY
}

@test "a current rubric that skipped setup reconciliation blocks acceptance" {
  printf '%s\n' '["bash"]' > "$TOOLS"
  printf '%s\n' '{"status":"accepted","current":true,"reconciled":false,"changed":false,"checks":[],"files":[]}' > "$RUBRIC"

  run_setup_result

  [ "$status" -eq 0 ]
  assert_complete_result
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "blocked"
assert r["evidence"]["outcome"] == "unproven"
assert "rubric capabilities were not reconciled" in r["blockers"]
PY
}

@test "a changed rubric requires the final Sync result" {
  printf '%s\n' '["bash"]' > "$TOOLS"
  printf '%s\n' '{"status":"accepted","current":true,"reconciled":true,"changed":true,"checks":["rubric changed"],"files":[]}' > "$RUBRIC"
  printf '%s\n' '{"initial":{"status":"accepted","checks":["sync initial"]},"final":{"status":"failed","checks":["push rejected"]},"files":[]}' > "$SYNC"

  run_setup_result

  [ "$status" -eq 0 ]
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "blocked"
assert "final Sync did not publish the changed rubric" in r["blockers"]
PY
}
