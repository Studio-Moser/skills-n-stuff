#!/usr/bin/env bash
# Idempotently stamp/refresh the studio-baseline managed block in a target file.
#   stamp-baseline.sh <target-file> <block-body-file>
# Replaces the content between the markers if present, else appends a fresh block.
# Never touches content outside the markers.
set -euo pipefail

target="$1"
body_file="$2"
start="<!-- studio-baseline:start -->"
end="<!-- studio-baseline:end -->"

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
