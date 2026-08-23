#!/usr/bin/env bats

setup() {
  SCRIPT="${LOCALIZE_SCRIPT:-${BATS_TEST_DIRNAME}/../scripts/localize-skill-overrides.py}"
  LIVE_SETTINGS="${BATS_TEST_TMPDIR}/settings.json"
  LOCAL_SETTINGS="${BATS_TEST_TMPDIR}/settings.local.json"
  REPO_SETTINGS="${BATS_TEST_TMPDIR}/repo-settings.json"
  SYNC_SKILL="${BATS_TEST_DIRNAME}/../skills/sync/SKILL.md"
}

assert_localized() {
  python3 - "$1" "$2" <<'PY'
import json
import sys

shared = json.load(open(sys.argv[1], encoding="utf-8"))
local = json.load(open(sys.argv[2], encoding="utf-8"))
assert "skillOverrides" not in shared, shared
assert shared["enabledPlugins"] == {"harness": True}, shared
assert local["theme"] == "dark", local
assert local["skillOverrides"] == {"review": {"model": "opus"}}, local
PY
}

@test "existing-repo keep-file path localizes overrides before copying machine settings" {
  printf '%s\n' '{"enabledPlugins":{"harness":true},"skillOverrides":{"review":{"model":"opus"}}}' > "$LIVE_SETTINGS"
  printf '%s\n' '{"theme":"dark"}' > "$LOCAL_SETTINGS"
  printf '%s\n' '{"enabledPlugins":{}}' > "$REPO_SETTINGS"

  "$SCRIPT" "$LIVE_SETTINGS" "$LOCAL_SETTINGS"
  cp "$LIVE_SETTINGS" "$REPO_SETTINGS"

  assert_localized "$REPO_SETTINGS" "$LOCAL_SETTINGS"
}

@test "pre-stage path removes overrides already leaked into shared settings" {
  printf '%s\n' '{"enabledPlugins":{"harness":true},"skillOverrides":{"review":{"model":"opus"}}}' > "$REPO_SETTINGS"
  printf '%s\n' '{"theme":"dark"}' > "$LOCAL_SETTINGS"

  "$SCRIPT" "$REPO_SETTINGS" "$LOCAL_SETTINGS"

  assert_localized "$REPO_SETTINGS" "$LOCAL_SETTINGS"
}

@test "localization creates a missing machine-local settings file" {
  printf '%s\n' '{"enabledPlugins":{"harness":true},"skillOverrides":{"review":{"model":"opus"}}}' > "$REPO_SETTINGS"

  "$SCRIPT" "$REPO_SETTINGS" "$LOCAL_SETTINGS"

  python3 - "$REPO_SETTINGS" "$LOCAL_SETTINGS" <<'PY'
import json
import sys

shared = json.load(open(sys.argv[1], encoding="utf-8"))
local = json.load(open(sys.argv[2], encoding="utf-8"))
assert "skillOverrides" not in shared, shared
assert local == {"skillOverrides": {"review": {"model": "opus"}}}, local
PY
}

@test "sync invokes localization for adoption, keep-file, and pre-stage flows" {
  run python3 - "$SYNC_SKILL" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8")
call = '"$harness/scripts/localize-skill-overrides.py"'
loose = text.index("For loose configuration:")
phase_one = text.index("## Phase 1: Link check")
real_file = text.index("**On `REAL-FILE`", phase_one)
phase_two = text.index("## Phase 2: Commit, pull, push")
phase_two_one = text.index("### 2.1 Commit local changes", phase_two)
status = text.index('git -C "$repo" status --short', phase_two_one)
assert call in text[loose:phase_one]
assert call in text[real_file:phase_two]
assert call in text[phase_two_one:status]
PY
  [ "$status" -eq 0 ]
}
