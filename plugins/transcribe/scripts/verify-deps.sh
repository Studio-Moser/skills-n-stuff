#!/bin/bash
# verify-deps.sh — Check that all transcribe plugin deps are present.
# Exit 0 if all present, 1 if any missing. Prints a table to stderr.

set -u

# Resolve from this script's own location, never from an env var. The whole
# point of the node_modules check below is "is *this* copy of the plugin
# installed", and each runtime (Claude Code, Codex, ...) gets its own copy.
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

missing=0
check() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    printf "  %-14s %s\n" "$name" "OK" >&2
  else
    printf "  %-14s %s\n" "$name" "MISSING" >&2
    missing=1
  fi
}

# Tier 2 only. Reported but never fatal: tiers 0 and 1 do not touch Playwright,
# and blocking a YouTube-caption fetch because a browser dep is absent would be
# a worse failure than the one it prevents. Tier 2 guards itself.
check_tier2() {
  local name="$1"
  local cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    printf "  %-14s %s\n" "$name" "OK" >&2
  else
    printf "  %-14s %s\n" "$name" "MISSING (tier 2 only)" >&2
  fi
}

echo "Checking transcribe plugin dependencies:" >&2
check "yt-dlp"       "yt-dlp --version || command -v uvx || python3 -c 'import yt_dlp'"
check "ffmpeg"       "command -v ffmpeg"
check "python3"      "command -v python3"
check "mlx-whisper"  "python3 -c 'import mlx_whisper'"
check "node"         "command -v node"
# The npm package, not just the browser binaries. A machine can have the
# Chromium download cached globally while this plugin copy has no node_modules
# at all, which used to pass this script and then die inside tier 2 with a raw
# ERR_MODULE_NOT_FOUND stack trace.
check_tier2 "playwright"   "test -d \"$PLUGIN_ROOT/node_modules/playwright\""
check_tier2 "chromium"     "test -d \"$HOME/.cache/ms-playwright\" || test -d \"$HOME/Library/Caches/ms-playwright\""

if [[ $missing -eq 1 ]]; then
  echo "" >&2
  echo "One or more dependencies are missing." >&2
  echo "Run: bash \"\${CLAUDE_PLUGIN_ROOT:-plugins/transcribe}/scripts/install.sh\"" >&2
  exit 1
fi

echo "All dependencies OK." >&2
exit 0
