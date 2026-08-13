#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/link-plan.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
  export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/claude"
  mkdir -p "$REPO/skills" "$REPO/claude" "$CLAUDE_CONFIG_DIR"
  : > "$REPO/claude/CLAUDE.md"
  : > "$REPO/claude/settings.json"
  : > "$REPO/claude/statusline-command.sh"
}

link_all() {
  ln -s "$REPO/skills" "$CLAUDE_CONFIG_DIR/skills"
  ln -s "$REPO/claude/CLAUDE.md" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  ln -s "$REPO/claude/settings.json" "$CLAUDE_CONFIG_DIR/settings.json"
  ln -s "$REPO/claude/statusline-command.sh" "$CLAUDE_CONFIG_DIR/statusline-command.sh"
}

@test "all four links correct -> exit 0, every line ok" {
  link_all
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c ' ok$')" -eq 4 ]
}

@test "missing link is reported ABSENT and exits 1" {
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ABSENT"* ]]
}

@test "a symlink replaced by a real file is reported REAL-FILE" {
  link_all
  rm "$CLAUDE_CONFIG_DIR/settings.json"
  printf '{}' > "$CLAUDE_CONFIG_DIR/settings.json"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"settings.json"* ]]
  [[ "$output" == *"REAL-FILE"* ]]
}

@test "a symlink pointing somewhere else is reported RELINK" {
  link_all
  rm "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  ln -s "${BATS_TEST_TMPDIR}/elsewhere.md" "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"RELINK"* ]]
}

@test "file absent from the repo is reported MISSING-IN-REPO" {
  link_all
  rm "$REPO/claude/statusline-command.sh"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING-IN-REPO"* ]]
}

@test "read-only: reports drift without fixing it" {
  run "$SCRIPT" "$REPO"
  [ ! -e "$CLAUDE_CONFIG_DIR/CLAUDE.md" ]
}
