#!/usr/bin/env bash
# Resolve the user-global model-rubric path; --check reports set/unset.
#   rubric-path.sh          -> prints the resolved absolute path
#   rubric-path.sh --check  -> prints "set" if a usable rubric exists, else "unset"
set -euo pipefail

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
rubric_path="$config_home/studio-moser/model-rubric.yml"

if [ "${1:-}" = "--check" ]; then
  if [ -s "$rubric_path" ] && yq -e '.models' "$rubric_path" >/dev/null 2>&1; then
    echo "set"
  else
    echo "unset"
  fi
  exit 0
fi

echo "$rubric_path"
