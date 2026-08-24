#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/sync-finalize.sh"
  PREFLIGHT="${BATS_TEST_DIRNAME}/../scripts/sync-preflight.sh"
  REMOTE="${BATS_TEST_TMPDIR}/remote.git"
  REPO="${BATS_TEST_TMPDIR}/agents"
  git init -q --bare "$REMOTE"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config user.name "Harness Test"
  printf 'base\n' > "$REPO/README.md"
  git -C "$REPO" add README.md
  git -C "$REPO" commit -q -m base
  git -C "$REPO" remote add origin "$REMOTE"
  git -C "$REPO" push -q -u origin main
  BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
  "$PREFLIGHT" "$REPO" >/dev/null
}

remote_head() {
  git --git-dir="$REMOTE" rev-parse refs/heads/main
}

@test "secret scan stops the only commit and push before remote mutation" {
  before="$(remote_head)"
  secret_value="not-a-real-test-""secret-value-123456"
  printf 'API_TOKEN=%s\n' "$secret_value" > "$REPO/secret.env"

  run "$SCRIPT" "$REPO" "harness: sync test config"

  [ "$status" -eq 1 ]
  [[ "$output" == *"staged secret scan failed"* ]] || return 1
  [ "$(remote_head)" = "$before" ]
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 1 ]
}

@test "provider API key assignments are blocked in common config forms" {
  before="$(remote_head)"
  openai_value="sk-""proj-not-a-real-value-1234567890"
  anthropic_value="sk-""ant-not-a-real-value-1234567890"
  google_value="AI""za-not-a-real-value-1234567890"
  groq_value="gsk_""not-a-real-value-1234567890"
  azure_value="not-a-real-azure-secret-1234567890"
  deepseek_value="not-a-real-deepseek-secret-1234567890"
  assignments=(
    "OPENAI_API_KEY=$openai_value"
    "export ANTHROPIC_API_KEY = \"$anthropic_value\""
    "\"GOOGLE_API_KEY\": \"$google_value\""
    "groq_api_key='$groq_value'"
    "AZURE_OPENAI_API_KEY=$azure_value"
    "export DEEPSEEK_API_KEY = '$deepseek_value'"
  )

  for assignment in "${assignments[@]}"; do
    printf '%s\n' "$assignment" > "$REPO/provider-config.txt"

    run "$SCRIPT" "$REPO" "harness: sync test provider secret"

    [ "$status" -eq 1 ]
    [[ "$output" == *"staged secret scan failed"* ]] || return 1
    [ "$(remote_head)" = "$before" ]
    [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 1 ]
    git -C "$REPO" reset -q
    rm "$REPO/provider-config.txt"
  done
}

@test "bare Google and Groq provider credentials are blocked" {
  before="$(remote_head)"
  google_value="AI""za-not-a-real-bare-value-1234567890"
  groq_value="gsk_""not-a-real-bare-value-1234567890"

  for value in "$google_value" "$groq_value"; do
    printf '%s\n' "$value" > "$REPO/provider-token.txt"

    run "$SCRIPT" "$REPO" "harness: sync test bare provider secret"

    [ "$status" -eq 1 ]
    [[ "$output" == *"staged secret scan failed"* ]] || return 1
    [ "$(remote_head)" = "$before" ]
    git -C "$REPO" reset -q
    rm "$REPO/provider-token.txt"
  done
}

@test "secret scan covers the complete post-ingest index, not only changed paths" {
  provider_value="sk-""proj-not-a-real-ingested-value-1234567890"
  printf 'OPENAI_API_KEY=%s\n' "$provider_value" > "$REPO/ingested.env"
  git -C "$REPO" add ingested.env
  git -C "$REPO" commit -q -m "simulate already-ingested remote state"
  git -C "$REPO" push -q
  before="$(remote_head)"
  printf 'harmless local change\n' > "$REPO/local.md"

  run "$SCRIPT" "$REPO" "harness: sync final index scan"

  [ "$status" -eq 1 ]
  [[ "$output" == *"SECRET_FINDING=ingested.env"* ]] || return 1
  [[ "$output" == *"staged secret scan failed"* ]] || return 1
  [ "$(remote_head)" = "$before" ]
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
}

@test "provider environment references are not treated as literal secrets" {
  cat > "$REPO/provider-env.txt" <<'EOF'
OPENAI_API_KEY=$OPENAI_API_KEY
"ANTHROPIC_API_KEY": "${ANTHROPIC_API_KEY}"
AZURE_OPENAI_API_KEY=${AZURE_OPENAI_API_KEY}
"DEEPSEEK_API_KEY": "$DEEPSEEK_API_KEY"
EOF

  run "$SCRIPT" "$REPO" "harness: sync environment references"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SYNC_STATE=clean"* ]] || return 1
  [ "$(remote_head)" = "$(git -C "$REPO" rev-parse HEAD)" ]
}

make_racing_git() {
  RACE_BIN="$BATS_TEST_TMPDIR/race-bin"
  RACE_MARKER="$BATS_TEST_TMPDIR/race-ran"
  mkdir -p "$RACE_BIN"
  cat > "$RACE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [ "$arg" = push ] && [ ! -e "$RACE_MARKER" ]; then
    : > "$RACE_MARKER"
    case "$RACE_ACTION" in
      delete) "$REAL_GIT" --git-dir="$RACE_REMOTE" update-ref -d "$RACE_REF" ;;
      update) "$REAL_GIT" --git-dir="$RACE_REMOTE" update-ref "$RACE_REF" "$RACE_TARGET" ;;
      *) exit 97 ;;
    esac
    break
  fi
done
exec "$REAL_GIT" "$@"
EOF
  chmod +x "$RACE_BIN/git"
}

@test "preflight persists the exact actual remote expectation in Git metadata" {
  state_path="$(git -C "$REPO" rev-parse --absolute-git-dir)/harness-sync-expected-remote"

  [ -f "$state_path" ]
  grep -qFx 'origin' "$state_path"
  grep -qFx 'refs/heads/main' "$state_path"
  grep -qFx "$(remote_head)" "$state_path"
}

@test "exact lease rejects a remote branch deletion after final comparison" {
  printf 'portable change\n' > "$REPO/config.md"
  make_racing_git

  run env \
    PATH="$RACE_BIN:$PATH" \
    REAL_GIT="$(command -v git)" \
    RACE_MARKER="$RACE_MARKER" \
    RACE_ACTION=delete \
    RACE_REMOTE="$REMOTE" \
    RACE_REF=refs/heads/main \
    "$SCRIPT" "$REPO" "harness: sync deletion race"

  [ "$status" -ne 0 ]
  [ -e "$RACE_MARKER" ]
  ! git --git-dir="$REMOTE" show-ref --verify --quiet refs/heads/main
}

@test "exact lease rejects a remote rewind after final comparison" {
  printf 'preflight remote\n' > "$REPO/preflight.md"
  git -C "$REPO" add preflight.md
  git -C "$REPO" commit -q -m "remote state for preflight"
  git -C "$REPO" push -q
  "$PREFLIGHT" "$REPO" >/dev/null
  printf 'portable change\n' > "$REPO/config.md"
  make_racing_git

  run env \
    PATH="$RACE_BIN:$PATH" \
    REAL_GIT="$(command -v git)" \
    RACE_MARKER="$RACE_MARKER" \
    RACE_ACTION=update \
    RACE_REMOTE="$REMOTE" \
    RACE_REF=refs/heads/main \
    RACE_TARGET="$BASE_SHA" \
    "$SCRIPT" "$REPO" "harness: sync rewind race"

  [ "$status" -ne 0 ]
  [ -e "$RACE_MARKER" ]
  [ "$(remote_head)" = "$BASE_SHA" ]
}

@test "exact empty lease rejects creation of an absent remote branch" {
  git -C "$REPO" switch -q -c new-sync-branch
  "$PREFLIGHT" "$REPO" >/dev/null
  printf 'portable change\n' > "$REPO/config.md"
  make_racing_git

  run env \
    PATH="$RACE_BIN:$PATH" \
    REAL_GIT="$(command -v git)" \
    RACE_MARKER="$RACE_MARKER" \
    RACE_ACTION=update \
    RACE_REMOTE="$REMOTE" \
    RACE_REF=refs/heads/new-sync-branch \
    RACE_TARGET="$BASE_SHA" \
    "$SCRIPT" "$REPO" "harness: sync absent branch race"

  [ "$status" -ne 0 ]
  [ -e "$RACE_MARKER" ]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/new-sync-branch)" = "$BASE_SHA" ]
}

@test "a distinct push URL is rejected before staging, committing, or pushing" {
  push_remote="$BATS_TEST_TMPDIR/push-remote.git"
  git init -q --bare "$push_remote"
  git -C "$REPO" remote set-url --push origin "$push_remote"
  before_local="$(git -C "$REPO" rev-parse HEAD)"
  before_fetch="$(remote_head)"
  printf 'portable change\n' > "$REPO/config.md"

  run "$SCRIPT" "$REPO" "harness: sync distinct push endpoint"

  [ "$status" -eq 1 ]
  [[ "$output" == *"distinct push URL"* ]] || return 1
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$before_local" ]
  git -C "$REPO" diff --cached --quiet
  [ "$(remote_head)" = "$before_fetch" ]
  ! git --git-dir="$push_remote" show-ref --verify --quiet refs/heads/main
}

@test "remote movement after preflight stops before commit without pulling" {
  updater="$BATS_TEST_TMPDIR/updater"
  git clone -q "$REMOTE" "$updater"
  git -C "$updater" config user.email updater@example.com
  git -C "$updater" config user.name "Remote Updater"
  printf 'remote change\n' > "$updater/remote.md"
  git -C "$updater" add remote.md
  git -C "$updater" commit -q -m "remote moved"
  git -C "$updater" push -q
  printf 'local change\n' > "$REPO/local.md"

  run "$SCRIPT" "$REPO" "harness: sync stale preflight"

  [ "$status" -eq 1 ]
  [[ "$output" == *"remote moved after preflight"* ]] || return 1
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 1 ]
  [ "$(git --git-dir="$REMOTE" rev-list --count main)" -eq 2 ]
  [ ! -e "$REPO/remote.md" ]
}

@test "post-push dirty state fails even when the remote received the commit" {
  printf 'portable change\n' > "$REPO/config.md"
  cat > "$REPO/.git/hooks/pre-push" <<EOF
#!/usr/bin/env bash
printf 'late local change\n' > "$REPO/post-push-dirty.txt"
EOF
  chmod +x "$REPO/.git/hooks/pre-push"

  run "$SCRIPT" "$REPO" "harness: sync test config"

  [ "$status" -eq 1 ]
  [[ "$output" == *"worktree changed during or after push"* ]] || return 1
  [ "$(remote_head)" = "$(git -C "$REPO" rev-parse HEAD)" ]
  [ -f "$REPO/post-push-dirty.txt" ]
}

@test "final remote proof queries the remote instead of trusting its tracking ref" {
  printf 'portable change\n' > "$REPO/config.md"
  cat > "$REMOTE/hooks/post-receive" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
export GIT_AUTHOR_NAME="Remote Race"
export GIT_AUTHOR_EMAIL="remote-race@example.com"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
while read -r _old pushed ref; do
  tree="$(git rev-parse "$pushed^{tree}")"
  moved="$(printf 'remote moved after push\n' | git commit-tree "$tree" -p "$pushed")"
  git update-ref "$ref" "$moved" "$pushed"
done
EOF
  chmod +x "$REMOTE/hooks/post-receive"

  run "$SCRIPT" "$REPO" "harness: sync test config"

  [ "$status" -eq 1 ]
  [[ "$output" == *"remote moved during or after push"* ]] || return 1
  [ "$(remote_head)" != "$(git -C "$REPO" rev-parse HEAD)" ]
}

@test "one final transaction leaves a clean tree at the remote SHA" {
  printf 'portable change\n' > "$REPO/config.md"

  run "$SCRIPT" "$REPO" "harness: sync test config"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SYNC_STATE=clean"* ]] || return 1
  [ -z "$(git -C "$REPO" status --porcelain)" ]
  [ "$(remote_head)" = "$(git -C "$REPO" rev-parse HEAD)" ]
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
}
