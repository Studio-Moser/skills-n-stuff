#!/bin/bash
# install.sh — One-time install for the transcribe plugin.
# Installs: yt-dlp, ffmpeg, mlx-whisper, Node.js, Playwright Chromium.
#
# Apple Silicon only. Intel Macs and Linux are not supported in v0.1.

set -euo pipefail

# ── Platform check ───────────────────────────────────────────────────────────

if [[ "$(uname)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "ERROR: transcribe plugin v0.1 supports Apple Silicon only." >&2
  echo "Detected: $(uname) $(uname -m)" >&2
  exit 1
fi

# ── Homebrew ─────────────────────────────────────────────────────────────────

if ! command -v brew >/dev/null 2>&1; then
  echo "ERROR: Homebrew is required. Install from https://brew.sh and retry." >&2
  exit 1
fi

echo "→ Installing system packages via Homebrew..."
for pkg in yt-dlp ffmpeg node; do
  if brew list --formula "$pkg" >/dev/null 2>&1; then
    echo "  $pkg already installed."
  else
    brew install "$pkg"
  fi
done

# ── mlx-whisper ──────────────────────────────────────────────────────────────

echo "→ Installing mlx-whisper..."
if python3 -c "import mlx_whisper" >/dev/null 2>&1; then
  echo "  mlx-whisper already installed."
else
  pip3 install --break-system-packages mlx-whisper
fi

# ── Playwright Chromium ──────────────────────────────────────────────────────

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

echo "→ Installing Playwright and Chromium..."
pushd "$PLUGIN_ROOT" >/dev/null
if [[ ! -f package.json ]]; then
  cat > package.json <<'JSON'
{
  "name": "transcribe-plugin",
  "version": "0.1.0",
  "private": true,
  "dependencies": {
    "playwright": "^1.48.0"
  }
}
JSON
fi
npm install --no-audit --no-fund
npx playwright install chromium
popd >/dev/null

# ── Profile dir ──────────────────────────────────────────────────────────────

mkdir -p "$HOME/.cache/transcribe-plugin/playwright-profile"

echo ""
echo "Install complete. Verify with: bash $PLUGIN_ROOT/scripts/verify-deps.sh"
