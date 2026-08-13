#!/usr/bin/env bats

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/discover-config.sh"
  TMP="$(mktemp -d)"

  # Build a fake repo with .pm/config.yml + pulse-config.yaml so the
  # walk-up loop terminates inside the fixture, not in the user's tree.
  ( cd "$TMP" && git init -q && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init )
  mkdir -p "$TMP/.pm" "$TMP/Research"
  cat > "$TMP/pulse-config.yaml" <<'EOF'
project_id: testproj
default_branch: main
repos:
  - name: testproj
    path: .
    role: primary
backlog:
  active: planning/todos.md
  ideas: planning/ideas.md
EOF
}

teardown() { rm -rf "$TMP"; }

@test "github backend emits gh_owner/gh_repo and no trello keys" {
  cp "$BATS_TEST_DIRNAME/fixtures/github/config.yml" "$TMP/.pm/config.yml"
  run bash -c "cd '$TMP' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backend=github"* ]] || return 1
  [[ "$output" == *"gh_owner=acme"* ]] || return 1
  [[ "$output" == *"gh_repo=widgets"* ]] || return 1
  [[ "$output" != *'trello_boards_json=[{'* ]] || return 1
  # project_sync defaults to off when not specified
  [[ "$output" == *"gh_project_sync_enabled=false"* ]]
}

@test "github backend with project_sync emits project fields" {
  cp "$BATS_TEST_DIRNAME/fixtures/github/config.with-project-sync.yml" "$TMP/.pm/config.yml"
  run bash -c "cd '$TMP' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backend=github"* ]] || return 1
  [[ "$output" == *"gh_project_sync_enabled=true"* ]] || return 1
  [[ "$output" == *"gh_project_number=7"* ]] || return 1
  [[ "$output" == *"gh_project_owner=acme"* ]] || return 1
  [[ "$output" == *"gh_project_owner_type=org"* ]] || return 1
  [[ "$output" == *"gh_project_status_field_sync=true"* ]] || return 1
  [[ "$output" == *'"status/ready":"Ready"'* ]]
}

@test "trello backend emits boards_json and statuses_json" {
  cp "$BATS_TEST_DIRNAME/fixtures/trello/config.yml" "$TMP/.pm/config.yml"
  run bash -c "cd '$TMP' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"backend=trello"* ]] || return 1
  [[ "$output" == *'trello_boards_json=[{'*'TEST_BOARD_1'* ]] || return 1
  [[ "$output" == *'trello_statuses_json={'*'"done":["needs_changes"]'* ]] || return 1
  [[ "$output" != *"gh_owner=acme"* ]]
}

@test "trello backend with no webhook_url emits empty trello_webhook_url" {
  cp "$BATS_TEST_DIRNAME/fixtures/trello/config.yml" "$TMP/.pm/config.yml"
  run bash -c "cd '$TMP' && '$SCRIPT'"
  [ "$status" -eq 0 ]
  # The fixture has no webhook_url field, so the emitted line is "trello_webhook_url="
  [[ "$output" == *$'\ntrello_webhook_url=\n'* ]]
}
