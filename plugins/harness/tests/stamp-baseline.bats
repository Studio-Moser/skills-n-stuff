#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/stamp-baseline.sh"
  TARGET="${BATS_TEST_TMPDIR}/AGENTS.md"
  BODY="${BATS_TEST_TMPDIR}/body.md"
  printf '## Harness baseline\n\nfirst version\n' > "$BODY"
}

@test "stamps a block into an empty/absent target" {
  run "$SCRIPT" "$TARGET" "$BODY"
  [ "$status" -eq 0 ]
  grep -qF "<!-- harness:baseline:start -->" "$TARGET"
  grep -qF "<!-- harness:baseline:end -->" "$TARGET"
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
  [ "$(grep -cF "<!-- harness:baseline:start -->" "$TARGET")" -eq 1 ]
}

@test "refresh replaces the block body, not the whole file" {
  printf '# My Repo\n' > "$TARGET"
  "$SCRIPT" "$TARGET" "$BODY"
  printf '## Harness baseline\n\nsecond version\n' > "$BODY"
  "$SCRIPT" "$TARGET" "$BODY"
  grep -qF "# My Repo" "$TARGET"
  grep -qF "second version" "$TARGET"
  ! grep -qF "first version" "$TARGET"
  [ "$(grep -cF "<!-- harness:baseline:start -->" "$TARGET")" -eq 1 ]
}

@test "refuses to stamp an empty body file (no clobber)" {
  printf '# Keep me\n<!-- harness:baseline:start -->\nold body\n<!-- harness:baseline:end -->\n' > "$TARGET"
  empty="${BATS_TEST_TMPDIR}/empty.md"; : > "$empty"
  run "$SCRIPT" "$TARGET" "$empty"
  [ "$status" -eq 2 ]
  grep -qF "old body" "$TARGET"   # unchanged
}

@test "uses the bundled Harness template by default" {
  run "$SCRIPT" "$TARGET"
  [ "$status" -eq 0 ]
  grep -qF "## Harness baseline" "$TARGET"
  grep -qF "Harness Request" "$TARGET"
  grep -qF "plugins/harness/templates/AGENTS_Baseline.md" "$TARGET"
}
