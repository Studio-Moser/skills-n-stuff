#!/bin/bash
# verify-deps.sh — Check that all transcribe plugin deps are present.
# Exit 0 if all present, 1 if any missing. Prints a table to stderr.

set -u

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

echo "Checking transcribe plugin dependencies:" >&2
check "yt-dlp"       "command -v yt-dlp"
check "ffmpeg"       "command -v ffmpeg"
check "python3"      "command -v python3"
check "mlx-whisper"  "python3 -c 'import mlx_whisper'"
check "node"         "command -v node"
check "chromium"     "test -d \"$HOME/.cache/ms-playwright\" || test -d \"$HOME/Library/Caches/ms-playwright\""

if [[ $missing -eq 1 ]]; then
  echo "" >&2
  echo "One or more dependencies are missing." >&2
  echo "Run: bash \"\${CLAUDE_PLUGIN_ROOT:-plugins/transcribe}/scripts/install.sh\"" >&2
  exit 1
fi

echo "All dependencies OK." >&2
exit 0
