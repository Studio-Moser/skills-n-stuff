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
