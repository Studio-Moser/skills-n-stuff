#!/usr/bin/env bash
# Compare the committed skills.manifest against reality (`npx skills list
# -g --json`, read on stdin) and this machine's local overrides
# ($repo/.fleet-local.json). READ-ONLY — prints a plan, installs/removes
# nothing. fleet:sync's Phase 2.6 acts on this output.
#
# One line per finding, tab-separated:
#   INSTALL      <name>  <source>   manifest entry not on this machine — offer to install
#   SKIP-INSTALL <name>              same, but skipInstall says leave it alone
#   EXTRA        <name>  <source>   on this machine, not in the manifest — offer add/remove
#   KEEP-LOCAL   <name>              same, but keepLocal says leave it alone
set -euo pipefail

repo="${1:?usage: skills-reconcile.sh <repo>  (reads npx skills list -g --json on stdin)}"
repo="${repo%/}"

# `npx skills` hardcodes its install directory to $HOME/.agents/skills
# (getCanonicalSkillsDir) — it never looks at $FLEET_REPO. Diffing against
# "$repo/skills/" when $repo points somewhere else would make every real
# install look uninstalled and every declared entry look missing. Skip
# cleanly instead of reporting that.
canonical_agents="${HOME%/}/.agents"
if [ "$repo" != "$canonical_agents" ]; then
  echo "SKILLS_STATE=skipped: skill management requires \$FLEET_REPO=\$HOME/.agents (npx skills always installs under \$HOME/.agents/skills); this repo is $repo"
  exit 0
fi
store="$canonical_agents/skills/"

py_reconcile="$(mktemp)"
trap 'rm -f "$py_reconcile"' EXIT

cat > "$py_reconcile" <<'PY'
import json, sys

store, repo = sys.argv[1], sys.argv[2]
manifest_path = repo + "/skills.manifest"
local_path = repo + "/.fleet-local.json"

manifest = {}
try:
    with open(manifest_path) as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            name, _, source = line.partition("\t")
            manifest[name] = source
except FileNotFoundError:
    pass  # absent manifest == first run == nothing declared yet

try:
    with open(local_path) as f:
        overrides = json.load(f)
except FileNotFoundError:
    overrides = {}
skip_install = set(overrides.get("skipInstall", []))
keep_local = set(overrides.get("keepLocal", []))

# `npx skills list -g --json` can fail to produce valid JSON (offline, a
# registry error, a truncated pipe) — that must not traceback into the
# middle of a sync.
try:
    listing = json.load(sys.stdin)
except Exception as e:
    print(f"invalid or empty JSON on stdin: {e}", file=sys.stderr)
    sys.exit(1)

reality = {}
for entry in listing:
    source = entry.get("source")
    path = entry.get("path") or ""
    if source is None or not path.startswith(store):
        continue
    reality[entry.get("name", "")] = source

for name in sorted(manifest):
    if name in reality:
        continue
    if name in skip_install:
        print(f"SKIP-INSTALL\t{name}")
    else:
        print(f"INSTALL\t{name}\t{manifest[name]}")

for name in sorted(reality):
    if name in manifest:
        continue
    if name in keep_local:
        print(f"KEEP-LOCAL\t{name}")
    else:
        print(f"EXTRA\t{name}\t{reality[name]}")
PY

python3 "$py_reconcile" "$store" "$repo" \
  || { echo "SKILLS_STATE=failed: npx skills list -g --json produced no parseable output"; exit 1; }
