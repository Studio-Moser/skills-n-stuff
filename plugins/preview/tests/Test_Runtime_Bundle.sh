#!/usr/bin/env bash
set -euo pipefail

plugin_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)"
controller="$plugin_root/skills/serve-preview/scripts/Preview.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin"
printf '%s\n' \
  '#!/usr/bin/env sh' \
  'if [ "$1 $2" = "network inspect" ]; then' \
  '  printf "%s\n" "172.30.0.1"' \
  'elif [ "$1" = "compose" ]; then' \
  '  printf "%s\n" "${PREVIEW_ROUTER_CONTROL_IP:-}" > "$PREVIEW_TEST_LOG"' \
  'fi' \
  'exit 0' > "$test_root/bin/docker"
chmod +x "$test_root/bin/docker"

PATH="$test_root/bin:$PATH" PREVIEW_CONFIG_DIR="$test_root/config" PREVIEW_TEST_LOG="$test_root/docker-env" \
  "$controller" router-status >/dev/null

version="$(sed -nE 's/^RUNTIME_BUNDLE_VERSION="([^"]+)"$/\1/p' "$controller")"
test -n "$version"
bundle="$test_root/config/runtime/$version"
test -f "$bundle/.complete"
test -f "$bundle/DockTail.compose.yaml"
test -f "$bundle/Static_Preview.conf.template"
test -f "$bundle/Preview_Hub/Preview_Hub.py"
grep -Fxq '172.30.0.2' "$test_root/docker-env"

rm "$bundle/.complete"
if PATH="$test_root/bin:$PATH" PREVIEW_CONFIG_DIR="$test_root/config" PREVIEW_TEST_LOG="$test_root/docker-env" \
    "$controller" router-status >"$test_root/output" 2>&1; then
  echo "expected an incomplete runtime bundle to be rejected" >&2
  exit 1
fi
grep -Fq 'Preview runtime bundle is incomplete' "$test_root/output"
