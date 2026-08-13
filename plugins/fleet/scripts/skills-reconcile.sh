#!/usr/bin/env bash
# Compare the committed skills.manifest against reality (`npx skills list
# -g --json`, read on stdin) and this machine's local overrides
# ($repo/.fleet-local.json). READ-ONLY — prints a plan, installs/removes
# nothing. fleet:sync's Phase 2.6 acts on this output.
#
# One line per finding, tab-separated:
#   INSTALL      <name>  <source>   manifest entry not on this machine — install it
#   SKIP-INSTALL <name>              same, but skipInstall says leave it alone
#   EXTRA        <name>  <source>   on this machine, not in the manifest — offer add/remove
#   KEEP-LOCAL   <name>              same, but keepLocal says leave it alone
set -euo pipefail

repo="${1:?usage: skills-reconcile.sh <repo>  (reads npx skills list -g --json on stdin)}"
repo="${repo%/}"

py_reconcile="$(mktemp)"
trap 'rm -f "$py_reconcile"' EXIT

cat > "$py_reconcile" <<'PY'
import json, sys

repo = sys.argv[1]
manifest_path = repo + "/skills.manifest"
local_path = repo + "/.fleet-local.json"
store = repo + "/skills/"

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

reality = {}
for entry in json.load(sys.stdin):
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

python3 "$py_reconcile" "$repo"
