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
#
# Usage: skills-manifest.sh <repo> [failed-name ...]
#
# Trailing args name manifest entries whose install failed *this run* (see
# Phase 2.6 step 2) — they're absent from reality for a known, transient
# reason and must survive regeneration, same as a skipInstall entry, or a
# retriable failure would get silently un-declared on the very next sync.
set -euo pipefail

repo="${1:?usage: skills-manifest.sh <repo> [failed-name ...]  (reads npx skills list -g --json on stdin)}"
repo="${repo%/}"
shift
failed_names="$*"

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
local_file="$repo/.fleet-local.json"
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
import json, os, sys

store, manifest_path, local_path = sys.argv[1], sys.argv[2], sys.argv[3]
failed_names = set(sys.argv[4].split())

# `npx skills list -g --json` can fail to produce valid JSON (offline, a
# registry error, a truncated pipe) — that must not traceback into the
# middle of a sync. One clean line to stderr, non-zero exit, and the
# manifest file below is never opened, so a bad run can't clobber a good one.
try:
    data = json.load(sys.stdin)
except Exception as e:
    print(f"invalid or empty JSON on stdin: {e}", file=sys.stderr)
    sys.exit(1)

reality = {}
for entry in data:
    source = entry.get("source")
    path = entry.get("path") or ""
    if source is None:
        continue
    if not path.startswith(store):
        continue
    reality[entry.get("name", "")] = source

# The manifest is the shared declaration; the .fleet-local.json overrides are
# local reasons this machine's reality differs from it. A local reason must
# never edit the shared declaration — in EITHER direction:
#
#   skipInstall / this-run install failure — declared but not here. Preserve
#     the declaration; absence here is not a removal for everyone else.
#   keepLocal — here but deliberately undeclared. Do not add it. Without this,
#     a "leave it undeclared" choice was written into the manifest on the very
#     same run and pushed fleet-wide, which is the mirror of the bug above.
#
# Anything declared-but-absent with no recorded reason is a genuine removal and
# correctly drops out — that is the only case allowed to un-declare something.
#
# keepLocal is deliberately powerless over an already-declared skill: if the
# manifest already carries it, another machine declared it, and dropping it
# here would be exactly the local-edits-shared move this rule forbids. In that
# case the declaration wins and the override is moot.
old_manifest = {}
try:
    with open(manifest_path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            name, _, source = line.partition("\t")
            old_manifest[name] = source
except FileNotFoundError:
    pass

try:
    with open(local_path) as f:
        overrides = json.load(f)
except FileNotFoundError:
    overrides = {}
skip_install = set(overrides.get("skipInstall", []))
keep_local = set(overrides.get("keepLocal", []))

# here, minus anything deliberately kept undeclared (unless already declared)
entries = {
    name: source
    for name, source in reality.items()
    if name not in keep_local or name in old_manifest
}
# plus anything declared that is absent here for a recorded reason
for name, source in old_manifest.items():
    if name in entries:
        continue
    if name in skip_install or name in failed_names:
        entries[name] = source

# Backstop: this exact shape (a good manifest silently replaced by an empty
# one) has already caused a silent wipe by two different routes in review.
# Refuse instead of guessing — SKILLS_ALLOW_EMPTY_MANIFEST=1 is the explicit
# human confirmation that every declared skill is genuinely gone.
if old_manifest and not entries and os.environ.get("SKILLS_ALLOW_EMPTY_MANIFEST") != "1":
    print(
        f"REFUSING to overwrite a manifest with {len(old_manifest)} entrie(s) with an "
        "empty result. If every declared skill is genuinely gone from this machine, "
        "rerun with SKILLS_ALLOW_EMPTY_MANIFEST=1 to confirm.",
        file=sys.stderr,
    )
    sys.exit(1)

with open(manifest_path, "w") as f:
    for name, source in sorted(entries.items()):
        f.write(f"{name}\t{source}\n")
PY

python3 "$py_filter" "$store" "$manifest" "$local_file" "$failed_names" \
  || { echo "SKILLS_STATE=failed: skills.manifest not regenerated (see error above)"; exit 1; }

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
# (Phase 2.6 step 0 also ensures these exist unconditionally, since this
# step is skipped on a machine with no npx/node — this is a second,
# idempotent pass, not a second source of truth.)
while IFS= read -r static_line; do
  [ -n "$static_line" ] || continue
  grep -qxF "$static_line" "$tmp_gitignore" 2>/dev/null || printf '%s\n' "$static_line" >> "$tmp_gitignore"
done <<EOF
$static_ignore_lines
EOF

mv "$tmp_gitignore" "$gitignore"
