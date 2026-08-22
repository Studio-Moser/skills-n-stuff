#!/bin/bash
set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_BIN="$(mktemp -d)"

cleanup() {
  rm -f "$TEST_BIN/yt-dlp"
  rmdir "$TEST_BIN"
}
trap cleanup EXIT

cat > "$TEST_BIN/yt-dlp" <<'STUB'
#!/bin/bash
set -euo pipefail

if [[ "${1:-}" == "--version" ]]; then
  echo "test"
  exit 0
fi

if [[ " $* " == *" --print "* ]]; then
  echo "Partial captions test|||42"
  exit 0
fi

output=""
while (($#)); do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    break
  fi
  shift
done

output="$(printf '%s' "$output" | sed 's/%(ext)s/en.vtt/')"
cat > "$output" <<'VTT'
WEBVTT

00:00:00.000 --> 00:00:02.000
usable captions
VTT

# Simulate yt-dlp downloading a usable track before a later track is rate-limited.
exit 1
STUB
chmod +x "$TEST_BIN/yt-dlp"

result="$(PATH="$TEST_BIN:$PATH" "$PLUGIN_ROOT/bin/transcribe" \
  "https://www.youtube.com/watch?v=partial-test" --json)"

RESULT="$result" python3 - <<'PY'
import json
import os

result = json.loads(os.environ["RESULT"])
assert result["tier"] == "youtube-captions-manual", result
assert result["text"] == "usable captions", result
PY
