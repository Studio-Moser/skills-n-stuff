# Portable MCP Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the names-only `mcp.manifest` with a secret-free `mcp.manifest.json` that carries each server's portable shape and per-machine presence, and give `harness:sync` an interactive match / replace / merge step plus a secrets export and import helper.

**Architecture:** Three scripts under `plugins/harness/scripts`, one concern each: `mcp-manifest.sh` (generator, migration, `--check`, `--prune-to-local`), `mcp-reconcile.sh` (read-only table and plan), `mcp-secrets.sh` (`export` and `import`). The sync skill text drives them the same way it drives the skills phase. The finalizer validates the new file. Each script has one bats file.

**Tech Stack:** bash, python3 (stdlib only), bats 1.14, git. No new dependencies.

**Spec:** `docs/superpowers/specs/Portable MCP Sync Design-2026-09-02.md`

## Global Constraints

- Tracked manifest path is `mcp.manifest.json` at the agents repo root. The old `mcp.manifest` is migrated once and removed.
- Portable keys are exactly `type`, `command`, `args`, `url`, `env`, `headers`, plus the generated `machines`.
- Every `env` and `headers` value in the manifest matches `^\$\{[A-Z][A-Z0-9_]*\}$`. Header references are `${<SERVER>_<HEADER>}` uppercased with every non-alphanumeric replaced by `_`.
- A key-like arg (token pattern, or `--flag=value` with a value of 16 or more characters) fails the generator naming the server only. An absolute home path in `command` or `args` fails the same way.
- Hostname comes from `MCP_HOSTNAME` when set, otherwise `hostname -s`. Tests always set `MCP_HOSTNAME`.
- The generator refuses to write an empty server set over a non-empty manifest unless `MCP_ALLOW_EMPTY_MANIFEST=1`.
- No script prints a secret value, an env value, a header value, or a registry path with a value in it. Findings name servers and variable names only.
- `.fleet-local.json` gains `skipMcp` and `keepLocalMcp`. It stays untracked.
- All scripts: `set -euo pipefail`, python3 via heredoc, atomic writes with `mktemp` in the target directory and `mv`.
- Plugin version bumps from `0.8.3` to `0.9.0` in `plugins/harness/.claude-plugin/plugin.json` and the harness entry of `.claude-plugin/marketplace.json`.
- Run the suite with `plugins/harness/tests/run-tests.sh` from the repo root. Every task ends green.
- Commit messages end with the session's attribution trailer:

```
Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Q7LbNXbWw7isyrhgBFzDHy
```

---

## File map

| File | Responsibility |
|---|---|
| `plugins/harness/scripts/mcp-manifest.sh` | Rewrite. Generate `mcp.manifest.json` from the live registry, migrate the names-only file, validate with `--check`, prune with `--prune-to-local`. |
| `plugins/harness/tests/mcp-manifest.bats` | Rewrite. Generator and check behaviours. |
| `plugins/harness/scripts/mcp-reconcile.sh` | New. Read-only table and plan lines. |
| `plugins/harness/tests/mcp-reconcile.bats` | New. |
| `plugins/harness/scripts/mcp-secrets.sh` | New. `export` and `import`. |
| `plugins/harness/tests/mcp-secrets.bats` | New. |
| `plugins/harness/scripts/sync-finalize.sh:76` | Validate `mcp.manifest.json`. |
| `plugins/harness/tests/sync-finalize.bats` | Two new scan cases. |
| `plugins/harness/tests/sync-workflow.bats:83,100` | New filename and JSON assertion. |
| `plugins/harness/skills/sync/SKILL.md` | Dry run, 2.3, 2.5 MCP half, overrides, 3.75, Phase 4. |
| `plugins/harness/tests/sync-procedure.bats` | Marker and manifest updates. |
| `plugins/harness/README.md:153` | Scripts table. |
| `plugins/harness/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Version 0.9.0. |

---

### Task 1: Rewrite `mcp-manifest.sh` as the JSON generator

**Files:**
- Modify: `plugins/harness/scripts/mcp-manifest.sh` (full rewrite)
- Modify: `plugins/harness/tests/mcp-manifest.bats` (full rewrite)

**Interfaces:**
- Consumes: Claude Code's user registry JSON with a top-level `mcpServers` object.
- Produces: `mcp-manifest.sh [--prune-to-local] <live-registry> <manifest.json>` writes the manifest and prints `MCP_MANIFEST_STATE=written|migrated` on stdout. `mcp-manifest.sh --check <manifest.json>` exits 0 on a valid file, 1 with `MCP_MANIFEST_STATE=failed: <reason>` on stderr. Exit 2 on usage errors. Env: `MCP_HOSTNAME`, `MCP_ALLOW_EMPTY_MANIFEST`.
- The manifest shape, used by Tasks 3, 4, and 5:

```json
{"version": 1, "servers": {"<name>": {"type": "...", "command": "...", "args": [], "url": "...", "env": {"K": "${K}"}, "headers": {"H": "${NAME_H}"}, "machines": ["host"]}}}
```

- [ ] **Step 1: Write the failing tests**

Replace `plugins/harness/tests/mcp-manifest.bats` with:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mcp-manifest.sh"
  DIR="${BATS_TEST_TMPDIR}/agents"
  mkdir -p "$DIR"
  RUNTIME="${BATS_TEST_TMPDIR}/claude.json"
  MANIFEST="$DIR/mcp.manifest.json"
  export MCP_HOSTNAME="test-host"
}

field() {
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d = d[k] if isinstance(d, dict) else d[int(k)]
print(json.dumps(d, sort_keys=True))' "$MANIFEST" "$@"
}

@test "generator keeps portable keys, redacts env and headers, and stamps this host" {
  cat > "$RUNTIME" <<'JSON'
{
  "mcpServers": {
    "zeta": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@acme/zeta"],
      "env": {"ZETA_TOKEN": "do-not-copy"},
      "oauth": {"refresh": "do-not-copy-either"}
    },
    "alpha": {
      "type": "http",
      "url": "https://example.invalid/mcp",
      "headers": {"Authorization": "Bearer do-not-copy"}
    }
  }
}
JSON

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=written"* ]] || return 1

  [ "$(field version)" = "1" ]
  [ "$(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1]))["servers"]))' "$MANIFEST")" = "['alpha', 'zeta']" ]
  [ "$(field servers zeta env ZETA_TOKEN)" = '"${ZETA_TOKEN}"' ]
  [ "$(field servers alpha headers Authorization)" = '"${ALPHA_AUTHORIZATION}"' ]
  [ "$(field servers zeta machines)" = '["test-host"]' ]
  [ "$(field servers zeta args)" = '["-y", "@acme/zeta"]' ]
  run cat "$MANIFEST"
  [[ "$output" != *"do-not-copy"* ]] || return 1
  [[ "$output" != *"oauth"* ]]
}

@test "generator preserves other hosts and removes this host from servers no longer here" {
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "gone": {"type": "stdio", "command": "gone", "machines": ["other", "test-host"]},
  "shared": {"type": "stdio", "command": "old-command", "machines": ["other"]}
}}
JSON
  printf '%s\n' '{"mcpServers":{"shared":{"type":"stdio","command":"new-command"}}}' > "$RUNTIME"

  "$SCRIPT" "$RUNTIME" "$MANIFEST"

  [ "$(field servers gone machines)" = '["other"]' ]
  [ "$(field servers gone command)" = '"gone"' ]
  [ "$(field servers shared machines)" = '["other", "test-host"]' ]
  [ "$(field servers shared command)" = '"new-command"' ]
}

@test "generator prunes to this machine only when asked" {
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "elsewhere": {"type": "stdio", "command": "x", "machines": ["other"]},
  "here": {"type": "stdio", "command": "y", "machines": ["other"]}
}}
JSON
  printf '%s\n' '{"mcpServers":{"here":{"type":"stdio","command":"y"}}}' > "$RUNTIME"

  "$SCRIPT" --prune-to-local "$RUNTIME" "$MANIFEST"

  [ "$(python3 -c 'import json,sys; print(list(json.load(open(sys.argv[1]))["servers"]))' "$MANIFEST")" = "['here']" ]
  [ "$(field servers here machines)" = '["other", "test-host"]' ]
}

@test "generator migrates the names-only manifest into shapeless entries and removes it" {
  printf 'alpha\nlegacy-only\n' > "$DIR/mcp.manifest"
  printf '%s\n' '{"mcpServers":{"alpha":{"type":"http","url":"https://example.invalid/mcp"}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=migrated"* ]] || return 1
  [ ! -e "$DIR/mcp.manifest" ]
  [ "$(field servers legacy-only)" = '{"machines": []}' ]
  [ "$(field servers alpha machines)" = '["test-host"]' ]
  [ "$(field servers alpha url)" = '"https://example.invalid/mcp"' ]
}

@test "generator untracks the names-only manifest inside a git repo" {
  git init -q -b main "$DIR"
  git -C "$DIR" config user.email test@example.com
  git -C "$DIR" config user.name "Harness Test"
  printf 'alpha\n' > "$DIR/mcp.manifest"
  git -C "$DIR" add mcp.manifest
  git -C "$DIR" commit -q -m base
  printf '%s\n' '{"mcpServers":{"alpha":{"type":"stdio","command":"a"}}}' > "$RUNTIME"

  "$SCRIPT" "$RUNTIME" "$MANIFEST"

  ! git -C "$DIR" ls-files --error-unmatch mcp.manifest >/dev/null 2>&1
  [ ! -e "$DIR/mcp.manifest" ]
}

@test "generator fails on a key-like arg naming the server only" {
  printf '%s\n' '{"mcpServers":{"leaky":{"type":"stdio","command":"srv","args":["--api-key=sk-abcdefghijklmnopqrstuvwxyz"]}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: server leaky has a secret-like argument"* ]] || return 1
  [[ "$output" != *"abcdefghijklmnopqrstuvwxyz"* ]] || return 1
  [ ! -e "$MANIFEST" ]
}

@test "generator fails on an absolute home path" {
  printf '%s\n' '{"mcpServers":{"local":{"type":"stdio","command":"/Users/someone/bin/srv"}}}' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: server local uses a machine-specific path"* ]] || return 1
  [ ! -e "$MANIFEST" ]
}

@test "generator refuses to empty a non-empty manifest without the override" {
  printf '%s\n' '{"version":1,"servers":{"only":{"type":"stdio","command":"x","machines":["test-host"]}}}' > "$MANIFEST"
  printf '%s\n' '{"mcpServers":{}}' > "$RUNTIME"

  run "$SCRIPT" --prune-to-local "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: refusing to write an empty manifest"* ]] || return 1
  [ "$(field servers only command)" = '"x"' ]

  MCP_ALLOW_EMPTY_MANIFEST=1 "$SCRIPT" --prune-to-local "$RUNTIME" "$MANIFEST"
  [ "$(field servers)" = "{}" ]
}

@test "generator leaves the manifest untouched on an unreadable registry" {
  printf '%s\n' '{"version":1,"servers":{}}' > "$MANIFEST"
  printf 'not json\n' > "$RUNTIME"

  run "$SCRIPT" "$RUNTIME" "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_MANIFEST_STATE=failed: Claude user state is not readable"* ]] || return 1
  [ "$(cat "$MANIFEST")" = '{"version":1,"servers":{}}' ]
}

@test "check accepts a valid manifest" {
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "a": {"type": "http", "url": "https://example.invalid", "headers": {"X-Key": "${A_X_KEY}"}, "machines": ["h1", "h2"]},
  "b": {"machines": []}
}}
JSON
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 0 ]
}

@test "check rejects unsorted names, unredacted values, and extra keys" {
  printf '%s\n' '{"version":1,"servers":{"b":{"machines":[]},"a":{"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sorted"* ]] || return 1

  printf '%s\n' '{"version":1,"servers":{"a":{"env":{"T":"literal-value"},"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"server a has an unredacted env value"* ]] || return 1
  [[ "$output" != *"literal-value"* ]] || return 1

  printf '%s\n' '{"version":1,"servers":{"a":{"oauth":{},"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"server a has a non-portable key"* ]] || return 1
}

@test "check rejects an invalid server name without echoing it" {
  printf '%s\n' '{"version":1,"servers":{"/Users/x/bin":{"machines":[]}}}' > "$MANIFEST"
  run "$SCRIPT" --check "$MANIFEST"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid portable MCP server name"* ]] || return 1
  [[ "$output" != *"/Users/x"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats plugins/harness/tests/mcp-manifest.bats`
Expected: most tests FAIL. The old script writes a names-only file, so `field version` fails with a JSON error.

- [ ] **Step 3: Write the generator**

Replace `plugins/harness/scripts/mcp-manifest.sh` with:

```bash
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
```

Note the outer heredoc uses an unquoted `<<PY` so `$py_common` is substituted, and the Python inside `py_common` is a single-quoted bash string. No `$` in the Python beyond the `"${"` literal, which is inside a Python string and safe because bash does not expand inside single quotes.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats plugins/harness/tests/mcp-manifest.bats`
Expected: 12 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness/scripts/mcp-manifest.sh plugins/harness/tests/mcp-manifest.bats
git commit -m "feat(harness): generate a portable JSON MCP manifest with redacted secrets"
```

---

### Task 2: Point the finalizer and workflow test at the new manifest

**Files:**
- Modify: `plugins/harness/scripts/sync-finalize.sh:76`
- Modify: `plugins/harness/tests/sync-finalize.bats` (append two tests)
- Modify: `plugins/harness/tests/sync-workflow.bats:83,100-102`

**Interfaces:**
- Consumes: `mcp-manifest.sh --check` from Task 1.
- Produces: the finalizer validates `mcp.manifest.json` when present; the staged secret scan accepts `${VAR}` values.

- [ ] **Step 1: Write the failing tests**

Append to `plugins/harness/tests/sync-finalize.bats` (read lines 1-24 first to reuse its `setup` fixture, which creates `$REPO` with a remote and a preflight state):

```bash
@test "a manifest with variable references passes the staged secret scan" {
  cat > "$REPO/mcp.manifest.json" <<'JSON'
{"version": 1, "servers": {"kie": {"type": "stdio", "command": "npx", "args": ["-y", "@acme/kie"], "env": {"KIE_AI_API_KEY": "${KIE_AI_API_KEY}"}, "machines": ["h1"]}}}
JSON
  run "$SCRIPTS/sync-finalize.sh" "$REPO" "harness: manifest refs"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SYNC_STATE=clean"* ]] || return 1
}

@test "a manifest with a literal secret value fails validation before commit" {
  before="$(git -C "$REPO" rev-parse HEAD)"
  cat > "$REPO/mcp.manifest.json" <<'JSON'
{"version": 1, "servers": {"kie": {"type": "stdio", "command": "npx", "env": {"KIE_AI_API_KEY": "sk-abcdefghijklmnopqrstuvwxyz0123"}, "machines": ["h1"]}}}
JSON
  run "$SCRIPTS/sync-finalize.sh" "$REPO" "harness: manifest literal"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unredacted env value"* ]] || return 1
  [[ "$output" != *"abcdefghijklmnopqrstuvwxyz"* ]] || return 1
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$before" ]
}
```

If the existing `setup` does not run `sync-preflight.sh`, add `"$SCRIPTS/sync-preflight.sh" "$REPO"` as the first line of each new test, matching how the existing test at line 322 (`one final transaction leaves a clean tree at the remote SHA`) prepares the repo.

In `plugins/harness/tests/sync-workflow.bats` change line 83 to:

```bash
  "$SCRIPTS/mcp-manifest.sh" "$RUNTIME_MCP" "$REPO/mcp.manifest.json"
```

and lines 100-102 to:

```bash
  run git --git-dir="$REMOTE" show main:mcp.manifest.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"portable-memory"'* ]] || return 1
  [[ "$output" == *'"machines"'* ]] || return 1
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats plugins/harness/tests/sync-finalize.bats plugins/harness/tests/sync-workflow.bats`
Expected: the literal-secret test FAILS because the finalizer never validates `mcp.manifest.json`; the workflow test FAILS on the `machines` assertion until the finalizer knows the new file. The ref test may already pass.

- [ ] **Step 3: Update the finalizer**

In `plugins/harness/scripts/sync-finalize.sh` replace line 76:

```bash
[ ! -e "$repo/mcp.manifest" ] || "$scripts/mcp-manifest.sh" --check "$repo/mcp.manifest"
```

with:

```bash
[ ! -e "$repo/mcp.manifest.json" ] || "$scripts/mcp-manifest.sh" --check "$repo/mcp.manifest.json"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats plugins/harness/tests/sync-finalize.bats plugins/harness/tests/sync-workflow.bats`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness/scripts/sync-finalize.sh plugins/harness/tests/sync-finalize.bats plugins/harness/tests/sync-workflow.bats
git commit -m "feat(harness): validate mcp.manifest.json in the final transaction"
```

---

### Task 3: Add `mcp-reconcile.sh`, the read-only table and plan

**Files:**
- Create: `plugins/harness/scripts/mcp-reconcile.sh`
- Create: `plugins/harness/tests/mcp-reconcile.bats`

**Interfaces:**
- Consumes: `mcp.manifest.json` (Task 1 shape), the live registry, `settings.local.json` (`disabledMcpjsonServers`), `$repo/.fleet-local.json` (`skipMcp`, `keepLocalMcp`).
- Produces: `mcp-reconcile.sh <repo> <live-registry> <settings.local.json>`. Stdout: a table, a blank line, then tab-separated plan lines. Exit 0 always on valid input; exit 1 with `MCP_RECONCILE_STATE=failed: <reason>` on unreadable input. Plan line kinds, used by Task 5:

```
INSTALL <name>
NO-CONFIG <name>
SKIP <name>
EXTRA <name>
KEEP-LOCAL <name>
NEEDS-SECRET <name> <VAR>
UNRESOLVED <name>
```

- [ ] **Step 1: Write the failing tests**

Create `plugins/harness/tests/mcp-reconcile.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mcp-reconcile.sh"
  REPO="${BATS_TEST_TMPDIR}/agents"
  mkdir -p "$REPO"
  RUNTIME="${BATS_TEST_TMPDIR}/claude.json"
  LOCAL="${BATS_TEST_TMPDIR}/settings.local.json"
  printf '{}\n' > "$LOCAL"
  export MCP_HOSTNAME="here-host"
  cat > "$REPO/mcp.manifest.json" <<'JSON'
{"version": 1, "servers": {
  "both": {"type": "stdio", "command": "sh", "machines": ["here-host", "other"]},
  "installable": {"type": "stdio", "command": "sh", "env": {"INST_KEY": "${INST_KEY}"}, "machines": ["other"]},
  "shapeless": {"machines": []},
  "skipped": {"type": "stdio", "command": "sh", "machines": ["other"]},
  "unresolvable": {"type": "stdio", "command": "definitely-not-a-command-xyz", "machines": ["here-host"]}
}}
JSON
  cat > "$RUNTIME" <<'JSON'
{"mcpServers": {
  "both": {"type": "stdio", "command": "sh"},
  "extra": {"type": "http", "url": "https://example.invalid"},
  "kept": {"type": "stdio", "command": "sh"},
  "unresolvable": {"type": "stdio", "command": "definitely-not-a-command-xyz"}
}}
JSON
  printf '%s\n' '{"skipMcp": ["skipped"], "keepLocalMcp": ["kept"]}' > "$REPO/.fleet-local.json"
}

plan() {
  run env -u INST_KEY "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 0 ]
  PLAN="$(printf '%s\n' "$output" | sed -n '/^$/,$p')"
}

@test "table has one column per known host plus here" {
  run "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 0 ]
  header="$(printf '%s\n' "$output" | head -1)"
  [[ "$header" == *"server"* ]] || return 1
  [[ "$header" == *"here-host"* ]] || return 1
  [[ "$header" == *"other"* ]] || return 1
  [[ "$header" == *"here"* ]] || return 1
  both_row="$(printf '%s\n' "$output" | grep '^both')"
  [[ "$both_row" == *"x"*"x"*"x"* ]] || return 1
  shapeless_row="$(printf '%s\n' "$output" | grep '^shapeless')"
  [[ "$shapeless_row" == *"no config in manifest"* ]]
}

@test "plan reports every kind" {
  plan
  [[ "$PLAN" == *$'INSTALL\tinstallable'* ]] || return 1
  [[ "$PLAN" == *$'NEEDS-SECRET\tinstallable\tINST_KEY'* ]] || return 1
  [[ "$PLAN" == *$'NO-CONFIG\tshapeless'* ]] || return 1
  [[ "$PLAN" == *$'SKIP\tskipped'* ]] || return 1
  [[ "$PLAN" == *$'EXTRA\textra'* ]] || return 1
  [[ "$PLAN" == *$'KEEP-LOCAL\tkept'* ]] || return 1
  [[ "$PLAN" == *$'UNRESOLVED\tunresolvable'* ]] || return 1
  [[ "$PLAN" != *"both"* ]]
}

@test "a secret already present in the environment is not reported" {
  INST_KEY=value run "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 0 ]
  [[ "$output" != *"NEEDS-SECRET"* ]] || return 1
  [[ "$output" != *"value"* ]]
}

@test "a secret already held by another live server is not reported" {
  python3 - "$RUNTIME" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["mcpServers"]["kept"]["env"] = {"INST_KEY": "shared-secret"}
json.dump(d, open(p, "w"))
PY
  plan
  [[ "$PLAN" != *"NEEDS-SECRET"* ]] || return 1
  [[ "$PLAN" != *"shared-secret"* ]]
}

@test "disabled servers are not findings" {
  printf '%s\n' '{"disabledMcpjsonServers": ["installable", "unresolvable"]}' > "$LOCAL"
  plan
  [[ "$PLAN" != *"installable"* ]] || return 1
  [[ "$PLAN" != *"unresolvable"* ]]
}

@test "absent manifest and overrides are treated as empty" {
  rm "$REPO/mcp.manifest.json" "$REPO/.fleet-local.json"
  plan
  [[ "$PLAN" == *$'EXTRA\tboth'* ]] || return 1
  [[ "$PLAN" == *$'EXTRA\tkept'* ]] || return 1
  [[ "$PLAN" != *"INSTALL"* ]]
}

@test "an unreadable registry fails without printing state" {
  printf 'nope\n' > "$RUNTIME"
  run "$SCRIPT" "$REPO" "$RUNTIME" "$LOCAL"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_RECONCILE_STATE=failed"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats plugins/harness/tests/mcp-reconcile.bats`
Expected: all FAIL, script not found.

- [ ] **Step 3: Write the planner**

Create `plugins/harness/scripts/mcp-reconcile.sh`:

```bash
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
#   NEEDS-SECRET  <name> <VAR>    installable, but VAR has no value on this machine
#   UNRESOLVED    <name>          here, command not on PATH
#
# Never prints a command, URL, env value, or header value.
set -euo pipefail

[ $# -eq 3 ] || { echo "usage: mcp-reconcile.sh <repo> <claude-user-state.json> <settings.local.json>" >&2; exit 2; }
repo="${1%/}"
host="${MCP_HOSTNAME:-$(hostname -s)}"

python3 - "$repo/mcp.manifest.json" "$2" "$3" "$repo/.fleet-local.json" "$host" <<'PY'
import json, os, re, shutil, sys
from pathlib import Path

manifest_path, live_path, local_path, overrides_path, host = sys.argv[1:6]

def load(path, default):
    try:
        return json.loads(Path(path).read_text())
    except FileNotFoundError:
        return default

def fail(reason):
    print(f"MCP_RECONCILE_STATE=failed: {reason}", file=sys.stderr)
    raise SystemExit(1)

try:
    manifest = load(manifest_path, {"version": 1, "servers": {}})
    live = load(live_path, {})
    local = load(local_path, {})
    overrides = load(overrides_path, {})
except Exception as error:
    fail(f"input is not valid JSON: {type(error).__name__}")

declared = manifest.get("servers", {})
servers = live.get("mcpServers", {})
if not isinstance(declared, dict) or not isinstance(servers, dict):
    fail("servers must be objects")
disabled = set(local.get("disabledMcpjsonServers", []))
skip = set(overrides.get("skipMcp", []))
keep = set(overrides.get("keepLocalMcp", []))

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
known = set(k for k in os.environ)
for name, entry in servers.items():
    for key, value in (entry.get("env") or {}).items():
        if value:
            known.add(key)
    for key, value in (entry.get("headers") or {}).items():
        if value:
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
                plan.append(("NEEDS-SECRET", name, m.group(1)))
for name in sorted(servers):
    if name in disabled:
        continue
    if name not in declared:
        plan.append(("KEEP-LOCAL", name) if name in keep else ("EXTRA", name))
    if not resolves(servers[name]):
        plan.append(("UNRESOLVED", name))

for line in plan:
    print("\t".join(line))
PY
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `chmod +x plugins/harness/scripts/mcp-reconcile.sh && bats plugins/harness/tests/mcp-reconcile.bats`
Expected: 7 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness/scripts/mcp-reconcile.sh plugins/harness/tests/mcp-reconcile.bats
git commit -m "feat(harness): add read-only MCP reconcile table and plan"
```

---

### Task 4: Add `mcp-secrets.sh` for export and import

**Files:**
- Create: `plugins/harness/scripts/mcp-secrets.sh`
- Create: `plugins/harness/tests/mcp-secrets.bats`

**Interfaces:**
- Consumes: manifest (Task 1 shape) and live registry.
- Produces:
  - `mcp-secrets.sh export [--stdout] <manifest.json> <live-registry>`: prints `NAME=value` per referenced variable, `NAME=` when unknown, sorted. When stdout is not a TTY and `--stdout` is absent, exits 1 with `MCP_SECRETS_STATE=refused: stdout is not a terminal; pass --stdout to export anyway`.
  - `mcp-secrets.sh import <live-registry>`: reads `NAME=value` lines on stdin, writes values into every live server whose env key or header reference matches, skips empty values, prints `MCP_SECRETS_STATE=imported <N> value(s) into <M> server(s)`.

- [ ] **Step 1: Write the failing tests**

Create `plugins/harness/tests/mcp-secrets.bats`:

```bash
#!/usr/bin/env bats

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/mcp-secrets.sh"
  MANIFEST="${BATS_TEST_TMPDIR}/mcp.manifest.json"
  RUNTIME="${BATS_TEST_TMPDIR}/claude.json"
  cat > "$MANIFEST" <<'JSON'
{"version": 1, "servers": {
  "kie": {"type": "stdio", "command": "npx", "env": {"KIE_AI_API_KEY": "${KIE_AI_API_KEY}"}, "machines": ["a"]},
  "web": {"type": "http", "url": "https://example.invalid", "headers": {"Authorization": "${WEB_AUTHORIZATION}"}, "machines": ["a"]},
  "missing": {"type": "stdio", "command": "x", "env": {"MISSING_KEY": "${MISSING_KEY}"}, "machines": ["a"]}
}}
JSON
  cat > "$RUNTIME" <<'JSON'
{"mcpServers": {
  "kie": {"type": "stdio", "command": "npx", "env": {"KIE_AI_API_KEY": "kie-value"}},
  "web": {"type": "http", "url": "https://example.invalid", "headers": {"Authorization": "Bearer web-value"}},
  "other": {"type": "stdio", "command": "y", "env": {"UNRELATED": "keep-me"}}
}, "projects": {"/p": {"mcpServers": {}}}}
JSON
}

@test "export lists every referenced variable with its local value or empty" {
  run "$SCRIPT" export --stdout "$MANIFEST" "$RUNTIME"
  [ "$status" -eq 0 ]
  [ "$output" = $'KIE_AI_API_KEY=kie-value\nMISSING_KEY=\nWEB_AUTHORIZATION=Bearer web-value' ]
}

@test "export refuses a non-terminal stdout without --stdout" {
  run "$SCRIPT" export "$MANIFEST" "$RUNTIME"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MCP_SECRETS_STATE=refused"* ]] || return 1
  [[ "$output" != *"kie-value"* ]]
}

@test "import writes values into referencing entries only and skips empty values" {
  python3 - "$RUNTIME" <<'PY'
import json, sys
p = sys.argv[1]; d = json.load(open(p))
d["mcpServers"]["kie"]["env"]["KIE_AI_API_KEY"] = "${KIE_AI_API_KEY}"
d["mcpServers"]["web"]["headers"]["Authorization"] = "${WEB_AUTHORIZATION}"
d["mcpServers"]["missing"] = {"type": "stdio", "command": "x", "env": {"MISSING_KEY": "${MISSING_KEY}"}}
json.dump(d, open(p, "w"))
PY
  run "$SCRIPT" import "$RUNTIME" <<'EOF'
KIE_AI_API_KEY=new-kie
WEB_AUTHORIZATION=Bearer new-web
MISSING_KEY=
not a pair
EOF
  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_SECRETS_STATE=imported 2 value(s) into 2 server(s)"* ]] || return 1
  [[ "$output" != *"new-kie"* ]] || return 1
  python3 - "$RUNTIME" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))["mcpServers"]
assert d["kie"]["env"]["KIE_AI_API_KEY"] == "new-kie"
assert d["web"]["headers"]["Authorization"] == "Bearer new-web"
assert d["missing"]["env"]["MISSING_KEY"] == "${MISSING_KEY}"
assert d["other"]["env"]["UNRELATED"] == "keep-me"
PY
  python3 -c 'import json,sys; assert "projects" in json.load(open(sys.argv[1]))' "$RUNTIME"
}

@test "import leaves the registry untouched when it is unreadable" {
  printf 'nope\n' > "$RUNTIME"
  run "$SCRIPT" import "$RUNTIME" <<'EOF'
KIE_AI_API_KEY=x
EOF
  [ "$status" -eq 1 ]
  [ "$(cat "$RUNTIME")" = "nope" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats plugins/harness/tests/mcp-secrets.bats`
Expected: all FAIL, script not found.

- [ ] **Step 3: Write the helper**

Create `plugins/harness/scripts/mcp-secrets.sh`:

```bash
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
            values[key] = value
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
    trap 'rm -f "$tmp"' EXIT HUP INT TERM
    python3 - "$registry" "$tmp" <<'PY'
import json, re, sys
from pathlib import Path

registry, out = sys.argv[1:3]
try:
    live = json.loads(Path(registry).read_text())
except Exception as error:
    print(f"MCP_SECRETS_STATE=failed: registry is not readable: {type(error).__name__}", file=sys.stderr)
    raise SystemExit(1)

def ref_name(*parts):
    return "_".join(re.sub(r"[^A-Za-z0-9]", "_", p).upper() for p in parts)

incoming = {}
for line in sys.stdin.read().splitlines():
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
        if key in incoming:
            env[key] = incoming[key]
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
    ;;
  *)
    echo "usage: mcp-secrets.sh export|import ..." >&2
    exit 2
    ;;
esac
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `chmod +x plugins/harness/scripts/mcp-secrets.sh && bats plugins/harness/tests/mcp-secrets.bats`
Expected: 4 tests PASS. Note the unreadable-registry test relies on the `trap` removing the temp file and `mv` never running because python exited 1 under `set -e`.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness/scripts/mcp-secrets.sh plugins/harness/tests/mcp-secrets.bats
git commit -m "feat(harness): add MCP secrets export and import helper"
```

---

### Task 5: Rewrite the sync skill's MCP phases

**Files:**
- Modify: `plugins/harness/skills/sync/SKILL.md` — sections "Dry run" (lines 37-84), "2.3" (458-505), "Phase 2.5" intro and "MCP servers" subsection (506-511, 645-717), "Overrides" (947-1008), "Phase 3.75" block (1130-1169), "Phase 4" (1170-1235)
- Modify: `plugins/harness/tests/sync-procedure.bats` — tests at lines 200-296 (three MCP verifier tests), 297-386 (three generation tests), 387-445 (final validation test)

**Interfaces:**
- Consumes: the three scripts. Plan line kinds from Task 3. `MCP_PRUNE_TO_LOCAL=1` chooses `--prune-to-local` in Phase 3.75.
- Produces: skill text whose bash blocks the tests extract and run.

- [ ] **Step 1: Update the skill-text tests so they fail**

In `plugins/harness/tests/sync-procedure.bats`:

Replace the three tests headed `the dry-run MCP verifier ...` (the marker they extract is `### MCP servers — verify, report, never auto-install`) with these three, which extract from the new marker `### MCP servers — compare, choose, apply`:

```bash
@test "the MCP reconcile block prints the table and plan against the custom Claude user registry" {
  phase="$BATS_TEST_TMPDIR/mcp-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$agents" "$claude" "$harness/scripts"
  cp "$REPO/plugins/harness/scripts/mcp-reconcile.sh" "$REPO/plugins/harness/scripts/mcp-manifest.sh" "$harness/scripts/"
  printf '%s\n' '{"version":1,"servers":{"portable-memory":{"type":"stdio","command":"sh","machines":["other"]},"elsewhere":{"type":"stdio","command":"sh","machines":["other"]}}}' > "$agents/mcp.manifest.json"
  cat > "$claude/.claude.json" <<'EOF'
{
  "mcpServers": {
    "portable-memory": {"command": "sh", "env": {"TOKEN": "do-not-print"}}
  },
  "projects": {"/tmp/project": {"mcpServers": {"project-only": {"command": "sh"}}}}
}
EOF
  printf '{}\n' > "$claude/settings.local.json"

  extract_first_bash_block_after "### MCP servers — compare, choose, apply" "$phase"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    MCP_HOSTNAME="test-host" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'INSTALL\telsewhere'* ]] || return 1
  [[ "$output" != *"project-only"* ]] || return 1
  [[ "$output" != *"do-not-print"* ]]
}

@test "the MCP reconcile block uses the default Claude user registry" {
  phase="$BATS_TEST_TMPDIR/mcp-default-phase.sh"
  home="$BATS_TEST_TMPDIR/home"
  agents="$BATS_TEST_TMPDIR/agents"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$home/.claude" "$agents" "$harness/scripts"
  cp "$REPO/plugins/harness/scripts/mcp-reconcile.sh" "$REPO/plugins/harness/scripts/mcp-manifest.sh" "$harness/scripts/"
  printf '%s\n' '{"version":1,"servers":{"portable-memory":{"type":"stdio","command":"sh","machines":["other"]}}}' > "$agents/mcp.manifest.json"
  printf '%s\n' '{"mcpServers":{"portable-memory":{"command":"sh"}}}' > "$home/.claude.json"
  printf '{}\n' > "$home/.claude/settings.local.json"

  extract_first_bash_block_after "### MCP servers — compare, choose, apply" "$phase"

  run env -u CLAUDE_CONFIG_DIR \
    HOME="$home" \
    AGENTS_REPO="$agents" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    MCP_HOSTNAME="test-host" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"portable-memory"* ]] || return 1
  [[ "$output" != *"INSTALL"* ]] || return 1
}

@test "the MCP reconcile block reports a missing Claude user registry as not configured" {
  phase="$BATS_TEST_TMPDIR/mcp-missing-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  mkdir -p "$agents" "$claude" "$harness/scripts"
  cp "$REPO/plugins/harness/scripts/mcp-reconcile.sh" "$REPO/plugins/harness/scripts/mcp-manifest.sh" "$harness/scripts/"
  printf '%s\n' '{"version":1,"servers":{"portable-memory":{"type":"stdio","command":"sh","machines":["other"]}}}' > "$agents/mcp.manifest.json"
  printf '{}\n' > "$claude/settings.local.json"

  extract_first_bash_block_after "### MCP servers — compare, choose, apply" "$phase"

  run env \
    AGENTS_REPO="$agents" \
    CLAUDE_CONFIG_DIR="$claude" \
    CLAUDE_PLUGIN_ROOT="$harness" \
    MCP_HOSTNAME="test-host" \
    bash "$phase"

  [ "$status" -eq 0 ]
  [[ "$output" == *"MCP_STATE=not configured"* ]] || return 1
  [[ "$output" == *$'INSTALL\tportable-memory'* ]]
}
```

In the three generation tests (`MCP inventory generation reads ...`, `... reports a missing ...`, `failed MCP inventory generation ...`) change every `mcp.manifest` filename to `mcp.manifest.json`: the stub `printf 'portable-memory\n' > "$2"` becomes `printf '%s\n' '{"version":1,"servers":{}}' > "$2"`, and `[ ! -e "$agents/mcp.manifest" ]` becomes `[ ! -e "$agents/mcp.manifest.json" ]`. The marker string `### 2.3 Generate the portable MCP inventory and clean up the legacy tracked file` stays.

Add one test for the prune switch after `final validation regenerates MCP inventory from the custom Claude user registry`:

```bash
@test "final validation passes --prune-to-local only when the replace choice was recorded" {
  phase="$BATS_TEST_TMPDIR/mcp-prune-phase.sh"
  agents="$BATS_TEST_TMPDIR/agents"
  claude="$BATS_TEST_TMPDIR/claude-config"
  harness="$BATS_TEST_TMPDIR/harness"
  args_marker="$BATS_TEST_TMPDIR/mcp-args"
  mkdir -p "$agents" "$claude" "$harness/scripts"
  printf '%s\n' '{"mcpServers":{"portable-memory":{"command":"sh"}}}' > "$claude/.claude.json"

  extract_first_bash_block_after "## Phase 3.75:" "$phase"

  for name in localize-skill-overrides.py reconcile_shared_settings.py render-codex-agents.sh link-plan.sh portability-lint.sh sync-finalize.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$harness/scripts/$name"
    chmod +x "$harness/scripts/$name"
  done
  cat > "$harness/scripts/mcp-manifest.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$MCP_ARGS_MARKER"
exit 0
EOF
  chmod +x "$harness/scripts/mcp-manifest.sh"

  run env AGENTS_REPO="$agents" CLAUDE_CONFIG_DIR="$claude" CLAUDE_PLUGIN_ROOT="$harness" MCP_ARGS_MARKER="$args_marker" bash "$phase"
  [ "$status" -eq 0 ]
  [[ "$(cat "$args_marker")" != *"--prune-to-local"* ]] || return 1

  run env AGENTS_REPO="$agents" CLAUDE_CONFIG_DIR="$claude" CLAUDE_PLUGIN_ROOT="$harness" MCP_ARGS_MARKER="$args_marker" MCP_PRUNE_TO_LOCAL=1 bash "$phase"
  [ "$status" -eq 0 ]
  [[ "$(cat "$args_marker")" == "--prune-to-local "*"mcp.manifest.json" ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats plugins/harness/tests/sync-procedure.bats`
Expected: the three reconcile tests FAIL (marker missing), the prune test FAILS, the generation tests FAIL on the filename.

- [ ] **Step 3: Rewrite the skill sections**

Edit `plugins/harness/skills/sync/SKILL.md`. Each replacement is quoted in full.

**3a. Dry run (lines 37-84).** Replace the sentence fragment `` `mcp-manifest.sh --check` for the portable MCP inventory, Phase 2.5's MCP verification block against the machine-local user registry, `` with `` `mcp-manifest.sh --check` for the portable MCP manifest, Phase 2.5's MCP reconcile block (table and plan only, no question), ``. Replace the paragraph starting `Phase 2.5's MCP block only reads the portable inventory` with:

```
Phase 2.5's MCP block only reads the portable manifest and Claude Code's
machine-local user registry, then prints the per-host table and plan lines;
it belongs in a dry run because that's exactly the kind of thing someone
previewing a sync wants to see. The match / replace / merge question is not
asked and nothing is installed, removed, or imported.
```

Under "Skip everything else", replace the `**Phase 2.5's plugin half**` bullet's last sentence with `Run only its MCP reconcile block's table and plan, not the question or anything after it.`

**3b. Section 2.3 (lines 458-505).** Replace the heading body with:

````
### 2.3 Generate the portable MCP inventory and clean up the legacy tracked file

Claude Code stores user-scope MCP servers in the top-level `mcpServers` object of
`${CLAUDE_CONFIG_DIR}/.claude.json` when `CLAUDE_CONFIG_DIR` is set, or
`$HOME/.claude.json` otherwise. Read that file only to generate
`mcp.manifest.json`: each server's portable shape (`type`, `command`, `args`,
`url`, `env`, `headers`) with every env and header value replaced by a `${NAME}`
reference, plus a `machines` list naming the hosts that have it. The generator
adds this host to every server present here and removes it from every server
that is not. Never copy, link, print, stage, or commit the state file.

A names-only `mcp.manifest` from an older sync is migrated once: its names
become shapeless entries (`{"machines": []}`), the old file is untracked and
deleted, and the generator prints `MCP_MANIFEST_STATE=migrated`. A shapeless
entry shows as `NO-CONFIG` in Phase 2.5 until a machine that has the server
syncs.

The generator fails, naming the server only, when an arg looks like a token or
a `--flag=value` with a long value, or when `command` or an arg is an absolute
home path. Fix the server locally (move the secret to `env`, or the binary onto
`PATH`) and rerun.

`$claude/mcp.json` is a legacy path. If an older repo tracks it or the live legacy
path is a symlink into the repo, preserve its resolved bytes as a regular live file
before untracking it. Never print its command, args, URL, headers, or environment:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
runtime_mcp="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
legacy_runtime="$claude/mcp.json"
if [ -L "$legacy_runtime" ]; then
  temporary="$(mktemp "$claude/.mcp.json.migrate.XXXXXX")"
  trap 'rm -f "$temporary"' EXIT HUP INT TERM
  cp -pL "$legacy_runtime" "$temporary"
  unlink "$legacy_runtime"
  mv "$temporary" "$legacy_runtime"
  temporary=""
  trap - EXIT HUP INT TERM
fi
if [ -f "$runtime_mcp" ]; then
  "$harness/scripts/mcp-manifest.sh" "$runtime_mcp" "$repo/mcp.manifest.json" || exit $?
else
  echo "MCP_STATE=not configured"
fi
grep -qxF 'claude/mcp.json' "$repo/.gitignore" 2>/dev/null || printf '%s\n' 'claude/mcp.json' >> "$repo/.gitignore"
git -C "$repo" rm --cached claude/mcp.json --ignore-unmatch -q
```

If the user registry is missing, report `MCP_STATE=not configured` and do not
invent a manifest. In dry-run mode, do not run this block; validate an existing
manifest with `mcp-manifest.sh --check "$repo/mcp.manifest.json"` and run Phase
2.5's reconcile block read-only.
````

**3c. Phase 2.5 MCP subsection (lines 645-717).** Replace from `### MCP servers — verify, report, never auto-install` to the end of its bash block and trailing paragraph with:

````
### MCP servers — compare, choose, apply

Read the tracked `mcp.manifest.json` and the machine-local user registry
(`${CLAUDE_CONFIG_DIR}/.claude.json` when configured, otherwise
`$HOME/.claude.json`). Validate the manifest first. The reconcile script is
read-only: it prints a table with one column per host that has ever synced plus
`here`, a blank line, then plan lines. Honour `disabledMcpjsonServers` in
`settings.local.json`; a server disabled here is not a finding. Never print a
command, URL, header, env value, or credential; findings name servers and
variable names only.

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
claude="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
runtime_mcp="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
[ ! -e "$repo/mcp.manifest.json" ] || "$harness/scripts/mcp-manifest.sh" --check "$repo/mcp.manifest.json"
[ -f "$runtime_mcp" ] || { echo "MCP_STATE=not configured"; runtime_mcp=/dev/null; }
"$harness/scripts/mcp-reconcile.sh" "$repo" "$runtime_mcp" "$claude/settings.local.json"
```

`/dev/null` as the registry makes the planner treat this machine as empty, so
every declared server shows as `INSTALL` or `NO-CONFIG`; that is the correct
picture for a machine that has never added a server.

**Read the plan here; do not carry it in a shell variable** (nothing persists
between blocks, see Phase 0). The plan line kinds:

| line | meaning |
|---|---|
| `INSTALL <name>` | declared with a shape, not here |
| `NO-CONFIG <name>` | declared without a shape; nothing to install from until a machine that has it syncs |
| `SKIP <name>` | declared, not here, recorded in `.fleet-local.json` `skipMcp` |
| `EXTRA <name>` | here, not declared |
| `KEEP-LOCAL <name>` | here, not declared, recorded in `keepLocalMcp` |
| `NEEDS-SECRET <name> <VAR>` | installable, but `VAR` has no value on this machine |
| `UNRESOLVED <name>` | here, command not on `PATH` |

**In a dry run, stop after the table and plan.** Otherwise, if there is no
`INSTALL`, `NO-CONFIG`, or `EXTRA` line, print `MCP_STATE=up to date` and
continue to Phase 2.6. If there is, ask **one** question with exactly these
three options, listing the affected names under each:

1. **Match this machine to the repo** — install every `INSTALL` server here,
   then list the `EXTRA` servers and ask a second confirm before removing them
   from this machine. A declined removal is recorded as `keepLocalMcp`.
2. **Replace the repo with this machine** — the manifest's server set becomes
   this machine's set. List, by name, every server only other machines have,
   and confirm: the next sync on those machines will offer to remove them. On
   yes, remember to run Phase 3.75 with `MCP_PRUNE_TO_LOCAL=1`. Nothing is
   installed here.
3. **Merge** — install every `INSTALL` server here and keep every `EXTRA` in the
   manifest. No removals anywhere.

Never pick for the user. `NO-CONFIG` and `SKIP` lines are reported, never acted
on.

**Installing** a server uses the manifest entry with its references intact.
Claude Code expands `${VAR}` from the environment at launch, and the secrets
flow below replaces the reference with the value in the live registry when the
user supplies one:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
name="<name>"
claude mcp add-json -s user "$name" "$(python3 -c '
import json, sys
entry = json.load(open(sys.argv[1]))["servers"][sys.argv[2]]
print(json.dumps({k: v for k, v in entry.items() if k != "machines"}))
' "$repo/mcp.manifest.json" "$name")"
```

If the command exits non-zero, report `install failed: <name>` as an unresolved
finding and never write it to overrides.

**Removing** a server from this machine (match, after the confirm):

```bash
claude mcp remove -s user "<name>"
```

A non-zero exit is `remove failed: <name>`, an unresolved finding.

**Secrets.** After installs, for every `NEEDS-SECRET <name> <VAR>` line, say
once that pasted values pass through this session's transcript, then print the
command to run on a machine that has the values:

```bash
repo="${AGENTS_REPO:-$HOME/.agents}"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
echo "On the other machine, run:  \"$harness/scripts/mcp-secrets.sh\" export \"$repo/mcp.manifest.json\" \"\${CLAUDE_CONFIG_DIR:-\$HOME}/.claude.json\""
```

Then ask for the values. The user may paste the whole export block at the first
prompt; feed everything received to `import`, which skips empty values and
names it does not find, and then skip the remaining prompts for names it
covered:

```bash
runtime_mcp="${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json"
harness="${CLAUDE_PLUGIN_ROOT:-$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ 2>/dev/null | sort -V | tail -1)}"; harness="${harness%/}"
"$harness/scripts/mcp-secrets.sh" import "$runtime_mcp" <<'EOF'
<NAME=value lines>
EOF
```

`import` prints counts only. Never echo a value back. A variable the user
leaves empty stays a `NEEDS-SECRET` finding in the report.

**Unresolved commands.** After installs, rerun the reconcile block. If any
`UNRESOLVED <name>` lines remain, list them once and ask a single follow-up:
skip these on this machine? On yes, remove each with `claude mcp remove -s user
"<name>"` and record it as `skipMcp` (see Overrides in Phase 2.6), so a machine
without Blender does not keep a blender server. On no, they stay as
`<name> command unavailable on this machine` findings.

Servers present here but absent from the manifest after a choice are picked up
by Phase 3.75's regeneration, which stamps this host into `machines`.
````

**3d. Overrides (Phase 2.6, lines 947-1008).** Change the JSON example to:

```json
{"skipInstall": ["name", "…"], "keepLocal": ["name", "…"], "skipMcp": ["name", "…"], "keepLocalMcp": ["name", "…"]}
```

Add two bullets after `keepLocal`:

```
- `skipMcp` — declared in `mcp.manifest.json`, deliberately not on this
  machine. Reached by the unresolved-command follow-up in Phase 2.5.
- `keepLocalMcp` — an MCP server present here, deliberately left undeclared.
  Reached by declining a removal under "match" in Phase 2.5.
```

In the `override_script` add two `setdefault` lines after the existing two:

```python
data.setdefault("skipMcp", [])
data.setdefault("keepLocalMcp", [])
```

Change the deviations report line to:

```
Skills local deviations: skipInstall <name>, … | keepLocal <name>, … | none
MCP local deviations:    skipMcp <name>, … | keepLocalMcp <name>, … | none
```

**3e. Phase 3.75 block (lines 1130-1169).** Replace the `mcp-manifest.sh` line with:

```bash
[ ! -f "$runtime_mcp" ] || "$harness/scripts/mcp-manifest.sh" ${MCP_PRUNE_TO_LOCAL:+--prune-to-local} "$runtime_mcp" "$repo/mcp.manifest.json"
```

Add before the block:

```
If the user chose **Replace the repo with this machine** in Phase 2.5, run this
block with `MCP_PRUNE_TO_LOCAL=1` set in front of the command. Otherwise leave it
unset; the generator then only updates this host's `machines` entries.
```

**3f. Phase 4 report.** Replace the `MCP:` line with:

```
  MCP:        {up to date | N ok, M remote (no local command) | N ok, M skipped here,
               K need config: <names>, J need secrets: <NAME>, … | not configured}
  MCP local deviations: skipMcp <name>, … | keepLocalMcp <name>, … | none
```

Add to the unresolved-findings paragraph: `an MCP install failed: <name> or remove failed: <name>, a NEEDS-SECRET left empty, and every NO-CONFIG name until a machine with the config syncs.`

Also replace the remaining mentions of `names-only` and `mcp.manifest` in the adoption text (lines 221 and 263) with `mcp.manifest.json` and "secret-free shape", and change `Generate the secret-free, names-only` to `Generate the secret-free`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats plugins/harness/tests/sync-procedure.bats plugins/harness/tests/skill-contracts.bats plugins/harness/tests/documentation-boundary.bats`
Expected: all PASS. If `skill-contracts.bats` or `documentation-boundary.bats` asserts a phrase that moved, keep the phrase in the new text rather than editing the test.

- [ ] **Step 5: Commit**

```bash
git add plugins/harness/skills/sync/SKILL.md plugins/harness/tests/sync-procedure.bats
git commit -m "feat(harness): interactive MCP reconcile and secrets flow in sync"
```

---

### Task 6: README, version bump, full suite

**Files:**
- Modify: `plugins/harness/README.md:153`
- Modify: `plugins/harness/.claude-plugin/plugin.json` (`version`)
- Modify: `.claude-plugin/marketplace.json` (harness entry `version`)

**Interfaces:**
- Consumes: all previous tasks.
- Produces: a releasable 0.9.0.

- [ ] **Step 1: Update the scripts table**

Replace README line 153 with three rows:

```
| `scripts/mcp-manifest.sh [--prune-to-local] <claude-user-state.json> <mcp.manifest.json>` | generate the portable MCP manifest (shape with `${VAR}` references, per-host `machines`), migrate a names-only file, or `--check` one |
| `scripts/mcp-reconcile.sh <repo> <claude-user-state.json> <settings.local.json>` | read-only per-host table and plan lines for `harness:sync`'s match / replace / merge step |
| `scripts/mcp-secrets.sh export [--stdout] <manifest> <registry>` \| `import <registry>` | move `${VAR}` values between machines without the repo seeing them |
```

- [ ] **Step 2: Bump the version**

```bash
python3 - <<'PY'
import json, re
from pathlib import Path
p = Path("plugins/harness/.claude-plugin/plugin.json")
d = json.loads(p.read_text()); assert d["version"] == "0.8.3"; d["version"] = "0.9.0"
p.write_text(json.dumps(d, indent=2) + "\n")
m = Path(".claude-plugin/marketplace.json")
md = json.loads(m.read_text())
for e in md["plugins"]:
    if e["name"] == "harness":
        assert e["version"] == "0.8.3"; e["version"] = "0.9.0"
m.write_text(json.dumps(md, indent=2) + "\n")
PY
git diff --stat
```

If the marketplace file's indentation differs from two spaces, re-indent to match the existing file before committing so the diff is two lines.

- [ ] **Step 3: Run the full suite**

Run: `plugins/harness/tests/run-tests.sh`
Expected: all bats files PASS, including `version-consistency.bats`, `reference-contracts.bats`, and `documentation-boundary.bats`.

- [ ] **Step 4: Commit**

```bash
git add plugins/harness/README.md plugins/harness/.claude-plugin/plugin.json .claude-plugin/marketplace.json
git commit -m "chore(harness): document MCP scripts and release 0.9.0"
```

---

## Self-review

**Spec coverage.** Section 1 manifest format: Task 1. Section 2 table, plan kinds, three choices, unresolved follow-up, install/remove commands, failure reporting: Tasks 3 and 5. Section 3 secrets export/import, TTY refusal, prompt path, transcript warning: Tasks 4 and 5. Section 4 phase placement, dry run, overrides, prune flag, report line, README: Tasks 5 and 6. Section 5 tests: each task; the finalizer scan cases are Task 2. Out of scope items have no task.

**Deviation from the spec's table example.** The spec's sample table shows a `needs authentication` note. Deriving it requires `claude mcp list`, which is a live call, and the planner is read-only. The planner prints `remote (no local command)` for URL servers instead. Authentication state still surfaces through `claude mcp list` output in Phase 2.5's install step when the user runs it.

**Type consistency.** `ref_name` is defined identically in Tasks 1, 3, and 4. Plan line kinds in Task 3's script match Task 5's table. `MCP_PRUNE_TO_LOCAL` is the only cross-block signal and is named the same in Task 5's text, block, and test. `MCP_HOSTNAME` is honoured by Tasks 1 and 3.
