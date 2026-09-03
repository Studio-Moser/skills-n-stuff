#!/usr/bin/env bash
# Move MCP secret values between machines without the agents repo seeing them.
#
#   mcp-secrets.sh export [--stdout] <mcp.manifest.json> <claude-user-state.json>
#       Print NAME=value for every ${NAME} the manifest references, NAME= when
#       this registry has no value. Refuses when stdout is not a terminal
#       unless --stdout is given, so an agent cannot capture it silently.
#
#   mcp-secrets.sh import <claude-user-state.json>
#       Read NAME=value lines on stdin and write each value into every live
#       server whose env key or header reference matches. Empty values are
#       skipped. Prints counts only.
set -euo pipefail

mode="${1:-}"
shift || true

case "$mode" in
  export)
    allow_pipe=0
    if [ "${1:-}" = "--stdout" ]; then allow_pipe=1; shift; fi
    [ $# -eq 2 ] || { echo "usage: mcp-secrets.sh export [--stdout] <mcp.manifest.json> <claude-user-state.json>" >&2; exit 2; }
    if [ ! -t 1 ] && [ "$allow_pipe" -ne 1 ]; then
      echo "MCP_SECRETS_STATE=refused: stdout is not a terminal; pass --stdout to export anyway" >&2
      exit 1
    fi
    python3 - "$1" "$2" <<'PY'
import json, re, sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text())
live = json.loads(Path(sys.argv[2]).read_text())
REF = re.compile(r"^\$\{([A-Z][A-Z0-9_]*)\}$")

def ref_name(*parts):
    return "_".join(re.sub(r"[^A-Za-z0-9]", "_", p).upper() for p in parts)

wanted = set()
for entry in manifest.get("servers", {}).values():
    for value in list((entry.get("env") or {}).values()) + list((entry.get("headers") or {}).values()):
        m = REF.match(value)
        if m:
            wanted.add(m.group(1))

values = {}
for name, entry in live.get("mcpServers", {}).items():
    for key, value in (entry.get("env") or {}).items():
        if value and not REF.match(value):
            values[ref_name(key)] = value
    for key, value in (entry.get("headers") or {}).items():
        if value and not REF.match(value):
            values[ref_name(name, key)] = value

for name in sorted(wanted):
    print(f"{name}={values.get(name, '')}")
PY
    ;;
  import)
    [ $# -eq 1 ] || { echo "usage: mcp-secrets.sh import <claude-user-state.json>" >&2; exit 2; }
    registry="$1"
    parent="$(dirname "$registry")"
    tmp="$(mktemp "$parent/.claude.json.secrets.XXXXXX")"
    incoming_file="$(mktemp "$parent/.claude.json.secrets-input.XXXXXX")"
    trap 'rm -f "$tmp" "$incoming_file"' EXIT HUP INT TERM
    cat > "$incoming_file"
    python3 - "$registry" "$tmp" "$incoming_file" <<'PY'
import json, re, sys
from pathlib import Path

registry, out, incoming_file = sys.argv[1:4]
try:
    live = json.loads(Path(registry).read_text())
except Exception as error:
    print(f"MCP_SECRETS_STATE=failed: registry is not readable: {type(error).__name__}", file=sys.stderr)
    raise SystemExit(1)

def ref_name(*parts):
    return "_".join(re.sub(r"[^A-Za-z0-9]", "_", p).upper() for p in parts)

incoming = {}
for line in Path(incoming_file).read_text().splitlines():
    name, sep, value = line.partition("=")
    name = name.strip()
    if not sep or not re.fullmatch(r"[A-Z][A-Z0-9_]*", name) or not value:
        continue
    incoming[name] = value

written = 0
touched = set()
for name, entry in live.get("mcpServers", {}).items():
    env = entry.get("env") or {}
    for key in list(env):
        ref = ref_name(key)
        if ref in incoming:
            env[key] = incoming[ref]
            written += 1
            touched.add(name)
    headers = entry.get("headers") or {}
    for key in list(headers):
        ref = ref_name(name, key)
        if ref in incoming:
            headers[key] = incoming[ref]
            written += 1
            touched.add(name)

Path(out).write_text(json.dumps(live, indent=2) + "\n")
print(f"MCP_SECRETS_STATE=imported {written} value(s) into {len(touched)} server(s)")
PY
    mv "$tmp" "$registry"
    trap - EXIT HUP INT TERM
    rm -f "$incoming_file"
    ;;
  *)
    echo "usage: mcp-secrets.sh export|import ..." >&2
    exit 2
    ;;
esac
