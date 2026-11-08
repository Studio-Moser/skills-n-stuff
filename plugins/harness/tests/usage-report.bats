#!/usr/bin/env bats

setup() {
  SCRIPTS="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CODEX_HOME="$HOME/.codex"
  export AGENTS_REPO="$HOME/.agents"
  mkdir -p "$CLAUDE_CONFIG_DIR/projects/p/subagents" "$CODEX_HOME/sessions/2026/10/21" "$AGENTS_REPO"
  cache="$CLAUDE_CONFIG_DIR/plugins/cache/studio-moser/harness"
  mkdir -p "$cache/2.4.0/skills/old" "$cache/2.5.0/skills/delegate" "$cache/2.5.0/skills/audit"
  touch "$cache/2.4.0/skills/old/SKILL.md" "$cache/2.5.0/skills/delegate/SKILL.md" "$cache/2.5.0/skills/audit/SKILL.md"
  printf '%s\n' '{"enabledPlugins":{"harness@studio-moser":true}}' > "$CLAUDE_CONFIG_DIR/settings.json"
}

write_fixtures() {
  python3 - "$CLAUDE_CONFIG_DIR/projects/p" "$CODEX_HOME/sessions/2026/10/21" <<'PY'
import json, pathlib, sys
claude, codex = map(pathlib.Path, sys.argv[1:])
def lines(path, records):
    path.write_text("".join(json.dumps(r) + "\n" for r in records))
lines(claude / "s1.jsonl", [
    {"type": "user", "message": {"role": "user", "content": "<command-name>/harness:audit</command-name>"}},
    {"type": "user", "message": {"role": "user", "content": "<command-name>/compact</command-name>"}},
    {"type": "assistant", "message": {"content": [
        {"type": "text", "text": "I've classified this as a Small change."},
        {"type": "tool_use", "id": "t1", "name": "Skill", "input": {"skill": "harness:delegate"}},
        {"type": "tool_use", "id": "t2", "name": "Bash", "input": {"command": "ls *.zzz"}},
    ]}},
    {"type": "user", "message": {"content": [
        {"type": "tool_result", "tool_use_id": "t2", "is_error": True, "content": "(eval):1: no matches found: *.zzz"},
    ]}},
    {"type": "system", "subtype": "compact_boundary", "compactMetadata": {"trigger": "manual"}},
])
# Sub-agent transcripts are dispatched work, not sessions.
lines(claude / "subagents" / "a1.jsonl", [
    {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Skill", "input": {"skill": "harness:delegate"}}]}},
])
lines(codex / "rollout-1.jsonl", [
    {"type": "session_meta", "payload": {"source": "cli"}},
    {"type": "response_item", "payload": {"type": "message", "role": "user", "content": [
        {"type": "input_text", "text": "<skill>\n<name>harness:delegate</name>\n<path>x</path>"}]}},
    {"type": "response_item", "payload": {"type": "function_call", "name": "exec", "arguments":
        "{\"cmd\":\"cat /h/.codex/plugins/cache/studio-moser/pm/0.25.4/skills/dev-task/SKILL.md\"}"}},
    {"type": "response_item", "payload": {"type": "function_call", "name": "exec", "arguments":
        "{\"cmd\":\"cat plugins/harness/skills/risk-gate/SKILL.md\"}"}},
    {"type": "response_item", "payload": {"type": "function_call_output", "output":
        "{\"output\":\"zsh:1: no matches found: *.zzz\",\"metadata\":{\"exit_code\":1}}"}},
    {"type": "response_item", "payload": {"type": "function_call_output", "output":
        "{\"output\":\"ok\",\"metadata\":{\"exit_code\":0}}"}},
    {"type": "compacted", "payload": {"message": ""}},
])
PY
}

@test "usage report counts skills, errors, compactions, detectors, shims, and results" {
  write_fixtures
  "$SCRIPTS/telemetry.py" record-result --operation execute --result '{"status":"accepted","route":{"requested":"bulk","model":"m","effort":"low","provider":"p","executor":"native","dispatch":"delegated"},"evidence":{"checks":[],"outcome":"proven"},"blockers":[]}' >/dev/null
  printf '%s\n' '{"tool_name":"Bash","cwd":"/tmp","tool_input":{"command":"ls --x=*.zzz"}}' | SHELL=/bin/zsh "$SCRIPTS/zsh-glob-guard.py" >/dev/null

  run "$SCRIPTS/usage-report.py" --days 30
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
r = json.loads(sys.argv[1])
assert r["sessions"] == {"claude": 1, "codex": 1}, r["sessions"]
assert r["skills"]["harness:delegate"] == {"claude_tool": 1, "codex_sessions": 1}, r["skills"]
assert r["skills"]["harness:audit"] == {"claude_slash": 1}, r["skills"]
assert r["skills"]["pm:dev-task"] == {"codex_sessions": 1}, r["skills"]
assert "risk-gate" not in r["skills"], "a repository source read is not skill use"
assert r["unused_skills"] == [], r["unused_skills"]
assert r["commands"] == {"compact": 1}, r["commands"]
assert r["tool_errors"] == {"claude": {"zsh-nomatch": 1}, "codex": {"zsh-nomatch": 1}}, r["tool_errors"]
assert r["compactions"] == {"claude-manual": 1, "codex": 1}, r["compactions"]
assert r["shim_firings"] == {"zsh-glob-guard": 1}, r["shim_firings"]
assert r["results"]["total"] == 1 and r["results"]["by_route"] == {"bulk": {"accepted/proven": 1}}, r["results"]
assert {k: r["delegate"][k] for k in ("invocations", "recorded_results")} == {"invocations": 2, "recorded_results": 1}, r["delegate"]
try:
    import tomllib  # noqa: F401
except ImportError:
    pass
else:
    assert r["detector_hits"].get("silent-routing") == 1, r["detector_hits"]
' "$output"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "usage report totals review rounds and flags unapproved overruns and diff growth" {
  record() { "$SCRIPTS/telemetry.py" record-review --consumer pm:dev-task --target "$1" --model "$2" --provider p --round "$3" --limit 2 --findings "$4" --diff-lines "$5" ${6:-} >/dev/null; }
  record '#1' astra 0 '{"fixed":3,"unique":2}' 100
  record '#1' opus 0 '{"fixed":1,"disputed":1,"regraded":1}' 100
  record '#1' astra 1 '{}' 140
  record '#2' astra 3 '{"open":1}' 50
  record '#3' astra 3 '{}' 50 --extension-approved

  run "$SCRIPTS/usage-report.py" --days 30
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
r = json.loads(sys.argv[1])["reviews"]
assert r["rounds"] == 5, r
assert r["by_model"]["astra"]["rounds"] == 4 and r["by_model"]["astra"]["unique"] == 2, r
assert r["by_model"]["opus"]["disputed"] == 1 and r["by_model"]["opus"]["regraded"] == 1, r
assert r["unapproved_over_limit"] == ["pm:dev-task #2"], r
assert r["diff_growth"] == {"pm:dev-task #1": {"first": 100, "last": 140}}, r
' "$output"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

write_session_fixture() {
  python3 - "$CLAUDE_CONFIG_DIR/projects/p" <<'PY'
import json, pathlib, sys
claude = pathlib.Path(sys.argv[1])
def at(minute):
    return f"2026-10-10T{minute // 60:02d}:{minute % 60:02d}:00Z"
def human(minute, text):
    return {"type": "user", "timestamp": at(minute), "message": {"role": "user", "content": text}}
def call(minute, use_id, name, tool_input):
    return {"type": "assistant", "timestamp": at(minute), "message": {"content": [
        {"type": "tool_use", "id": use_id, "name": name, "input": tool_input}]}}
def bash(minute, use_id, command, description="run"):
    return call(minute, use_id, "Bash", {"command": command, "description": description})
def result(minute, use_id, text, error=False):
    block = {"type": "tool_result", "tool_use_id": use_id, "content": text}
    if error:
        block["is_error"] = True
    return {"type": "user", "timestamp": at(minute), "message": {"content": [block]}}
def say(minute, text):
    return {"type": "assistant", "timestamp": at(minute), "message": {"content": [{"type": "text", "text": text}]}}
def boundary(minute, trigger, pre_tokens):
    return {"type": "system", "subtype": "compact_boundary", "timestamp": at(minute),
            "compactMetadata": {"trigger": trigger, "preTokens": pre_tokens}}
records = [
    human(0, "fix the failing test"),
    bash(1, "b1", "npm test"),
    bash(1, "b1", "npm test"),  # a duplicated record of one call counts once
    result(1, "b1", "Exit code 1\nconfig: Timeout setting is 5", error=True),
    result(1, "b1", "Exit code 1\nconfig: Timeout setting is 5", error=True),
    bash(2, "b2", "npm  test", "run again"),  # same command, different description
    result(2, "b2", "Exit code 1", error=True),
    bash(3, "b3", "npm test"),
    result(3, "b3", "Exit code 1", error=True),
    call(4, "e1", "Edit", {"file_path": "a.js", "old_string": "x", "new_string": "y"}),
    result(4, "e1", "ok"),
    bash(5, "b4", "npm run test"),
    result(5, "b4", "1 passed"),
    bash(6, "b5", "npm run test"),
    result(6, "b5", "1 passed"),
    call(6, "n1", "Write", {"file_path": "/x/memory/notes.md", "content": "a note does not invalidate the check"}),
    result(6, "n1", "ok"),
    call(7, "m1", "mcp__github__update_issue", {"issue": 1}),
    result(7, "m1", "Error: Authentication Failed: Requires authentication", error=True),
    call(8, "r1", "Read", {"file_path": "missing.md"}),
    result(8, "r1", "File does not exist. Note: your current working directory is /x", error=True),
    bash(9, "t1", "sleep 999"),
    result(9, "t1", "Exit code 143\nCommand timed out after 2m 0s", error=True),
    bash(10, "w1", "\"$h/scripts/telemetry.py\" record-result --result x"),
    result(10, "w1", "ok"),
    say(11, "All tests pass, done."),
    boundary(70, "manual", 300000),
    human(80, "now tweak the copy"),
    call(81, "e2", "Write", {"file_path": "b.js", "content": "z"}),
    result(81, "e2", "ok"),
    say(82, "Fixed; the tests pass now."),
    boundary(83, "manual", 200000),
    boundary(84, "auto", 900000),
]
(claude / "s2.jsonl").write_text("".join(json.dumps(r) + "\n" for r in records))
PY
}

@test "usage report dedupes calls, classifies errors by tool, and splits compactions" {
  write_session_fixture
  run "$SCRIPTS/usage-report.py" --since 2026-10-10 --until 2026-10-12
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
r = json.loads(sys.argv[1])
assert r["tool_calls"] == {"claude": 12}, r["tool_calls"]
assert r["tool_errors"]["claude"] == {"nonzero-exit": 3, "mcp-auth": 1, "missing-file": 1, "timeout": 1}, r["tool_errors"]
by_tool = r["tool_errors_by_tool"]["claude"]
assert by_tool["Bash"] == {"nonzero-exit": 3, "timeout": 1}, by_tool
assert by_tool["mcp:github"] == {"mcp-auth": 1} and by_tool["Read"] == {"missing-file": 1}, by_tool
assert r["compactions"] == {"claude-manual": 2, "claude-auto": 1}, r["compactions"]
detail = r["compaction_detail"]["claude"]
assert detail["manual_after_idle"] == 1 and detail["manual_in_session"] == 1 and detail["auto"] == 1, detail
assert detail["pre_tokens"] == {"count": 3, "min": 200000, "median": 300000, "max": 900000}, detail
assert r["delegate"]["local"] == {"skill_loads": 0, "record_calls": 1, "results": 0}, r["delegate"]
assert "flagged_sessions" not in r, "session ids appear only on request"
' "$output"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "usage report counts sequence patterns and lists flagged sessions on request" {
  write_session_fixture
  run "$SCRIPTS/usage-report.py" --since 2026-10-10 --until 2026-10-12 --flagged
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
r = json.loads(sys.argv[1])
s = r["sequences"]["claude"]
assert s["repeated_failure"] == {"events": 1, "sessions": 1}, s
assert s["recovered_failure"] == {"events": 1, "sessions": 1}, s
assert s["verification_rerun"] == {"events": 1, "sessions": 1}, s
assert s["unsupported_completion"] == {"events": 1, "sessions": 1}, s
assert r["flagged_sessions"] == {kind: ["s2"] for kind in s}, r["flagged_sessions"]
' "$output"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "usage report separates review changes requested from failures without checks" {
  result() { "$SCRIPTS/telemetry.py" record-result --operation "$1" --result "{\"status\":\"$2\",\"route\":{\"requested\":\"review\",\"model\":\"m\",\"effort\":\"low\",\"provider\":\"p\",\"executor\":\"codex\",\"dispatch\":\"delegated\"},\"evidence\":{\"checks\":$3,\"outcome\":\"unproven\"},\"blockers\":[\"x\"]}" >/dev/null; }
  result review failed '["ran tests"]'
  result review failed '[]'
  result computer-use failed '["opened app"]'
  result review accepted '["ran tests"]'
  run "$SCRIPTS/usage-report.py" --days 30
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
r = json.loads(sys.argv[1])
assert r["results"]["failed"] == {"review_changes_requested": 1, "no_checks": 1, "other": 1}, r["results"]
assert r["delegate"]["local"]["results"] == 4, r["delegate"]
' "$output"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "error classes are anchored to the failure, not to words in printed output" {
  run python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("usage_report", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cases = {
    "Exit code 1\nretry: Timeout is configurable": "nonzero-exit",
    "locator.click: Timeout 30000ms exceeded.": "timeout",
    "ssh: connect to host x port 22: Connection timed out": "timeout",
    "(eval):1: no matches found: *.zzz": "zsh-nomatch",
    "Exit code 1\nthe docs say no matches found is common": "nonzero-exit",
    "The user doesn'"'"'t want to take this action right now.": "user-rejected",
    "The tool call was interrupted before a result was received.": "interrupted",
    "File access denied: /tmp/a.png is outside allowed roots.": "sandbox-path",
    "<tool_use_error>Unknown skill: dino</tool_use_error>": "skill-unavailable",
    "No browser is connected. Install the Browser MCP extension": "browser-disconnected",
    "{\"error\": \"Credits insufficient : balance\"}": "quota",
    "{\"code\":\"rate_limited\",\"status\":429}": "rate-limit",
    "Blocked: sleep 60 followed by cat": "host-blocked",
    "Exit code 1\nE   asyncio.TimeoutError": "nonzero-exit",
    "Exit code 2\nFound 3 matches": "nonzero-exit",
    "Found 2 matches of the string to replace, but replace_all is false.": "edit-mismatch",
    "preview snapshot timed out after 15000ms": "timeout",
}
wrong = {text: (m.error_class(text), want) for text, want in cases.items() if m.error_class(text) != want}
assert not wrong, wrong
' "$SCRIPTS/usage-report.py"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "checks and changes are read at command position" {
  run python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("usage_report", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
checks = {
    "cd x && python3 -m unittest discover -s tests": True,
    "FOO=1 npx vitest run": True,
    "cd plugins/harness/tests && bats *.bats 2>&1 | tail -3": True,
    "cat tests/x.bats": False,
    "grep foo jest.config.js": False,
}
changes = {
    "rm -f build/out.js && npm test": True,
    "npx eslint --fix src": True,
    "ruff format .": True,
    "echo x > out.txt": True,
    "git log --format=%h -3": False,
    "git status 2>&1 | head": False,
    "ls >/dev/null": False,
}
wrong = [c for c, want in checks.items() if m.is_check(c) != want]
wrong += [c for c, want in changes.items() if m.is_change(c) != want]
assert not wrong, wrong
' "$SCRIPTS/usage-report.py"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "a never-used installed skill is reported as unused" {
  run "$SCRIPTS/usage-report.py" --days 30
  [ "$status" -eq 0 ]
  [[ "$output" == *'"unused_skills": ['* ]] || return 1
  run python3 -c 'import json,sys; assert json.loads(sys.argv[1])["unused_skills"] == ["harness:audit", "harness:delegate"]' "$output"
  [ "$status" -eq 0 ]
}

@test "mixed numbered and hash-named plugin versions do not crash the report" {
  cache="$CLAUDE_CONFIG_DIR/plugins/cache/mixed/hashy"
  mkdir -p "$cache/1.0.1/skills/old" "$cache/1da406f428c2/skills/new"
  touch "$cache/1.0.1/skills/old/SKILL.md" "$cache/1da406f428c2/skills/new/SKILL.md"
  printf '%s\n' '{"enabledPlugins":{"harness@studio-moser":true,"hashy@mixed":true}}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run "$SCRIPTS/usage-report.py" --days 30
  [ "$status" -eq 0 ]
  python3 -c 'import json, sys; assert "hashy:new" in json.loads(sys.argv[1])["unused_skills"]' "$output"
}

@test "tokens count each Claude message once and take Codex deltas inside the window" {
  python3 - "$CLAUDE_CONFIG_DIR/projects/p" "$CODEX_HOME/sessions/2026/10/21" <<'PY'
import json, pathlib, sys
claude, codex = map(pathlib.Path, sys.argv[1:])
def lines(path, records):
    path.write_text("".join(json.dumps(r) + "\n" for r in records))
usage = {"input_tokens": 2, "cache_read_input_tokens": 10, "cache_creation_input_tokens": 5, "output_tokens": 3}
def assistant(message_id, ts, model="opus"):
    return {"type": "assistant", "timestamp": ts, "message": {"id": message_id, "model": model, "usage": usage, "content": []}}
lines(claude / "s1.jsonl", [
    assistant("m0", "2026-10-09T00:00:00Z"),
    assistant("m1", "2026-10-10T00:00:00Z"),
    assistant("m1", "2026-10-10T00:00:01Z"),
    assistant("m2", "2026-10-11T00:00:00Z"),
])
lines(claude / "copy.jsonl", [assistant("m2", "2026-10-11T00:00:00Z")])
lines(claude / "subagents" / "a1.jsonl", [assistant("m3", "2026-10-10T00:00:00Z", "haiku")])
def tally(ts, input_, cached, output):
    return {"type": "event_msg", "timestamp": ts, "payload": {"type": "token_count", "info": {"total_token_usage": {
        "input_tokens": input_, "cached_input_tokens": cached, "cache_write_input_tokens": 0, "output_tokens": output}}}}
lines(codex / "rollout-1.jsonl", [
    {"type": "session_meta", "payload": {"source": "exec"}},
    {"type": "turn_context", "payload": {"model": "sol"}},
    tally("2026-10-09T00:00:00Z", 100, 40, 10),
    {"type": "event_msg", "timestamp": "2026-10-10T00:00:00Z", "payload": {"type": "token_count", "info": None}},
    tally("2026-10-10T00:00:00Z", 150, 70, 15),
    tally("2026-10-11T00:00:00Z", 160, 75, 20),
    tally("2026-10-20T00:00:00Z", 900, 75, 90),
])
lines(codex / "rollout-2.jsonl", [
    {"type": "session_meta", "payload": {"source": {"subagent": "x"}}},
    {"type": "turn_context", "payload": {"model": "astra"}},
    tally("2026-10-10T00:00:00Z", 8, 3, 1),
])
PY
  run "$SCRIPTS/usage-report.py" --since 2026-10-10 --until 2026-10-12
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
r = json.loads(sys.argv[1])
assert r["window"]["label"] == "2026-10-10 to 2026-10-12", r["window"]
t = r["tokens"]
assert t["claude"]["main"]["opus"] == {"input": 4, "cache_read": 20, "cache_write": 10, "output": 6}, t
assert t["claude"]["subagent"]["haiku"] == {"input": 2, "cache_read": 10, "cache_write": 5, "output": 3}, t
assert t["codex"]["exec"]["sol"] == {"input": 25, "cache_read": 35, "cache_write": 0, "output": 10}, t
assert t["codex"]["subagent"]["astra"] == {"input": 5, "cache_read": 3, "cache_write": 0, "output": 1}, t
' "$output"
  if [ "$status" -ne 0 ]; then printf '%s\n' "$output" >&2; fi
  [ "$status" -eq 0 ]
}

@test "until without since is rejected" {
  run "$SCRIPTS/usage-report.py" --until 2026-10-12
  [ "$status" -eq 2 ]
}
