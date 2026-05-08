#!/usr/bin/env bash
# check-prereqs.sh — Validates required CLI tools are available.
# Used by plugin hooks to catch missing dependencies early.
#
# Usage: check-prereqs.sh [backend]
#   backend: "github" (default) or "local"
#
# Exits 0 on success, 1 with error message on failure.

set -euo pipefail

backend="${1:-github}"
missing=()

# yq is required for all backends (YAML parsing)
if ! command -v yq &>/dev/null; then
  missing+=("yq (install: brew install yq)")
fi

# gh is required for GitHub backend
if [ "$backend" = "github" ]; then
  if ! command -v gh &>/dev/null; then
    missing+=("gh (install: brew install gh)")
  elif ! gh auth status &>/dev/null 2>&1; then
    missing+=("gh auth (run: gh auth login)")
  fi
fi

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing prerequisites:"
  for dep in "${missing[@]}"; do
    echo "  - $dep"
  done
  exit 1
fi
