#!/usr/bin/env bats

setup() {
  BOOT="$(cd "${BATS_TEST_DIRNAME}/../scripts" && pwd)/rulesync-bootstrap.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export HARNESS_SECRETS_BACKEND=file
  REPO="$HOME/.agents"
  FIX="$BATS_TEST_TMPDIR/fixtures"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.cursor" "$FIX/claudecode" "$FIX/codexcli" "$FIX/cursor" "$BIN"
  echo '{}' > "$HOME/.claude.json"

  cat > "$FIX/claudecode/mcp.jsonc" <<'EOF'
{ "mcpServers": {
  "shared-a": { "command": "npx", "args": ["-y", "a"], "env": {} },
  "kie": { "command": "npx", "args": ["-y", "kie"], "env": { "KIE_API_KEY": "secret-kie", "MODE": "x" } },
  "gh": { "type": "http", "url": "https://gh.test/mcp", "headers": { "Authorization": "Bearer secret-gh", "X-Toolsets": "repos" } },
  "diff": { "type": "http", "url": "https://diff.test/claude" }
} }
EOF
  echo '{ "version": 1, "hooks": { "stop": [{ "command": "echo claude-stop" }] } }' > "$FIX/claudecode/hooks.jsonc"
  cat > "$FIX/codexcli/mcp.jsonc" <<'EOF'
{ "mcpServers": {
  "shared-a": { "command": "npx", "args": ["-y", "a"] },
  "diff": { "type": "http", "url": "https://diff.test/codex" },
  "local-tool": { "command": "/Users/someone/bin/tool" },
  "codex-only": { "type": "http", "url": "https://only.test/codex" }
} }
EOF
  echo '{ "version": 1, "hooks": { "stop": [{ "command": "/Users/someone/.superset/notify.sh" }, { "command": "echo codex-stop" }] } }' > "$FIX/codexcli/hooks.jsonc"
  echo '{ "mcpServers": {} }' > "$FIX/cursor/mcp.jsonc"

  # Stub npx: `rulesync import --global --targets T` writes T's fixtures into the
  # temporary HOME, as rulesync's importer does.
  cat > "$BIN/npx" <<EOF
#!/bin/sh
case "\$*" in
  *" import "*)
    tool=\$(echo "\$*" | sed -n 's/.*--targets \([^ ]*\).*/\1/p')
    mkdir -p "\$HOME/.rulesync"
    for f in mcp.jsonc hooks.jsonc; do [ -f "$FIX/\$tool/\$f" ] && cp "$FIX/\$tool/\$f" "\$HOME/.rulesync/\$f"; done
    exit 0 ;;
esac
EOF
  chmod +x "$BIN/npx"
  export PATH="$BIN:$PATH"

  git init -q "$REPO"
  git -C "$REPO" config user.email t@t && git -C "$REPO" config user.name t
  mkdir -p "$REPO/skills/mine" "$REPO/skills/taste"
  echo mine > "$REPO/skills/mine/SKILL.md"
  echo vendored > "$REPO/skills/taste/SKILL.md"
  touch "$REPO/skills/.keep"
  printf 'taste\towner/taste-repo\n' > "$REPO/skills.manifest"
  echo '{ "skills": { "taste": { "source": "owner/taste-repo", "skillPath": "skills/taste/SKILL.md" } } }' > "$REPO/.skill-lock.json"
  git -C "$REPO" add -A && git -C "$REPO" commit -qm base
}

jq_() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$@"; }

@test "preview reports the plan by name and writes nothing" {
  run "$BOOT" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tools: claudecode, codexcli, cursor"* ]] || return 1
  [[ "$output" == *"secrets moved to the secret store: KIE_API_KEY, MCP_GH_TOKEN"* ]] || return 1
  [[ "$output" == *"your own skills moving to .rulesync/skills: mine"* ]] || return 1
  [[ "$output" == *"BOOTSTRAP=preview"* ]] || return 1
  [[ "$output" != *secret-kie* && "$output" != *secret-gh* ]] || return 1
  [ ! -e "$REPO/rulesync.jsonc" ] && [ ! -e "$REPO/.rulesync" ] && [ ! -e "$XDG_CONFIG_HOME/agent-secrets" ]
}

@test "write composes shared, per-tool, and machine-only MCP servers" {
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  m="$REPO/.rulesync/mcp.jsonc"
  [ "$(jq_ "$m" 'sorted(d["mcpServers"])')" = "['codex-only', 'diff', 'gh', 'kie', 'shared-a']" ]
  [ "$(jq_ "$m" 'd["mcpServers"]["diff"]["url"]')" = "https://diff.test/claude" ]
  [ "$(jq_ "$m" 'd["codexcli"]["mcpServers"]["diff"]["url"]')" = "https://diff.test/codex" ]
  [ "$(jq_ "$REPO/.rulesync.local/mcp.jsonc" 'list(d["codexcli"]["mcpServers"])')" = "['local-tool']" ]
  [ "$(jq_ "$m" '"shared-a" in d.get("codexcli", {}).get("mcpServers", {})')" = "False" ]
}

@test "secrets move to the store and servers start through the launcher" {
  "$BOOT" --write "$REPO" >/dev/null
  m="$REPO/.rulesync/mcp.jsonc"
  [ "$(jq_ "$m" 'd["mcpServers"]["kie"]["args"][1]')" = 'exec "$HOME/.agents/bin/with-secrets" KIE_API_KEY -- npx -y kie' ]
  [ "$(jq_ "$m" 'd["mcpServers"]["kie"]["env"]')" = "{'MODE': 'x'}" ]
  [[ "$(jq_ "$m" 'd["mcpServers"]["gh"]["args"][1]')" == *"mcp-remote@0.15.2 https://gh.test/mcp --header 'Authorization:Bearer \${MCP_GH_TOKEN}' --header X-Toolsets:repos" ]] || return 1
  [[ "$(jq_ "$m" 'd["claudecode"]["mcpServers"]["gh"]["headersHelper"]')" == '"$HOME/.agents/bin/with-secrets" MCP_GH_TOKEN -- sh -c '* ]] || return 1
  grep -qx 'KIE_API_KEY=secret-kie' "$XDG_CONFIG_HOME/agent-secrets/secrets.env"
  grep -qx 'MCP_GH_TOKEN=secret-gh' "$XDG_CONFIG_HOME/agent-secrets/secrets.env"
  grep -qx 'MCP_GH_TOKEN' "$REPO/secrets.names"
  run grep -rl -e secret-kie -e secret-gh "$REPO" --exclude-dir=.git
  [ "$status" -ne 0 ]
}

@test "the Claude headersHelper prints the header JSON from the stored token" {
  "$BOOT" --write "$REPO" >/dev/null
  mkdir -p "$REPO/bin"
  cp "${BATS_TEST_DIRNAME}/../templates/with-secrets" "$REPO/bin/with-secrets"
  helper="$(jq_ "$REPO/.rulesync/mcp.jsonc" 'd["claudecode"]["mcpServers"]["gh"]["headersHelper"]')"
  run sh -c "$helper"
  [ "$status" -eq 0 ]
  [ "$output" = '{"Authorization": "Bearer secret-gh"}' ]
}

@test "hooks stay per tool and home-path hooks stay on this machine" {
  "$BOOT" --write "$REPO" >/dev/null
  h="$REPO/.rulesync/hooks.jsonc"
  [ "$(jq_ "$h" 'd["hooks"]')" = "{}" ]
  [ "$(jq_ "$h" '[e["command"] for e in d["claudecode"]["hooks"]["stop"]]')" = "['echo claude-stop']" ]
  [ "$(jq_ "$h" '[e["command"] for e in d["codexcli"]["hooks"]["stop"]]')" = "['echo codex-stop']" ]
  [ "$(jq_ "$REPO/.rulesync.local/hooks.jsonc" '[e["command"] for e in d["codexcli"]["hooks"]["stop"]]')" = "['/Users/someone/.superset/notify.sh']" ]
}

@test "skills: declared ones become sources, your own move into the source tree" {
  "$BOOT" --write "$REPO" >/dev/null
  [ "$(jq_ "$REPO/rulesync.jsonc" 'd["sources"]')" = "[{'source': 'owner/taste-repo', 'skills': ['taste'], 'path': 'skills'}]" ]
  [ "$(jq_ "$REPO/rulesync.jsonc" '(d["delete"], d["global"], d["targets"])')" = "(False, True, ['claudecode', 'codexcli', 'cursor'])" ]
  [ "$(cat "$REPO/.rulesync/skills/mine/SKILL.md")" = "mine" ]
  git -C "$REPO" ls-files --error-unmatch .rulesync/skills/mine/SKILL.md >/dev/null
  [ -d "$REPO/skills/taste" ]
}

@test "a managed repo is never bootstrapped twice, and the repo must live under HOME" {
  "$BOOT" --write "$REPO" >/dev/null
  run "$BOOT" --write "$REPO"
  [ "$output" = "BOOTSTRAP=skipped: $(cd "$REPO" && pwd -P) already has rulesync.jsonc" ]
  outside="$BATS_TEST_TMPDIR/outside"
  git init -q "$outside"
  run "$BOOT" "$outside"
  [ "$status" -eq 1 ]
  [ "$output" = "BOOTSTRAP=failed: the agents repo must live under your home folder, at a plain path" ]
}

@test "machine capture keeps this machine's extras the shared source lacks, once" {
  "$BOOT" --write "$REPO" >/dev/null
  rm -rf "$REPO/.rulesync.local"
  # This machine also has a server and a hook the shared source does not define.
  python3 - "$FIX/codexcli/mcp.jsonc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["mcpServers"]["extra"] = {"type": "http", "url": "https://extra.test"}
json.dump(d, open(sys.argv[1], "w"))
PY
  run "$BOOT" --machine "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "RULESYNC_CAPTURE=kept on this machine only: 2 server(s), 1 hook(s) (move them into .rulesync/ to share them)" ]
  [ "$(jq_ "$REPO/.rulesync.local/mcp.jsonc" 'sorted(d["codexcli"]["mcpServers"])')" = "['extra', 'local-tool']" ]
  [ "$(jq_ "$REPO/.rulesync.local/hooks.jsonc" '[e["command"] for e in d["codexcli"]["hooks"]["stop"]]')" = "['/Users/someone/.superset/notify.sh']" ]
  run "$BOOT" --machine "$REPO"
  [ "$output" = "RULESYNC_CAPTURE=skipped" ]
}

@test "importer spellings of the same server are one definition; a Claude-only one is never shared" {
  python3 - "$FIX/codexcli/mcp.jsonc" "$FIX/cursor/mcp.jsonc" <<'PY'
import json, sys
codex = json.load(open(sys.argv[1]))
codex["mcpServers"]["shared-a"]["type"] = "stdio"      # explicit where Claude leaves it implied
codex["mcpServers"]["remote"] = {"url": "https://r.test"}
json.dump(codex, open(sys.argv[1], "w"))
json.dump({"mcpServers": {"remote": {"type": "http", "url": "https://r.test"}}}, open(sys.argv[2], "w"))
PY
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  m="$REPO/.rulesync/mcp.jsonc"
  [ "$(jq_ "$m" '"shared-a" in d.get("codexcli", {}).get("mcpServers", {})')" = "False" ]
  [ "$(jq_ "$m" '"remote" in d.get("cursor", {}).get("mcpServers", {})')" = "False" ]
  # gh: the launcher is shared; Claude keeps its headersHelper variant in its own block.
  [ "$(jq_ "$m" 'd["mcpServers"]["gh"]["command"]')" = "sh" ]
  [ "$(jq_ "$m" '"headersHelper" in d["claudecode"]["mcpServers"]["gh"]')" = "True" ]
}

@test "a manifest skill without a lock entry is reported and never moved as yours" {
  rm "$REPO/.skill-lock.json"
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skills without a source in .skill-lock.json (left as they are): taste"* ]] || return 1
  [[ "$output" == *"your own skills moving to .rulesync/skills: mine"* ]] || return 1
  [ -d "$REPO/skills/taste" ] && [ ! -e "$REPO/.rulesync/skills/taste" ]
}

@test "a server inside an app bundle stays with the tools that have it" {
  python3 - "$FIX/codexcli/mcp.jsonc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["mcpServers"]["app-tool"] = {"command": "/Applications/Tool.app/Contents/MacOS/tool"}
json.dump(d, open(sys.argv[1], "w"))
PY
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  m="$REPO/.rulesync/mcp.jsonc"
  [ "$(jq_ "$m" '"app-tool" in d["mcpServers"]')" = "False" ]
  [ "$(jq_ "$m" 'd["codexcli"]["mcpServers"]["app-tool"]["command"]')" = "/Applications/Tool.app/Contents/MacOS/tool" ]
}

@test "F1: a secret that no conversion can move stops --write and names only the field" {
  python3 - "$FIX/claudecode/mcp.jsonc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["mcpServers"]["url-env"] = {"type": "http", "url": "https://u.test", "env": {"API_KEY": "leak-one"}}
json.dump(d, open(sys.argv[1], "w"))
PY
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"BOOTSTRAP=failed: SecretError: url-env.env.API_KEY holds a secret Harness cannot move"* ]] || return 1
  [[ "$output" != *leak-one* ]] || return 1
  [ ! -e "$REPO/rulesync.jsonc" ] && [ ! -e "$REPO/.rulesync" ]
}

@test "F1: an httpUrl server's token header is converted like a url one" {
  python3 - "$FIX/codexcli/mcp.jsonc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["mcpServers"]["alias"] = {"httpUrl": "https://a.test", "headers": {"Authorization": "Bearer leak-two"}}
json.dump(d, open(sys.argv[1], "w"))
PY
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  run grep -rl leak-two "$REPO" --exclude-dir=.git
  [ "$status" -ne 0 ]
  grep -qx 'MCP_ALIAS_TOKEN=leak-two' "$XDG_CONFIG_HOME/agent-secrets/secrets.env"
}

@test "F2/F3: distinct values never share a stored name, including one already stored" {
  "${BATS_TEST_DIRNAME}/../scripts/agent-secrets.py" set KIE_API_KEY <<<"already-stored" >/dev/null
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  grep -qx 'KIE_API_KEY=already-stored' "$XDG_CONFIG_HOME/agent-secrets/secrets.env"
  grep -qx 'KIE_KIE_API_KEY=secret-kie' "$XDG_CONFIG_HOME/agent-secrets/secrets.env"
  [[ "$(jq_ "$REPO/.rulesync/mcp.jsonc" 'd["mcpServers"]["kie"]["args"][1]')" == *'KIE_API_KEY="$KIE_KIE_API_KEY" exec'* ]] || return 1
}

@test "F5/F10: only Authorization schemes are split, and other server fields survive" {
  python3 - "$FIX/claudecode/mcp.jsonc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["mcpServers"]["keyed"] = {"type": "http", "url": "https://k.test", "headers": {"X-Api-Key": "abc def"}, "disabled": True}
json.dump(d, open(sys.argv[1], "w"))
PY
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  m="$REPO/.rulesync/mcp.jsonc"
  [[ "$(jq_ "$m" 'd["mcpServers"]["keyed"]["args"][1]')" == *"--header 'X-Api-Key:\${MCP_KEYED_X_API_KEY}'"* ]] || return 1
  [ "$(jq_ "$m" 'd["mcpServers"]["keyed"]["disabled"]')" = "True" ]
  run grep -rl -e "abc def" -e "abc " "$REPO/.rulesync"
  [ "$status" -ne 0 ]
}

@test "F11/F12: secrets.names gets shared names on new lines; a root-level skill is unresolved" {
  printf 'EXISTING' > "$REPO/secrets.names"
  echo '{ "skills": { "taste": { "source": "owner/taste-repo", "skillPath": "SKILL.md" } } }' > "$REPO/.skill-lock.json"
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$REPO/secrets.names")" = "EXISTING" ]
  grep -qx 'KIE_API_KEY' "$REPO/secrets.names"
  [[ "$output" == *"left as they are): taste"* ]] || return 1
}

@test "N1/N2: an env secret under an unexportable name is refused; lowercase names are listed" {
  python3 - "$FIX/claudecode/mcp.jsonc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["mcpServers"]["lower"] = {"command": "npx", "args": ["lower"], "env": {"api_key": "lower-secret"}}
json.dump(d, open(sys.argv[1], "w"))
PY
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 0 ]
  grep -qx 'api_key' "$REPO/secrets.names"
  python3 - "$FIX/codexcli/mcp.jsonc" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
d["mcpServers"]["bad"] = {"command": "npx", "env": {"X$(id)_KEY": "v1"}}
json.dump(d, open(sys.argv[1], "w"))
PY
  rm -rf "$REPO/.rulesync" "$REPO/rulesync.jsonc"
  run "$BOOT" --write "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *'BOOTSTRAP=failed: SecretError: bad.env.X$(id)_KEY is a secret under a name a launcher cannot export'* ]] || return 1
}
