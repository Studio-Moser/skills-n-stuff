#!/usr/bin/env bats

setup() {
  PLUGIN="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  TOOL="$PLUGIN/scripts/agent-secrets.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export AGENTS_REPO="$BATS_TEST_TMPDIR/agents"
  export HARNESS_SECRETS_BACKEND=file
  mkdir -p "$HOME" "$AGENTS_REPO"
  STORE="$XDG_CONFIG_HOME/agent-secrets/secrets.env"
  SECRET='s3cr3t "q" $HOME sp ace\x'
}

@test "set stores a value privately and never prints it" {
  run "$TOOL" set API_KEY <<<"$SECRET"
  [ "$status" -eq 0 ]
  [ "$output" = "API_KEY stored (file)" ]
  [ "$(stat -f '%Lp' "$STORE" 2>/dev/null || stat -c '%a' "$STORE")" = "600" ]
  [ "$(stat -f '%Lp' "$(dirname "$STORE")" 2>/dev/null || stat -c '%a' "$(dirname "$STORE")")" = "700" ]
}

@test "exec hands the value only to the child process" {
  "$TOOL" set API_KEY <<<"$SECRET" >/dev/null
  run "$TOOL" exec --env API_KEY -- sh -c 'printf "%s" "$API_KEY"'
  [ "$status" -eq 0 ]
  [ "$output" = "$SECRET" ]
  # A value already in the environment wins over the store.
  run env API_KEY=from-env "$TOOL" exec --env API_KEY -- sh -c 'printf "%s" "$API_KEY"'
  [ "$output" = "from-env" ]
}

@test "exec refuses to start without a required secret and names the fix" {
  run "$TOOL" exec --env MISSING_KEY -- true
  [ "$status" -eq 78 ]
  [[ "$output" == *"MISSING_KEY is not stored on this machine; run: agent-secrets.py set MISSING_KEY"* ]] || return 1
  run "$TOOL" exec --optional --env MISSING_KEY -- sh -c 'printf "[%s]" "${MISSING_KEY:-}"'
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "check reports names from secrets.names without values" {
  printf '# MCP servers\nAPI_KEY\nOTHER_KEY  # not stored yet\n' > "$AGENTS_REPO/secrets.names"
  "$TOOL" set API_KEY <<<"$SECRET" >/dev/null
  run "$TOOL" check
  [ "$status" -eq 1 ]
  [ "$output" = "$(printf 'API_KEY\tpresent\nOTHER_KEY\tmissing\nbackend\tfile')" ]
}

@test "multi-line values and invalid names are rejected" {
  run "$TOOL" set API_KEY <<<"$(printf 'one\ntwo')"
  [ "$status" -eq 2 ]
  [[ "$output" == *"single line"* ]] || return 1
  run "$TOOL" set 'BAD;NAME' <<<"x"
  [ "$status" -eq 2 ]
  [ ! -e "$STORE" ]
}

@test "copy-to pipes each value into the remote machine's own set command" {
  # The fake remote is this machine with its own HOME, Harness cache, and store.
  remote_home="$BATS_TEST_TMPDIR/remote"
  mkdir -p "$remote_home/.codex/plugins/cache/studio-moser/harness/9.9.9" "$BATS_TEST_TMPDIR/bin"
  ln -s "$PLUGIN/scripts" "$remote_home/.codex/plugins/cache/studio-moser/harness/9.9.9/scripts"
  cat > "$BATS_TEST_TMPDIR/bin/ssh" <<EOF
#!/bin/sh
while [ "\$1" = "-o" ]; do shift 2; done
shift  # host alias
exec env HOME="$remote_home" XDG_CONFIG_HOME="$remote_home/.config" HARNESS_SECRETS_BACKEND=file sh -c "\$1"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/ssh"
  printf 'API_KEY\nNOT_HERE\n' > "$AGENTS_REPO/secrets.names"
  "$TOOL" set API_KEY <<<"$SECRET" >/dev/null

  run env PATH="$BATS_TEST_TMPDIR/bin:$PATH" "$TOOL" copy-to studio-moser
  [ "$status" -eq 1 ]
  [ "$output" = "$(printf 'API_KEY\tcopied\nNOT_HERE\tmissing locally')" ]
  [ "$(cat "$remote_home/.config/agent-secrets/secrets.env")" = "API_KEY=$SECRET" ]
}

@test "the macOS Keychain backend round-trips through a throwaway keychain" {
  command -v security >/dev/null || skip "macOS security CLI not available"
  export HARNESS_SECRETS_BACKEND=keychain
  export HARNESS_KEYCHAIN="$BATS_TEST_TMPDIR/test.keychain-db"
  security create-keychain -p pw "$HARNESS_KEYCHAIN"
  security unlock-keychain -p pw "$HARNESS_KEYCHAIN"
  run "$TOOL" set API_KEY <<<"$SECRET"
  status_set="$status"
  run "$TOOL" exec --env API_KEY -- sh -c 'printf "%s" "$API_KEY"'
  security delete-keychain "$HARNESS_KEYCHAIN"
  [ "$status_set" -eq 0 ]
  [ "$output" = "$SECRET" ]
}

@test "the Linux libsecret backend stores through secret-tool stdin, never argv" {
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/ring"
  # Stub keyring: one file per account; records argv so the test can prove the value is not in it.
  cat > "$BATS_TEST_TMPDIR/bin/secret-tool" <<EOF2
#!/bin/sh
echo "\$*" >> "$BATS_TEST_TMPDIR/argv.log"
cmd="\$1"; shift
while [ "\$#" -gt 0 ]; do [ "\$1" = account ] && account="\$2"; shift; done
case "\$cmd" in
  store) cat > "$BATS_TEST_TMPDIR/ring/\$account" ;;
  lookup) [ -f "$BATS_TEST_TMPDIR/ring/\$account" ] && cat "$BATS_TEST_TMPDIR/ring/\$account" ;;
esac
EOF2
  chmod +x "$BATS_TEST_TMPDIR/bin/secret-tool"
  export HARNESS_SECRETS_BACKEND=libsecret PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  run "$TOOL" set API_KEY <<<"$SECRET"
  [ "$status" -eq 0 ]
  [ "$output" = "API_KEY stored (libsecret)" ]
  run "$TOOL" exec --env API_KEY -- sh -c 'printf "%s" "$API_KEY"'
  [ "$output" = "$SECRET" ]
  run grep -qF "s3cr3t" "$BATS_TEST_TMPDIR/argv.log"
  [ "$status" -ne 0 ]
}

@test "a value too long for security -i is refused before anything is overwritten" {
  command -v security >/dev/null || skip "macOS security CLI not available"
  export HARNESS_SECRETS_BACKEND=keychain
  export HARNESS_KEYCHAIN="$BATS_TEST_TMPDIR/long.keychain-db"
  security create-keychain -p pw "$HARNESS_KEYCHAIN"
  security unlock-keychain -p pw "$HARNESS_KEYCHAIN"
  "$TOOL" set API_KEY <<<"good" >/dev/null
  run "$TOOL" set API_KEY <<<"$(head -c 4000 /dev/zero | tr '\0' 'x')"
  status_long="$status"
  run "$TOOL" exec --env API_KEY -- sh -c 'printf "%s" "$API_KEY"'
  security delete-keychain "$HARNESS_KEYCHAIN"
  [ "$status_long" -eq 2 ]
  [ "$output" = "good" ]
}
