#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
controller="$plugin_root/skills/serve-preview/scripts/Preview.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' > "$test_root/bin/docker"
chmod +x "$test_root/bin/docker"

PATH="$test_root/bin:$PATH" PREVIEW_CONFIG_DIR="$test_root/config" \
  "$controller" router-status >/dev/null

bundle="$test_root/config/runtime/0.1.0"
test -f "$bundle/.complete"
test -f "$bundle/DockTail.compose.yaml"
test -f "$bundle/Static_Preview.conf.template"
test -f "$bundle/Preview_Hub/Preview_Hub.py"

rm "$bundle/.complete"
if PATH="$test_root/bin:$PATH" PREVIEW_CONFIG_DIR="$test_root/config" \
    "$controller" router-status >"$test_root/output" 2>&1; then
  echo "expected an incomplete runtime bundle to be rejected" >&2
  exit 1
fi
grep -Fq 'Preview runtime bundle is incomplete' "$test_root/output"
