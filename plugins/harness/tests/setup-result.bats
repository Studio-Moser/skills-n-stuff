#!/usr/bin/env bats

setup() {
  SCRIPT="${HARNESS_SETUP_RESULT:-${BATS_TEST_DIRNAME}/../scripts/setup-result.py}"
  FIXTURE="$BATS_TEST_TMPDIR/setup-result"
  mkdir -p "$FIXTURE"
  SYNC="$FIXTURE/sync.json"
  RUBRIC="$FIXTURE/rubric.json"
  TOOLS="$FIXTURE/tools.json"
  SHELBY="$FIXTURE/shelby.json"
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
assert list(r) == ["status", "route", "artifacts", "evidence", "telemetry", "shelby", "blockers"]
assert list(r["route"]) == [
    "requested", "actual_model", "effort", "provider", "executor",
    "resolution", "attempted", "fallback_reason",
]
assert list(r["artifacts"]) == ["files", "report"]
assert list(r["evidence"]) == ["fixed_target", "checks", "outcome"]
assert list(r["telemetry"]) == ["attempts", "elapsed", "verification_failures", "token_or_quota_usage"]
assert list(r["shelby"]) == ["project_id", "run_id", "checkpoint_ids"]
assert r["route"] == {
    "requested": "default", "actual_model": "setup-model", "effort": "medium",
    "provider": "native", "executor": "current-runtime",
    "resolution": "primary", "attempted": ["setup-model@medium"],
    "fallback_reason": None,
}
PY
}

@test "Shelby-present fixture returns successful Shelby identifiers in a complete result" {
  printf '%s\n' '["mcp__shelby_memory__get_brief","mcp__shelby_memory__log_run"]' > "$TOOLS"
  printf '%s\n' '{"status":"accepted","project_id":"project-id","run_id":"run-id","checkpoint_ids":["checkpoint-id"],"checks":["Shelby run logged"]}' > "$SHELBY"

  run_setup_result --shelby-result "$SHELBY"

  [ "$status" -eq 0 ]
  assert_complete_result
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "accepted"
assert r["evidence"]["outcome"] == "proven"
assert r["shelby"] == {"project_id":"project-id", "run_id":"run-id", "checkpoint_ids":["checkpoint-id"]}
assert r["blockers"] == []
PY
}

@test "Shelby-absent fixture completes with empty optional identifiers" {
  printf '%s\n' '["bash","read","edit"]' > "$TOOLS"

  run_setup_result

  [ "$status" -eq 0 ]
  assert_complete_result
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "accepted"
assert r["shelby"] == {"project_id":None, "run_id":None, "checkpoint_ids":[]}
assert r["blockers"] == []
PY
}

@test "Shelby failure remains non-blocking and cannot invent identifiers" {
  printf '%s\n' '["mcp__shelby_memory__get_brief"]' > "$TOOLS"
  printf '%s\n' '{"status":"failed","error":"Shelby unavailable","project_id":"invented","run_id":"invented","checkpoint_ids":["invented"]}' > "$SHELBY"

  run_setup_result --shelby-result "$SHELBY"

  [ "$status" -eq 0 ]
  assert_complete_result
  RESULT_JSON="$output" python3 - <<'PY'
import json, os
r = json.loads(os.environ["RESULT_JSON"])
assert r["status"] == "accepted"
assert r["shelby"] == {"project_id":None, "run_id":None, "checkpoint_ids":[]}
assert any("Shelby enrichment failed" in check for check in r["evidence"]["checks"])
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
