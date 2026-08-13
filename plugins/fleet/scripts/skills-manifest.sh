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

# `npx skills` hardcodes its install directory to $HOME/.agents/skills
# (getCanonicalSkillsDir) — it never looks at $FLEET_REPO. Filtering by
# "$repo/skills/" when $repo points somewhere else would make every real
# install look uninstalled, and step 1 below would happily write an empty
# manifest over a real one. Skip cleanly instead of producing that.
canonical_agents="${HOME%/}/.agents"
if [ "$repo" != "$canonical_agents" ]; then
  echo "SKILLS_STATE=skipped: skill management requires \$FLEET_REPO=\$HOME/.agents (npx skills always installs under \$HOME/.agents/skills); this repo is $repo"
  exit 0
fi
store="$canonical_agents/skills/"

manifest="$repo/skills.manifest"
gitignore="$repo/.gitignore"
start_marker="# fleet:skills start — generated, do not edit"
end_marker="# fleet:skills end"
# Both are machine-local and must never be committed: .fleet-local.json
# holds this machine's deliberate deviations, .skill-lock.json is `npx
# skills`' own lockfile, whose `source` field goes stale (never null→null,
# but null→wrong) the moment another machine removes a skill this one still
# has installed. See Phase 2.6's migration step for the tracked-repo case.
static_ignore_lines=".fleet-local.json
.skill-lock.json"

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

store, manifest_path = sys.argv[1], sys.argv[2]

# `npx skills list -g --json` can fail to produce valid JSON (offline, a
# registry error, a truncated pipe) — that must not traceback into the
# middle of a sync. One clean line to stderr, non-zero exit, and the
# manifest file below is never opened, so a bad run can't clobber a good one.
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f"invalid or empty JSON on stdin: {e}", file=sys.stderr)
    sys.exit(1)

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

python3 "$py_filter" "$store" "$manifest" \
  || { echo "SKILLS_STATE=failed: npx skills list -g --json produced no parseable output"; exit 1; }

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

# Static (non-generated) lines: add each once if missing, never duplicate.
while IFS= read -r static_line; do
  [ -n "$static_line" ] || continue
  grep -qxF "$static_line" "$tmp_gitignore" 2>/dev/null || printf '%s\n' "$static_line" >> "$tmp_gitignore"
done <<EOF
$static_ignore_lines
EOF

mv "$tmp_gitignore" "$gitignore"
