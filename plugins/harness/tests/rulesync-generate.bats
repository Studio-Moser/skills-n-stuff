#!/usr/bin/env bats

setup() {
  STEP="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)/rulesync-generate.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  REPO="$BATS_TEST_TMPDIR/agents"
  BIN="$BATS_TEST_TMPDIR/bin"
  LOG="$BATS_TEST_TMPDIR/npx.log"
  mkdir -p "$HOME" "$REPO/.rulesync/rules" "$BIN"
  printf -- '---\nroot: true\n---\nRule\n' > "$REPO/.rulesync/rules/Global_Instructions.md"
  # Stub npx: records each rulesync call, captures the merged MCP source, and prints
  # rulesync-shaped output. STUB_DELETE lists dry-run --delete paths; STUB_FAIL fails generate.
  cat > "$BIN/npx" <<EOF
#!/bin/sh
shift 2  # -y rulesync@<version>
echo "\$*" >> "$LOG"
input=""
prev=""
for arg in "\$@"; do [ "\$prev" = "--input-roots" ] && input="\$arg"; prev="\$arg"; done
case "\$1" in
  install) echo "Installed 1 skill(s)"; mkdir -p .rulesync/skills/.curated/alpha ;;
  generate)
    [ -n "\${STUB_FAIL:-}" ] && { echo "boom" >&2; exit 1; }
    [ -f "\$input/mcp.jsonc" ] && cp "\$input/mcp.jsonc" "$BATS_TEST_TMPDIR/merged-mcp.json"
    case "\$*" in *--delete*) printf '%s\n' "\${STUB_DELETE:-}" ;; esac
    echo "Written 3 file(s) total" ;;
esac
EOF
  chmod +x "$BIN/npx"
  export PATH="$BIN:$PATH"
}

@test "an unmanaged repo is skipped without calling rulesync" {
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "RULESYNC_STATE=skipped: no rulesync.jsonc" ]
  [ ! -e "$LOG" ]
}

@test "install runs only when sources are declared, then generate runs globally" {
  printf '{ "global": true, "delete": false, // comment\n  "targets": ["claudecode",], }\n' > "$REPO/rulesync.jsonc"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == "RULESYNC_STATE=generated: 3 file(s) written; 0 skill(s); 0 stale skill folder(s) removed" ]] || return 1
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 1 ]
  grep -q '^generate --global --input-roots .*/\.rulesync$' "$LOG"

  printf '{ "global": true, "sources": [{ "source": "o/r", "skills": ["alpha"] }] }\n' > "$REPO/rulesync.jsonc"
  : > "$LOG"
  run "$STEP" "$REPO"
  [ "$(head -1 "$LOG")" = "install" ]
  [[ "$output" == *"1 skill(s)"* ]]
}

@test "machine-local MCP servers are merged into a temporary source, never the repo" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  printf '{ "mcpServers": { "shared": { "command": "a" } },\n  "codexcli": { "mcpServers": { "codex-only": { "url": "https://x" } } } }\n' > "$REPO/.rulesync/mcp.jsonc"
  mkdir -p "$REPO/.rulesync.local"
  printf '{ /* this Mac only */ "mcpServers": { "local": { "command": "b" } },\n  "codexcli": { "mcpServers": { "app": { "command": "c" } } } }\n' > "$REPO/.rulesync.local/mcp.jsonc"
  before="$(cat "$REPO/.rulesync/mcp.jsonc")"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
m = json.load(open(sys.argv[1]))
assert sorted(m["mcpServers"]) == ["local", "shared"], m
assert sorted(m["codexcli"]["mcpServers"]) == ["app", "codex-only"], m
' "$BATS_TEST_TMPDIR/merged-mcp.json"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/.rulesync/mcp.jsonc")" = "$before" ]
}

@test "only folders of skills dropped since the last run are removed" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  mkdir -p "$REPO/.rulesync/skills/alpha" "$HOME/.agents/skills/beta" "$HOME/.claude/skills/beta" "$HOME/.claude/skills/synced"
  mkdir -p "$XDG_STATE_HOME/studio-moser/harness"
  printf '["alpha", "beta"]\n' > "$XDG_STATE_HOME/studio-moser/harness/rulesync-skills.json"
  export STUB_DELETE="$(printf '[DRY RUN] Would delete directory: "%s"\n' "$HOME/.agents/skills/beta" "$HOME/.claude/skills/beta" "$HOME/.claude/skills/synced")"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 skill(s); 2 stale skill folder(s) removed" ]] || return 1
  [ ! -e "$HOME/.agents/skills/beta" ]
  [ ! -e "$HOME/.claude/skills/beta" ]
  [ -d "$HOME/.claude/skills/synced" ]
  [ "$(cat "$XDG_STATE_HOME/studio-moser/harness/rulesync-skills.json")" = '["alpha"]' ]
}

@test "a failed generate reports failure and keeps the previous skill state" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  run env STUB_FAIL=1 "$STEP" "$REPO"
  [ "$status" -eq 1 ]
  [ "$output" = "RULESYNC_STATE=failed: generate: boom" ]
  [ ! -e "$XDG_STATE_HOME/studio-moser/harness/rulesync-skills.json" ]
}

@test "dry run neither installs, removes, nor records state" {
  printf '{ "global": true, "sources": [{ "source": "o/r" }] }\n' > "$REPO/rulesync.jsonc"
  run "$STEP" --dry-run "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == "RULESYNC_STATE=generated: dry run;"* ]] || return 1
  [ "$(cat "$LOG")" = "generate --global --input-roots $(sed -n 's/.*--input-roots //p' "$LOG")" ]
  grep -q -- '--dry-run' "$LOG"
  run grep -c '^install' "$LOG"
  [ "$output" = "0" ]
  [ ! -e "$XDG_STATE_HOME/studio-moser/harness/rulesync-skills.json" ]
}
