#!/usr/bin/env bats

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/../../.." && pwd)"
}

@test "plugin versions match entries and marketplace metadata releases independently" {
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
if not isinstance(metadata_version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", metadata_version):
    failures.append(f"invalid marketplace metadata version {metadata_version!r}")

readme = (root / "README.md").read_text()
if "Marketplace metadata has its own release version" not in readme:
    failures.append("README does not document the independent marketplace release")

assert not failures, "\n".join(failures)
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
