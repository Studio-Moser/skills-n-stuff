#!/usr/bin/env bash
# Generate or validate the portable MCP manifest (mcp.manifest.json).
#
#   mcp-manifest.sh [--prune-to-local] <claude-user-state.json> <mcp.manifest.json>
#   mcp-manifest.sh --check <mcp.manifest.json>
#
# The manifest carries each user-scope server's portable shape (type, command,
# args, url, env, headers) with every env and header VALUE replaced by a
# ${NAME} reference, plus a `machines` list naming the hosts that have it.
# Secret values, OAuth state, and everything else stay in the live registry.
# Undeclared live servers in `.fleet-local.json` `keepLocalMcp` stay undeclared.
#
# Env: MCP_HOSTNAME overrides `hostname -s`. MCP_ALLOW_EMPTY_MANIFEST=1 lets
# the generator replace a non-empty manifest with an empty server set.
set -euo pipefail

py_common='
import json, os, re, sys

PORTABLE = {"type", "command", "args", "url", "env", "headers"}
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
REF_RE = re.compile(r"^\$\{[A-Z][A-Z0-9_]*\}$")
TOKEN_RE = re.compile(
    r"(?:ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{16,}|"
    r"xox[abp]-[A-Za-z0-9-]{10,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,}|gsk_[A-Za-z0-9]{20,})"
)
FLAG_RE = re.compile(r"^--?[A-Za-z][A-Za-z0-9_-]*=(.{16,})$")

def fail(reason):
    print(f"MCP_MANIFEST_STATE=failed: {reason}", file=sys.stderr)
    raise SystemExit(1)

def ref_name(*parts):
    return "${" + "_".join(re.sub(r"[^A-Za-z0-9]", "_", p).upper() for p in parts) + "}"

def home_prefixes():
    home = os.environ.get("HOME", "")
    prefixes = ["/Users/", "/home/"]
    if home and home not in ("/",):
        prefixes.append(home.rstrip("/") + "/")
    return tuple(prefixes)

def is_machine_path(value):
    return isinstance(value, str) and value.startswith(home_prefixes())

def is_secret_like(value):
    if not isinstance(value, str):
        return False
    if TOKEN_RE.search(value):
        return True
    return bool(FLAG_RE.match(value))

def validate_shape(name, entry):
    if not NAME_RE.fullmatch(name):
        fail("invalid portable MCP server name")
    if not isinstance(entry, dict):
        fail(f"server {name} is not an object")
    extra = set(entry) - PORTABLE - {"machines"}
    if extra:
        fail(f"server {name} has a non-portable key")
    for key in ("env", "headers"):
        values = entry.get(key, {})
        if not isinstance(values, dict):
            fail(f"server {name} {key} must be an object")
        for value in values.values():
            if not isinstance(value, str) or not REF_RE.fullmatch(value):
                fail(f"server {name} has an unredacted {key} value")
    args = entry.get("args", [])
    if not isinstance(args, list) or any(not isinstance(a, str) for a in args):
        fail(f"server {name} args must be a list of strings")
    for value in [entry.get("command", "")] + args:
        if is_secret_like(value):
            fail(f"server {name} has a secret-like argument")
        if is_machine_path(value):
            fail(f"server {name} uses a machine-specific path")
    machines = entry.get("machines")
    if not isinstance(machines, list) or any(not isinstance(m, str) for m in machines):
        fail(f"server {name} machines must be a list of strings")
    if machines != sorted(set(machines)):
        fail(f"server {name} machines must be sorted and unique")

def validate_manifest(data):
    if not isinstance(data, dict) or data.get("version") != 1:
        fail("manifest version must be 1")
    servers = data.get("servers")
    if not isinstance(servers, dict):
        fail("manifest servers must be an object")
    if list(servers) != sorted(servers):
        fail("manifest servers must be sorted by name")
    for name, entry in servers.items():
        validate_shape(name, entry)
'

if [ "${1:-}" = "--check" ]; then
  [ $# -eq 2 ] || { echo "usage: mcp-manifest.sh --check <mcp.manifest.json>" >&2; exit 2; }
  python3 - "$2" <<PY
$py_common
from pathlib import Path
path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text())
except FileNotFoundError:
    fail(f"missing {path}")
except Exception as error:
    fail(f"manifest is not valid JSON: {type(error).__name__}")
validate_manifest(data)
PY
  exit 0
fi

prune=0
if [ "${1:-}" = "--prune-to-local" ]; then
  prune=1
  shift
fi
[ $# -eq 2 ] || { echo "usage: mcp-manifest.sh [--prune-to-local] <claude-user-state.json> <mcp.manifest.json>" >&2; exit 2; }
user_state="$1"
manifest="$2"
parent="$(dirname "$manifest")"
[ -d "$parent" ] || { echo "mcp-manifest: target parent '$parent' is missing" >&2; exit 2; }
legacy="$parent/mcp.manifest"
host="${MCP_HOSTNAME:-$(hostname -s)}"

tmp="$(mktemp "$parent/.mcp.manifest.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT HUP INT TERM

state="$(python3 - "$user_state" "$manifest" "$legacy" "$host" "$prune" "$tmp" <<PY
$py_common
from pathlib import Path

user_state, manifest_path, legacy_path, host, prune, out = sys.argv[1:7]
prune = prune == "1"

try:
    live = json.loads(Path(user_state).read_text())
except Exception as error:
    fail(f"Claude user state is not readable: {type(error).__name__}")
servers = live.get("mcpServers", {})
if not isinstance(servers, dict):
    fail("mcpServers must be an object")

state = "written"
old = {"version": 1, "servers": {}}
if Path(manifest_path).exists():
    try:
        old = json.loads(Path(manifest_path).read_text())
    except Exception as error:
        fail(f"existing manifest is not valid JSON: {type(error).__name__}")
    validate_manifest(old)
elif Path(legacy_path).exists():
    state = "migrated"
    for line in Path(legacy_path).read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        if not NAME_RE.fullmatch(line):
            fail("invalid portable MCP server name in legacy manifest")
        old["servers"][line] = {"machines": []}

try:
    fleet_local = json.loads(Path(os.path.join(os.path.dirname(manifest_path), ".fleet-local.json")).read_text())
except FileNotFoundError:
    fleet_local = {}
except Exception as error:
    fail(f"fleet-local overrides are not readable: {type(error).__name__}")
if not isinstance(fleet_local, dict):
    fail("fleet-local overrides must be an object")
keep_local_raw = fleet_local.get("keepLocalMcp", [])
if not isinstance(keep_local_raw, list) or not all(isinstance(name, str) for name in keep_local_raw):
    fail("fleet-local keepLocalMcp must be a list of strings")
keep_local = set(keep_local_raw)

result = {}
for name, entry in old["servers"].items():
    if name in servers:
        continue
    if prune:
        continue
    kept = dict(entry)
    kept["machines"] = sorted(set(kept.get("machines", [])) - {host})
    result[name] = kept

for name, entry in servers.items():
    if name not in old["servers"] and name in keep_local:
        continue
    if not NAME_RE.fullmatch(name):
        fail("invalid portable MCP server name")
    if not isinstance(entry, dict):
        fail(f"server {name} is not an object")
    shape = {}
    for key in ("type", "command", "url"):
        if key in entry:
            shape[key] = entry[key]
    if "args" in entry:
        shape["args"] = list(entry["args"])
    if isinstance(entry.get("env"), dict) and entry["env"]:
        shape["env"] = {k: ref_name(k) for k in sorted(entry["env"])}
    if isinstance(entry.get("headers"), dict) and entry["headers"]:
        shape["headers"] = {k: ref_name(name, k) for k in sorted(entry["headers"])}
    previous = old["servers"].get(name, {}).get("machines", [])
    shape["machines"] = sorted(set(previous) | {host})
    validate_shape(name, shape)
    result[name] = shape

if old["servers"] and not result and os.environ.get("MCP_ALLOW_EMPTY_MANIFEST") != "1":
    fail("refusing to write an empty manifest over a non-empty one; set MCP_ALLOW_EMPTY_MANIFEST=1 to confirm")

data = {"version": 1, "servers": {k: result[k] for k in sorted(result)}}
validate_manifest(data)
Path(out).write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
print(state)
PY
)"

mv "$tmp" "$manifest"
trap - EXIT HUP INT TERM

if [ "$state" = "migrated" ]; then
  if git -C "$parent" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$parent" rm --cached --ignore-unmatch -q mcp.manifest
  fi
  rm -f "$legacy"
fi
echo "MCP_MANIFEST_STATE=$state"
