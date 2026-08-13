#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/skills-manifest.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
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
  [[ "$output" == *"foo"$'\t'"acme/foo"* ]]
  [[ "$output" != *"local"* ]]
}

@test "filters out paths outside this repo's skills store" {
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo),$(json_entry other /home/x/.cursor/skills/other acme/other)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [[ "$output" == *"foo"$'\t'"acme/foo"* ]]
  [[ "$output" != *"other"* ]]
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
  [[ "$output" == *"# fleet:skills start — generated, do not edit"* ]]
  [[ "$output" == *"skills/foo/"* ]]
  [[ "$output" == *"# fleet:skills end"* ]]
}

@test "gitignore block is updated in place as the manifest changes" {
  mkdir -p "$REPO/skills/foo"
  json1="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json1" | "$SCRIPT" "$REPO"

  mkdir -p "$REPO/skills/bar"
  json2="[$(json_entry bar skills/bar acme/bar)]"
  printf '%s' "$json2" | "$SCRIPT" "$REPO"

  run cat "$REPO/.gitignore"
  [[ "$output" == *"skills/bar/"* ]]
  [[ "$output" != *"skills/foo/"* ]]
}

@test "gitignore preserves content outside the generated block" {
  printf 'node_modules/\n.DS_Store\n' > "$REPO/.gitignore"
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/.gitignore"
  [[ "$output" == *"node_modules/"* ]]
  [[ "$output" == *".DS_Store"* ]]
  [[ "$output" == *"skills/foo/"* ]]
}

@test "gitignore preserves content on both sides of an existing block" {
  printf 'before\n# fleet:skills start — generated, do not edit\nskills/old/\n# fleet:skills end\nafter\n' > "$REPO/.gitignore"
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | "$SCRIPT" "$REPO"
  run cat "$REPO/.gitignore"
  [[ "$output" == *"before"* ]]
  [[ "$output" == *"after"* ]]
  [[ "$output" == *"skills/foo/"* ]]
  [[ "$output" != *"skills/old/"* ]]
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
  [[ "$output" == *".fleet-local.json"* ]]
}

@test "runs under zsh with no lost output" {
  command -v zsh >/dev/null 2>&1 || skip "zsh not available"
  mkdir -p "$REPO/skills/foo"
  json="[$(json_entry foo skills/foo acme/foo)]"
  printf '%s' "$json" | zsh "$SCRIPT" "$REPO"
  run cat "$REPO/skills.manifest"
  [[ "$output" == *"foo"* ]]
}
