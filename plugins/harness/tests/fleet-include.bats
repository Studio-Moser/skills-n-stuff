#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fleet-include.sh"
  REPO="${BATS_TEST_TMPDIR}/my repo"
  CONFIG="${BATS_TEST_TMPDIR}/home/.ssh/config"
  mkdir -p "$REPO/ssh" "${BATS_TEST_TMPDIR}/repo/ssh"
  : > "$REPO/ssh/config"; : > "${BATS_TEST_TMPDIR}/repo/ssh/config"
  LINE="Include \"$REPO/ssh/config\""
}

@test "creates a private config that starts with the quoted Include" {
  run "$SCRIPT" "$REPO" "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$CONFIG")" = "$LINE" ]
  [ "$(stat -f %Lp "$CONFIG" 2>/dev/null || stat -c %a "$CONFIG")" = 600 ]
}

@test "prepends once and keeps existing content" {
  mkdir -p "$(dirname "$CONFIG")"
  printf 'Host x\n  User y\n' > "$CONFIG"
  "$SCRIPT" "$REPO" "$CONFIG"
  "$SCRIPT" "$REPO" "$CONFIG"
  [ "$(grep -c '^Include' "$CONFIG")" -eq 1 ]
  [ "$(head -1 "$CONFIG")" = "$LINE" ]
  grep -qx 'Host x' "$CONFIG"
}

@test "an Include nested under Host does not count as global" {
  mkdir -p "$(dirname "$CONFIG")"
  printf 'Host foo\n%s\n' "$LINE" > "$CONFIG"
  run "$SCRIPT" "$REPO" "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" == included* ]]
  [ "$(head -1 "$CONFIG")" = "$LINE" ]
}

@test "an unquoted global Include is recognized" {
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$(dirname "$CONFIG")"
  printf '  include = %s\nHost x\n' "$REPO/ssh/config" > "$CONFIG"
  before="$(cat "$CONFIG")"
  run "$SCRIPT" "$REPO" "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" == already* ]]
  [ "$(cat "$CONFIG")" = "$before" ]
}

@test "a symlinked config is refused and left a symlink" {
  mkdir -p "$(dirname "$CONFIG")"
  printf 'Host x\n' > "${BATS_TEST_TMPDIR}/real"
  ln -s "${BATS_TEST_TMPDIR}/real" "$CONFIG"
  run "$SCRIPT" "$REPO" "$CONFIG"
  [ "$status" -eq 1 ]
  [ -L "$CONFIG" ]
  [ "$(cat "${BATS_TEST_TMPDIR}/real")" = "Host x" ]
}

@test "two quoted paths do not satisfy one path containing a space" {
  mkdir -p "$(dirname "$CONFIG")"
  first="${REPO%% *}"; rest="${REPO#* }"
  printf 'Include "%s" "%s/ssh/config"\nHost x\n' "$first" "$rest" > "$CONFIG"
  run "$SCRIPT" "$REPO" "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" == included* ]]
  [ "$(head -1 "$CONFIG")" = "$LINE" ]
}

@test "a directory at the config path or a quote in the repo path is refused" {
  mkdir -p "$CONFIG"
  run "$SCRIPT" "$REPO" "$CONFIG"
  [ "$status" -eq 1 ]
  [ -z "$(ls -A "$CONFIG")" ]
  rmdir "$CONFIG"
  mkdir -p "${BATS_TEST_TMPDIR}/re\"po/ssh"; : > "${BATS_TEST_TMPDIR}/re\"po/ssh/config"
  run "$SCRIPT" "${BATS_TEST_TMPDIR}/re\"po" "$CONFIG"
  [ "$status" -eq 1 ]
  [ ! -e "$CONFIG" ]
}

@test "a relative repo path is written as an absolute Include" {
  cd "${BATS_TEST_TMPDIR}/repo"
  run "$SCRIPT" . "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$CONFIG")" = "Include \"$(pwd)/ssh/config\"" ]
}

@test "a missing inventory or a glob in the path is refused" {
  run "$SCRIPT" "${BATS_TEST_TMPDIR}/nowhere" "$CONFIG"
  [ "$status" -eq 2 ]
  mkdir -p "${BATS_TEST_TMPDIR}/re*po/ssh"; : > "${BATS_TEST_TMPDIR}/re*po/ssh/config"
  run "$SCRIPT" "${BATS_TEST_TMPDIR}/re*po" "$CONFIG"
  [ "$status" -eq 1 ]
  mkdir -p "${BATS_TEST_TMPDIR}/re%dpo/ssh"; : > "${BATS_TEST_TMPDIR}/re%dpo/ssh/config"
  run "$SCRIPT" "${BATS_TEST_TMPDIR}/re%dpo" "$CONFIG"
  [ "$status" -eq 1 ]
  [ ! -e "$CONFIG" ]
}

@test "a failure to prepare the config exits nonzero" {
  printf 'not a directory\n' > "${BATS_TEST_TMPDIR}/blocker"
  run "$SCRIPT" "$REPO" "${BATS_TEST_TMPDIR}/blocker/config"
  [ "$status" -ne 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/blocker")" = "not a directory" ]
}
