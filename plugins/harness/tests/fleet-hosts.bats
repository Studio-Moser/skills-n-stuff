#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/fleet-hosts.sh"
  REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$REPO/ssh"
}

@test "parses every OpenSSH Host spelling and skips patterns" {
  printf '%s\n' '# fleet' 'Host a b # inline note' '  host c' 'Host=d' 'Host = e' 'HOST *.ts.net !x' \
    '  HostName a.example' 'Match host f' 'Host a' > "$REPO/ssh/config"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'a\nb\nc\nd\ne')" ]
}

@test "an inventory with no concrete alias fails instead of returning nothing" {
  printf 'Host *\n  User x\n' > "$REPO/ssh/config"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
}

@test "an alias ssh could read as an option is rejected" {
  printf 'Host good -oProxyCommand=touch\n' > "$REPO/ssh/config"
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *"-oProxyCommand"* ]]
}

@test "missing inventory exits 2" {
  run "$SCRIPT" "${BATS_TEST_TMPDIR}/nowhere"
  [ "$status" -eq 2 ]
}
