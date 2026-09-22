#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
skill_root="$plugin_root/skills/serve-preview"

bash -n "$skill_root/scripts/Preview.sh"
node --check "$skill_root/assets/Preview_Hub/Static/App.js"
PYTHONDONTWRITEBYTECODE=1 python3 "$plugin_root/tests/Test_Preview_Hub.py"
"$plugin_root/tests/Test_Runtime_Bundle.sh"

python3 - "$plugin_root" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / ".claude-plugin/plugin.json").read_text())
codex_manifest = json.loads((root / ".codex-plugin/plugin.json").read_text())
script = (root / "skills/serve-preview/scripts/Preview.sh").read_text()
match = re.search(r'^RUNTIME_BUNDLE_VERSION="([^"]+)"$', script, re.MULTILINE)
assert match, "runtime bundle version is missing"
assert match.group(1) == manifest["version"], "runtime bundle and plugin versions differ"
for field in ("name", "version", "description", "author", "repository", "license", "keywords"):
    assert codex_manifest[field] == manifest[field], f"Claude and Codex manifests differ at {field}"
PY
