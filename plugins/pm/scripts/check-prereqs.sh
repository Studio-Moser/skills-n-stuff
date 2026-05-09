#!/usr/bin/env bash
# check-prereqs.sh — Validate required dependencies are present for the configured backend.
# Used by plugin SessionStart hook.
#
# Usage: check-prereqs.sh [backend]
#   backend: "github" (default) | "local" | "trello"

set -euo pipefail

backend="${1:-github}"
missing=()

# yq is required for all backends.
if ! command -v yq &>/dev/null; then
  missing+=("yq (install: brew install yq)")
fi

# jq is required for trello (and used elsewhere). Cheap check, always run.
if ! command -v jq &>/dev/null; then
  missing+=("jq (install: brew install jq)")
fi

case "$backend" in
  github)
    if ! command -v gh &>/dev/null; then
      missing+=("gh (install: brew install gh)")
    elif ! gh auth status &>/dev/null 2>&1; then
      missing+=("gh auth (run: gh auth login)")
    fi
    ;;
  trello)
    if [ -z "${TRELLO_API_KEY:-}" ]; then
      missing+=("TRELLO_API_KEY env var (set in your shell profile or .env)")
    fi
    if [ -z "${TRELLO_TOKEN:-}" ]; then
      missing+=("TRELLO_TOKEN env var (set in your shell profile or .env)")
    fi
    # Best-effort: warn (not fail) if the MCP server isn't installed.
    # We can't `--help` it (it's a stdio server, not a CLI), so just check the
    # npm cache / npx availability. The skill itself surfaces a clearer error
    # when the MCP tool calls fail.
    if ! command -v npx &>/dev/null; then
      missing+=("npx (install: brew install node)")
    fi
    ;;
  local)
    : # no extra deps
    ;;
  *)
    echo "check-prereqs.sh: unknown backend '$backend' (expected github|local|trello)" >&2
    exit 1
    ;;
esac

if [ ${#missing[@]} -gt 0 ]; then
  echo "Missing prerequisites for backend=$backend:" >&2
  for dep in "${missing[@]}"; do echo "  - $dep" >&2; done
  exit 1
fi
