#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/skills-reconcile.sh"
  # The script hardcodes its store to $HOME/.agents/skills (matching `npx
  # skills`' own getCanonicalSkillsDir, which ignores $AGENTS_REPO) — so
  # tests point $HOME at a throwaway dir and use $HOME/.agents as the repo.
  export HOME="${BATS_TEST_TMPDIR}/home"
  REPO="$HOME/.agents"
  mkdir -p "$REPO/skills"
}

# json_entry name path source
# source: an unquoted "null" produces a literal JSON null; anything else is
# quoted as a string. path is relative to $REPO unless it already starts
# with /.
json_entry() {
  name="$1"; rel="$2"; source="$3"
  case "$rel" in
    /*) path="$rel" ;;
    *) path="$REPO/$rel" ;;
  esac
  if [ "$source" = "null" ]; then
    src_json="null"
  else
    src_json="\"$source\""
  fi
  printf '{"name":"%s","path":"%s","source":%s}' "$name" "$path" "$src_json"
}

@test "manifest entry missing on disk is reported INSTALL" {
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  run bash -c "printf '[]' | '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"INSTALL"$'\t'"foo"$'\t'"acme/foo"* ]] || return 1
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
  [[ "$output" == *"EXTRA"$'\t'"bar"$'\t'"acme/bar"* ]] || return 1
}

@test "extra skill in keepLocal is reported KEEP-LOCAL, not EXTRA" {
  mkdir -p "$REPO/skills/bar"
  printf '{"skipInstall":[],"keepLocal":["bar"]}' > "$REPO/.fleet-local.json"
  json="[$(json_entry bar skills/bar acme/bar)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [[ "$output" == *"KEEP-LOCAL"$'\t'"bar"* ]] || return 1
  [[ "$output" != *"EXTRA"$'\t'"bar"* ]] || return 1
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
  [[ "$output" == *"EXTRA"$'\t'"foo"* ]] || return 1
}

@test "absent .fleet-local.json is treated as no overrides" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA"* ]] || return 1
}

@test "a locally-authored skill (source: null) is never reported EXTRA" {
  mkdir -p "$REPO/skills/homegrown"
  json="[$(json_entry homegrown skills/homegrown null)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a skill outside this repo's store (another agent's) is never reported EXTRA" {
  json="[$(json_entry other-agent /home/x/.cursor/skills/other-agent acme/other)]"
  run bash -c "printf '%s' '$json' | '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a repo other than \$HOME/.agents is skipped, not misreported" {
  other_repo="${BATS_TEST_TMPDIR}/elsewhere"
  mkdir -p "$other_repo"
  printf 'foo\tacme/foo\n' > "$other_repo/skills.manifest"
  run bash -c "printf '[]' | '$SCRIPT' '$other_repo'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILLS_STATE=skipped"* ]] || return 1
  [[ "$output" != *"INSTALL"* ]] || return 1
}

@test "invalid JSON on stdin fails cleanly, no traceback" {
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  run bash -c "printf 'not json' | '$SCRIPT' '$REPO'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILLS_STATE=failed"* ]] || return 1
  [[ "$output" != *"Traceback"* ]] || return 1
}

@test "runs under zsh with no lost output" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  run bash -c "printf '[]' | zsh '$SCRIPT' '$REPO'"
  [[ "$output" == *"INSTALL"$'\t'"foo"* ]] || return 1
}
