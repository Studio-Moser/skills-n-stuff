#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mcp-secrets.sh"
  MANIFEST="${BATS_TEST_TMPDIR}/mcp.manifest.json"
  RUNTIME="${BATS_TEST_TMPDIR}/claude.json"
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "kie": {"type": "stdio", "command": "npx", "env": {"KIE_AI_API_KEY": "${KIE_AI_API_KEY}"}, "machines": ["a"]},
  "web": {"type": "http", "url": "https://example.invalid", "headers": {"Authorization": "${WEB_AUTHORIZATION}"}, "machines": ["a"]},
  "missing": {"type": "stdio", "command": "x", "env": {"MISSING_KEY": "${MISSING_KEY}"}, "machines": ["a"]}
}}
JSON
  cat > "$RUNTIME" <<'JSON'
{"mcpServers": {
  "kie": {"type": "stdio", "command": "npx", "env": {"KIE_AI_API_KEY": "kie-value"}},
  "web": {"type": "http", "url": "https://example.invalid", "headers": {"Authorization": "Bearer web-value"}},
  "other": {"type": "stdio", "command": "y", "env": {"UNRELATED": "keep-me"}}
}, "projects": {"/p": {"mcpServers": {}}}}
JSON
}

@test "export lists every referenced variable with its local value or empty" {
  run "$SCRIPT" export --stdout "$MANIFEST" "$RUNTIME"
  [ "$status" -eq 0 ]
  [ "$output" = $'KIE_AI_API_KEY=kie-value\nMISSING_KEY=\nWEB_AUTHORIZATION=Bearer web-value' ]
}

@test "export refuses a non-terminal stdout without --stdout" {
  run "$SCRIPT" export "$MANIFEST" "$RUNTIME"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_SECRETS_STATE=refused"* ]] || return 1
  [[ "$output" != *"kie-value"* ]]
}

@test "import writes values into referencing entries only and skips empty values" {
  python3 - "$RUNTIME" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["mcpServers"]["kie"]["env"]["KIE_AI_API_KEY"] = "${KIE_AI_API_KEY}"
d["mcpServers"]["web"]["headers"]["Authorization"] = "${WEB_AUTHORIZATION}"
d["mcpServers"]["missing"] = {"type": "stdio", "command": "x", "env": {"MISSING_KEY": "${MISSING_KEY}"}}
json.dump(d, open(p, "w"))
PY
  run "$SCRIPT" import "$RUNTIME" <<'EOF'
KIE_AI_API_KEY=new-kie
WEB_AUTHORIZATION=Bearer new-web
MISSING_KEY=
not a pair
EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_SECRETS_STATE=imported 2 value(s) into 2 server(s)"* ]] || return 1
  [[ "$output" != *"new-kie"* ]] || return 1
  python3 - "$RUNTIME" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["mcpServers"]
assert d["kie"]["env"]["KIE_AI_API_KEY"] == "new-kie"
assert d["web"]["headers"]["Authorization"] == "Bearer new-web"
assert d["missing"]["env"]["MISSING_KEY"] == "${MISSING_KEY}"
assert d["other"]["env"]["UNRELATED"] == "keep-me"
PY
  python3 -c 'import json,sys; assert "projects" in json.load(open(sys.argv[1]))' "$RUNTIME"
}

@test "import leaves the registry untouched when it is unreadable" {
  printf 'nope\n' > "$RUNTIME"
  run "$SCRIPT" import "$RUNTIME" <<'EOF'
KIE_AI_API_KEY=x
EOF
  [ "$status" -eq 1 ]
  [ "$(cat "$RUNTIME")" = "nope" ]
}
