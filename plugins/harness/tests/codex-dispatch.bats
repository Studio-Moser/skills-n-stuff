#!/usr/bin/env bats

setup() {
  SCRIPT="${HARNESS_CODEX_DISPATCH:-${BATS_TEST_DIRNAME}/../scripts/codex-dispatch.sh}"
  FIXTURE="$BATS_TEST_TMPDIR/dispatch"
  mkdir -p "$FIXTURE/cwd"
  PROMPT="$FIXTURE/prompt.md"
  REPORT="$FIXTURE/report.md"
  CAPTURE="$FIXTURE/argv"
  STUB="$FIXTURE/codex-stub"
  printf '%s\n' 'bounded request' > "$PROMPT"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$@" > "$HARNESS_CODEX_CAPTURE"' \
    'cat >/dev/null' \
    'printf "stub report\\n"' > "$STUB"
  chmod +x "$STUB"
  export HARNESS_CODEX_BIN="$STUB"
  export HARNESS_CODEX_CAPTURE="$CAPTURE"
}

assert_argv() {
  printf '%s\n' "$@" > "$FIXTURE/expected-argv"
  diff -u "$FIXTURE/expected-argv" "$CAPTURE"
}

@test "execute passes the enforceable sandbox and explicit never approval policy" {
  run "$SCRIPT" \
    --operation execute \
    --cwd "$FIXTURE/cwd" \
    --sandbox workspace-write \
    --approval never \
    --model gpt-test \
    --effort high \
    --prompt "$PROMPT" \
    --report "$REPORT"

  [ "$status" -eq 0 ]
  assert_argv \
    -C "$FIXTURE/cwd" \
    -s workspace-write \
    -a never \
    -m gpt-test \
    -c model_reasoning_effort=high \
    exec -
  [ "$(cat "$REPORT")" = "stub report" ]
}

@test "computer-use passes an explicitly authorized full-machine sandbox without bypassing approval" {
  run "$SCRIPT" \
    --operation computer-use \
    --cwd "$FIXTURE/cwd" \
    --sandbox danger-full-access \
    --approval never \
    --model gpt-ui \
    --effort medium \
    --prompt "$PROMPT" \
    --report "$REPORT" \
    --skip-git-repo-check

  [ "$status" -eq 0 ]
  assert_argv \
    -C "$FIXTURE/cwd" \
    -s danger-full-access \
    -a never \
    -m gpt-ui \
    -c model_reasoning_effort=medium \
    exec \
    --skip-git-repo-check \
    -
}

@test "review always passes read-only sandbox and explicit never approval policy" {
  run "$SCRIPT" \
    --operation review \
    --cwd "$FIXTURE/cwd" \
    --sandbox read-only \
    --approval never \
    --model gpt-review \
    --effort max \
    --prompt "$PROMPT" \
    --report "$REPORT" \
    --fixed-target 1111111111111111111111111111111111111111

  [ "$status" -eq 0 ]
  assert_argv \
    -C "$FIXTURE/cwd" \
    -s read-only \
    -a never \
    -m gpt-review \
    -c model_reasoning_effort=max \
    review --commit 1111111111111111111111111111111111111111 -
}

@test "outstanding approval is blocked before Codex runs" {
  run "$SCRIPT" \
    --operation execute \
    --cwd "$FIXTURE/cwd" \
    --sandbox workspace-write \
    --approval on-request \
    --model gpt-test \
    --effort high \
    --prompt "$PROMPT" \
    --report "$REPORT"

  [ "$status" -eq 4 ]
  [[ "$output" == *"BLOCKED"* ]]
  [ ! -e "$CAPTURE" ]
}

@test "review rejects a write-capable sandbox before Codex runs" {
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
  [[ "$output" == *"read-only"* ]]
  [ ! -e "$CAPTURE" ]
}

@test "execute rejects a full-machine sandbox before Codex runs" {
  run "$SCRIPT" \
    --operation execute \
    --cwd "$FIXTURE/cwd" \
    --sandbox danger-full-access \
    --approval never \
    --model gpt-test \
    --effort high \
    --prompt "$PROMPT" \
    --report "$REPORT"

  [ "$status" -eq 4 ]
  [[ "$output" == *"sandbox"* ]]
  [ ! -e "$CAPTURE" ]
}
