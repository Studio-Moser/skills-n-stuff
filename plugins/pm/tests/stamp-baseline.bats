#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/stamp-baseline.sh"
  TARGET="${BATS_TEST_TMPDIR}/AGENTS.md"
  BODY="${BATS_TEST_TMPDIR}/body.md"
  printf '## Studio Moser baseline\n\nfirst version\n' > "$BODY"
}

@test "stamps a block into an empty/absent target" {
  run "$SCRIPT" "$TARGET" "$BODY"
  [ "$status" -eq 0 ]
  grep -qF "<!-- studio-baseline:start -->" "$TARGET"
  grep -qF "<!-- studio-baseline:end -->" "$TARGET"
  grep -qF "first version" "$TARGET"
}

@test "preserves existing content outside the block" {
  printf '# My Repo\n\nProject-specific notes.\n' > "$TARGET"
  "$SCRIPT" "$TARGET" "$BODY"
  grep -qF "# My Repo" "$TARGET"
  grep -qF "Project-specific notes." "$TARGET"
  grep -qF "first version" "$TARGET"
}

@test "re-stamping is idempotent (exactly one block)" {
  "$SCRIPT" "$TARGET" "$BODY"
  "$SCRIPT" "$TARGET" "$BODY"
  [ "$(grep -cF "<!-- studio-baseline:start -->" "$TARGET")" -eq 1 ]
}

@test "refresh replaces the block body, not the whole file" {
  printf '# My Repo\n' > "$TARGET"
  "$SCRIPT" "$TARGET" "$BODY"
  printf '## Studio Moser baseline\n\nsecond version\n' > "$BODY"
  "$SCRIPT" "$TARGET" "$BODY"
  grep -qF "# My Repo" "$TARGET"
  grep -qF "second version" "$TARGET"
  ! grep -qF "first version" "$TARGET"
  [ "$(grep -cF "<!-- studio-baseline:start -->" "$TARGET")" -eq 1 ]
}
