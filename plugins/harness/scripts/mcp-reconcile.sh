#!/usr/bin/env bash
# Compare mcp.manifest.json against this machine's live MCP registry.
# READ-ONLY: prints a per-host table, a blank line, then one plan line per
# finding. harness:sync's Phase 2.5 acts on the plan.
#
#   mcp-reconcile.sh <repo> <claude-user-state.json> <settings.local.json>
#
# Plan lines (tab-separated):
#   INSTALL       <name>          declared with a shape, not here
#   NO-CONFIG     <name>          declared without a shape; cannot install
#   SKIP          <name>          declared, not here, in .fleet-local.json skipMcp
#   EXTRA         <name>          here, not declared
#   KEEP-LOCAL    <name>          here, not declared, in keepLocalMcp
#   NEEDS-SECRET  <name> <VAR>    declared or installed here, but VAR has no value on this machine
#   UNRESOLVED    <name>          here, command not on PATH
#
# Never prints a command, URL, env value, or header value.
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: mcp-reconcile.sh <repo> <claude-user-state.json> <settings.local.json>" >&2; exit 2; }
repo="${1%/}"

python3 - "$repo/mcp.manifest.json" "$2" "$3" "$repo/.fleet-local.json" <<'PY'
import json, os, re, shutil, sys
from pathlib import Path

manifest_path, live_path, local_path, overrides_path = sys.argv[1:5]

class InputShapeError(ValueError):
    pass

def load(path, default):
    try:
        text = Path(path).read_text()
    except FileNotFoundError:
        return default
    value = default if not text.strip() else json.loads(text)
    if not isinstance(value, dict):
        raise InputShapeError("input must be a JSON object")
    return value

def fail(reason):
    print(f"MCP_RECONCILE_STATE=failed: {reason}", file=sys.stderr)
    raise SystemExit(1)

try:
    manifest = load(manifest_path, {"version": 1, "servers": {}})
    live = load(live_path, {})
    local = load(local_path, {})
    overrides = load(overrides_path, {})
except InputShapeError as error:
    fail(str(error))
except Exception as error:
    fail(f"input is not valid JSON: {type(error).__name__}")

declared = manifest.get("servers", {})
servers = live.get("mcpServers", {})
if not isinstance(declared, dict) or not isinstance(servers, dict):
    fail("servers must be objects")
def string_list(data, key):
    values = data.get(key, [])
    if not isinstance(values, list) or any(not isinstance(value, str) for value in values):
        fail(f"{key} must be a list of strings")
    return set(values)

disabled = string_list(local, "disabledMcpjsonServers")
skip = string_list(overrides, "skipMcp")
keep = string_list(overrides, "keepLocalMcp")

REF = re.compile(r"^\$\{([A-Z][A-Z0-9_]*)\}$")

def ref_name(*parts):
    return "_".join(re.sub(r"[^A-Za-z0-9]", "_", p).upper() for p in parts)

def has_shape(entry):
    return bool(set(entry) & {"command", "url"})

def resolves(entry):
    cmd = entry.get("command", "")
    if not cmd:
        return True
    return os.access(cmd, os.X_OK) if cmd.startswith("/") else shutil.which(cmd) is not None

# Values this machine already holds, by reference name.
known = {k for k, v in os.environ.items() if v}
for name, entry in servers.items():
    for key, value in (entry.get("env") or {}).items():
        if value and not REF.match(value):
            known.add(ref_name(key))
    for key, value in (entry.get("headers") or {}).items():
        if value and not REF.match(value):
            known.add(ref_name(name, key))

hosts = sorted({m for e in declared.values() for m in e.get("machines", [])})
columns = ["server"] + hosts + ["here", "note"]
rows = []
for name in sorted(set(declared) | set(servers)):
    entry = declared.get(name, {})
    row = [name]
    for h in hosts:
        row.append("x" if h in entry.get("machines", []) else "-")
    row.append("x" if name in servers else "-")
    note = ""
    if name in declared and not has_shape(entry):
        note = "no config in manifest"
    elif name in servers and not resolves(servers[name]):
        note = "command not on PATH"
    elif name in servers and not servers[name].get("command"):
        note = "remote (no local command)"
    elif name in disabled:
        note = "disabled here"
    row.append(note)
    rows.append(row)

widths = [max(len(str(r[i])) for r in [columns] + rows) for i in range(len(columns))]
for r in [columns] + rows:
    print("  ".join(str(c).ljust(widths[i]) for i, c in enumerate(r)).rstrip())
print()

plan = []
for name in sorted(declared):
    if name in disabled or name in servers:
        continue
    entry = declared[name]
    if not has_shape(entry):
        plan.append(("NO-CONFIG", name))
    elif name in skip:
        plan.append(("SKIP", name))
    else:
        plan.append(("INSTALL", name))
        refs = list((entry.get("env") or {}).values()) + list((entry.get("headers") or {}).values())
        for value in refs:
            m = REF.match(value)
            if m and m.group(1) not in known:
                finding = ("NEEDS-SECRET", name, m.group(1))
                if finding not in plan:
                    plan.append(finding)

for name in sorted(servers):
    if name in disabled:
        continue
    if name not in declared:
        plan.append(("KEEP-LOCAL", name) if name in keep else ("EXTRA", name))
    if not resolves(servers[name]):
        plan.append(("UNRESOLVED", name))

for name in sorted(servers):
    if name in disabled:
        continue
    entry = servers[name]
    refs = list((entry.get("env") or {}).values()) + list((entry.get("headers") or {}).values())
    for value in refs:
        m = REF.match(value)
        if m and m.group(1) not in known:
            finding = ("NEEDS-SECRET", name, m.group(1))
            if finding not in plan:
                plan.append(finding)

for line in plan:
    print("\t".join(line))
PY
