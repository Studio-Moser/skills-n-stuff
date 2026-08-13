#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/skills-manifest.sh"
  # The script hardcodes its store to $HOME/.agents/skills (matching `npx
  # skills`' own getCanonicalSkillsDir, which ignores $FLEET_REPO) — so
  # tests point $HOME at a throwaway dir and use $HOME/.agents as the repo.
  export HOME="${BATS_TEST_TMPDIR}/home"
  REPO="$HOME/.agents"
  mkdir -p "$REPO/skills"
}

# json_entry name path source
# path is relative to $REPO unless it already starts with /.
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
  printf '{"name":"%s","path":"%s","scope":"user","agents":["claude"],"source":%s,"sourceUrl":null,"sourceType":null}' \
    "$name" "$path" "$src_json"
}

@test "filters out entries with source: null" {
  mkdir -p "$REPO/skills/foo" "$REPO/skills/local"
  json="[$(json_entry foo skills/foo acme/foo),$(json_entry local skills/local null)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [[ "$output" == *"foo"$'\t'"acme/foo"* ]] || return 1
  [[ "$output" != *"local"* ]] || return 1
}

@test "filters out paths outside this repo's skills store" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo),$(json_entry other /home/x/.cursor/skills/other acme/other)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [[ "$output" == *"foo"$'\t'"acme/foo"* ]] || return 1
  [[ "$output" != *"other"* ]] || return 1
}

@test "manifest is sorted by name" {
  mkdir -p "$REPO/skills/zeta" "$REPO/skills/alpha"
  json="[$(json_entry zeta skills/zeta acme/zeta),$(json_entry alpha skills/alpha acme/alpha)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [ "${lines[0]}" = "$(printf 'alpha\tacme/alpha')" ]
  [ "${lines[1]}" = "$(printf 'zeta\tacme/zeta')" ]
}

@test "manifest has a trailing newline" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  tail -c1 "$REPO/skills.manifest" | od -c | grep -q '\\n'
}

@test "no third-party skills produces an empty manifest" {
  json="[$(json_entry local skills/local null)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  [ ! -s "$REPO/skills.manifest" ]
}

@test "round-trips: two runs of the same input produce the same manifest" {
  mkdir -p "$REPO/skills/foo" "$REPO/skills/bar"
  json="[$(json_entry foo skills/foo acme/foo),$(json_entry bar skills/bar acme/bar)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  first="$(cat "$REPO/skills.manifest")"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  second="$(cat "$REPO/skills.manifest")"
  [ "$first" = "$second" ]
}

@test "gitignore block is created when .gitignore is absent" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/.gitignore"
  [[ "$output" == *"# fleet:skills start — generated, do not edit"* ]] || return 1
  [[ "$output" == *"skills/foo/"* ]] || return 1
  [[ "$output" == *"# fleet:skills end"* ]] || return 1
}

@test "gitignore block is updated in place as the manifest changes" {
  mkdir -p "$REPO/skills/foo"
  json1="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json1" | "$SCRIPT" "$REPO"

  mkdir -p "$REPO/skills/bar"
  json2="[$(json_entry bar skills/bar acme/bar)]"
  printf '%s' "$json2" | "$SCRIPT" "$REPO"

  run cat "$REPO/.gitignore"
  [[ "$output" == *"skills/bar/"* ]] || return 1
  [[ "$output" != *"skills/foo/"* ]] || return 1
}

@test "gitignore preserves content outside the generated block" {
  printf 'node_modules/\n.DS_Store\n' > "$REPO/.gitignore"
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/.gitignore"
  [[ "$output" == *"node_modules/"* ]] || return 1
  [[ "$output" == *".DS_Store"* ]] || return 1
  [[ "$output" == *"skills/foo/"* ]] || return 1
}

@test "gitignore preserves content on both sides of an existing block" {
  printf 'before\n# fleet:skills start — generated, do not edit\nskills/old/\n# fleet:skills end\nafter\n' > "$REPO/.gitignore"
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/.gitignore"
  [[ "$output" == *"before"* ]] || return 1
  [[ "$output" == *"after"* ]] || return 1
  [[ "$output" == *"skills/foo/"* ]] || return 1
  [[ "$output" != *"skills/old/"* ]] || return 1
}

@test "re-stamping is idempotent (exactly one block)" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run bash -c "grep -c 'fleet:skills start' '$REPO/.gitignore'"
  [ "$output" = "1" ]
}

@test "gitignore always gets a static .fleet-local.json entry" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/.gitignore"
  [[ "$output" == *".fleet-local.json"* ]] || return 1
}

@test "gitignore always gets a static .skill-lock.json entry" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/.gitignore"
  [[ "$output" == *".skill-lock.json"* ]] || return 1
}

@test "a repo other than \$HOME/.agents is skipped, not wiped" {
  other_repo="${BATS_TEST_TMPDIR}/elsewhere"
  mkdir -p "$other_repo"
  printf 'preexisting\tacme/preexisting\n' > "$other_repo/skills.manifest"
  run bash -c "printf '[]' | '$SCRIPT' '$other_repo'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKILLS_STATE=skipped"* ]] || return 1
  run cat "$other_repo/skills.manifest"
  [ "$output" = "$(printf 'preexisting\tacme/preexisting')" ]
}

@test "invalid JSON on stdin fails cleanly (no traceback) and leaves the manifest untouched" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  before="$(cat "$REPO/skills.manifest")"

  run bash -c "printf 'not json' | '$SCRIPT' '$REPO'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKILLS_STATE=failed"* ]] || return 1
  [[ "$output" != *"Traceback"* ]] || return 1

  after="$(cat "$REPO/skills.manifest")"
  [ "$before" = "$after" ]
}

@test "a skipInstall entry survives regeneration even though it's absent from reality" {
  mkdir -p "$REPO/skills/foo"
  printf 'bar\tacme/bar\nfoo\tacme/foo\n' > "$REPO/skills.manifest"
  printf '{"skipInstall":["bar"],"keepLocal":[]}' > "$REPO/.fleet-local.json"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [[ "$output" == *"bar"$'\t'"acme/bar"* ]] || return 1
  [[ "$output" == *"foo"$'\t'"acme/foo"* ]] || return 1
}

@test "a name passed as a failed-install argument survives regeneration" {
  mkdir -p "$REPO/skills/foo"
  printf 'bar\tacme/bar\nfoo\tacme/foo\n' > "$REPO/skills.manifest"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO" bar
  run cat "$REPO/skills.manifest"
  [[ "$output" == *"bar"$'\t'"acme/bar"* ]] || return 1
  [[ "$output" == *"foo"$'\t'"acme/foo"* ]] || return 1
}

@test "an entry absent for no recorded reason is dropped (genuine removal)" {
  mkdir -p "$REPO/skills/foo"
  printf 'bar\tacme/bar\nfoo\tacme/foo\n' > "$REPO/skills.manifest"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [[ "$output" != *"bar"* ]] || return 1
  [[ "$output" == *"foo"$'\t'"acme/foo"* ]] || return 1
}

@test "refuses to overwrite a non-empty manifest with an empty result" {
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  before="$(cat "$REPO/skills.manifest")"
  run bash -c "printf '[]' | '$SCRIPT' '$REPO'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"REFUSING"* ]] || return 1
  after="$(cat "$REPO/skills.manifest")"
  [ "$before" = "$after" ]
}

@test "SKILLS_ALLOW_EMPTY_MANIFEST=1 confirms an intentional empty result" {
  printf 'foo\tacme/foo\n' > "$REPO/skills.manifest"
  run bash -c "printf '[]' | SKILLS_ALLOW_EMPTY_MANIFEST=1 '$SCRIPT' '$REPO'"
  [ "$status" -eq 0 ]
  [ ! -s "$REPO/skills.manifest" ]
}

@test "runs under zsh with no lost output" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | zsh "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [[ "$output" == *"foo"* ]] || return 1
}
