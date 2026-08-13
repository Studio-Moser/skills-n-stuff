#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/rubric-path.sh"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/cfg"
  mkdir -p "$XDG_CONFIG_HOME"
}

@test "prints resolved path under XDG_CONFIG_HOME" {
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = "$XDG_CONFIG_HOME/studio-moser/model-rubric.yml" ]
}

@test "--check reports unset when file is missing" {
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [ "$output" = "unset" ]
}

@test "--check reports set when a valid rubric exists" {
  mkdir -p "$XDG_CONFIG_HOME/studio-moser"
  printf 'models:\n  - { name: x, cost: 1, intelligence: 1, taste: 1 }\n' \
    > "$XDG_CONFIG_HOME/studio-moser/model-rubric.yml"
  run "$SCRIPT" --check
  [ "$status" -eq 0 ]
  [ "$output" = "set" ]
}

@test "--check reports unset when file exists but lacks models key" {
  mkdir -p "$XDG_CONFIG_HOME/studio-moser"
  printf 'reviewed: 2026-01-01\n' > "$XDG_CONFIG_HOME/studio-moser/model-rubric.yml"
  run "$SCRIPT" --check
  [ "$output" = "unset" ]
}
