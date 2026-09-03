#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mcp-reconcile.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
  mkdir -p "$REPO"
  RUNTIME="${BATS_TEST_TMPDIR}/claude.json"
  LOCAL="${BATS_TEST_TMPDIR}/settings.local.json"
  printf '{}\n' > "$LOCAL"
  export MCP_HOSTNAME="here-host"
  cat > "$REPO/mcp.manifest.json" <<'JSON'
{"version": 1, "servers": {
  "both": {"type": "stdio", "command": "sh", "machines": ["here-host", "other"]},
  "installable": {"type": "stdio", "command": "sh", "env": {"INST_KEY": "${INST_KEY}"}, "machines": ["other"]},
  "shapeless": {"machines": []},
  "skipped": {"type": "stdio", "command": "sh", "machines": ["other"]},
  "unresolvable": {"type": "stdio", "command": "definitely-not-a-command-xyz", "machines": ["here-host"]}
}}
JSON
  cat > "$RUNTIME" <<'JSON'
{"mcpServers": {
  "both": {"type": "stdio", "command": "sh"},
  "extra": {"type": "http", "url": "https://example.invalid"},
  "kept": {"type": "stdio", "command": "sh"},
  "unresolvable": {"type": "stdio", "command": "definitely-not-a-command-xyz"}
}}
JSON
  printf '%s\n' '{"skipMcp": ["skipped"], "keepLocalMcp": ["kept"]}' > "$REPO/.fleet-local.json"
}

plan() {
  run env -u INST_KEY "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 0 ]
  PLAN="$(printf '%s\n' "$output" | sed -n '/^$/,$p')"
}

@test "table has one column per known host plus here" {
  run "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 0 ]
  header="$(printf '%s\n' "$output" | head -1)"
  [[ "$header" == *"server"* ]] || return 1
  [[ "$header" == *"here-host"* ]] || return 1
  [[ "$header" == *"other"* ]] || return 1
  [[ "$header" == *"here"* ]] || return 1
  both_row="$(printf '%s\n' "$output" | grep '^both')"
  [[ "$both_row" == *"x"*"x"*"x"* ]] || return 1
  shapeless_row="$(printf '%s\n' "$output" | grep '^shapeless')"
  [[ "$shapeless_row" == *"no config in manifest"* ]]
}

@test "plan reports every kind" {
  plan
  [[ "$PLAN" == *$'INSTALL\tinstallable'* ]] || return 1
  [[ "$PLAN" == *$'NEEDS-SECRET\tinstallable\tINST_KEY'* ]] || return 1
  [[ "$PLAN" == *$'NO-CONFIG\tshapeless'* ]] || return 1
  [[ "$PLAN" == *$'SKIP\tskipped'* ]] || return 1
  [[ "$PLAN" == *$'EXTRA\textra'* ]] || return 1
  [[ "$PLAN" == *$'KEEP-LOCAL\tkept'* ]] || return 1
  [[ "$PLAN" == *$'UNRESOLVED\tunresolvable'* ]] || return 1
  [[ "$PLAN" != *"both"* ]]
}

@test "a secret already present in the environment is not reported" {
  INST_KEY=value run "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 0 ]
  [[ "$output" != *"NEEDS-SECRET"* ]] || return 1
  [[ "$output" != *"value"* ]]
}

@test "a secret already held by another live server is not reported" {
  python3 - "$RUNTIME" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["mcpServers"]["kept"]["env"] = {"INST_KEY": "shared-secret"}
json.dump(d, open(p, "w"))
PY
  plan
  [[ "$PLAN" != *"NEEDS-SECRET"* ]] || return 1
  [[ "$PLAN" != *"shared-secret"* ]]
}

@test "a lowercase live env key satisfies its uppercased reference" {
  python3 - "$REPO/mcp.manifest.json" "$RUNTIME" <<'PY'
import json, sys
mp, rp = sys.argv[1:3]
m = json.load(open(mp)); m["servers"]["installable"]["env"] = {"inst-key": "${INST_KEY}"}; json.dump(m, open(mp, "w"))
r = json.load(open(rp)); r["mcpServers"]["kept"]["env"] = {"inst-key": "held"}; json.dump(r, open(rp, "w"))
PY
  plan
  [[ "$PLAN" == *$'INSTALL\tinstallable'* ]] || return 1
  [[ "$PLAN" != *"NEEDS-SECRET"* ]] || return 1
  [[ "$PLAN" != *"held"* ]]
}

@test "disabled servers are not findings" {
  printf '%s\n' '{"disabledMcpjsonServers": ["installable", "unresolvable"]}' > "$LOCAL"
  plan
  [[ "$PLAN" != *"installable"* ]] || return 1
  [[ "$PLAN" != *"unresolvable"* ]]
}

@test "absent manifest and overrides are treated as empty" {
  rm "$REPO/mcp.manifest.json" "$REPO/.fleet-local.json"
  plan
  [[ "$PLAN" == *$'EXTRA\tboth'* ]] || return 1
  [[ "$PLAN" == *$'EXTRA\tkept'* ]] || return 1
  [[ "$PLAN" != *"INSTALL"* ]]
}

@test "an unreadable registry fails without printing state" {
  printf 'nope\n' > "$RUNTIME"
  run "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_RECONCILE_STATE=failed"* ]]
}

@test "an empty registry file is treated as no servers" {
  : > "$RUNTIME"
  plan
  [[ "$PLAN" == *$'INSTALL\tinstallable'* ]] || return 1
  [[ "$PLAN" != *"EXTRA"* ]]
}
