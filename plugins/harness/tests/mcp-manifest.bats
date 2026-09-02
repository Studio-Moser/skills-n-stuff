#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mcp-manifest.sh"
  RUNTIME="${BATS_TEST_TMPDIR}/mcp.json"
  MANIFEST="${BATS_TEST_TMPDIR}/mcp.manifest"
}

@test "portable inventory keeps only sorted server names" {
  cat > "$RUNTIME" <<'JSON'
{
  "mcpServers": {
    "zeta": {
      "command": "/Applications/Private.app/Contents/MacOS/server",
      "env": {"API_TOKEN": "do-not-copy"}
    },
    "alpha": {
      "url": "https://example.invalid/mcp",
      "headers": {"Authorization": "Bearer do-not-copy"}
    }
  }
}
JSON

  "$SCRIPT" "$RUNTIME" "$MANIFEST"

  run cat "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$output" = $'alpha\nzeta' ]
  [[ "$output" != *"command"* ]] || return 1
  [[ "$output" != *"env"* ]] || return 1
  [[ "$output" != *"TOKEN"* ]] || return 1
  [[ "$output" != *"/Applications"* ]]
}

@test "portable inventory merges names declared by other machines" {
  printf 'alpha\nother-machine-only\n' > "$MANIFEST"
  cat > "$RUNTIME" <<'JSON'
{"mcpServers": {"zeta": {"command": "server"}, "alpha": {"url": "https://example.invalid/mcp"}}}
JSON

  "$SCRIPT" "$RUNTIME" "$MANIFEST"

  run cat "$MANIFEST"
  [ "$status" -eq 0 ]
  [ "$output" = $'alpha\nother-machine-only\nzeta' ]
}

@test "portable inventory refuses to merge over an invalid existing manifest" {
  printf '/Applications/Private.app/Contents/MacOS/server\n' > "$MANIFEST"
  printf '%s\n' '{"mcpServers": {"alpha": {"command": "server"}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid portable MCP server name"* ]] || return 1
  run cat "$MANIFEST"
  [ "$output" = "/Applications/Private.app/Contents/MacOS/server" ]
}

@test "portable inventory check rejects an absolute command" {
  printf '/Applications/Private.app/Contents/MacOS/server\n' > "$MANIFEST"

  run "$SCRIPT" --check "$MANIFEST"

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid portable MCP server name"* ]] || return 1
}

@test "portable inventory check rejects structured credential fields" {
  printf '%s\n' '{"command":"server","env":{"TOKEN":"secret"}}' > "$MANIFEST"

  run "$SCRIPT" --check "$MANIFEST"

  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid portable MCP server name"* ]] || return 1
  [[ "$output" != *"secret"* ]]
}
