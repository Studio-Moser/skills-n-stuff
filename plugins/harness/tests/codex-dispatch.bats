#!/usr/bin/env bats

setup() {
  SCRIPT="${HARNESS_CODEX_DISPATCH:-${BATS_TEST_DIRNAME}/../scripts/codex-dispatch.sh}"
  DRIVER="${BATS_TEST_DIRNAME}/../scripts/codex-app-server.py"
  FIXTURE="$BATS_TEST_TMPDIR/dispatch"
  mkdir -p "$FIXTURE/cwd" "$FIXTURE/non-git"
  git -C "$FIXTURE/cwd" init -q
  PROMPT="$FIXTURE/prompt.md"
  REPORT="$FIXTURE/report.md"
  CAPTURE="$FIXTURE/protocol.jsonl"
  STUB="${BATS_TEST_DIRNAME}/fixtures/codex-app-server-stub.py"
  printf '%s\n' 'bounded request' > "$PROMPT"
  chmod +x "$STUB"
  export HARNESS_CODEX_BIN="$STUB"
  export HARNESS_CODEX_CAPTURE="$CAPTURE"
  export HARNESS_CODEX_STUB_MODE=success
}

run_dispatch() {
  run "$SCRIPT" \
    --operation execute \
    --cwd "$FIXTURE/cwd" \
    --sandbox workspace-write \
    --approval never \
    --model gpt-test \
    --effort high \
    --prompt "$PROMPT" \
    --report "$REPORT" \
    "$@"
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

@test "App Server preflight requires the typed terminal error seam" {
  run "$DRIVER" check --codex-bin "$STUB"
  [ "$status" -eq 0 ]
  assert_result 'result == {"status": "available"}'

  export HARNESS_CODEX_STUB_MODE=incompatible
  run "$DRIVER" check --codex-bin "$STUB"
  [ "$status" -eq 69 ]
  assert_result 'result == {"status": "missing_executor"}'

  export HARNESS_CODEX_STUB_MODE=stdio_incompatible
  run "$DRIVER" check --codex-bin "$STUB"
  [ "$status" -eq 69 ]
  assert_result 'result == {"status": "missing_executor"}'
  [[ "$output" != *"RAW_SECRET_MARKER"* ]] || return 1
}

@test "execute preserves cwd model effort approval and turn-scoped sandbox" {
  run_dispatch

  [ "$status" -eq 0 ]
  assert_result 'result == {"status": "succeeded"}'
  [ "$(cat "$REPORT")" = "stub final report" ]
  CAPTURE_PATH="$CAPTURE" EXPECTED_CWD="$FIXTURE/cwd" python3 - <<'PY'
import json
import os

messages = [json.loads(line) for line in open(os.environ["CAPTURE_PATH"], encoding="utf-8")]
thread = next(message["params"] for message in messages if message.get("method") == "thread/start")
turn = next(message["params"] for message in messages if message.get("method") == "turn/start")
assert thread["ephemeral"] is True
assert thread["cwd"] == os.environ["EXPECTED_CWD"]
assert thread["model"] == "gpt-test"
assert thread["approvalPolicy"] == "never"
assert thread["sandbox"] == "read-only"
assert turn["cwd"] == os.environ["EXPECTED_CWD"]
assert turn["model"] == "gpt-test"
assert turn["effort"] == "high"
assert turn["approvalPolicy"] == "never"
assert turn["sandboxPolicy"]["type"] == "workspaceWrite"
PY
}

@test "computer-use preserves an explicitly authorized full-machine sandbox" {
  run "$SCRIPT" \
    --operation computer-use \
    --cwd "$FIXTURE/non-git" \
    --sandbox danger-full-access \
    --approval never \
    --model gpt-ui \
    --effort medium \
    --prompt "$PROMPT" \
    --report "$REPORT" \
    --skip-git-repo-check

  [ "$status" -eq 0 ]
  CAPTURE_PATH="$CAPTURE" python3 - <<'PY'
import json
import os

messages = [json.loads(line) for line in open(os.environ["CAPTURE_PATH"], encoding="utf-8")]
turn = next(message["params"] for message in messages if message.get("method") == "turn/start")
assert turn["sandboxPolicy"] == {"type": "dangerFullAccess"}
PY
}

@test "review binds the immutable target into a read-only turn" {
  local target=1111111111111111111111111111111111111111
  run "$SCRIPT" \
    --operation review \
    --cwd "$FIXTURE/cwd" \
    --sandbox read-only \
    --approval never \
    --model gpt-review \
    --effort max \
    --prompt "$PROMPT" \
    --report "$REPORT" \
    --fixed-target "$target"

  [ "$status" -eq 0 ]
  CAPTURE_PATH="$CAPTURE" EXPECTED_TARGET="$target" python3 - <<'PY'
import json
import os

messages = [json.loads(line) for line in open(os.environ["CAPTURE_PATH"], encoding="utf-8")]
turn = next(message["params"] for message in messages if message.get("method") == "turn/start")
text = turn["input"][0]["text"]
assert turn["sandboxPolicy"]["type"] == "readOnly"
assert os.environ["EXPECTED_TARGET"] in text
assert "immutable fixed target" in text
assert text.endswith("bounded request\n")
PY
}

@test "structured terminal metadata maps exactly to four availability reasons" {
  local case
  for case in \
    'quota|quota' \
    'authentication|authentication' \
    'rate_limit|rate_limit' \
    'provider_unavailable|provider_unavailable' \
    'http_401|authentication' \
    'http_403|authentication' \
    'http_500|provider_unavailable' \
    'connection|provider_unavailable'
  do
    IFS='|' read -r mode reason <<< "$case"
    export HARNESS_CODEX_STUB_MODE="$mode"
    run_dispatch
    [ "$status" -eq 75 ]
    RESULT_JSON="$output" EXPECTED_REASON="$reason" python3 - <<'PY'
import json
import os

assert json.loads(os.environ["RESULT_JSON"]) == {
    "status": "availability_failure",
    "reason": os.environ["EXPECTED_REASON"],
}
PY
    [[ "$output" != *"RAW_SECRET_MARKER"* ]] || return 1
  done
}

@test "untyped malformed policy task and generic failures never become availability" {
  local mode
  for mode in untyped malformed non_availability_http bad_request process_failure malformed_protocol; do
    export HARNESS_CODEX_STUB_MODE="$mode"
    run_dispatch
    [ "$status" -eq 1 ]
    assert_result 'result == {"status": "failed"}'
    [[ "$output" != *"RAW_SECRET_MARKER"* ]] || return 1
    if [ -e "$REPORT" ]; then
      [[ "$(cat "$REPORT")" != *"RAW_SECRET_MARKER"* ]] || return 1
    fi
  done
}

@test "missing or incompatible App Server is a bounded preflight result" {
  export HARNESS_CODEX_BIN="$FIXTURE/missing-codex"
  run_dispatch
  [ "$status" -eq 69 ]
  assert_result 'result == {"status": "missing_executor"}'
  [ ! -e "$CAPTURE" ]

  export HARNESS_CODEX_BIN="$STUB"
  export HARNESS_CODEX_STUB_MODE=incompatible
  run_dispatch
  [ "$status" -eq 69 ]
  assert_result 'result == {"status": "missing_executor"}'
  [ ! -e "$CAPTURE" ]
}

@test "skip-git-repo-check is required for a non-repository working directory" {
  run_dispatch --cwd "$FIXTURE/non-git"
  [ "$status" -eq 1 ]
  assert_result 'result == {"status": "failed"}'
  CAPTURE_PATH="$CAPTURE" python3 - <<'PY'
import json
import os

messages = [json.loads(line) for line in open(os.environ["CAPTURE_PATH"], encoding="utf-8")]
assert any(message.get("method") == "initialize" for message in messages)
assert not any(message.get("method") == "thread/start" for message in messages)
PY

  run_dispatch --cwd "$FIXTURE/non-git" --skip-git-repo-check
  [ "$status" -eq 0 ]
  assert_result 'result == {"status": "succeeded"}'
}

@test "outstanding approval is blocked before App Server starts" {
  run_dispatch --approval on-request
  [ "$status" -eq 4 ]
  assert_result 'result == {"status": "failed"}'
  [ ! -e "$CAPTURE" ]
}

@test "review rejects a write-capable sandbox before App Server starts" {
  run "$SCRIPT" \
    --operation review \
    --cwd "$FIXTURE/cwd" \
    --sandbox workspace-write \
    --approval never \
    --model gpt-review \
    --effort high \
    --prompt "$PROMPT" \
    --report "$REPORT" \
    --fixed-target 2222222222222222222222222222222222222222

  [ "$status" -eq 4 ]
  assert_result 'result == {"status": "failed"}'
  [ ! -e "$CAPTURE" ]
}

@test "execute rejects a full-machine sandbox before App Server starts" {
  run_dispatch --sandbox danger-full-access
  [ "$status" -eq 4 ]
  assert_result 'result == {"status": "failed"}'
  [ ! -e "$CAPTURE" ]
}
