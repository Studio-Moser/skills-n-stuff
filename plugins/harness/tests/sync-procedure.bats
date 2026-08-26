#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SKILL="$REPO/plugins/harness/skills/sync/SKILL.md"
}

extract_first_bash_block_after() {
  local marker="$1"
  local target="$2"
  python3 - "$SKILL" "$marker" "$target" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text().split(sys.argv[2], 1)[1]
match = re.search(r"```bash\n(.*?)\n```", text, re.DOTALL)
assert match, f"bash block is missing after {sys.argv[2]}"
Path(sys.argv[3]).write_text(match.group(1) + "\n")
PY
}

@test "sync performs every reconciliation before one guarded final transaction" {
  run python3 - "$SKILL" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
failures = []
required = (
    "sync-preflight.sh",
    "reconcile_shared_settings.py",
    "mcp-manifest.sh",
    "skills-manifest.sh",
    "render-codex-agents.sh",
    "portability-lint.sh",
    "sync-finalize.sh",
)
for value in required:
    if value not in text:
        failures.append(f"missing sync operation: {value}")

preflight = text.find('"$harness/scripts/sync-preflight.sh"')
first_writer = text.find("## Phase 1: Link check")
if preflight < 0 or first_writer < 0 or preflight > first_writer:
    failures.append("remote preflight does not precede write-producing reconciliation")

finalizer = text.find('"$harness/scripts/sync-finalize.sh"')
for value in required[1:-1]:
    position = text.rfind(value)
    if position < 0 or position > finalizer:
        failures.append(f"{value} is not completed before finalization")

for direct in ('git -C "$repo" commit', 'git -C "$repo" push'):
    if direct in text:
        failures.append(f"direct transaction bypass remains: {direct}")
for phrase in (
    "at most one commit",
    "exactly one push",
    "never pulls",
    "final clean worktree",
    "remote SHA",
    "staged secret",
    "machine-local state",
):
    if phrase.lower() not in text.lower():
        failures.append(f"missing final gate: {phrase}")

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "every shell block resolves the repo it uses" {
  run python3 - "$SKILL" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
blocks = re.findall(r"```(?:bash|sh)\n(.*?)\n```", text, re.DOTALL)
failures = []
assignment = re.compile(r'^repo="\$\{AGENTS_REPO:-\$HOME/\.agents\}"', re.MULTILINE)
for number, block in enumerate(blocks, 1):
    if "$repo" in block and not assignment.search(block):
        first = block.strip().splitlines()[0] if block.strip() else "<empty>"
        failures.append(f"block {number} uses stale repo: {first}")
assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}

@test "final validation preserves Phase 2.6 skill state when Node is unavailable" {
  phase="$BATS_TEST_TMPDIR/phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  harness="$BATS_TEST_TMPDIR/harness"
  bin="$BATS_TEST_TMPDIR/bin"
  manifest_marker="$BATS_TEST_TMPDIR/manifest-ran"
  finalizer_marker="$BATS_TEST_TMPDIR/finalizer-ran"
  mkdir -p "$agents" "$harness/scripts" "$bin"

  python3 - "$SKILL" "$phase" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text().split("## Phase 3.75:", 1)[1]
match = re.search(r"```bash\n(.*?)\n```", text, re.DOTALL)
assert match, "Phase 3.75 bash block is missing"
Path(sys.argv[2]).write_text(match.group(1) + "\n")
PY

  for name in localize-skill-overrides.py reconcile_shared_settings.py mcp-manifest.sh render-codex-agents.sh link-plan.sh portability-lint.sh; do
    cat > "$harness/scripts/$name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$harness/scripts/$name"
  done
  cat > "$harness/scripts/skills-manifest.sh" <<'EOF'
#!/usr/bin/env bash
touch "$MANIFEST_MARKER"
exit 86
EOF
  chmod +x "$harness/scripts/skills-manifest.sh"
  cat > "$harness/scripts/sync-finalize.sh" <<'EOF'
#!/usr/bin/env bash
touch "$FINALIZER_MARKER"
exit 0
EOF
  chmod +x "$harness/scripts/sync-finalize.sh"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    MANIFEST_MARKER="$manifest_marker" \
    FINALIZER_MARKER="$finalizer_marker" \
    PATH="$bin:/usr/bin:/bin" \
    /bin/bash "$phase"

  [ "$status" -eq 0 ]
  [ ! -e "$manifest_marker" ]
  [ -e "$finalizer_marker" ]
}

@test "a final validation generator failure stops before the transaction" {
  phase="$BATS_TEST_TMPDIR/phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  harness="$BATS_TEST_TMPDIR/harness"
  finalizer_marker="$BATS_TEST_TMPDIR/finalizer-ran"
  mkdir -p "$agents" "$harness/scripts"

  python3 - "$SKILL" "$phase" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text().split("## Phase 3.75:", 1)[1]
match = re.search(r"```bash\n(.*?)\n```", text, re.DOTALL)
assert match, "Phase 3.75 bash block is missing"
Path(sys.argv[2]).write_text(match.group(1) + "\n")
PY

  for name in localize-skill-overrides.py reconcile_shared_settings.py mcp-manifest.sh link-plan.sh portability-lint.sh; do
    cat > "$harness/scripts/$name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$harness/scripts/$name"
  done
  cat > "$harness/scripts/render-codex-agents.sh" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
  chmod +x "$harness/scripts/render-codex-agents.sh"
  cat > "$harness/scripts/sync-finalize.sh" <<'EOF'
#!/usr/bin/env bash
touch "$FINALIZER_MARKER"
exit 0
EOF
  chmod +x "$harness/scripts/sync-finalize.sh"
  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    FINALIZER_MARKER="$finalizer_marker" \
    bash "$phase"

  [ "$status" -eq 23 ]
  [ ! -e "$finalizer_marker" ]
}

@test "the dry-run MCP verifier executes against names-only and the custom Claude user registry" {
  phase="$BATS_TEST_TMPDIR/mcp-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$agents" "$claude" "$harness/scripts"
  printf 'portable-memory\n' > "$agents/mcp.manifest"
  cat > "$claude/.claude.json" <<'EOF'
{
  "mcpServers": {
    "portable-memory": {
      "command": "sh",
      "env": {"TOKEN": "do-not-print"}
    }
  },
  "projects": {
    "/tmp/project": {
      "mcpServers": {
        "project-only": {
          "command": "sh"
        }
      }
    }
  }
}
EOF
  printf '{}\n' > "$claude/settings.local.json"
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"

  extract_first_bash_block_after \
    "### MCP servers — verify, report, never auto-install" \
    "$phase"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_STATE=1 ok"* ]] || return 1
  [[ "$output" != *"project-only"* ]] || return 1
  [[ "$output" != *"do-not-print"* ]]
}

@test "the dry-run MCP verifier uses the default Claude user registry" {
  phase="$BATS_TEST_TMPDIR/mcp-default-phase.sh"
  home="$BATS_TEST_TMPDIR/home"
  agents="$BATS_TEST_TMPDIR/agents"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$home/.claude" "$agents" "$harness/scripts"
  printf 'portable-memory\n' > "$agents/mcp.manifest"
  printf '%s\n' '{"mcpServers":{"portable-memory":{"command":"sh"}}}' > "$home/.claude.json"
  printf '{}\n' > "$home/.claude/settings.local.json"
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"

  extract_first_bash_block_after \
    "### MCP servers — verify, report, never auto-install" \
    "$phase"

  run env -u CLAUDE_CONFIG_DIR \
    HOME="$home" \
    AGENTS_REPO="$agents" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_STATE=1 ok"* ]] || return 1
}

@test "the dry-run MCP verifier reports a missing Claude user registry without leaking state" {
  phase="$BATS_TEST_TMPDIR/mcp-missing-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$agents" "$claude" "$harness/scripts"
  printf 'portable-memory\n' > "$agents/mcp.manifest"
  printf '{}\n' > "$claude/settings.local.json"
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"

  extract_first_bash_block_after \
    "### MCP servers — verify, report, never auto-install" \
    "$phase"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_STATE=0 ok, 1 unresolved"* ]] || return 1
  [[ "$output" == *"MCP_FINDING=portable-memory not configured on this machine"* ]]
}

@test "MCP inventory generation reads the Claude user registry and only localizes the legacy file" {
  phase="$BATS_TEST_TMPDIR/mcp-generation-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  input_marker="$BATS_TEST_TMPDIR/mcp-input"
  mkdir -p "$agents/claude" "$claude" "$harness/scripts"
  git init -q -b main "$agents"
  git -C "$agents" config user.email test@example.com
  git -C "$agents" config user.name "Harness Test"
  printf '%s\n' '{"mcpServers":{"legacy":{"command":"sh","env":{"TOKEN":"legacy-secret"}}}}' > "$agents/claude/mcp.json"
  printf '\n' > "$agents/.gitignore"
  git -C "$agents" add .gitignore claude/mcp.json
  git -C "$agents" commit -q -m base
  ln -s "$agents/claude/mcp.json" "$claude/mcp.json"
  printf '%s\n' '{"mcpServers":{"portable-memory":{"command":"sh","env":{"TOKEN":"user-secret"}}}}' > "$claude/.claude.json"
  before="$(shasum -a 256 "$claude/.claude.json")"
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$MCP_INPUT_MARKER"
printf 'portable-memory\n' > "$2"
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"

  extract_first_bash_block_after \
    "### 2.3 Generate the portable MCP inventory and clean up the legacy tracked file" \
    "$phase"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    MCP_INPUT_MARKER="$input_marker" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [ "$(cat "$input_marker")" = "$claude/.claude.json" ]
  [ "$(shasum -a 256 "$claude/.claude.json")" = "$before" ]
  [ -f "$claude/mcp.json" ]
  [ ! -L "$claude/mcp.json" ]
  ! git -C "$agents" ls-files --error-unmatch claude/mcp.json >/dev/null 2>&1
  grep -qxF 'claude/mcp.json' "$agents/.gitignore"
  [[ "$output" != *"legacy-secret"* ]] || return 1
  [[ "$output" != *"user-secret"* ]]
}

@test "MCP inventory generation reports a missing Claude user registry" {
  phase="$BATS_TEST_TMPDIR/mcp-generation-missing-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$agents" "$claude" "$harness/scripts"
  git init -q -b main "$agents"
  printf '\n' > "$agents/.gitignore"
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
exit 99
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"
  extract_first_bash_block_after \
    "### 2.3 Generate the portable MCP inventory and clean up the legacy tracked file" \
    "$phase"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_STATE=not configured"* ]] || return 1
  [ ! -e "$agents/mcp.manifest" ]
}

@test "failed MCP inventory generation stops before legacy cleanup" {
  phase="$BATS_TEST_TMPDIR/mcp-generation-failure-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$agents/claude" "$claude" "$harness/scripts"
  git init -q -b main "$agents"
  git -C "$agents" config user.email test@example.com
  git -C "$agents" config user.name "Harness Test"
  printf 'legacy\n' > "$agents/claude/mcp.json"
  printf '\n' > "$agents/.gitignore"
  git -C "$agents" add .gitignore claude/mcp.json
  git -C "$agents" commit -q -m base
  printf '%s\n' '{"mcpServers":{"portable-memory":{"command":"sh"}}}' > "$claude/.claude.json"
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
exit 23
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"
  extract_first_bash_block_after \
    "### 2.3 Generate the portable MCP inventory and clean up the legacy tracked file" \
    "$phase"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    bash "$phase"

  [ "$status" -eq 23 ]
  git -C "$agents" ls-files --error-unmatch claude/mcp.json >/dev/null
  ! grep -qxF 'claude/mcp.json' "$agents/.gitignore"
}

@test "final validation regenerates MCP inventory from the custom Claude user registry" {
  phase="$BATS_TEST_TMPDIR/mcp-final-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  input_marker="$BATS_TEST_TMPDIR/mcp-input"
  mkdir -p "$agents" "$claude" "$harness/scripts"
  printf '%s\n' '{"mcpServers":{"portable-memory":{"command":"sh"}}}' > "$claude/.claude.json"

  extract_first_bash_block_after "## Phase 3.75:" "$phase"

  for name in localize-skill-overrides.py reconcile_shared_settings.py render-codex-agents.sh link-plan.sh portability-lint.sh sync-finalize.sh; do
    cat > "$harness/scripts/$name" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$harness/scripts/$name"
  done
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$MCP_INPUT_MARKER"
exit 0
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    MCP_INPUT_MARKER="$input_marker" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [ "$(cat "$input_marker")" = "$claude/.claude.json" ]
}

@test "skills reconciliation rejects parseable stdout from a failed npx command" {
  phase="$BATS_TEST_TMPDIR/skills-reconcile-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  harness="$BATS_TEST_TMPDIR/harness"
  bin="$BATS_TEST_TMPDIR/bin"
  reconcile_marker="$BATS_TEST_TMPDIR/reconcile-ran"
  mkdir -p "$agents" "$harness/scripts" "$bin"

  python3 - "$SKILL" "$phase" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text().split(
    "### 1. Read the manifest, compare to reality", 1
)[1]
match = re.search(r"```bash\n(.*?)\n```", text, re.DOTALL)
assert match, "Phase 2.6 reconciliation bash block is missing"
Path(sys.argv[2]).write_text(match.group(1) + "\n")
PY

  cat > "$bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '[]\n'
exit 23
EOF
  chmod +x "$bin/npx"
  cat > "$harness/scripts/skills-reconcile.sh" <<'EOF'
#!/usr/bin/env bash
touch "$RECONCILE_MARKER"
EOF
  chmod +x "$harness/scripts/skills-reconcile.sh"

  run env \
    HOME="$BATS_TEST_TMPDIR/home" \
    AGENTS_REPO="$agents" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    RECONCILE_MARKER="$reconcile_marker" \
    PATH="$bin:/usr/bin:/bin" \
    /bin/bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILLS_STATE=failed"* ]] || return 1
  [[ "$output" == *"exited non-zero"* ]] || return 1
  [ ! -e "$reconcile_marker" ]
}

@test "manifest regeneration preserves the manifest when npx fails with parseable stdout" {
  phase="$BATS_TEST_TMPDIR/skills-manifest-phase.sh"
  agents="$BATS_TEST_TMPDIR/home/.agents"
  bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$agents/skills/replacement" "$bin"
  printf 'existing\tacme/existing\n' > "$agents/skills.manifest"
  before="$(cat "$agents/skills.manifest")"

  python3 - "$SKILL" "$phase" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text().split(
    "### 3. Regenerate — only after step 2 has run", 1
)[1]
match = re.search(r"```bash\n(.*?)\n```", text, re.DOTALL)
assert match, "Phase 2.6 manifest bash block is missing"
block = match.group(1).replace(" <failed-name> <failed-name> ...", "")
Path(sys.argv[2]).write_text(block + "\n")
PY

  cat > "$bin/npx" <<EOF
#!/usr/bin/env bash
printf '%s\n' '[{"name":"replacement","source":"acme/replacement","path":"$agents/skills/replacement"}]'
exit 23
EOF
  chmod +x "$bin/npx"

  run env \
    HOME="$BATS_TEST_TMPDIR/home" \
    AGENTS_REPO="$agents" \
    CLAUDE_PLUGIN_ROOT="$REPO/plugins/harness" \
    PATH="$bin:/usr/bin:/bin" \
    /bin/bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILLS_STATE=failed"* ]] || return 1
  [[ "$output" == *"manifest not regenerated"* ]] || return 1
  [ "$(cat "$agents/skills.manifest")" = "$before" ]
}
