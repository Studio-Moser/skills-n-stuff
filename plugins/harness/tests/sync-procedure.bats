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

make_sync_repo() {
  local target="$1" remote="$2"
  mkdir -p "$target/claude/output-styles" "$target/config/studio-moser" "$target/codex" "$target/skills"
  git init -q --bare "$remote"
  git init -q -b main "$target"
  git -C "$target" config user.email test@example.com
  git -C "$target" config user.name "Harness Test"
  cat > "$target/claude/output-styles/House Style.md" <<'EOF'
---
name: House Style
---

# Local policy
EOF
  cat > "$target/claude/CLAUDE.md" <<'EOF'
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
  printf '%s\n' '{"enabledPlugins":{"harness@studio-moser":true}}' > "$target/claude/settings.json"
  printf 'exit 0\n' > "$target/claude/statusline-command.sh"
  printf 'portable\n' > "$target/config/studio-moser/config"
  printf 'keep\n' > "$target/skills/.keep"
  printf 'placeholder\n' > "$target/codex/AGENTS.md"
  git -C "$target" add .
  git -C "$target" commit -q -m base
  git -C "$target" remote add origin "$remote"
  git -C "$target" push -q -u origin main
}

install_sync_stubs() {
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
  [ ! -e "$HOME_DIR/npx-called" ]
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
  [[ "$output" == *"Machines:   skipped: not requested"* ]] || return 1
}

@test "nested agents path is refused without changing the outer index or remote" {
  outer="$BATS_TEST_TMPDIR/private-project"
  seed="$BATS_TEST_TMPDIR/seed"
  remote="$BATS_TEST_TMPDIR/outer.git"
  make_sync_repo "$outer" "$remote"
  make_sync_repo "$seed" "$BATS_TEST_TMPDIR/seed.git"
  nested="$outer/config/agents"
  mkdir -p "$nested/config"
  cp -R "$seed/claude" "$seed/codex" "$seed/skills" "$nested/"
  cp -R "$seed/config/studio-moser" "$nested/config/"
  printf 'staged and unrelated\n' > "$outer/staged.txt"
  printf 'untracked and unrelated\n' > "$outer/untracked.txt"
  git -C "$outer" add staged.txt
  before_index="$(git -C "$outer" diff --cached --binary)"
  before_remote="$(git --git-dir="$remote" rev-parse refs/heads/main)"

  run env \
    HOME="$HOME_DIR" \
    AGENTS_REPO="$nested" \
    CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    CODEX_HOME="$HOME_DIR/.codex" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT"

  [ "$status" -eq 22 ]
  [[ "$output" == *"SYNC_REFUSED=agents repository path is nested inside another Git worktree"* ]] || return 1
  [ "$(git -C "$outer" diff --cached --binary)" = "$before_index" ]
  [ "$(git --git-dir="$remote" rev-parse refs/heads/main)" = "$before_remote" ]
  [ -f "$outer/untracked.txt" ]
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

@test "replacement refuses root home live roots and every overlap before backup" {
  run python3 - "$SCRIPT" "$HOME_DIR" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys

sync = SourceFileLoader("harness_sync", sys.argv[1]).load_module()
home = Path(sys.argv[2])
roots = {"claude": home / ".claude", "config": home / ".config", "codex": home / ".codex"}
targets = [
    Path("/"), home, home.parent,
    roots["claude"], roots["claude"] / "nested",
    roots["config"], roots["config"] / "nested",
    roots["codex"], roots["codex"] / "nested",
    home / ".config-parent",
]
for target in targets[:-1]:
    try:
        sync.validate_repo_replacement(target, home, roots)
    except sync.Stop as error:
        assert error.code == 22, (target, error.code)
    else:
        raise AssertionError(f"accepted dangerous target {target}")
sync.validate_repo_replacement(targets[-1], home, roots)
PY
  [ "$status" -eq 0 ]
  [ -z "$(find "$HOME_DIR" -maxdepth 1 -name 'agents-config-backup-*.tar.gz' -print -quit)" ]
}

@test "secure backup is mode 0600 includes git repo and legacy MCP and removes a failed partial" {
  mkdir -p "$AGENTS/.git" "$HOME_DIR/.claude"
  printf 'repo data\n' > "$AGENTS/work.txt"
  printf 'secret\n' > "$HOME_DIR/.claude/mcp.json"
  run env HOME="$HOME_DIR" python3 - "$SCRIPT" "$HOME_DIR" "$AGENTS" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import os, stat, sys, tarfile

sync = SourceFileLoader("harness_sync", sys.argv[1]).load_module()
home, repo = map(Path, sys.argv[2:])
archive = sync.backup_live(home, home / ".claude", home / ".config", home / ".codex", repo)
assert stat.S_IMODE(archive.stat().st_mode) == 0o600
with tarfile.open(archive) as bundle:
    names = bundle.getnames()
assert "claude/mcp.json" in names
assert "agents-repo/work.txt" in names

original = sync.tarfile.open
def fail_open(*args, **kwargs):
    fileobj = kwargs["fileobj"]
    assert stat.S_IMODE(os.fstat(fileobj.fileno()).st_mode) == 0o600
    raise OSError("injected archive failure")
sync.tarfile.open = fail_open
try:
    sync.backup_live(home, home / ".claude", home / ".config", home / ".codex", repo)
except sync.Stop as error:
    assert error.code == 1
else:
    raise AssertionError("injected failure did not propagate")
finally:
    sync.tarfile.open = original
assert not list(home.glob(".agents-config-backup-*.tar.gz.*"))
PY
  [ "$status" -eq 0 ]
}

@test "repository backup preserves an external directory symlink without archiving its contents" {
  outside="$BATS_TEST_TMPDIR/outside"
  mkdir -p "$AGENTS" "$outside"
  printf 'must stay outside\n' > "$outside/private-key"
  ln -s "$outside" "$AGENTS/secrets"

  run env HOME="$HOME_DIR" python3 - "$SCRIPT" "$HOME_DIR" "$AGENTS" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys, tarfile

sync = SourceFileLoader("harness_sync", sys.argv[1]).load_module()
home, repo = map(Path, sys.argv[2:])
archive = sync.backup_live(home, home / ".claude", home / ".config", home / ".codex", repo)
with tarfile.open(archive) as bundle:
    member = bundle.getmember("agents-repo/secrets")
    assert member.issym()
    assert "agents-repo/secrets/private-key" not in bundle.getnames()
PY
  [ "$status" -eq 0 ]
}

@test "concurrent backup publication never overwrites a colliding final name" {
  mkdir -p "$AGENTS"
  printf 'repo data\n' > "$AGENTS/work.txt"

  run env HOME="$HOME_DIR" python3 - "$SCRIPT" "$HOME_DIR" "$AGENTS" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys, threading

sync = SourceFileLoader("harness_sync", sys.argv[1]).load_module()
home, repo = map(Path, sys.argv[2:])
barrier = threading.Barrier(2)
original_mkstemp = sync.tempfile.mkstemp

class FixedDatetime:
    @classmethod
    def now(cls):
        return cls()

    def strftime(self, _format):
        return "20260102-030405"

def synchronized_mkstemp(*args, **kwargs):
    result = original_mkstemp(*args, **kwargs)
    barrier.wait(timeout=5)
    return result

sync.datetime = FixedDatetime
sync.tempfile.mkstemp = synchronized_mkstemp
existing = home / "agents-config-backup-20260102-030405.tar.gz"
existing.write_bytes(b"pre-existing backup")
archives = []
errors = []

def create_backup():
    try:
        archives.append(sync.backup_live(home, home / ".claude", home / ".config", home / ".codex", repo))
    except BaseException as error:
        errors.append(error)

threads = [threading.Thread(target=create_backup) for _ in range(2)]
for thread in threads:
    thread.start()
for thread in threads:
    thread.join(timeout=10)
assert all(not thread.is_alive() for thread in threads)
assert not errors, errors
assert len(set(archives)) == 2, archives
assert existing.read_bytes() == b"pre-existing backup"
assert len(list(home.glob("agents-config-backup-20260102-030405*.tar.gz"))) == 3
PY
  [ "$status" -eq 0 ]
}

@test "clone failure preserves clean occupied repo live link and remote SHA" {
  old_remote="$BATS_TEST_TMPDIR/old.git"
  git init -q --bare "$old_remote"
  git init -q -b main "$AGENTS"
  git -C "$AGENTS" config user.email test@example.com
  git -C "$AGENTS" config user.name "Harness Test"
  printf 'old\n' > "$AGENTS/kept.txt"
  git -C "$AGENTS" add kept.txt
  git -C "$AGENTS" commit -q -m old
  git -C "$AGENTS" remote add origin "$old_remote"
  git -C "$AGENTS" push -q -u origin main
  old_sha="$(git -C "$AGENTS" rev-parse HEAD)"
  mkdir -p "$HOME_DIR/.claude"
  ln -s "$AGENTS/kept.txt" "$HOME_DIR/.claude/CLAUDE.md"

  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="/usr/bin:/bin" \
    "$SCRIPT" --source existing --repo-url "$BATS_TEST_TMPDIR/missing.git" --replace-repo-path

  [ "$status" -eq 1 ]
  [[ "$output" == *"existing repository was left unchanged"* ]] || return 1
  [ "$(git -C "$AGENTS" rev-parse HEAD)" = "$old_sha" ]
  [ "$(git --git-dir="$old_remote" rev-parse refs/heads/main)" = "$old_sha" ]
  [ "$(cat "$HOME_DIR/.claude/CLAUDE.md")" = old ]
}

@test "injected staged-swap failure restores the occupied repository" {
  new_remote="$BATS_TEST_TMPDIR/new.git"
  seed="$BATS_TEST_TMPDIR/seed"
  git init -q --bare "$new_remote"
  git init -q -b main "$seed"
  git -C "$seed" config user.email test@example.com
  git -C "$seed" config user.name "Harness Test"
  printf 'new\n' > "$seed/new.txt"
  git -C "$seed" add new.txt
  git -C "$seed" commit -q -m new
  git -C "$seed" remote add origin "$new_remote"
  git -C "$seed" push -q origin main
  mkdir -p "$AGENTS"
  printf 'old\n' > "$AGENTS/old.txt"

  run python3 - "$SCRIPT" "$new_remote" "$AGENTS" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys

sync = SourceFileLoader("harness_sync", sys.argv[1]).load_module()
remote, repo = sys.argv[2], Path(sys.argv[3])
original = sync.os.replace
def injected(source, target):
    source, target = Path(source), Path(target)
    if target == repo and ".clone." in source.name:
        raise OSError("injected swap failure")
    return original(source, target)
sync.os.replace = injected
try:
    sync.clone_and_replace(remote, repo)
except sync.Stop as error:
    assert error.code == 1
else:
    raise AssertionError("injected swap failure did not propagate")
assert (repo / "old.txt").read_text() == "old\n"
assert not (repo / "new.txt").exists()
assert not list(repo.parent.glob(f".{repo.name}.clone.*"))
PY
  [ "$status" -eq 0 ]
}

@test "injected live-link swap failure restores the original path" {
  live="$HOME_DIR/.claude/settings.json"
  want="$AGENTS/claude/settings.json"
  mkdir -p "$(dirname "$live")" "$(dirname "$want")"
  printf 'live\n' > "$live"
  printf 'repo\n' > "$want"

  run python3 - "$SCRIPT" "$live" "$want" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys

sync = SourceFileLoader("harness_sync", sys.argv[1]).load_module()
live, want = map(Path, sys.argv[2:])
original = sync.os.replace
def injected(source, target):
    source, target = Path(source), Path(target)
    if target == live and ".link." in source.name:
        raise OSError("injected link failure")
    return original(source, target)
sync.os.replace = injected
try:
    sync.replace_with_symlink(live, want)
except sync.Stop as error:
    assert error.code == 1
else:
    raise AssertionError("injected link failure did not propagate")
assert not live.is_symlink()
assert live.read_text() == "live\n"
assert not list(live.parent.glob(".settings.json.link.*"))
assert not list(live.parent.glob(".settings.json.old.*"))
PY
  [ "$status" -eq 0 ]
}

@test "startup refuses crash-left swap artifacts and preserves every artifact" {
  physical_home="$(cd "$HOME_DIR" && pwd -P)"
  canonical_agents="$physical_home/.agents"
  previous="$physical_home/..agents.previous-4242"
  clone="$physical_home/..agents.clone.crashed"
  old_live="$physical_home/.claude/.settings.json.old.crashed"
  mkdir -p "$previous" "$clone" "$(dirname "$old_live")"
  printf 'old repository\n' > "$previous/kept.txt"
  printf 'staged clone\n' > "$clone/kept.txt"
  printf 'old live settings\n' > "$old_live"

  run env \
    HOME="$HOME_DIR" \
    AGENTS_REPO="$canonical_agents" \
    CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    CODEX_HOME="$HOME_DIR/.codex" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" --dry-run

  [ "$status" -eq 21 ]
  [[ "$output" == *"SYNC_CONFLICT=incomplete swap artifacts"* ]] || return 1
  [[ "$output" == *"$previous (canonical missing: $canonical_agents)"* ]] || return 1
  [[ "$output" == *"$clone (canonical missing: $canonical_agents)"* ]] || return 1
  [[ "$output" == *"$old_live (canonical missing: $physical_home/.claude/settings.json)"* ]] || return 1
  [ "$(cat "$previous/kept.txt")" = "old repository" ]
  [ "$(cat "$clone/kept.txt")" = "staged clone" ]
  [ "$(cat "$old_live")" = "old live settings" ]
  [ ! -e "$canonical_agents" ]
  [ ! -e "$physical_home/.claude/settings.json" ]
}

@test "replacement refuses dirty and unpushed git repositories" {
  old_remote="$BATS_TEST_TMPDIR/old.git"
  git init -q --bare "$old_remote"
  git init -q -b main "$AGENTS"
  git -C "$AGENTS" config user.email test@example.com
  git -C "$AGENTS" config user.name "Harness Test"
  printf 'base\n' > "$AGENTS/work.txt"
  git -C "$AGENTS" add work.txt
  git -C "$AGENTS" commit -q -m base
  git -C "$AGENTS" remote add origin "$old_remote"
  git -C "$AGENTS" push -q -u origin main
  printf 'dirty\n' >> "$AGENTS/work.txt"

  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="/usr/bin:/bin" \
    "$SCRIPT" --source existing --repo-url "$BATS_TEST_TMPDIR/new.git" --replace-repo-path
  [ "$status" -eq 22 ]
  [[ "$output" == *"uncommitted work"* ]] || return 1

  git -C "$AGENTS" add work.txt
  git -C "$AGENTS" commit -q -m local
  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="/usr/bin:/bin" \
    "$SCRIPT" --source existing --repo-url "$BATS_TEST_TMPDIR/new.git" --replace-repo-path
  [ "$status" -eq 22 ]
  [[ "$output" == *"unpushed commits"* ]] || return 1
  [ "$(cat "$AGENTS/work.txt")" = $'base\ndirty' ]
}

@test "dry run never invokes npx and returns failed for invalid shared settings" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  make_sync_repo "$AGENTS" "$remote"
  printf '{invalid\n' > "$AGENTS/claude/settings.json"
  cat > "$BIN/npx" <<EOF
#!/usr/bin/env bash
touch "$HOME_DIR/npx-called"
exit 99
EOF
  chmod +x "$BIN/npx"
  before="$(git -C "$AGENTS" status --porcelain=v1 --untracked-files=all)"

  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="$BIN:/usr/bin:/bin" "$SCRIPT" --dry-run

  [ "$status" -eq 1 ]
  [[ "$output" == *"SETTINGS_STATE=failed"* ]] || return 1
  [ ! -e "$HOME_DIR/npx-called" ]
  [ "$(git -C "$AGENTS" status --porcelain=v1 --untracked-files=all)" = "$before" ]
}

@test "symlinked default agents store still runs installed-only skill inventory" {
  actual="$BATS_TEST_TMPDIR/actual-agents"
  remote="$BATS_TEST_TMPDIR/remote.git"
  make_sync_repo "$actual" "$remote"
  ln -s "$actual" "$AGENTS"
  cat > "$BIN/skills" <<EOF
#!/usr/bin/env bash
touch "$HOME_DIR/skills-called"
printf '[]\n'
EOF
  chmod +x "$BIN/skills"

  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="$BIN:/usr/bin:/bin" "$SCRIPT" --dry-run

  [ "$status" -eq 0 ]
  [ -e "$HOME_DIR/skills-called" ]
  [[ "$output" == *"Skills:     0 plan item(s)"* ]] || return 1
}

@test "skill decision after local mutation leaves remote unchanged and is recoverable" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  make_sync_repo "$AGENTS" "$remote"
  install_sync_stubs
  cat > "$BIN/npx" <<EOF
#!/usr/bin/env bash
printf '[{"name":"extra","source":"owner/repo","path":"$AGENTS/skills/extra"}]\n'
EOF
  chmod +x "$BIN/npx"
  initial_remote="$(git --git-dir="$remote" rev-parse refs/heads/main)"

  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="$BIN:/usr/bin:/bin" "$SCRIPT"

  [ "$status" -eq 20 ]
  [[ "$output" == *"extra: --add-skill, --remove-skill, or --keep-local-skill"* ]] || return 1
  [ "$(git --git-dir="$remote" rev-parse refs/heads/main)" = "$initial_remote" ]
  [ -L "$HOME_DIR/.claude/skills" ]

  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="$BIN:/usr/bin:/bin" "$SCRIPT" --keep-local-skill extra

  [ "$status" -eq 0 ]
  [ "$(git -C "$AGENTS" rev-parse HEAD)" = "$(git --git-dir="$remote" rev-parse refs/heads/main)" ]
}

@test "MCP replace without a runtime registry fails explicitly" {
  mkdir -p "$AGENTS"
  run python3 - "$SCRIPT" "$AGENTS" <<'PY'
from importlib.machinery import SourceFileLoader
from pathlib import Path
import sys

sync = SourceFileLoader("harness_sync", sys.argv[1]).load_module()
try:
    sync.final_mcp(Path(sys.argv[2]), Path(sys.argv[2]) / "missing.json", Path(sys.argv[1]).parent, prune_to_local=True)
except sync.Stop as error:
    assert error.code == 1
    assert "without a runtime registry" in error.message
else:
    raise AssertionError("replace silently ignored a missing registry")
PY
  [ "$status" -eq 0 ]
}

@test "failed MCP replace leaves no marker and later merge preserves other-machine servers" {
  remote="$BATS_TEST_TMPDIR/remote.git"
  make_sync_repo "$AGENTS" "$remote"
  install_sync_stubs
  cat > "$AGENTS/mcp.manifest.json" <<'EOF'
{"version":1,"servers":{"shared":{"command":"true","machines":["other"]}}}
EOF
  printf '%s\n' '{"skipInstall":[],"keepLocal":[],"skipMcp":[],"keepLocalMcp":["extra"]}' > "$AGENTS/.fleet-local.json"
  printf 'path: /Users/alice/private\n' > "$AGENTS/bad.md"
  git -C "$AGENTS" add mcp.manifest.json bad.md
  git -C "$AGENTS" commit -q -m mcp
  git -C "$AGENTS" push -q
  initial_remote="$(git --git-dir="$remote" rev-parse refs/heads/main)"
  mkdir -p "$HOME_DIR/.claude"
  touch "$HOME_DIR/.claude/.mcp-prune-to-local"
  cat > "$HOME_DIR/.claude/.claude.json" <<'EOF'
{"mcpServers":{"extra":{"command":"true"}}}
EOF

  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="$BIN:/usr/bin:/bin" \
    "$SCRIPT" --mcp-mode replace --confirm-mcp-replace
  [ "$status" -eq 20 ]
  [[ "$output" == *"portability lint findings"* ]] || return 1
  [ ! -e "$HOME_DIR/.claude/.mcp-prune-to-local" ]
  [ "$(git --git-dir="$remote" rev-parse refs/heads/main)" = "$initial_remote" ]

  rm "$AGENTS/bad.md"
  run env HOME="$HOME_DIR" AGENTS_REPO="$AGENTS" CLAUDE_CONFIG_DIR="$HOME_DIR/.claude" XDG_CONFIG_HOME="$HOME_DIR/.config" CODEX_HOME="$HOME_DIR/.codex" PATH="$BIN:/usr/bin:/bin" \
    "$SCRIPT" --mcp-mode merge
  [ "$status" -eq 0 ]
  run python3 - "$AGENTS/mcp.manifest.json" <<'PY'
import json, sys
servers = json.load(open(sys.argv[1]))["servers"]
assert "shared" in servers
PY
  [ "$status" -eq 0 ]
  [ ! -e "$HOME_DIR/.claude/.mcp-prune-to-local" ]
  [ "$(git -C "$AGENTS" rev-parse HEAD)" = "$(git --git-dir="$remote" rev-parse refs/heads/main)" ]
}

@test "an MCP secret referenced as \${NAME} and set in the environment needs no import" {
  run env HARNESS_SYNC_TEST_SECRET=value python3 - "$REPO/plugins/harness/scripts/sync" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("sync_script", sys.argv[1])
spec = importlib.util.spec_from_loader("sync_script", loader)
sync = importlib.util.module_from_spec(spec)
loader.exec_module(sync)
placeholder = {"env": {"HARNESS_SYNC_TEST_SECRET": "${HARNESS_SYNC_TEST_SECRET}"}}
assert sync.environment_provides(placeholder, "HARNESS_SYNC_TEST_SECRET")
missing = {"env": {"HARNESS_SYNC_UNSET_SECRET_7Q": "${HARNESS_SYNC_UNSET_SECRET_7Q}"}}
assert not sync.environment_provides(missing, "HARNESS_SYNC_UNSET_SECRET_7Q")
literal = {"env": {"HARNESS_SYNC_TEST_SECRET": "literal"}}
assert not sync.environment_provides(literal, "HARNESS_SYNC_TEST_SECRET")
PY
  [ "$status" -eq 0 ]
}

@test "the environment secret check never prints the secret" {
  stub="$BATS_TEST_TMPDIR/bin"; mkdir -p "$stub"
  printf '#!/bin/sh\necho launchctl-secret-value\n' > "$stub/launchctl"; chmod +x "$stub/launchctl"
  run env PATH="$stub:$PATH" python3 - "$REPO/plugins/harness/scripts/sync" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("sync_script", sys.argv[1])
spec = importlib.util.spec_from_loader("sync_script", loader)
sync = importlib.util.module_from_spec(spec)
loader.exec_module(sync)
server = {"env": {"HARNESS_SYNC_LAUNCHCTL_ONLY_9Z": "${HARNESS_SYNC_LAUNCHCTL_ONLY_9Z}"}}
assert sync.environment_provides(server, "HARNESS_SYNC_LAUNCHCTL_ONLY_9Z")
PY
  [ "$status" -eq 0 ]
  [[ "$output" != *"launchctl-secret-value"* ]] || return 1
}

@test "fleet push runs each other machine's own sync through the fleet ssh config" {
  stub="$BATS_TEST_TMPDIR/bin"; mkdir -p "$stub"
  cat > "$stub/ssh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$SSH_LOG"
cat > "$SSH_LOG.stdin.$7"
case "$*" in
  *" laptop "*) echo "  Harness sync completed"; echo "REMOTE_STATE=synced exit=0"; exit 0 ;;
  *" warnmac "*) echo "  Harness sync completed with 1 unresolved finding(s)"; echo "REMOTE_STATE=synced exit=1"; exit 1 ;;
  *" brokenmac "*) echo "  SYNC_DECISION_REQUIRED=x"; echo "REMOTE_STATE=synced exit=20"; exit 20 ;;
  *" oldmac "*) echo "REMOTE_STATE=pulled"; exit 0 ;;
  *) echo "ssh: connect to host: Operation timed out" >&2; exit 255 ;;
esac
SH
  chmod +x "$stub/ssh"
  repo="$BATS_TEST_TMPDIR/agents"; mkdir -p "$repo/ssh"
  printf 'Host laptop\n  HostName laptop.example\nHost warnmac\n  HostName warnmac.example\nHost brokenmac\n  HostName brokenmac.example\nHost oldmac\n  HostName oldmac.example\nHost gone\n  HostName gone.example\n' > "$repo/ssh/config"
  export SSH_LOG="$BATS_TEST_TMPDIR/ssh.log"
  run env PATH="$stub:$PATH" SSH_LOG="$SSH_LOG" python3 - "$REPO/plugins/harness/scripts/sync" "$repo" <<'PY'
import argparse, importlib.machinery, importlib.util, sys
from pathlib import Path
loader = importlib.machinery.SourceFileLoader("sync_script", sys.argv[1])
spec = importlib.util.spec_from_loader("sync_script", loader)
sync = importlib.util.module_from_spec(spec)
loader.exec_module(sync)
state = sync.push_machines(argparse.Namespace(push_machines=True), Path(sys.argv[2]), Path(sys.argv[1]).parent)
print("STATE=" + state)
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *"STATE=synced: laptop; synced with findings: warnmac; pulled only: oldmac; failed: brokenmac; unreachable: gone"* ]] || return 1
  grep -q -- "-F $repo/ssh/config -o BatchMode=yes" "$SSH_LOG" || return 1
  grep -q -- '-l -s' "$SSH_LOG" || return 1
  grep -q 'claude plugin update harness@studio-moser' "$SSH_LOG.stdin.laptop" || return 1
  grep -q 'scripts/sync' "$SSH_LOG.stdin.laptop" || return 1
}
