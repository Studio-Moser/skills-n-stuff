#!/usr/bin/env bash
# Idempotently refresh PM's managed review baseline without touching project-owned text.
#   stamp-review-contract.sh <repository-root> [baseline-file] [project-template-file]
set -euo pipefail

[ $# -ge 1 ] && [ $# -le 3 ] || {
  echo "usage: stamp-review-contract.sh <repository-root> [baseline-file] [project-template-file]" >&2
  exit 2
}

repo_input="$1"
pm="$(cd "$(dirname "$0")/.." && pwd)"
baseline="${2:-$pm/templates/review-baseline.md}"
project_template="${3:-$pm/templates/review-project.md}"
start="<!-- pm:review-baseline:start -->"
end="<!-- pm:review-baseline:end -->"

[ -d "$repo_input" ] || {
  echo "stamp-review-contract: repository root '$repo_input' is missing" >&2
  exit 2
}
[ -s "$baseline" ] || {
  echo "stamp-review-contract: baseline '$baseline' is empty or missing" >&2
  exit 2
}
[ -s "$project_template" ] || {
  echo "stamp-review-contract: project template '$project_template' is empty or missing" >&2
  exit 2
}
if grep -qF "$start" "$baseline" || grep -qF "$end" "$baseline"; then
  echo "stamp-review-contract: baseline must not contain managed markers" >&2
  exit 2
fi

repo="$(cd "$repo_input" && pwd -P)"
target="$repo/REVIEW.md"
if [ -L "$target" ]; then
  echo "stamp-review-contract: target '$target' is a symlink; refusing to stamp" >&2
  exit 2
fi
if [ -e "$target" ] && [ ! -f "$target" ]; then
  echo "stamp-review-contract: target '$target' is not a regular file" >&2
  exit 2
fi
if [ -f "$target" ] && LC_ALL=C grep -q $'\r' "$target"; then
  echo "stamp-review-contract: REVIEW.md contains carriage returns; normalize it to LF before stamping" >&2
  exit 2
fi

tmp="$(mktemp "$repo/.REVIEW.md.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

start_count=0
end_count=0
if [ -f "$target" ]; then
  start_count="$(grep -cF "$start" "$target" || true)"
  end_count="$(grep -cF "$end" "$target" || true)"
fi
if [ "$start_count" -ne "$end_count" ] || [ "$start_count" -gt 1 ]; then
  echo "stamp-review-contract: REVIEW.md has malformed managed markers; refusing to rewrite it" >&2
  exit 2
fi

if [ "$start_count" -eq 1 ]; then
  start_line="$(grep -nF "$start" "$target" | cut -d: -f1)"
  end_line="$(grep -nF "$end" "$target" | cut -d: -f1)"
  if [ "$start_line" -ge "$end_line" ]; then
    echo "stamp-review-contract: REVIEW.md managed markers are out of order; refusing to rewrite it" >&2
    exit 2
  fi
  awk -v source_s="$start" -v source_e="$end" -v bf="$baseline" '
    BEGIN { while ((getline line < bf) > 0) body = body line "\n" }
    $0 == source_s { print source_s; printf "%s", body; print source_e; skip = 1; next }
    $0 == source_e { skip = 0; next }
    !skip { print }
  ' "$target" > "$tmp"
else
  {
    printf '%s\n' "$start"
    cat "$baseline"
    printf '%s\n\n' "$end"
    if [ -s "$target" ]; then
      cat "$target"
    else
      cat "$project_template"
    fi
  } > "$tmp"
fi

mv "$tmp" "$target"
trap - EXIT HUP INT TERM
