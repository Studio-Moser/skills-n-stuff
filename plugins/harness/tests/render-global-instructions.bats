#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/render-global-instructions.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
  PROFILE="${BATS_TEST_TMPDIR}/profile"
  mkdir -p "$REPO/claude" "$PROFILE"
  printf '# Rules\n\n1. **No hallucination** — say so.\n' > "$PROFILE/Global Instructions.md"
  printf '# Clear, Concise, Actionable Communication\n\nSay less.\n' > "$PROFILE/House Style.md"
}

@test "a fresh repo gets identical Claude and Codex files holding rules then style" {
  run "$SCRIPT" "$REPO" "$PROFILE"
  [ "$status" -eq 0 ]
  [ "$output" = "RENDER_STATE=regenerated" ]
  cmp -s "$REPO/claude/CLAUDE.md" "$REPO/codex/AGENTS.md"
  out="$REPO/claude/CLAUDE.md"
  [ "$(head -1 "$out")" = '<!-- harness:profile:start -->' ]
  [ "$(tail -1 "$out")" = '<!-- harness:profile:end -->' ]
  r=$(grep -n '^# Rules$' "$out" | cut -d: -f1)
  s=$(grep -n '^# Clear, Concise' "$out" | cut -d: -f1)
  [ "$r" -lt "$s" ]
}

@test "a second run is unchanged and a profile edit regenerates both files" {
  "$SCRIPT" "$REPO" "$PROFILE" > /dev/null
  run "$SCRIPT" "$REPO" "$PROFILE"
  [ "$output" = "RENDER_STATE=unchanged" ]
  printf '\nSay even less.\n' >> "$PROFILE/House Style.md"
  run "$SCRIPT" "$REPO" "$PROFILE"
  [ "$output" = "RENDER_STATE=regenerated" ]
  grep -q 'Say even less.' "$REPO/claude/CLAUDE.md"
  cmp -s "$REPO/claude/CLAUDE.md" "$REPO/codex/AGENTS.md"
}

@test "text outside the managed block is kept and reaches Codex" {
  "$SCRIPT" "$REPO" "$PROFILE" > /dev/null
  printf '\nMy own note.\n' >> "$REPO/claude/CLAUDE.md"
  printf '\nNew rule.\n' >> "$PROFILE/Global Instructions.md"
  run "$SCRIPT" "$REPO" "$PROFILE"
  [ "$output" = "RENDER_STATE=regenerated" ]
  [ "$(grep -c 'My own note.' "$REPO/codex/AGENTS.md")" -eq 1 ]
  grep -q 'New rule.' "$REPO/codex/AGENTS.md"
  e=$(grep -n 'harness:profile:end' "$REPO/claude/CLAUDE.md" | cut -d: -f1)
  n=$(grep -n 'My own note.' "$REPO/claude/CLAUDE.md" | cut -d: -f1)
  [ "$e" -lt "$n" ]
}

@test "a hand-written file is not replaced without --adopt" {
  printf '# Rules\n\nOld hand-written rule.\n\n<!-- shelby:bootstrap start -->\nUse Shelby.\n<!-- shelby:bootstrap end -->\n' > "$REPO/claude/CLAUDE.md"
  cp "$REPO/claude/CLAUDE.md" "${BATS_TEST_TMPDIR}/before.md"
  run "$SCRIPT" "$REPO" "$PROFILE"
  [ "$status" -eq 4 ]
  [ "$output" = "RENDER_STATE=adopt-required" ]
  cmp -s "$REPO/claude/CLAUDE.md" "${BATS_TEST_TMPDIR}/before.md"
  [ ! -e "$REPO/codex/AGENTS.md" ]
}

@test "--adopt replaces a hand-written file and keeps only its Shelby block" {
  printf '# Rules\n\nOld hand-written rule.\n\n<!-- shelby:bootstrap start -->\nUse Shelby.\n<!-- shelby:bootstrap end -->\n' > "$REPO/claude/CLAUDE.md"
  run "$SCRIPT" --adopt "$REPO" "$PROFILE"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'Old hand-written rule.' "$REPO/claude/CLAUDE.md")" -eq 0 ]
  grep -q 'Use Shelby.' "$REPO/claude/CLAUDE.md"
  [ "$(grep -c '^# Rules$' "$REPO/claude/CLAUDE.md")" -eq 1 ]
  cmp -s "$REPO/claude/CLAUDE.md" "$REPO/codex/AGENTS.md"
  run "$SCRIPT" "$REPO" "$PROFILE"
  [ "$output" = "RENDER_STATE=unchanged" ]
}

@test "a missing profile source fails with exit 3 and writes nothing" {
  rm "$PROFILE/House Style.md"
  run "$SCRIPT" "$REPO" "$PROFILE"
  [ "$status" -eq 3 ]
  [[ "$output" == *"House Style"* ]] || return 1
  [ ! -e "$REPO/claude/CLAUDE.md" ]
}

@test "the bundled profile renders and usage errors exit 2" {
  run "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  grep -q '^## Engineering discipline$' "$REPO/codex/AGENTS.md"
  grep -q '^## Hard Operational Boundaries$' "$REPO/codex/AGENTS.md"
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}
