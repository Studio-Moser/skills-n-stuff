#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "Harness consumer plugin versions match their marketplace entries" {
  run python3 - "$REPO" <<'PY'
import json
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
marketplace = json.loads((root / ".claude-plugin/marketplace.json").read_text())
entries = {entry["name"]: entry for entry in marketplace["plugins"]}
failures = []
for name in ("harness", "pm", "product-pulse"):
    manifest = json.loads(
        (root / "plugins" / name / ".claude-plugin" / "plugin.json").read_text()
    )
    manifest_version = manifest.get("version")
    marketplace_version = entries.get(name, {}).get("version")
    if not isinstance(manifest_version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", manifest_version):
        failures.append(f"{name}: invalid manifest version {manifest_version!r}")
    if marketplace_version != manifest_version:
        failures.append(
            f"{name}: marketplace {marketplace_version!r} != manifest {manifest_version!r}"
        )

metadata_version = marketplace.get("metadata", {}).get("version")
pm_version = entries["pm"]["version"]
if metadata_version != pm_version:
    failures.append(
        f"marketplace metadata {metadata_version!r} != PM release line {pm_version!r}"
    )

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
