#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"

bash -n "$plugin_root/skills/serve-preview/scripts/Preview.sh"
"$plugin_root/tests/Test_Preview.sh"

python3 - "$plugin_root" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / ".claude-plugin/plugin.json").read_text())
codex_manifest = json.loads((root / ".codex-plugin/plugin.json").read_text())
for field in ("name", "version", "description", "author", "repository", "license", "keywords"):
    assert codex_manifest[field] == manifest[field], f"Claude and Codex manifests differ at {field}"
PY
