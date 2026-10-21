#!/usr/bin/env bats

setup() {
  STEP="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)/rulesync-generate.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  REPO="$BATS_TEST_TMPDIR/agents"
  BIN="$BATS_TEST_TMPDIR/bin"
  LOG="$BATS_TEST_TMPDIR/npx.log"
  mkdir -p "$HOME" "$REPO/.rulesync/rules" "$REPO/.rulesync.local" "$BIN"
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
  install)
    if [ "\${2:-}" = "--outdated" ]; then printf '%b' "\${STUB_OUTDATED:-}"; exit "\${STUB_OUTDATED_EXIT:-0}"; fi
    pwd > "$BATS_TEST_TMPDIR/install-cwd"
    rm -rf .rulesync/skills/.curated
    if [ -n "\${STUB_FETCH_NOTHING:-}" ] || [ -d skills/alpha ]; then
      echo "Installed 0 skill(s)"
    else
      echo "Installed 1 skill(s)"; mkdir -p .rulesync/skills/.curated/alpha .rulesync/rules/.curated
      echo r > .rulesync/rules/.curated/fetched.md; echo '{}' > rulesync-npm.lock.json
      if [ -f rulesync.local.jsonc ]; then cp rulesync.local.jsonc "$BATS_TEST_TMPDIR/seen-local-config"; fi
    fi ;;
  generate)
    [ -n "\${STUB_FAIL:-}" ] && { echo "boom" >&2; exit 1; }
    [ -f "\$input/mcp.jsonc" ] && cp "\$input/mcp.jsonc" "$BATS_TEST_TMPDIR/merged-mcp.json"
    [ -f "\$input/hooks.jsonc" ] && cp "\$input/hooks.jsonc" "$BATS_TEST_TMPDIR/merged-hooks.json"
    case "\$*" in *--delete*) printf '%s\n' "\${STUB_DELETE:-}" ;; *--dry-run*) [ -n "\${STUB_WRITES:-}" ] && printf '[DRY RUN] Would write: %s\n' \$STUB_WRITES ;; esac
    echo "Written 3 file(s) total" ;;
esac
EOF
  chmod +x "$BIN/npx"
  # Stub npm: the latest published rulesync, counted so caching can be checked.
  printf '#!/bin/sh\necho view >> "%s"\necho "${STUB_LATEST:-39.0.0}"\n' "$BATS_TEST_TMPDIR/npm.log" > "$BIN/npm"
  chmod +x "$BIN/npm"
  export PATH="$BIN:$PATH"
}

state() { printf '%s\n' "$output" | grep "^RULESYNC_STATE="; }
updates() { printf '%s\n' "$output" | grep "^RULESYNC_UPDATES="; }

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
  [ "$(state)" = "RULESYNC_STATE=generated: 3 file(s) written; 0 skill(s); 0 stale skill folder(s) removed" ]
  [ "$(updates)" = "RULESYNC_UPDATES=none" ]
  run grep -c '^install' "$LOG"
  [ "$output" = "0" ]
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
  mkdir -p "$REPO/.rulesync/skills/alpha" "$REPO/.rulesync/skills/beta"
  "$STEP" "$REPO" >/dev/null
  rm -rf "$REPO/.rulesync/skills/beta"
  mkdir -p "$HOME/.agents/skills/beta" "$HOME/.claude/skills/beta" "$HOME/.claude/skills/synced"
  export STUB_DELETE="$(printf '[DRY RUN] Would delete directory: "%s"\n' "$HOME/.agents/skills/beta" "$HOME/.claude/skills/beta" "$HOME/.claude/skills/synced")"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$(state)" == *"1 skill(s); 2 stale skill folder(s) removed" ]] || return 1
  [ ! -e "$HOME/.agents/skills/beta" ]
  [ ! -e "$HOME/.claude/skills/beta" ]
  [ -d "$HOME/.claude/skills/synced" ]
  [ "$(cat "$XDG_STATE_HOME"/studio-moser/harness/rulesync-skills-*.json)" = '["alpha"]' ]
}

@test "a failed generate reports failure and keeps the previous skill state" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  run env STUB_FAIL=1 "$STEP" "$REPO"
  [ "$status" -eq 1 ]
  [ "$(state)" = "RULESYNC_STATE=failed: generate: boom" ]
  run ls "$XDG_STATE_HOME/studio-moser/harness/"
  [[ "$output" != *rulesync-skills* ]] || return 1
}

@test "dry run neither installs, removes, nor records state" {
  printf '{ "global": true, "sources": [{ "source": "o/r" }] }\n' > "$REPO/rulesync.jsonc"
  run "$STEP" --dry-run "$REPO"
  [ "$status" -eq 0 ]
  [[ "$(state)" == "RULESYNC_STATE=generated: dry run;"* ]] || return 1
  grep -q -- '^generate --global --input-roots .* --dry-run$' "$LOG"
  # Only the read-only update check may call install.
  run grep -c -x 'install' "$LOG"
  [ "$output" = "0" ]
  run ls "$XDG_STATE_HOME/studio-moser/harness/"
  [[ "$output" != *rulesync-skills* ]] || return 1
}

@test "machine-local hooks are appended per event for shared and per-tool blocks" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  printf '{ "version": 1, "codexcli": { "hooks": { "stop": [{ "command": "shared-stop" }] } } }\n' > "$REPO/.rulesync/hooks.jsonc"
  mkdir -p "$REPO/.rulesync.local"
  printf '{ "codexcli": { "hooks": { "stop": [{ "command": "local-stop" }], "sessionStart": [{ "command": "local-start" }] } } }\n' > "$REPO/.rulesync.local/hooks.jsonc"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  run python3 -c '
import json, sys
merged = json.load(open(sys.argv[1]))
assert merged["hooks"] == {}, merged
h = merged["codexcli"]["hooks"]
assert [e["command"] for e in h["stop"]] == ["shared-stop", "local-stop"], h
assert [e["command"] for e in h["sessionStart"]] == ["local-start"], h
' "$BATS_TEST_TMPDIR/merged-hooks.json"
  [ "$status" -eq 0 ]
}

@test "install is skipped while config, lock, and installed skills are unchanged" {
  printf '{ "global": true, "sources": [{ "source": "o/r", "skills": ["alpha"] }] }\n' > "$REPO/rulesync.jsonc"
  printf '{ "lockfileVersion": 1, "sources": { "o/r": { "skills": { "alpha": {} } } } }\n' > "$REPO/rulesync.lock"
  "$STEP" "$REPO" >/dev/null
  : > "$LOG"
  "$STEP" "$REPO" >/dev/null
  run grep -c '^install' "$LOG"
  [ "$output" = "0" ]
  # A missing installed skill or a lockfile change installs again.
  rm -rf "$REPO/.rulesync/skills/.curated/alpha"
  "$STEP" "$REPO" >/dev/null
  run grep -c '^install' "$LOG"
  [ "$output" = "1" ]
}

@test "install runs from a private root, so generated copies in <repo>/skills never block it" {
  printf '{ "global": true, "sources": [{ "source": "o/r", "skills": ["alpha"] }] }\n' > "$REPO/rulesync.jsonc"
  # In global mode ~/.agents/skills is both <repo>/skills and rulesync's Codex output.
  mkdir -p "$REPO/skills/alpha"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [ -d "$REPO/.rulesync/skills/.curated/alpha" ]
  [ "$(cat "$BATS_TEST_TMPDIR/install-cwd")" != "$REPO" ]
  [ -d "$REPO/skills/alpha" ]
}

@test "a declared skill that a run fails to fetch is never removed" {
  printf '{ "global": true, "sources": [{ "source": "o/r", "skills": ["alpha"] }] }\n' > "$REPO/rulesync.jsonc"
  "$STEP" "$REPO" >/dev/null
  printf '{ "lockfileVersion": 1 }\n' > "$REPO/rulesync.lock"  # a lock change re-runs install
  mkdir -p "$HOME/.agents/skills/alpha"
  export STUB_FETCH_NOTHING=1 STUB_DELETE="[DRY RUN] Would delete directory: \"$HOME/.agents/skills/alpha\""
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$(state)" == *"0 stale skill folder(s) removed" ]] || return 1
  [ -d "$HOME/.agents/skills/alpha" ]
}

@test "rulesync delete mode is refused, since its sweep removes other installers' skills" {
  printf '{ "global": true, "delete": true }\n' > "$REPO/rulesync.jsonc"
  run "$STEP" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == 'RULESYNC_STATE=failed: set "delete": false'* ]] || return 1
  [ ! -e "$LOG" ]
}

@test "a malformed local overlay fails with a state line instead of a traceback" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  mkdir -p "$REPO/.rulesync.local"
  printf '{ not json' > "$REPO/.rulesync.local/mcp.jsonc"
  run "$STEP" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == "RULESYNC_STATE=failed: JSONDecodeError"* ]] || return 1
}

@test "install carries fetched rules, the npm lock, and the local config through its private root" {
  printf '{ "global": true, "sources": [{ "source": "o/r", "skills": ["alpha"] }] }\n' > "$REPO/rulesync.jsonc"
  printf '{ "verbose": false }\n' > "$REPO/rulesync.local.jsonc"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(cat "$REPO/.rulesync/rules/.curated/fetched.md")" = "r" ]
  [ -f "$REPO/rulesync-npm.lock.json" ]
  [ -f "$BATS_TEST_TMPDIR/seen-local-config" ]
}

@test "delete mode in rulesync.local.jsonc is refused too" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  printf '{ "delete": true }\n' > "$REPO/rulesync.local.jsonc"
  run "$STEP" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == 'RULESYNC_STATE=failed: set "delete": false'* ]] || return 1
}

@test "a newer rulesync and skill sources behind their lock are reported, once a day" {
  printf '{ "global": true, "sources": [{ "source": "o/r", "skills": ["alpha"] }] }\n' > "$REPO/rulesync.jsonc"
  export STUB_LATEST=40.1.0 STUB_OUTDATED_EXIT=1
  export STUB_OUTDATED='up to date  a/b (main): 111\nbehind      o/r (main): 222 -> 333\n'
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(updates)" = "RULESYNC_UPDATES=rulesync 39.0.0 -> 40.1.0 (bump the Harness pin after scripts/rulesync-rehearse.py 40.1.0); 1 skill source(s) behind: o/r (run /harness:sync --update-skills)" ]
  run "$STEP" "$REPO"
  [ "$(updates)" = "RULESYNC_UPDATES=rulesync 39.0.0 -> 40.1.0 (bump the Harness pin after scripts/rulesync-rehearse.py 40.1.0); 1 skill source(s) behind: o/r (run /harness:sync --update-skills)" ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/npm.log" | tr -d ' ')" -eq 1 ]
}

@test "--update re-resolves sources even when nothing else changed, and keeps the new lock" {
  printf '{ "global": true, "sources": [{ "source": "o/r", "skills": ["alpha"] }] }\n' > "$REPO/rulesync.jsonc"
  "$STEP" "$REPO" >/dev/null
  : > "$LOG"
  run "$STEP" --update "$REPO"
  [ "$status" -eq 0 ]
  grep -qx 'install --update' "$LOG"
}

@test "the first sync on a machine without an overlay captures it once" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  rmdir "$REPO/.rulesync.local"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RULESYNC_CAPTURE=kept on this machine only: 0 server(s), 0 hook(s)"* ]] || return 1
  [ -d "$REPO/.rulesync.local" ]
  run "$STEP" "$REPO"
  [[ "$output" != *RULESYNC_CAPTURE* ]] || return 1
}

@test "the first generate for a repo backs up every live file it will write, once" {
  printf '{ "global": true }\n' > "$REPO/rulesync.jsonc"
  mkdir -p "$HOME/.codex"
  echo live > "$HOME/.codex/config.toml"
  export STUB_WRITES="$HOME/.codex/config.toml $HOME/.codex/new-file.json"
  run "$STEP" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RULESYNC_BACKUP=1 live file(s) copied to $XDG_STATE_HOME/studio-moser/harness/backups/rulesync-"* ]] || return 1
  [ "$(cat "$XDG_STATE_HOME"/studio-moser/harness/backups/rulesync-*/.codex/config.toml)" = "live" ]
  [ "$(stat -f '%Lp' "$XDG_STATE_HOME"/studio-moser/harness/backups/rulesync-* 2>/dev/null || stat -c '%a' "$XDG_STATE_HOME"/studio-moser/harness/backups/rulesync-*)" = "700" ]
  run "$STEP" "$REPO"
  [[ "$output" != *RULESYNC_BACKUP* ]] || return 1
}
