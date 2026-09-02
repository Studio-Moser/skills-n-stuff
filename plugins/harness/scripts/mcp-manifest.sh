#!/usr/bin/env bash
# Write a portable MCP inventory containing server names only, or validate one.
# Commands, arguments, URLs, headers, environment, credentials, OAuth data, and
# application state remain machine-local in Claude Code's global .claude.json file.
#
# The inventory is the union of every machine's user-scope server names: this
# machine's names are merged into the existing manifest, never substituted for
# it, so two machines with different servers stop flipping the file on every
# sync. A name leaves the manifest only when it is deleted by hand on a machine
# that no longer has it and no other machine still declares it.
# ponytail: union-only, so a server retired everywhere lingers until hand-removed;
# add a per-machine tombstone file if retirements need to propagate.
set -euo pipefail

validate_manifest() {
  python3 - "$1" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
try:
    lines = path.read_text().splitlines()
except OSError as error:
    print(f"MCP_MANIFEST_STATE=failed: unreadable {path}: {type(error).__name__}", file=sys.stderr)
    raise SystemExit(1)

valid = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
for number, line in enumerate(lines, 1):
    if not valid.fullmatch(line):
        print(f"MCP_MANIFEST_STATE=failed: invalid portable MCP server name at line {number}", file=sys.stderr)
        raise SystemExit(1)
if lines != sorted(set(lines)):
    print("MCP_MANIFEST_STATE=failed: inventory must be sorted with unique names", file=sys.stderr)
    raise SystemExit(1)
PY
}

if [ "${1:-}" = "--check" ]; then
  [ $# -eq 2 ] || { echo "usage: mcp-manifest.sh --check <mcp.manifest>" >&2; exit 2; }
  validate_manifest "$2"
  exit 0
fi

[ $# -eq 2 ] || { echo "usage: mcp-manifest.sh <claude-user-state.json> <mcp.manifest>" >&2; exit 2; }
user_state="$1"
manifest="$2"
parent="$(dirname "$manifest")"
[ -d "$parent" ] || { echo "mcp-manifest: target parent '$parent' is missing" >&2; exit 2; }
tmp="$(mktemp "$parent/.mcp.manifest.XXXXXX")"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

[ ! -e "$manifest" ] || validate_manifest "$manifest"

python3 - "$user_state" "$manifest" > "$tmp" <<'PY'
import json
from pathlib import Path
import re
import sys

try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception as error:
    print(f"MCP_MANIFEST_STATE=failed: Claude user state is not readable: {type(error).__name__}", file=sys.stderr)
    raise SystemExit(1)

servers = data.get("mcpServers", {})
if not isinstance(servers, dict):
    print("MCP_MANIFEST_STATE=failed: mcpServers must be an object", file=sys.stderr)
    raise SystemExit(1)

valid = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
for name in servers:
    if not valid.fullmatch(name):
        print("MCP_MANIFEST_STATE=failed: Claude user state contains an invalid server name", file=sys.stderr)
        raise SystemExit(1)

existing = Path(sys.argv[2])
declared = set(existing.read_text().splitlines()) if existing.exists() else set()
for name in sorted(declared | set(servers)):
    print(name)
PY

validate_manifest "$tmp"
mv "$tmp" "$manifest"
trap - EXIT HUP INT TERM
