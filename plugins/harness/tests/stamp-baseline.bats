#!/usr/bin/env bats

setup() {
  SCRIPT="${STAMP_SCRIPT:-${BATS_TEST_DIRNAME}/../scripts/stamp-baseline.sh}"
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

@test "migrates the retired managed block without duplicating it" {
  retired="studio""-baseline"
  printf '# Before\n<!-- %s:start -->\nstale managed body\n<!-- %s:end -->\n# After\n' "$retired" "$retired" > "$TARGET"

  "$SCRIPT" "$TARGET" "$BODY"

  [ "$(grep -cF '# Before' "$TARGET")" -eq 1 ]
  [ "$(grep -cF '# After' "$TARGET")" -eq 1 ]
  [ "$(grep -cF '<!-- harness:baseline:start -->' "$TARGET")" -eq 1 ]
  [ "$(grep -cF '<!-- harness:baseline:end -->' "$TARGET")" -eq 1 ]
  grep -qF "first version" "$TARGET"
  ! grep -qF "stale managed body" "$TARGET"
  ! grep -qF "<!-- ${retired}:start -->" "$TARGET"
  ! grep -qF "<!-- ${retired}:end -->" "$TARGET"
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

@test "refuses a symlink target without writing through it" {
  outside="${BATS_TEST_TMPDIR}/outside.md"
  printf 'outside stays unchanged\n' > "$outside"
  ln -s "$outside" "$TARGET"

  run "$SCRIPT" "$TARGET" "$BODY"

  [ "$status" -eq 2 ]
  [ "$(cat "$outside")" = "outside stays unchanged" ]
  [ -L "$TARGET" ]
}

@test "does not follow a pre-existing predictable temp symlink" {
  outside="${BATS_TEST_TMPDIR}/outside.md"
  printf 'outside stays unchanged\n' > "$outside"
  printf '# Keep me\n<!-- harness:baseline:start -->\nold body\n<!-- harness:baseline:end -->\n' > "$TARGET"
  ln -s "$outside" "$TARGET.tmp"

  "$SCRIPT" "$TARGET" "$BODY"

  [ "$(cat "$outside")" = "outside stays unchanged" ]
  grep -qF '# Keep me' "$TARGET"
  grep -qF 'first version' "$TARGET"
  [ -L "$TARGET.tmp" ]
}
