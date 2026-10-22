#!/usr/bin/env bats

setup() {
  PLUGIN="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  GUARD="$PLUGIN/scripts/zsh-glob-guard.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$HOME" "$WORK"
  touch "$WORK/present.md"
}

payload() {
  python3 -c 'import json,sys; print(json.dumps({"tool_name": sys.argv[1], "cwd": sys.argv[2], "permission_mode": sys.argv[4] if len(sys.argv) > 4 else "auto", "tool_input": {"command": sys.argv[3], "description": "d"}}))' "$@"
}

firings() {
  cat "$XDG_STATE_HOME"/studio-moser/harness/telemetry/Shim_Events-*.jsonl 2>/dev/null | wc -l | tr -d ' '
}

@test "auto and bypass modes prefix an unmatched glob without a permission decision" {
  for mode in auto bypassPermissions; do
    run env SHELL=/bin/zsh "$GUARD" <<<"$(payload Bash "$WORK" 'grep -rn x --include=*.zzz .' "$mode")"
    [ "$status" -eq 0 ]
    run python3 -c '
import json, sys
out = json.loads(sys.argv[1])["hookSpecificOutput"]
assert out["hookEventName"] == "PreToolUse"
assert "permissionDecision" not in out, out
assert out["updatedInput"] == {"command": "setopt no_nomatch; grep -rn x --include=*.zzz .", "description": "d"}, out
' "$output"
    [ "$status" -eq 0 ]
  done
  [ "$(firings)" -eq 2 ]
  grep -q '"action": "rewrite"' "$XDG_STATE_HOME"/studio-moser/harness/telemetry/Shim_Events-*.jsonl
}

@test "allowlist modes deny with a quoting reason instead of rewriting past allow rules" {
  for mode in default acceptEdits plan; do
    run env SHELL=/bin/zsh "$GUARD" <<<"$(payload Bash "$WORK" 'grep -rn x --include=*.zzz .' "$mode")"
    [ "$status" -eq 0 ]
    run python3 -c '
import json, sys
out = json.loads(sys.argv[1])["hookSpecificOutput"]
assert out["permissionDecision"] == "deny", out
assert "--include=*.zzz" in out["permissionDecisionReason"] and "Quote" in out["permissionDecisionReason"]
assert "updatedInput" not in out, out
' "$output"
    [ "$status" -eq 0 ]
  done
  [ "$(firings)" -eq 3 ]
  run grep -q '"allow"' "$XDG_STATE_HOME"/studio-moser/harness/telemetry/Shim_Events-*.jsonl
  [ "$status" -ne 0 ]
}

@test "Codex payloads always get the denial, never an allow-gated rewrite" {
  for mode in default bypassPermissions dontAsk; do
    codex_payload="$(python3 -c 'import json,sys; print(json.dumps({"tool_name": "Bash", "turn_id": "t1", "model": "m", "cwd": sys.argv[1], "permission_mode": sys.argv[2], "tool_input": {"command": "ls --x=*.zzz"}}))' "$WORK" "$mode")"
    run env SHELL=/bin/zsh "$GUARD" <<<"$codex_payload"
    [ "$status" -eq 0 ]
    run python3 -c '
import json, sys
out = json.loads(sys.argv[1])["hookSpecificOutput"]
assert out["permissionDecision"] == "deny", out
assert "updatedInput" not in out, out
' "$output"
    [ "$status" -eq 0 ]
  done
  [ "$(grep -c '"agent": "codex"' "$XDG_STATE_HOME"/studio-moser/harness/telemetry/Shim_Events-*.jsonl)" -eq 3 ]
}

@test "the rewritten command runs under zsh where the original failed" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -fc 'cd "$1" && echo --include=*.zzz' _ "$WORK"
  [ "$status" -ne 0 ]
  run zsh -fc 'cd "$1" && setopt no_nomatch; echo --include=*.zzz *.md' _ "$WORK"
  [ "$status" -eq 0 ]
  [ "$output" = "--include=*.zzz present.md" ]
}

@test "quoted, matching, non-glob, and non-zsh commands pass through untouched" {
  for command in "grep -rn x --include='*.zzz' ." 'ls *.md' 'echo $? ${a#*/}' '[ -x foo ] && echo ok' '[[ $x == *.zzz ]]'; do
    run env SHELL=/bin/zsh "$GUARD" <<<"$(payload Bash "$WORK" "$command")"
    [ "$status" -eq 0 ]
    [ -z "$output" ] || { echo "rewrote: $command -> $output" >&2; return 1; }
  done
  run env SHELL=/bin/bash "$GUARD" <<<"$(payload Bash "$WORK" 'ls *.zzz')"
  [ -z "$output" ]
  run env SHELL=/bin/zsh "$GUARD" <<<"$(payload Read "$WORK" 'ls *.zzz')"
  [ -z "$output" ]
  [ "$(firings)" -eq 0 ]
}

@test "malformed input exits zero with no output" {
  run env SHELL=/bin/zsh "$GUARD" <<<'not json'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the plugin registers the guard as a guarded PreToolUse Bash hook" {
  run python3 - "$PLUGIN/hooks/hooks.json" <<'PY'
import json, sys
hooks = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
entry = next(group for group in hooks if group["matcher"] == "Bash")
command = entry["hooks"][0]["command"]
assert command.startswith("command -v python3 >/dev/null 2>&1 && "), command
assert "${CLAUDE_PLUGIN_ROOT}/scripts/zsh-glob-guard.py" in command
assert command.endswith("|| true"), command
PY
  [ "$status" -eq 0 ]
}
