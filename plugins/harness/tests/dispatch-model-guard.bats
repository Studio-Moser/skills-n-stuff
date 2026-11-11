#!/usr/bin/env bats

setup() {
  PLUGIN="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  GUARD="$PLUGIN/scripts/dispatch-model-guard.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  unset CLAUDE_CONFIG_DIR
  WORK="$BATS_TEST_TMPDIR/work"
  mkdir -p "$HOME/.claude/agents" "$WORK/.claude/agents"
}

# payload TOOL INPUT_JSON [EXTRA_JSON]
payload() {
  python3 -c 'import json,sys; p={"tool_name": sys.argv[1], "cwd": sys.argv[3], "tool_input": json.loads(sys.argv[2])}; p.update(json.loads(sys.argv[4] or "{}")); print(json.dumps(p))' "$1" "$2" "$WORK" "${3:-}"
}

firings() {
  cat "$XDG_STATE_HOME"/studio-moser/harness/telemetry/Shim_Events-*.jsonl 2>/dev/null | wc -l | tr -d ' '
}

denied() {
  python3 -c 'import json,sys; o=json.loads(sys.argv[1])["hookSpecificOutput"]; assert o["permissionDecision"]=="deny", o; assert "`model`" in o["permissionDecisionReason"], o' "$output"
}

@test "an Agent or Task call without a model is denied and logged" {
  for tool in Agent Task; do
    run "$GUARD" <<<"$(payload "$tool" '{"description":"d","prompt":"p","subagent_type":"web-fetch"}')"
    [ "$status" -eq 0 ]
    denied
  done
  run "$GUARD" <<<"$(payload Agent '{"description":"d","prompt":"p"}')"
  denied
  [[ "$output" == *"general-purpose dispatch"* ]] || return 1
  [ "$(firings)" -eq 3 ]
  grep -q '"shim": "dispatch-model-guard"' "$XDG_STATE_HOME"/studio-moser/harness/telemetry/Shim_Events-*.jsonl
}

@test "a call with a model, a fork, or a non-Agent tool is left alone" {
  for input in '{"prompt":"p","model":"sonnet","subagent_type":"Explore"}' '{"prompt":"p","subagent_type":"fork"}'; do
    run "$GUARD" <<<"$(payload Agent "$input")"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  run "$GUARD" <<<"$(payload Bash '{"command":"ls"}')"
  [ -z "$output" ]
  [ "$(firings)" -eq 0 ]
}

@test "an agent type whose definition declares a model is left alone, wherever it is defined" {
  printf -- '---\nname: mine\nmodel: haiku\n---\nBody\n' > "$HOME/.claude/agents/mine.md"
  printf -- '---\nname: proj\nmodel: inherit\n---\nBody\n' > "$WORK/.claude/agents/proj.md"
  mkdir -p "$HOME/.claude/plugins/cache/mkt/tools/1.2.0/agents" "$HOME/.claude/plugins/cache/mkt/tools/1.10.0/agents"
  printf -- '---\nname: rev\n---\nBody\n' > "$HOME/.claude/plugins/cache/mkt/tools/1.2.0/agents/rev.md"
  printf -- '---\nname: rev\nmodel: fable\n---\nBody\n' > "$HOME/.claude/plugins/cache/mkt/tools/1.10.0/agents/rev.md"
  for type in mine proj tools:rev; do
    run "$GUARD" <<<"$(payload Agent "{\"prompt\":\"p\",\"subagent_type\":\"$type\"}")"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  printf -- '---\nname: bare\n---\nBody\n' > "$HOME/.claude/agents/bare.md"
  run "$GUARD" <<<"$(payload Agent '{"prompt":"p","subagent_type":"bare"}')"
  denied
}

@test "Codex payloads and malformed input get no decision" {
  run "$GUARD" <<<"$(payload Agent '{"prompt":"p"}' '{"turn_id":"t1"}')"
  [ -z "$output" ]
  run "$GUARD" <<<'not json'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the plugin registers the guard as a guarded PreToolUse Agent hook" {
  run python3 - "$PLUGIN/hooks/hooks.json" <<'PY'
import json, sys
hooks = json.load(open(sys.argv[1]))["hooks"]["PreToolUse"]
entry = next(group for group in hooks if group["matcher"] == "Agent|Task")
command = entry["hooks"][0]["command"]
assert command.startswith("command -v python3 >/dev/null 2>&1 && "), command
assert "${CLAUDE_PLUGIN_ROOT}/scripts/dispatch-model-guard.py" in command
assert command.endswith("|| true"), command
PY
  [ "$status" -eq 0 ]
}
