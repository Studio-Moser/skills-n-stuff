#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/reconcile_shared_settings.py"
  SETTINGS="${BATS_TEST_TMPDIR}/settings.json"
}

@test "migration enables Harness and removes the retired Machine plugin" {
  cat > "$SETTINGS" <<'JSON'
{
  "enabledPlugins": {
    "machine@studio-moser": true,
    "pm@studio-moser": true
  },
  "effortLevel": "high"
}
JSON

  "$SCRIPT" "$SETTINGS"

  python3 - "$SETTINGS" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text())
assert data["enabledPlugins"]["harness@studio-moser"] is True
assert "machine@studio-moser" not in data["enabledPlugins"]
assert data["enabledPlugins"]["pm@studio-moser"] is True
assert data["effortLevel"] == "high"
PY
}

@test "check scans every supplied managed config" {
  good="${BATS_TEST_TMPDIR}/good-settings.json"
  stale="${BATS_TEST_TMPDIR}/stale-settings.json"
  printf '%s\n' '{"enabledPlugins":{"harness@studio-moser":true}}' > "$good"
  printf '%s\n' '{"enabledPlugins":{"machine@studio-moser":true}}' > "$stale"

  run "$SCRIPT" --check "$good" "$stale"

  [ "$status" -eq 1 ]
  [[ "$output" == *"stale-settings.json"* ]] || return 1
  [[ "$output" != *"good-settings.json"* ]]
}

@test "invalid JSON fails without changing the file" {
  printf '{broken\n' > "$SETTINGS"
  before="$(cat "$SETTINGS")"

  run "$SCRIPT" "$SETTINGS"

  [ "$status" -eq 1 ]
  [ "$(cat "$SETTINGS")" = "$before" ]
  [[ "$output" != *"Traceback"* ]]
}

@test "migration preserves literal Unicode instead of rewriting escapes" {
  cat > "$SETTINGS" <<'JSON'
{
  "enabledPlugins": {
    "harness@studio-moser": true
  },
  "statusLine": "Harness — ready"
}
JSON
  before="$(cat "$SETTINGS")"

  "$SCRIPT" "$SETTINGS"

  [ "$(cat "$SETTINGS")" = "$before" ]
}
