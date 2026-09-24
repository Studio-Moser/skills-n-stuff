#!/usr/bin/env bats

setup() {
  SCRIPTS="${BATS_TEST_DIRNAME}/../scripts"
  REMOTE="${BATS_TEST_TMPDIR}/remote.git"
  REPO="${BATS_TEST_TMPDIR}/agents"
  UPDATER="${BATS_TEST_TMPDIR}/updater"
  RUNTIME_MCP="${BATS_TEST_TMPDIR}/mcp.json"

  git init -q --bare "$REMOTE"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name "Harness Test"
  mkdir -p "$REPO/claude/output-styles"
  cat > "$REPO/claude/output-styles/House Style.md" <<'EOF'
---
name: House Style
---

# Local policy
EOF
  cat > "$REPO/claude/CLAUDE.md" <<'EOF'
# Rules

1. **No hallucination** — If you don't know, say so.
2. **File naming** — Use Title Case.

## Engineering discipline

Keep the change small.

<!-- shelby:bootstrap start -->
## Shelby memory
Use optional memory.
<!-- shelby:bootstrap end -->
EOF
  cat > "$REPO/claude/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "harness@studio-moser": true
  }
}
EOF
  cat > "$RUNTIME_MCP" <<'EOF'
{
  "mcpServers": {
    "portable-memory": {
      "command": "node"
    }
  }
}
EOF
  git -C "$REPO" add .
  git -C "$REPO" commit -q -m base
  git -C "$REPO" remote add origin "$REMOTE"
  git -C "$REPO" push -q -u origin main
  git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main

  git clone -q "$REMOTE" "$UPDATER"
  git -C "$UPDATER" config user.email updater@example.com
  git -C "$UPDATER" config user.name "Remote Updater"
  printf '\nRemote-only policy.\n' >> "$UPDATER/claude/output-styles/House Style.md"
  cat > "$UPDATER/claude/settings.json" <<'EOF'
{
  "enabledPlugins": {
    "machine@studio-moser": true
  }
}
EOF
  git -C "$UPDATER" add .
  git -C "$UPDATER" commit -q -m "remote config update"
  git -C "$UPDATER" push -q
}

@test "ahead remote is ingested before every reconciliation and derived output" {
  ! grep -qF "Remote-only policy." "$REPO/claude/output-styles/House Style.md"

  run "$SCRIPTS/sync-preflight.sh" "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SYNC_PREFLIGHT=ready"* ]] || return 1
  grep -qF "Remote-only policy." "$REPO/claude/output-styles/House Style.md"

  "$SCRIPTS/reconcile_shared_settings.py" "$REPO/claude/settings.json"
  "$SCRIPTS/mcp-manifest.sh" "$RUNTIME_MCP" "$REPO/mcp.manifest.json"
  "$SCRIPTS/render-codex-agents.sh" "$REPO"
  "$SCRIPTS/portability-lint.sh" "$REPO"

  run "$SCRIPTS/sync-finalize.sh" "$REPO" "harness: sync complete workflow"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SYNC_STATE=clean"* ]] || return 1

  run git --git-dir="$REMOTE" show main:codex/AGENTS.md
  [ "$status" -eq 0 ]
  [[ "$output" == *"Remote-only policy."* ]] || return 1

  run git --git-dir="$REMOTE" show main:claude/settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"harness@studio-moser": true'* ]] || return 1
  [[ "$output" != *"machine@studio-moser"* ]] || return 1

  run git --git-dir="$REMOTE" show main:mcp.manifest.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"portable-memory"'* ]] || return 1
  [[ "$output" == *'"machines"'* ]] || return 1
}

@test "remote movement plus local work stops before ingestion or reconciliation" {
  before="$(git -C "$REPO" rev-parse HEAD)"
  printf 'local work\n' > "$REPO/local-change.txt"

  run "$SCRIPTS/sync-preflight.sh" "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"remote moved while local work exists"* ]] || return 1
  [[ "$output" == *"rerun sync"* ]] || return 1
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$before" ]
  ! grep -qF "Remote-only policy." "$REPO/claude/output-styles/House Style.md"
  [ -f "$REPO/local-change.txt" ]
}

@test "local work plus an already-fetched ahead remote still stops before writers" {
  git -C "$REPO" fetch -q origin main
  before="$(git -C "$REPO" rev-parse HEAD)"
  printf 'local work\n' > "$REPO/local-change.txt"

  run "$SCRIPTS/sync-preflight.sh" "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"remote has commits not present locally while local work exists"* ]] || return 1
  [[ "$output" == *"rerun sync"* ]] || return 1
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$before" ]
  ! grep -qF "Remote-only policy." "$REPO/claude/output-styles/House Style.md"
  [ -f "$REPO/local-change.txt" ]
}

@test "preflight rejects a distinct push URL before ingesting the fetch remote" {
  push_remote="$BATS_TEST_TMPDIR/push-remote.git"
  git init -q --bare "$push_remote"
  git -C "$REPO" remote set-url --push origin "$push_remote"
  before="$(git -C "$REPO" rev-parse HEAD)"

  run "$SCRIPTS/sync-preflight.sh" "$REPO"

  [ "$status" -eq 1 ]
  [[ "$output" == *"distinct push URL"* ]] || return 1
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$before" ]
  ! git --git-dir="$push_remote" show-ref --verify --quiet refs/heads/main
}

@test "loose-config adoption preflights exactly once before its first repo writer" {
  script="$SCRIPTS/sync"
  run python3 - "$script" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
main = text.split("def main", 1)[1]
preflight = main.index('helper(scripts, "sync-preflight.sh")')
adoption = main.index("adopt_loose(")
links = main.index("reconcile_links(")
assert preflight < adoption < links
assert main.count('helper(scripts, "sync-preflight.sh")') == 1
PY
  [ "$status" -eq 0 ]
}
