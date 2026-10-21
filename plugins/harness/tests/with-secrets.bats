#!/usr/bin/env bats

setup() {
  PLUGIN="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  LAUNCHER="$PLUGIN/templates/with-secrets"
  STORE_TOOL="$PLUGIN/scripts/agent-secrets.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export HARNESS_SECRETS_BACKEND=file
  mkdir -p "$HOME"
  SECRET='s3cr3t "q" $HOME sp=ace'
}

@test "the launcher reads values agent-secrets stored and passes them only by environment" {
  "$STORE_TOOL" set API_KEY <<<"$SECRET" >/dev/null
  "$STORE_TOOL" set OTHER_KEY <<<"two" >/dev/null
  run "$LAUNCHER" API_KEY OTHER_KEY -- sh -c 'printf "%s|%s" "$API_KEY" "$OTHER_KEY"'
  [ "$status" -eq 0 ]
  [ "$output" = "$SECRET|two" ]
}

@test "an exported value wins, and a missing secret stops the launch with the fix" {
  run env API_KEY=from-env "$LAUNCHER" API_KEY -- sh -c 'printf "%s" "$API_KEY"'
  [ "$output" = "from-env" ]
  run "$LAUNCHER" MISSING_KEY -- true
  [ "$status" -eq 78 ]
  [ "$output" = "with-secrets: MISSING_KEY is not stored on this machine; run: agent-secrets.py set MISSING_KEY" ]
}

@test "invalid names and a missing separator are usage errors" {
  run "$LAUNCHER" 'BAD;rm' -- true
  [ "$status" -eq 2 ]
  run "$LAUNCHER" API_KEY true
  [ "$status" -eq 2 ]
}

@test "the launcher needs no installed Harness and reads the macOS Keychain" {
  command -v security >/dev/null || skip "macOS security CLI not available"
  export HARNESS_SECRETS_BACKEND=keychain
  export HARNESS_KEYCHAIN="$BATS_TEST_TMPDIR/test.keychain-db"
  security create-keychain -p pw "$HARNESS_KEYCHAIN"
  security unlock-keychain -p pw "$HARNESS_KEYCHAIN"
  "$STORE_TOOL" set API_KEY <<<"$SECRET" >/dev/null
  # An empty HOME has no plugin caches: the launcher must not depend on them.
  run env -u CLAUDE_PLUGIN_ROOT "$LAUNCHER" API_KEY -- sh -c 'printf "%s" "$API_KEY"'
  security delete-keychain "$HARNESS_KEYCHAIN"
  [ "$status" -eq 0 ]
  [ "$output" = "$SECRET" ]
}
