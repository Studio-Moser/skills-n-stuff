#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/skills-reconcile.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
  mkdir -p "$REPO/skills"
}

json_entry() {
  name="$1"; rel="$2"; source="$3"
  case "$rel" in
    /*) path="$rel" ;;
    *) path="$REPO/$rel" ;;
  esac
  printf '{"name":"%s","path":"%s","source":"%s"}' "$name" "$path" "$source"
}

@test "manifest entry missing on disk is reported INSTALL" {
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  run bash -c "printf '[]' | '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INSTALL"$'\t'"foo"$'\t'"acme/foo"* ]]
}

@test "manifest entry in skipInstall is reported SKIP-INSTALL, not INSTALL" {
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  printf '{"skipInstall":["foo"],"keepLocal":[]}' > "$REPO/.fleet-local.json"
  run bash -c "printf '[]' | '$SCRIPT' '$REPO'"
  [ "$output" = "$(printf 'SKIP-INSTALL\tfoo')" ]
}

@test "on-disk skill absent from manifest is reported EXTRA" {
  mkdir -p "$REPO/skills/bar"
  json="[$(json_entry bar skills/bar acme/bar)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [[ "$output" == *"EXTRA"$'\t'"bar"$'\t'"acme/bar"* ]]
}

@test "extra skill in keepLocal is reported KEEP-LOCAL, not EXTRA" {
  mkdir -p "$REPO/skills/bar"
  printf '{"skipInstall":[],"keepLocal":["bar"]}' > "$REPO/.fleet-local.json"
  json="[$(json_entry bar skills/bar acme/bar)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [[ "$output" == *"KEEP-LOCAL"$'\t'"bar"* ]]
  [[ "$output" != *"EXTRA"$'\t'"bar"* ]]
}

@test "entry present in both manifest and reality is not reported at all" {
  mkdir -p "$REPO/skills/foo"
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  json="[$(json_entry foo skills/foo acme/foo)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [ -z "$output" ]
}

@test "absent manifest is treated as empty (first run), not an error" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA"$'\t'"foo"* ]]
}

@test "absent .fleet-local.json is treated as no overrides" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA"* ]]
}

@test "runs under zsh with no lost output" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  run bash -c "printf '[]' | zsh '$SCRIPT' '$REPO'"
  [[ "$output" == *"INSTALL"$'\t'"foo"* ]]
}
