#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="$REPO/plugins/harness/scripts/sync"
  SKILL="$REPO/plugins/harness/skills/sync/SKILL.md"
  HOME_DIR="$BATS_TEST_TMPDIR/home"
  AGENTS="$HOME_DIR/.agents"
  BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$HOME_DIR" "$BIN"
}

@test "sync skill is a short slash-only wrapper around the entry script" {
  run python3 - "$SKILL" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
frontmatter = text.split("---\n", 2)[1]
description = re.search(r"(?m)^description:\s*(.+)$", frontmatter).group(1).strip()
assert len(text.splitlines()) < 150
assert len(description) < 200
assert re.search(r"(?m)^name:\s*sync$", frontmatter)
assert re.search(r"(?m)^disable-model-invocation:\s*true$", frontmatter)
assert '"$harness/scripts/sync" --dry-run' in text
assert "SYNC_DECISION_REQUIRED" in text
PY
  [ "$status" -eq 0 ]

  run python3 - "$REPO/plugins/harness/skills/sync/agents/openai.yaml" <<'PY'
from pathlib import Path
import sys

assert Path(sys.argv[1]).read_text() == "policy:\n  allow_implicit_invocation: false\n"
PY
  [ "$status" -eq 0 ]
}

@test "entry script preserves helper ordering and the single final transaction" {
  run python3 - "$SCRIPT" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
required = (
    "sync-preflight.sh",
    "link-plan.sh",
    "localize-skill-overrides.py",
    "reconcile_shared_settings.py",
    "render-codex-agents.sh",
    "mcp-manifest.sh",
    "mcp-reconcile.sh",
    "mcp-secrets.sh",
    "skills-reconcile.sh",
    "skills-manifest.sh",
    "portability-lint.sh",
    "rubric-audit.sh",
    "sync-finalize.sh",
)
for name in required:
    assert name in text, name
main = text.split("def main", 1)[1]
assert main.index('"sync-preflight.sh"') < main.index("reconcile_links(")
assert main.index('"sync-finalize.sh"') > main.index("final_mcp(")
assert main.count('"sync-finalize.sh"') == 1
assert "git\", \"commit" not in text
assert "git\", \"push" not in text
PY
  [ "$status" -eq 0 ]
}

@test "dry run uses only temporary HOME and leaves repo and live roots unchanged" {
  mkdir -p "$AGENTS/claude/output-styles" "$AGENTS/config/studio-moser" "$AGENTS/codex" "$AGENTS/skills"
  git init -q -b main "$AGENTS"
  git -C "$AGENTS" config user.email test@example.com
  git -C "$AGENTS" config user.name "Harness Test"
  printf '%s\n' '{"enabledPlugins":{"harness@studio-moser":true}}' > "$AGENTS/claude/settings.json"
  printf '%s\n' '{"version":1,"servers":{}}' > "$AGENTS/mcp.manifest.json"
  printf '%s\n' '.fleet-local.json' '.skill-lock.json' > "$AGENTS/.gitignore"
  printf 'x\n' > "$AGENTS/claude/CLAUDE.md"
  printf 'x\n' > "$AGENTS/claude/statusline-command.sh"
  printf 'x\n' > "$AGENTS/claude/output-styles/style.md"
  printf 'x\n' > "$AGENTS/config/studio-moser/config"
  printf 'x\n' > "$AGENTS/codex/AGENTS.md"
  git -C "$AGENTS" add .
  git -C "$AGENTS" commit -q -m base

  cat > "$BIN/npx" <<'EOF'
#!/usr/bin/env bash
printf '[]\n'
EOF
  cat > "$BIN/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BIN/npx" "$BIN/node"

  before_tree="$(git -C "$AGENTS" status --porcelain=v1 --untracked-files=all)"
  before_head="$(git -C "$AGENTS" rev-parse HEAD)"

  run env \
    HOME="$HOME_DIR" \
    AGENTS_REPO="$AGENTS" \
    CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    CODEX_HOME="$HOME_DIR/.codex" \
    PATH="$BIN:/usr/bin:/bin" \
    "$SCRIPT" --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"Harness sync dry run"* ]] || return 1
  [[ "$output" == *"Ingest:     skipped in dry run"* ]] || return 1
  [[ "$output" == *"Committed:  skipped in dry run"* ]] || return 1
  [ "$(git -C "$AGENTS" rev-parse HEAD)" = "$before_head" ]
  [ "$(git -C "$AGENTS" status --porcelain=v1 --untracked-files=all)" = "$before_tree" ]
  [ ! -e "$HOME_DIR/.claude" ]
  [ ! -e "$HOME_DIR/.codex" ]
  [ ! -e "$HOME_DIR/.config" ]
}

@test "full entry point reconciles then performs one guarded commit and push in temporary HOME" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  mkdir -p "$AGENTS/claude/output-styles" "$AGENTS/config/studio-moser" "$AGENTS/codex" "$AGENTS/skills"
  git init -q --bare "$remote"
  git init -q -b main "$AGENTS"
  git -C "$AGENTS" config user.email test@example.com
  git -C "$AGENTS" config user.name "Harness Test"
  cat > "$AGENTS/claude/output-styles/House Style.md" <<'EOF'
---
name: House Style
---

# Local policy
EOF
  cat > "$AGENTS/claude/CLAUDE.md" <<'EOF'
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
  printf '%s\n' '{"enabledPlugins":{"harness@studio-moser":true}}' > "$AGENTS/claude/settings.json"
  printf 'exit 0\n' > "$AGENTS/claude/statusline-command.sh"
  printf 'portable\n' > "$AGENTS/config/studio-moser/config"
  printf 'keep\n' > "$AGENTS/skills/.keep"
  printf 'placeholder\n' > "$AGENTS/codex/AGENTS.md"
  git -C "$AGENTS" add .
  git -C "$AGENTS" commit -q -m base
  git -C "$AGENTS" remote add origin "$remote"
  git -C "$AGENTS" push -q -u origin main

  cat > "$BIN/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2 $3" = "plugin marketplace list" ]; then
  printf '❯ claude-plugins-official\n'
fi
exit 0
EOF
  cat > "$BIN/npx" <<'EOF'
#!/usr/bin/env bash
printf '[]\n'
EOF
  cat > "$BIN/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$BIN/claude" "$BIN/npx" "$BIN/node"

  run env \
    HOME="$HOME_DIR" \
    AGENTS_REPO="$AGENTS" \
    CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    CODEX_HOME="$HOME_DIR/.codex" \
    PATH="$BIN:/usr/bin:/bin" \
    "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Harness sync complete"* ]] || return 1
  [[ "$output" == *"SYNC_STATE=clean remote="* ]] || return 1
  [ -z "$(git -C "$AGENTS" status --porcelain=v1 --untracked-files=all)" ]
  [ "$(git -C "$AGENTS" rev-parse HEAD)" = "$(git --git-dir="$remote" rev-parse refs/heads/main)" ]
  [ -L "$HOME_DIR/.claude/skills" ]
  [ -L "$HOME_DIR/.codex/AGENTS.md" ]
}

@test "occupied first-run repository is refused without explicit replacement" {
  mkdir -p "$AGENTS"
  printf 'keep me\n' > "$AGENTS/local.txt"

  run env \
    HOME="$HOME_DIR" \
    AGENTS_REPO="$AGENTS" \
    CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    CODEX_HOME="$HOME_DIR/.codex" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" --source existing --repo-url "$BATS_TEST_TMPDIR/private.git"

  [ "$status" -eq 22 ]
  [[ "$output" == *"SYNC_REFUSED=repository path is occupied"* ]] || return 1
  [ "$(cat "$AGENTS/local.txt")" = "keep me" ]
  [ -z "$(find "$HOME_DIR" -maxdepth 1 -name 'agents-config-backup-*.tar.gz' -print -quit)" ]
}

@test "missing first-run source exits with the typed decision code and writes nothing" {
  run env \
    HOME="$HOME_DIR" \
    AGENTS_REPO="$AGENTS" \
    CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    CODEX_HOME="$HOME_DIR/.codex" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT"

  [ "$status" -eq 20 ]
  [[ "$output" == *"SYNC_DECISION_REQUIRED=first-run source of truth"* ]] || return 1
  [ ! -e "$AGENTS" ]
}
