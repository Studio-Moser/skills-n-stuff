#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mcp-manifest.sh"
  DIR="${BATS_TEST_TMPDIR}/agents"
  mkdir -p "$DIR"
  RUNTIME="${BATS_TEST_TMPDIR}/claude.json"
  MANIFEST="$DIR/mcp.manifest.json"
  export MCP_HOSTNAME="test-host"
}

field() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d = d[k] if isinstance(d, dict) else d[int(k)]
print(json.dumps(d, sort_keys=True))' "$MANIFEST" "$@"
}

@test "generator keeps portable keys, redacts env and headers, and stamps this host" {
  cat > "$RUNTIME" <<'JSON'
{
  "mcpServers": {
    "zeta": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@acme/zeta"],
      "env": {"ZETA_TOKEN": "do-not-copy"},
      "oauth": {"refresh": "do-not-copy-either"}
    },
    "alpha": {
      "type": "http",
      "url": "https://example.invalid/mcp",
      "headers": {"Authorization": "Bearer do-not-copy"}
    }
  }
}
JSON

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=written"* ]] || return 1

  [ "$(field version)" = "1" ]
  [ "$(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1]))["servers"]))' "$MANIFEST")" = "['alpha', 'zeta']" ]
  [ "$(field servers zeta env ZETA_TOKEN)" = '"${ZETA_TOKEN}"' ]
  [ "$(field servers alpha headers Authorization)" = '"${ALPHA_AUTHORIZATION}"' ]
  [ "$(field servers zeta machines)" = '["test-host"]' ]
  [ "$(field servers zeta args)" = '["-y", "@acme/zeta"]' ]
  run cat "$MANIFEST"
  [[ "$output" != *"do-not-copy"* ]] || return 1
  [[ "$output" != *"oauth"* ]]
}

@test "generator preserves other hosts and removes this host from servers no longer here" {
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "gone": {"type": "stdio", "command": "gone", "machines": ["other", "test-host"]},
  "shared": {"type": "stdio", "command": "old-command", "machines": ["other"]}
}}
JSON
  printf '%s\n' '{"mcpServers":{"shared":{"type":"stdio","command":"new-command"}}}' > "$RUNTIME"

  "$SCRIPT" "$RUNTIME" "$MANIFEST"

  [ "$(field servers gone machines)" = '["other"]' ]
  [ "$(field servers gone command)" = '"gone"' ]
  [ "$(field servers shared machines)" = '["other", "test-host"]' ]
  [ "$(field servers shared command)" = '"new-command"' ]
}

@test "generator prunes to this machine only when asked" {
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "elsewhere": {"type": "stdio", "command": "x", "machines": ["other"]},
  "here": {"type": "stdio", "command": "y", "machines": ["other"]}
}}
JSON
  printf '%s\n' '{"mcpServers":{"here":{"type":"stdio","command":"y"}}}' > "$RUNTIME"

  "$SCRIPT" --prune-to-local "$RUNTIME" "$MANIFEST"

  [ "$(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1]))["servers"]))' "$MANIFEST")" = "['here']" ]
  [ "$(field servers here machines)" = '["other", "test-host"]' ]
}

@test "generator leaves a keepLocalMcp server undeclared unless it was already declared" {
  printf '%s\n' '{"version":1,"servers":{"declared":{"type":"stdio","command":"d","machines":["other"]}}}' > "$MANIFEST"
  printf '%s\n' '{"keepLocalMcp":["declared","local-only"]}' > "$DIR/.fleet-local.json"
  printf '%s\n' '{"mcpServers":{"declared":{"type":"stdio","command":"d"},"local-only":{"type":"stdio","command":"l"},"fresh":{"type":"stdio","command":"f"}}}' > "$RUNTIME"

  "$SCRIPT" "$RUNTIME" "$MANIFEST"

  [ "$(python3 -c 'import json,sys; print(sorted(json.load(open(sys.argv[1]))["servers"]))' "$MANIFEST")" = "['declared', 'fresh']" ]
  [ "$(field servers declared machines)" = '["other", "test-host"]' ]
}

@test "generator stops on an unreadable fleet-local override file" {
  printf '%s\n' '{"version":1,"servers":{}}' > "$MANIFEST"
  printf 'not json\n' > "$DIR/.fleet-local.json"
  printf '%s\n' '{"mcpServers":{"alpha":{"type":"stdio","command":"a"}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: fleet-local overrides are not readable"* ]] || return 1
  [ "$(cat "$MANIFEST")" = '{"version":1,"servers":{}}' ]
}

@test "generator migrates the names-only manifest into shapeless entries and removes it" {
  printf 'alpha\nlegacy-only\n' > "$DIR/mcp.manifest"
  printf '%s\n' '{"mcpServers":{"alpha":{"type":"http","url":"https://example.invalid/mcp"}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=migrated"* ]] || return 1
  [ ! -e "$DIR/mcp.manifest" ]
  [ "$(field servers legacy-only)" = '{"machines": []}' ]
  [ "$(field servers alpha machines)" = '["test-host"]' ]
  [ "$(field servers alpha url)" = '"https://example.invalid/mcp"' ]
}

@test "generator untracks the names-only manifest inside a git repo" {
  git init -q -b main "$DIR"
  git -C "$DIR" config user.email test@example.com
  git -C "$DIR" config user.name "Harness Test"
  printf 'alpha\n' > "$DIR/mcp.manifest"
  git -C "$DIR" add mcp.manifest
  git -C "$DIR" commit -q -m base
  printf '%s\n' '{"mcpServers":{"alpha":{"type":"stdio","command":"a"}}}' > "$RUNTIME"

  "$SCRIPT" "$RUNTIME" "$MANIFEST"

  ! git -C "$DIR" ls-files --error-unmatch mcp.manifest >/dev/null 2>&1
  [ ! -e "$DIR/mcp.manifest" ]
}

@test "generator fails on a key-like arg naming the server only" {
  printf '%s\n' '{"mcpServers":{"leaky":{"type":"stdio","command":"srv","args":["--api-key=sk-abcdefghijklmnopqrstuvwxyz"]}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: server leaky has a secret-like argument"* ]] || return 1
  [[ "$output" != *"abcdefghijklmnopqrstuvwxyz"* ]] || return 1
  [ ! -e "$MANIFEST" ]
}

@test "generator fails on an absolute home path" {
  printf '%s\n' '{"mcpServers":{"local":{"type":"stdio","command":"/Users/someone/bin/srv"}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: server local uses a machine-specific path"* ]] || return 1
  [ ! -e "$MANIFEST" ]
}

@test "generator refuses to empty a non-empty manifest without the override" {
  printf '%s\n' '{"version":1,"servers":{"only":{"type":"stdio","command":"x","machines":["test-host"]}}}' > "$MANIFEST"
  printf '%s\n' '{"mcpServers":{}}' > "$RUNTIME"

  run "$SCRIPT" --prune-to-local "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: refusing to write an empty manifest"* ]] || return 1
  [ "$(field servers only command)" = '"x"' ]

  MCP_ALLOW_EMPTY_MANIFEST=1 "$SCRIPT" --prune-to-local "$RUNTIME" "$MANIFEST"
  [ "$(field servers)" = "{}" ]
}

@test "generator leaves the manifest untouched on an unreadable registry" {
  printf '%s\n' '{"version":1,"servers":{}}' > "$MANIFEST"
  printf 'not json\n' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: Claude user state is not readable"* ]] || return 1
  [ "$(cat "$MANIFEST")" = '{"version":1,"servers":{}}' ]
}

@test "check accepts a valid manifest" {
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "a": {"type": "http", "url": "https://example.invalid", "headers": {"X-Key": "${A_X_KEY}"}, "machines": ["h1", "h2"]},
  "b": {"machines": []}
}}
JSON
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "check rejects unsorted names, unredacted values, and extra keys" {
  printf '%s\n' '{"version":1,"servers":{"b":{"machines":[]},"a":{"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sorted"* ]] || return 1

  printf '%s\n' '{"version":1,"servers":{"a":{"env":{"T":"literal-value"},"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"server a has an unredacted env value"* ]] || return 1
  [[ "$output" != *"literal-value"* ]] || return 1

  printf '%s\n' '{"version":1,"servers":{"a":{"oauth":{},"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"server a has a non-portable key"* ]] || return 1
}

@test "check rejects an invalid server name without echoing it" {
  printf '%s\n' '{"version":1,"servers":{"/Users/x/bin":{"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid portable MCP server name"* ]] || return 1
  [[ "$output" != *"/Users/x"* ]]
}
