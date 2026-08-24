#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/sync-finalize.sh"
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

@test "one final transaction leaves a clean tree at the remote SHA" {
  printf 'portable change\n' > "$REPO/config.md"

  run "$SCRIPT" "$REPO" "harness: sync test config"

  [ "$status" -eq 0 ]
  [[ "$output" == *"SYNC_STATE=clean"* ]] || return 1
  [ -z "$(git -C "$REPO" status --porcelain)" ]
  [ "$(remote_head)" = "$(git -C "$REPO" rev-parse HEAD)" ]
  [ "$(git -C "$REPO" rev-list --count HEAD)" -eq 2 ]
}
