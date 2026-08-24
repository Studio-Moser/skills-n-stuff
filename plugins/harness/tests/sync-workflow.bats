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
  "$SCRIPTS/mcp-manifest.sh" "$RUNTIME_MCP" "$REPO/mcp.manifest"
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

  run git --git-dir="$REMOTE" show main:mcp.manifest
  [ "$status" -eq 0 ]
  [ "$output" = "portable-memory" ]
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
  loose_repo="$BATS_TEST_TMPDIR/loose-agents"
  loose_remote="$BATS_TEST_TMPDIR/loose-remote.git"
  phase="$BATS_TEST_TMPDIR/loose-preflight.sh"
  harness="$BATS_TEST_TMPDIR/harness"
  count_file="$BATS_TEST_TMPDIR/preflight-count"
  skill="$SCRIPTS/../skills/sync/SKILL.md"
  mkdir -p "$loose_repo" "$harness/scripts"
  git init -q --bare "$loose_remote"
  git init -q -b main "$loose_repo"
  git -C "$loose_repo" config user.email test@example.com
  git -C "$loose_repo" config user.name "Harness Test"
  git -C "$loose_repo" remote add origin "$loose_remote"

  python3 - "$skill" "$phase" <<'PY'
from pathlib import Path
import re
import sys

text = Path(sys.argv[1]).read_text()
loose = text.split("For loose configuration:", 1)[1].split(
    "## Phase 0.5:", 1
)[0]
assert "Continue to Phase 0.5" in loose
assert "Continue to Phase 1" not in loose
call = '"$harness/scripts/sync-preflight.sh" "$repo"'
assert text.count(call) == 1
phase = text.split("## Phase 0.5:", 1)[1]
match = re.search(r"```bash\n(.*?)\n```", phase, re.DOTALL)
assert match, "Phase 0.5 bash block is missing"
Path(sys.argv[2]).write_text(match.group(1) + "\n")
PY

  cat > "$harness/scripts/sync-preflight.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
[ ! -f "$PREFLIGHT_COUNT" ] || count="$(cat "$PREFLIGHT_COUNT")"
printf '%s\n' "$((count + 1))" > "$PREFLIGHT_COUNT"
exec "$REAL_PREFLIGHT" "$@"
EOF
  chmod +x "$harness/scripts/sync-preflight.sh"

  run env \
    AGENTS_REPO="$loose_repo" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    PREFLIGHT_COUNT="$count_file" \
    REAL_PREFLIGHT="$SCRIPTS/sync-preflight.sh" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [ "$(cat "$count_file")" = 1 ]

  mkdir -p "$loose_repo/claude/output-styles"
  cat > "$loose_repo/claude/output-styles/House Style.md" <<'EOF'
---
name: House Style
---

# Local policy
EOF
  cat > "$loose_repo/claude/CLAUDE.md" <<'EOF'
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
  printf '%s\n' '{"enabledPlugins":{"machine@studio-moser":true}}' > "$loose_repo/claude/settings.json"

  "$SCRIPTS/reconcile_shared_settings.py" "$loose_repo/claude/settings.json"
  "$SCRIPTS/render-codex-agents.sh" "$loose_repo"
  "$SCRIPTS/portability-lint.sh" "$loose_repo"

  run "$SCRIPTS/sync-finalize.sh" "$loose_repo" "harness: adopt loose config"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SYNC_STATE=clean"* ]] || return 1
  [ "$(cat "$count_file")" = 1 ]
  [ -z "$(git -C "$loose_repo" status --porcelain)" ]
  run git --git-dir="$loose_remote" show main:claude/settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"harness@studio-moser": true'* ]] || return 1
}
