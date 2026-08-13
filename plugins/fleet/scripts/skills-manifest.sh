#!/usr/bin/env bash
# Regenerate $repo/skills.manifest and the fleet:skills block in
# $repo/.gitignore from `npx skills list -g --json` (read on stdin).
#
# WRITE: overwrites skills.manifest and the generated .gitignore block.
# Everything in .gitignore outside the markers is preserved verbatim.
#
# Called by fleet:sync's Phase 2.6 — and only after that phase's installs
# have run. Regenerating from a fresh machine's `npx skills list` output
# before anything is installed would produce an empty manifest and wipe the
# developer's declaration; see sync/SKILL.md Phase 2.6 for the ordering.
set -euo pipefail

repo="${1:?usage: skills-manifest.sh <repo>  (reads npx skills list -g --json on stdin)}"
repo="${repo%/}"

manifest="$repo/skills.manifest"
gitignore="$repo/.gitignore"
start_marker="# fleet:skills start — generated, do not edit"
end_marker="# fleet:skills end"
static_ignore_line=".fleet-local.json"

# --- 1. Filter the JSON down to name<TAB>source, sorted, and write the
#        manifest. Only entries with a non-null source AND a path under
#        this repo's skills store are ours — anything else is either
#        locally-authored (source: null) or belongs to another agent's
#        store (path outside $repo/skills/).
#
# The python source goes to its own temp file rather than a `python3 -
# <<PY` heredoc: `python3 -` reads the *program* from stdin, which would
# consume the JSON this script is piped on stdin before json.load() ever
# ran. Writing the program to a file frees stdin for the actual JSON.
py_filter="$(mktemp)"
block_file="$(mktemp)"
tmp_gitignore="$(mktemp)"
trap 'rm -f "$py_filter" "$block_file" "$tmp_gitignore"' EXIT

cat > "$py_filter" <<'PY'
import json, sys

repo, manifest_path = sys.argv[1], sys.argv[2]
store = repo + "/skills/"

data = json.load(sys.stdin)
entries = []
for entry in data:
    source = entry.get("source")
    path = entry.get("path") or ""
    if source is None:
        continue
    if not path.startswith(store):
        continue
    entries.append((entry.get("name", ""), source))

with open(manifest_path, "w") as f:
    for name, source in sorted(entries):
        f.write(f"{name}\t{source}\n")
PY

python3 "$py_filter" "$repo" "$manifest"

# --- 2. Build the generated block from the manifest just written.

{
  printf '%s\n' "$start_marker"
  while IFS=$'\t' read -r name _source; do
    [ -n "$name" ] || continue
    printf 'skills/%s/\n' "$name"
  done < "$manifest"
  printf '%s\n' "$end_marker"
} > "$block_file"

# --- 3. Splice the block into .gitignore, replacing an existing block
#        in place or appending a new one, and never touching anything
#        outside the markers.

found_block=0
if [ -f "$gitignore" ]; then
  in_block=0
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$line" = "$start_marker" ]; then
      found_block=1
      in_block=1
      cat "$block_file" >> "$tmp_gitignore"
      continue
    fi
    if [ "$in_block" -eq 1 ]; then
      [ "$line" = "$end_marker" ] && in_block=0
      continue
    fi
    printf '%s\n' "$line" >> "$tmp_gitignore"
  done < "$gitignore"
fi

if [ "$found_block" -eq 0 ]; then
  [ -s "$tmp_gitignore" ] && printf '\n' >> "$tmp_gitignore"
  cat "$block_file" >> "$tmp_gitignore"
fi

# .fleet-local.json is machine-local and must never be committed; it lives
# in the static (non-generated) part of .gitignore, so add it once if
# missing rather than regenerating it every run.
grep -qxF "$static_ignore_line" "$tmp_gitignore" 2>/dev/null || printf '%s\n' "$static_ignore_line" >> "$tmp_gitignore"

mv "$tmp_gitignore" "$gitignore"
