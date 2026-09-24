#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/portability-lint.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO"
  cd "$REPO"
  git init -q -b main .
  git config user.email t@example.com
  git config user.name t
}

commit_all() {
  git add -A
  git commit -q -m x
}

@test "clean repo passes" {
  printf 'uses $HOME and nothing else\n' > ok.md
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "literal home path in file contents fails" {
  printf 'command: /Users/alice/.shelby/bin/hook\n' > bad.md
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad.md"* ]]
}

@test "linux home path in file contents fails" {
  printf 'path: /home/bob/.config/thing\n' > bad.md
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
}

@test "symlink with absolute target fails" {
  # The regression. A content grep follows this link and reads the target,
  # so a naive lint reports nothing.
  mkdir -p "${BATS_TEST_TMPDIR}/outside"
  printf 'harmless content with no home paths\n' > "${BATS_TEST_TMPDIR}/outside/f.md"
  ln -s "${BATS_TEST_TMPDIR}/outside" linked
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"linked"* ]]
}

@test "symlink with relative target passes" {
  mkdir -p real
  printf 'fine\n' > real/f.md
  ln -s real alias
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "untracked files are ignored" {
  printf 'ok\n' > tracked.md
  commit_all
  printf '/Users/alice/scratch\n' > untracked.md
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "non-git directory fails loudly" {
  NOTAREPO="${BATS_TEST_TMPDIR}/notarepo"
  mkdir -p "$NOTAREPO"
  run "$SCRIPT" "$NOTAREPO"
  [ "$status" -eq 1 ]
}

@test "non-ASCII filename is still scanned" {
  printf 'command: /Users/alice/.shelby/bin/hook\n' > "café.md"
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"caf"* ]]
}

@test "tracked symlink missing from worktree still reports other findings" {
  ln -s real missing-link
  printf 'command: /Users/alice/.shelby/bin/hook\n' > bad.md
  commit_all
  rm missing-link
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad.md"* ]]
}

@test "invoked from a subdirectory still scans the whole repo" {
  printf 'command: /Users/alice/.shelby/bin/hook\n' > bad.md
  mkdir -p sub
  printf 'harmless\n' > sub/ok.md
  commit_all
  # Mirrors real usage: `portability-lint.sh .` run from a subdirectory of
  # the repo. A root-level violation must still be caught.
  run bash -c 'cd "$1/sub" && "$2" .' _ "$REPO" "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"bad.md"* ]]
}

@test "guarded optional command hooks pass" {
  mkdir -p claude
  cat > claude/settings.json <<'EOF'
{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"[ -x \"$HOME/.tool/bin/hook\" ] && \"$HOME/.tool/bin/hook\" args || true"}]}]}}
EOF
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "each canonical guard form passes only when it invokes the matched executable" {
  mkdir -p claude
  cat > claude/settings.json <<'EOF'
{"hooks":{"PreToolUse":[{"hooks":[
  {"type":"command","command":"[ -x \"$HOME/.tool/bin/hook\" ] && \"$HOME/.tool/bin/hook\" args"},
  {"type":"command","command":"test -x \"$HOME/.tool/bin/hook\" && \"$HOME/.tool/bin/hook\" args"},
  {"type":"command","command":"command -v hook >/dev/null 2>&1 && hook args"}
]}]}}
EOF
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
}

@test "compound mismatched and unrelated guards do not protect optional commands" {
  mkdir -p claude
  cat > claude/settings.json <<'EOF'
{"hooks":{"PreToolUse":[{"hooks":[
  {"type":"command","command":"echo ready; \"$HOME/.tool/bin/hook\""},
  {"type":"command","command":"if command -v true; then \"$HOME/.tool/bin/hook\"; fi"},
  {"type":"command","command":"[ -x \"$HOME/.tool/bin/other\" ] && \"$HOME/.tool/bin/hook\""}
]}]}}
EOF
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *'echo ready; "$HOME/.tool/bin/hook"'* ]] || return 1
  [[ "$output" == *'if command -v true; then "$HOME/.tool/bin/hook"; fi'* ]] || return 1
  [[ "$output" == *'other" ] && "$HOME/.tool/bin/hook'* ]] || return 1
}

@test "unguarded optional command hooks fail" {
  mkdir -p claude
  cat > claude/settings.json <<'EOF'
{"hooks":{"PreToolUse":[{"hooks":[{"type":"command","command":"$HOME/.tool/bin/hook args"}]}]}}
EOF
  commit_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unguarded command hook"* ]]
  [[ "$output" == *"hooks.PreToolUse[0].hooks[0]"* ]]
}

@test "guard chains with a variable check, a fallback, or standard commands pass" {
  mkdir -p claude
  cat > claude/settings.json <<'JSON'
{"hooks":{"Stop":[{"hooks":[
  {"type":"command","command":"[ -n \"$SUPERSET_HOME_DIR\" ] && [ -x \"$SUPERSET_HOME_DIR/hooks/notify.sh\" ] && \"$SUPERSET_HOME_DIR/hooks/notify.sh\" || true"},
  {"type":"command","command":"touch /tmp/claude-compaction-$(date +%s).marker; true"},
  {"type":"command","command":"command -v notify >/dev/null 2>&1 && notify done"}
]}]}}
JSON
  commit_all
  run "$SCRIPT" "$REPO"
  [[ "$output" != *"unguarded command hook"* ]] || return 1
}
