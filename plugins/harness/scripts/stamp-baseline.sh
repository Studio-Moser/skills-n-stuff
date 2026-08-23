#!/usr/bin/env bash
# Idempotently stamp/refresh the Harness-managed block in a target file.
#   stamp-baseline.sh <target-file> [block-body-file]
# The optional body argument is a testing/explicit-source seam; production callers
# use the canonical template bundled with Harness.
# Replaces the content between the markers if present, else appends a fresh block.
# Never touches content outside the markers.
set -euo pipefail

[ $# -ge 1 ] && [ $# -le 2 ] || { echo "usage: stamp-baseline.sh <target-file> [block-body-file]" >&2; exit 2; }
target="$1"
harness="$(cd "$(dirname "$0")/.." && pwd)"
body_file="${2:-$harness/templates/AGENTS_Baseline.md}"
start="<!-- harness:baseline:start -->"
end="<!-- harness:baseline:end -->"

if [ ! -s "$body_file" ]; then
  echo "stamp-baseline: body file '$body_file' is empty or missing; refusing to stamp" >&2
  exit 2
fi

touch "$target"

if grep -qF "$start" "$target" && grep -qF "$end" "$target"; then
  # Replace the existing block in place, keeping everything outside the markers.
  awk -v s="$start" -v e="$end" -v bf="$body_file" '
    BEGIN { while ((getline line < bf) > 0) body = body line "\n" }
    $0 == s { print s; printf "%s", body; print e; skip = 1; next }
    $0 == e { skip = 0; next }
    !skip   { print }
  ' "$target" > "$target.tmp"
  mv "$target.tmp" "$target"
else
  {
    [ -s "$target" ] && printf '\n'
    printf '%s\n' "$start"
    cat "$body_file"
    printf '%s\n' "$end"
  } >> "$target"
fi
