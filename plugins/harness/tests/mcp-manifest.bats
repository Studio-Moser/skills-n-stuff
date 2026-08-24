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
