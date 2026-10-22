#!/usr/bin/env python3
"""Create a personal agents repo's rulesync source from the agent tools on this machine.

  rulesync-bootstrap.py [--write] <agents-repo>     first time: build the whole source
  rulesync-bootstrap.py --machine <agents-repo>     first sync on another machine

Without --write it only previews. Each installed tool's MCP servers and hooks are
imported with rulesync (through a temporary HOME that links to the real tool folders,
so nothing is written into them) and composed:

  MCP     a portable server joins the shared source (its most common definition);
          a tool whose definition differs gets its own block; a definition with a
          home-folder path goes to this machine's untracked .rulesync.local overlay.
  secrets an env or header value under a secret-looking name, or any Authorization
          header, moves into the OS secret store (agent-secrets.py) and the server
          is rewritten to start through bin/with-secrets (HTTP token headers use
          mcp-remote, and Claude's native headersHelper). Names only are printed.
          A credential-looking value anywhere else (another env or header value, the
          URL, an argument) keeps the server on this machine only, since the shared
          source is committed.
  hooks   each tool keeps its own hooks; entries with home-folder paths stay local.
  skills  skills.manifest + .skill-lock.json entries become rulesync `sources`;
          other committed folders under skills/ are yours and move to .rulesync/skills.

--apps runs before every generate: a server an app installs and rewrites itself (its
command lives inside an .app bundle, like Codex's node_repl from ChatGPT.app) is kept
in .rulesync.local as the app last wrote it, so a generate never restores a stale copy
after the app updates. Prints RULESYNC_APPS=... only when something changed.

--machine runs before the first generate of a managed repo on a machine without
.rulesync.local: every server or hook of this machine that the shared source does not
already define for that tool is kept in the overlay, so the first generate loses
nothing. Prints RULESYNC_CAPTURE=...
"""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("rulesync_generate", HERE / "rulesync-generate.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)
_store_spec = importlib.util.spec_from_file_location("agent_secrets", HERE / "agent-secrets.py")
store = importlib.util.module_from_spec(_store_spec)
_store_spec.loader.exec_module(store)

# rulesync target -> what to link into the temporary HOME so `import --global` sees it.
TOOLS = {
    "claudecode": (".claude", ".claude.json"),
    "codexcli": (".codex",),
    "cursor": (".cursor",),
    "factorydroid": (".factory",),
    "opencode": (".config/opencode",),
    "pi": (".pi",),
    "antigravity-cli": (".gemini",),
}
PREFERRED = list(TOOLS)  # tie order for the shared definition: Claude first
FEATURES = ["rules", "mcp", "hooks", "skills", "subagents", "commands"]
SECRET_NAME = re.compile(r"KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTH|PAT\b|BEARER|CREDENTIAL", re.I)
MCP_REMOTE = "mcp-remote@0.15.2"


def home_paths() -> re.Pattern:
    home = re.escape(str(Path.home()))
    return re.compile(rf"{home}|/(?:Users|home)/[A-Za-z0-9._-]+|(?<![\w$])~/")


def installed_tools() -> list[str]:
    home = Path.home()
    return [tool for tool, paths in TOOLS.items() if any((home / p).exists() for p in paths)]


def import_tool(tool: str) -> tuple[dict, dict]:
    """(mcpServers, hooks) for one tool, read with rulesync's own importer."""
    with tempfile.TemporaryDirectory(prefix="harness-bootstrap.") as temp:
        home = Path(temp)
        for rel in TOOLS[tool]:
            live = Path.home() / rel
            if live.exists():
                (home / rel).parent.mkdir(parents=True, exist_ok=True)
                (home / rel).symlink_to(live)
        real = Path.home()
        # rulesync reads HOME_DIR before HOME; npm keeps the real cache and registry config.
        env = dict(os.environ, HOME=str(home), HOME_DIR=str(home), npm_config_yes="true",
                   npm_config_cache=os.environ.get("npm_config_cache") or str(real / ".npm"))
        if (real / ".npmrc").is_file():
            env.setdefault("NPM_CONFIG_USERCONFIG", str(real / ".npmrc"))
        result = subprocess.run(["npx", "-y", gen.RULESYNC, "import", "--global", "--targets", tool, "--features", "mcp,hooks"],
                                cwd=home, env=env, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(f"rulesync import --targets {tool} failed: {(result.stderr or result.stdout).strip()[-200:]}")
        mcp_path, hooks_path = home / ".rulesync" / "mcp.jsonc", home / ".rulesync" / "hooks.jsonc"
        mcp = gen.load_jsonc(mcp_path).get("mcpServers", {}) if mcp_path.is_file() else {}
        hooks = gen.load_jsonc(hooks_path).get("hooks", {}) if hooks_path.is_file() else {}
        return mcp, hooks


def env_name(*parts: str) -> str:
    return re.sub(r"[^A-Z0-9]+", "_", "_".join(parts).upper()).strip("_")


class SecretError(Exception):
    pass


SAFE_HEADER = re.compile(r"^[A-Za-z0-9-]+$")
SAFE_REL = re.compile(r"^[A-Za-z0-9._/ -]+$")
SCHEMES = ("Bearer", "Basic", "Token", "token")


# Mirrors mcp-manifest.sh: known token prefixes and long --flag=value arguments.
TOKEN_RE = re.compile(
    r"(?:ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{16,}|sk_(?:live|test)_[A-Za-z0-9]{8,}|"
    r"xox[abp]-[A-Za-z0-9-]{10,}|AKIA[A-Z0-9]{16}|AIza[A-Za-z0-9_-]{30,}|gsk_[A-Za-z0-9]{20,})"
)
FLAG_RE = re.compile(r"^--?[A-Za-z][A-Za-z0-9_-]*=(.{16,})$")
# A credential inside a scheme-less connection string (Server=db;Password=...).
CONNECTION_SECRET = re.compile(r"(?i)\b(?:password|pwd|secret|token)=")
# A 20+ character run mixing letters and digits, as in a URL-embedded token.
LONG_TOKEN = re.compile(r"(?=[A-Za-z0-9_-]*\d)(?=[A-Za-z0-9_-]*[A-Za-z])[A-Za-z0-9_-]{20,}")


def credential_like(value: object) -> bool:
    """A token, a long letter-and-digit run, or a URL with credentials or a query."""
    if not isinstance(value, str) or not value or "${" in value:
        return False
    if TOKEN_RE.search(value) or LONG_TOKEN.search(value) or CONNECTION_SECRET.search(value):
        return True
    if "://" in value:
        parts = urlsplit(value)
        return bool(parts.username or parts.password or parts.query)
    return False


def leaks(spec: dict) -> bool:
    """True when a definition still carries a value that must not be committed.

    Secret-named env and header values move to the secret store; a credential under
    an innocent name (DATABASE_URL=postgres://user:pass@...), in the URL, or in an
    argument keeps the server on this machine, since the shared source is committed.
    """
    env = spec.get("env") or {}
    headers = spec.get("headers") or {}
    values = [v for k, v in env.items() if not is_secret_env(k, v)]
    values += [v for h, v in headers.items() if not is_secret_header(h, v)]
    values += [spec.get("url"), spec.get("httpUrl"), spec.get("command")]
    args = [a for a in spec.get("args") or [] if isinstance(a, str)]
    return any(credential_like(v) for v in values) or any(credential_like(a) or FLAG_RE.match(a) for a in args)


def is_secret_env(name: str, value: object) -> bool:
    return isinstance(value, str) and bool(value) and not value.startswith("${") and bool(SECRET_NAME.search(name))


def is_secret_header(name: str, value: object) -> bool:
    return (isinstance(value, str) and bool(value) and "${" not in value
            and (name.lower() == "authorization" or bool(SECRET_NAME.search(name))))


class Secrets:
    """Secret values found while composing; stored in the OS store only on --write.

    A name already stored on this machine, or claimed earlier, with a different value
    is never reused: the new value gets a server-qualified, then numbered, name.
    """

    def __init__(self, stored=None) -> None:
        self.values: dict[str, str] = {}
        self.stored = stored or (lambda name: None)

    def taken(self, name: str, value: str) -> bool:
        if name in self.values:
            return self.values[name] != value
        existing = self.stored(name)
        return existing is not None and existing != value

    def claim(self, name: str, value: str, server: str) -> str:
        candidate = name
        if self.taken(candidate, value):
            candidate = env_name(server, name)
        number = 1
        while self.taken(candidate, value):
            number += 1
            candidate = f"{env_name(server, name)}_{number}"
        self.values[candidate] = value
        return candidate


def launcher(repo_rel: str, names: list[str], command: list[str]) -> str:
    if not repo_rel:
        raise SecretError("a secret server needs the agents repo under your home folder, at a plain path")
    return f'exec "$HOME/{repo_rel}/bin/with-secrets" {" ".join(names)} -- {shlex.join(command)}'


def convert(server: str, spec: dict, secrets: Secrets, repo_rel: str) -> tuple[dict, dict | None]:
    """(definition for every tool, Claude-only variant or None), with secrets moved out.

    Fails closed: a secret no rule can move raises SecretError naming the field only.
    """
    spec = json.loads(json.dumps(spec))
    env = dict(spec.get("env") or {})
    headers = dict(spec.get("headers") or {})
    url = spec.get("url") or spec.get("httpUrl")
    secret_env = [k for k, v in env.items() if is_secret_env(k, v)]
    secret_headers = [h for h, v in headers.items() if is_secret_header(h, v)]
    if not secret_env and not secret_headers:
        return spec, None
    if secret_env and (not spec.get("command") or secret_headers):
        raise SecretError(f"{server}.env.{secret_env[0]} holds a secret Harness cannot move")
    if secret_headers and not url:
        raise SecretError(f"{server}.headers.{secret_headers[0]} holds a secret Harness cannot move")

    if secret_env:
        for key in secret_env:
            if not store.NAME.match(key):
                raise SecretError(f"{server}.env.{key} is a secret under a name a launcher cannot export")
        pairs = [(k, secrets.claim(k, env.pop(k), server)) for k in secret_env]
        names = [name for _k, name in pairs]
        command = [spec["command"], *spec.get("args", [])]
        renamed = [(k, name) for k, name in pairs if k != name]
        if renamed:
            # A stored name differs from what the server reads: assign in the shell,
            # so the value still never appears on a command line.
            assign = " ".join(f'{k}="${name}"' for k, name in renamed)
            command = ["sh", "-c", f'{assign} exec "$@"', "sh", *command]
        result = {**spec, "type": "stdio", "command": "sh", "args": ["-c", launcher(repo_rel, names, command)]}
        if env:
            result["env"] = env
        else:
            result.pop("env", None)
        return result, None

    for header in headers:
        if not SAFE_HEADER.match(header):
            raise SecretError(f"{server}.headers: header name {header!r} is not a plain token")
    parts, helper_fields, names = [], [], []
    for header in secret_headers:
        value = headers.pop(header)
        prefix, token = "", value
        if header.lower() == "authorization" and " " in value and value.split(" ", 1)[0] in SCHEMES:
            scheme, _, token = value.partition(" ")
            prefix = f"{scheme} "
        if any(c in token for c in '"\\') or any(ord(c) < 32 for c in token):
            raise SecretError(f"{server}.headers.{header} holds characters a JSON header helper cannot carry")
        label = "token" if header.lower() == "authorization" else header
        name = secrets.claim(env_name("mcp", server, label), token, server)
        names.append(name)
        parts += ["--header", f"{header}:{prefix}${{{name}}}"]
        helper_fields.append((header, prefix))
    plain = [arg for h, v in headers.items() for arg in ("--header", f"{h}:{v}")]
    # Keep every other field (disabled, timeouts, tool filters); replace only the transport.
    base = {k: v for k, v in spec.items() if k not in ("url", "httpUrl", "headers", "type", "command", "args")}
    command = ["npx", "-y", MCP_REMOTE, url, *parts, *plain]
    shared = {**base, "type": "stdio", "command": "sh", "args": ["-c", launcher(repo_rel, names, command)]}
    fmt = ", ".join(f'\\"{h}\\": \\"{p}%s\\"' for h, p in helper_fields)
    printf = f"printf \"{{{fmt}}}\" " + " ".join(f'"${n}"' for n in names)
    claude = {**base, "type": "http", "url": url,
              "headersHelper": f'"$HOME/{repo_rel}/bin/with-secrets" {" ".join(names)} -- sh -c {shlex.quote(printf)}'}
    if headers:
        claude["headers"] = headers
    return shared, claude


# Implied by command or url; importers also read remote servers back as sse.
IMPLIED_TYPES = {"stdio", "local", "http", "streamable-http", "sse"}
APP_BUNDLE = re.compile(r"\.app/")
CLAUDE_ONLY = ("headersHelper",)


def normalized(spec: dict) -> str:
    """Compare definitions, not each importer's spelling of them."""
    clean = {k: v for k, v in spec.items() if v not in ({}, [], None, "") and k not in ("description",)}
    if clean.get("type") in IMPLIED_TYPES:
        clean.pop("type")
    return json.dumps(clean, sort_keys=True)


def compose(imports: dict[str, tuple[dict, dict]], secrets: Secrets, repo_rel: str,
            claude_shared: bool = False) -> tuple[dict, dict, dict, dict]:
    """Return (source mcp, local mcp, source hooks, local hooks).

    claude_shared: Claude's settings.json is a repo link, so its hooks are shared already.
    """
    local_path = home_paths()
    local_mcp: dict = {}
    variants: dict[str, dict[str, dict]] = {}
    claude_only: dict[str, dict] = {}
    for tool, (servers, _hooks) in imports.items():
        for name, spec in servers.items():
            if leaks(spec):
                local_mcp.setdefault(tool, {"mcpServers": {}})["mcpServers"][name] = spec
                continue
            converted, claude_variant = convert(name, spec, secrets, repo_rel)
            variants.setdefault(name, {})[tool] = converted
            if claude_variant and tool == "claudecode":
                claude_only[name] = claude_variant
    source_mcp: dict = {"mcpServers": {}}
    for name in sorted(variants):
        by_tool = variants[name]
        portable = {t: s for t, s in by_tool.items() if not local_path.search(json.dumps(s))}
        for tool, spec in by_tool.items():
            if tool not in portable:
                local_mcp.setdefault(tool, {"mcpServers": {}})["mcpServers"][name] = spec
        if not portable:
            continue
        # A server inside an app bundle runs only where that app's tool has it, unless
        # every tool already has the same one (e.g. Xcode's bridge on every Mac).
        bundled = {t: s for t, s in portable.items() if APP_BUNDLE.search(json.dumps(s))}
        if set(bundled) == set(imports) and len({normalized(s) for s in bundled.values()}) == 1:
            bundled = {}
        for tool, spec in bundled.items():
            source_mcp.setdefault(tool, {"mcpServers": {}})["mcpServers"][name] = spec
        portable = {t: s for t, s in portable.items() if t not in bundled}
        if not portable:
            continue
        counts: dict[str, int] = {}
        for spec in portable.values():
            counts[normalized(spec)] = counts.get(normalized(spec), 0) + 1
        shareable = {t: s for t, s in portable.items() if not any(k in s for k in CLAUDE_ONLY)} or portable
        # The most common definition is shared (fewest per-tool blocks); Claude's wins ties.
        canonical_tool = max(shareable, key=lambda t: (counts[normalized(shareable[t])], -PREFERRED.index(t)))
        canonical = portable[canonical_tool]
        source_mcp["mcpServers"][name] = canonical
        for tool, spec in portable.items():
            if normalized(spec) != normalized(canonical):
                source_mcp.setdefault(tool, {"mcpServers": {}})["mcpServers"][name] = spec
        if name in claude_only and "claudecode" in portable:
            source_mcp.setdefault("claudecode", {"mcpServers": {}})["mcpServers"][name] = claude_only[name]
    source_hooks: dict = {"version": 1, "hooks": {}}
    local_hooks: dict = {}
    for tool, (_servers, hooks) in imports.items():
        for event, entries in hooks.items():
            for entry in entries:
                shared = tool == "claudecode" and claude_shared
                target = local_hooks if not shared and local_path.search(json.dumps(entry)) else source_hooks
                target.setdefault(tool, {"hooks": {}})["hooks"].setdefault(event, []).append(entry)
    return source_mcp, local_mcp, source_hooks, local_hooks


def manifest_names(repo: Path) -> set[str]:
    manifest = repo / "skills.manifest"
    if not manifest.is_file():
        return set()
    return {line.split("\t")[0].strip() for line in manifest.read_text().splitlines() if line.strip() and not line.startswith("#")}


def skill_sources(repo: Path) -> tuple[list[dict], list[str]]:
    """rulesync `sources` from npx skills' manifest and lock, plus unresolved names."""
    manifest = repo / "skills.manifest"
    lock_path = repo / ".skill-lock.json"
    names = []
    if manifest.is_file():
        names = [line.split("\t")[0].strip() for line in manifest.read_text().splitlines() if line.strip() and not line.startswith("#")]
    lock = {}
    if lock_path.is_file():
        try:
            data = json.loads(lock_path.read_text())
            lock = data.get("skills", data) if isinstance(data, dict) else {}
        except ValueError:
            lock = {}
    grouped: dict[tuple[str, str], list[str]] = {}
    unresolved = []
    for name in names:
        entry = lock.get(name)
        if not isinstance(entry, dict) or not entry.get("source") or not entry.get("skillPath"):
            unresolved.append(name)
            continue
        folder = Path(entry["skillPath"]).parent
        if not folder.name:  # a skill at its repo's root has no folder name to select
            unresolved.append(name)
            continue
        grouped.setdefault((entry["source"], str(folder.parent)), []).append(folder.name)
    sources = []
    for (source, path), skills in sorted(grouped.items()):
        item = {"source": source, "skills": sorted(skills)}
        if path not in ("", "."):
            item["path"] = path
        sources.append(item)
    return sources, unresolved


def personal_skills(repo: Path, declared: set[str]) -> list[str]:
    tracked = subprocess.run(["git", "-C", str(repo), "ls-files", "--", "skills"], text=True, capture_output=True).stdout.split()
    folders = {Path(p).parts[1] for p in tracked if len(Path(p).parts) > 2}
    return sorted(f for f in folders if not f.startswith(".") and f != "synced" and f not in declared)


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


LAUNCHED = re.compile(r'with-secrets\\?" ([A-Za-z0-9_ ]+?) --')


def store_secrets(repo: Path, secrets: Secrets, shared_source: dict | None) -> None:
    """Store every claimed value; list in secrets.names only the names shared servers use,
    since machine-only servers' secrets exist on this machine alone."""
    for name, value in secrets.values.items():
        store.put(name, value)
    if shared_source is None:
        return
    used = {n for match in LAUNCHED.findall(json.dumps(shared_source)) for n in match.split()}
    names_file = repo / "secrets.names"
    current = names_file.read_text() if names_file.is_file() else ""
    new = [n for n in secrets.values if n in used and n not in current.split()]
    if new:
        header = "" if current else "# Secret names this repo's agents need; values live in each machine's secret store.\n"
        separator = "\n" if current and not current.endswith("\n") else ""
        names_file.write_text(current + separator + header + "".join(f"{n}\n" for n in new))


def count(block: dict, key: str) -> int:
    total = 0
    for name, value in block.items():
        if name == key and isinstance(value, dict):
            total += sum(len(v) if isinstance(v, list) else 1 for v in value.values())
        elif isinstance(value, dict) and isinstance(value.get(key), dict):
            total += sum(len(v) if isinstance(v, list) else 1 for v in value[key].values())
    return total


def repo_path(repo: Path) -> str | None:
    """The repo's path under HOME, as launcher strings use it: same on every machine."""
    try:
        rel = str(repo.relative_to(Path.home().resolve()))
    except ValueError:
        return None
    return rel if SAFE_REL.match(rel) else None


def bootstrap(repo: Path, write: bool) -> int:
    if (repo / "rulesync.jsonc").exists():
        print(f"BOOTSTRAP=skipped: {repo} already has rulesync.jsonc")
        return 0
    repo_rel = repo_path(repo)
    if repo_rel is None:
        print("BOOTSTRAP=failed: the agents repo must live under your home folder, at a plain path")
        return 1
    existing = [p for p in (".rulesync/mcp.jsonc", ".rulesync/hooks.jsonc") if (repo / p).exists()]
    if existing:
        print(f"BOOTSTRAP=failed: {', '.join(existing)} already exist; move them aside first")
        return 1
    tools = installed_tools()
    imports = {tool: import_tool(tool) for tool in tools}
    secrets = Secrets(stored=store.get)
    source_mcp, local_mcp, source_hooks, local_hooks = compose(imports, secrets, repo_rel, gen.claude_settings_in_repo(repo))
    sources, unresolved = skill_sources(repo)
    declared = {s for item in sources for s in item["skills"]}
    # A skill named in skills.manifest is third-party even when its source is unknown.
    personal = personal_skills(repo, declared | set(unresolved) | manifest_names(repo))
    config = {
        "$schema": "https://github.com/dyoshikawa/rulesync/releases/latest/download/config-schema.json",
        "global": True, "delete": False, "targets": tools, "features": FEATURES, "sources": sources,
    }
    print(f"tools: {', '.join(tools) or 'none'}")
    print(f"MCP servers: {len(source_mcp['mcpServers'])} shared, {count(source_mcp, 'mcpServers') - len(source_mcp['mcpServers'])} per-tool, {count(local_mcp, 'mcpServers')} kept on this machine")
    print(f"hooks: {count(source_hooks, 'hooks')} synced, {count(local_hooks, 'hooks')} kept on this machine")
    print(f"secrets moved to the secret store: {', '.join(sorted(secrets.values)) or 'none'}")
    print(f"third-party skills declared: {', '.join(sorted(declared)) or 'none'}")
    if unresolved:
        print(f"skills without a source in .skill-lock.json (left as they are): {', '.join(unresolved)}")
    print(f"your own skills moving to .rulesync/skills: {', '.join(personal) or 'none'}")
    if not write:
        print("BOOTSTRAP=preview: run again with --write to apply, then /harness:sync")
        return 0
    store_secrets(repo, secrets, source_mcp)
    write_json(repo / ".rulesync" / "mcp.jsonc", source_mcp)
    write_json(repo / ".rulesync" / "hooks.jsonc", source_hooks)
    # Servers kept on this machine may hold plaintext values: ignore them before writing,
    # so a commit before the first sync cannot pick them up.
    ignore = repo / ".gitignore"
    current = ignore.read_text() if ignore.is_file() else ""
    if "/.rulesync.local/" not in current.splitlines():
        ignore.write_text(current + ("" if not current or current.endswith("\n") else "\n") + "/.rulesync.local/\n")
    write_json(repo / ".rulesync.local" / "mcp.jsonc", local_mcp)
    write_json(repo / ".rulesync.local" / "hooks.jsonc", local_hooks)
    for name in personal:
        (repo / ".rulesync" / "skills").mkdir(parents=True, exist_ok=True)
        subprocess.run(["git", "-C", str(repo), "mv", f"skills/{name}", f".rulesync/skills/{name}"], check=True, capture_output=True)
    write_json(repo / "rulesync.jsonc", config)
    print("BOOTSTRAP=written: run /harness:sync to generate every tool")
    return 0


def capture_machine(repo: Path) -> int:
    """First managed sync on this machine: keep what the shared source lacks."""
    local_dir = repo / ".rulesync.local"
    if local_dir.exists() or not (repo / "rulesync.jsonc").is_file():
        print("RULESYNC_CAPTURE=skipped")
        return 0
    repo_rel = repo_path(repo) or ""  # only a secret to convert needs it; launcher() refuses then
    settings = gen.load_jsonc(repo / "rulesync.jsonc")
    tools = [t for t in installed_tools() if t in (settings.get("targets") or list(TOOLS))]
    imports = {tool: import_tool(tool) for tool in tools}
    secrets = Secrets(stored=store.get)
    source_mcp_path, source_hooks_path = repo / ".rulesync" / "mcp.jsonc", repo / ".rulesync" / "hooks.jsonc"
    shared_mcp = gen.load_jsonc(source_mcp_path) if source_mcp_path.is_file() else {"mcpServers": {}}
    shared_hooks = gen.load_jsonc(source_hooks_path) if source_hooks_path.is_file() else {"hooks": {}}
    local_mcp: dict = {}
    local_hooks: dict = {}
    for tool, (servers, hooks) in imports.items():
        known = set(shared_mcp.get("mcpServers", {})) | set((shared_mcp.get(tool) or {}).get("mcpServers", {}))
        for name, spec in servers.items():
            if name not in known:
                converted, claude_variant = convert(name, spec, secrets, repo_rel)
                chosen = claude_variant if claude_variant and tool == "claudecode" else converted
                local_mcp.setdefault(tool, {"mcpServers": {}})["mcpServers"][name] = chosen
        defined = {**shared_hooks.get("hooks", {})}
        for event, entries in (shared_hooks.get(tool) or {}).get("hooks", {}).items():
            defined[event] = defined.get(event, []) + entries
        if tool == "claudecode" and gen.claude_settings_in_repo(repo):
            continue  # Claude's hooks already live in the shared settings.json
        for event, entries in hooks.items():
            commands = {e.get("command") for e in defined.get(event, [])}
            for entry in entries:
                if entry.get("command") not in commands:
                    local_hooks.setdefault(tool, {"hooks": {}})["hooks"].setdefault(event, []).append(entry)
    store_secrets(repo, secrets, None)
    write_json(local_dir / "mcp.jsonc", local_mcp)
    write_json(local_dir / "hooks.jsonc", local_hooks)
    servers, hooks_count = count(local_mcp, "mcpServers"), count(local_hooks, "hooks")
    note = " (move them into .rulesync/ to share them)" if servers or hooks_count else ""
    print(f"RULESYNC_CAPTURE=kept on this machine only: {servers} server(s), {hooks_count} hook(s){note}")
    return 0


def app_owned(spec: dict) -> bool:
    return bool(APP_BUNDLE.search(json.dumps(spec)))


def refresh_apps(repo: Path) -> int:
    """Re-read app-installed servers from each tool that has one in the overlay."""
    local_path = repo / ".rulesync.local" / "mcp.jsonc"
    if not local_path.is_file():
        return 0
    local = gen.load_jsonc(local_path)
    tools = [t for t, block in local.items() if t in TOOLS and isinstance(block, dict)
             and any(app_owned(s) for s in (block.get("mcpServers") or {}).values())]
    # ponytail: only tools that already have an app server are re-read (one import each);
    # an app's first server in a new tool waits for that tool's next capture.
    if not tools:
        return 0
    source_path = repo / ".rulesync" / "mcp.jsonc"
    shared = gen.load_jsonc(source_path) if source_path.is_file() else {}
    present = set(installed_tools())
    changed = 0
    for tool in tools:
        if tool not in present:
            continue
        live, _hooks = import_tool(tool)
        if not live:
            continue  # an empty import says nothing about what the app removed
        block = local[tool]["mcpServers"]
        known = set(shared.get("mcpServers", {})) | set((shared.get(tool) or {}).get("mcpServers", {}))
        for name in [n for n, spec in block.items() if app_owned(spec)]:
            if name not in live:
                del block[name]  # the app removed it
                changed += 1
            elif normalized(live[name]) != normalized(block[name]):
                block[name] = live[name]
                changed += 1
        for name, spec in live.items():
            if app_owned(spec) and name not in block and name not in known:
                block[name] = spec
                changed += 1
    if changed:
        write_json(local_path, local)
        print(f"RULESYNC_APPS=refreshed {changed} app-installed server(s) from their apps")
    return 0


def main(argv: list[str]) -> int:
    flags = {a for a in argv if a.startswith("--")}
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1 or flags - {"--write", "--machine", "--apps"} or len(flags) > 1:
        print(__doc__, file=sys.stderr)
        return 2
    repo = Path(args[0]).expanduser().resolve()
    try:
        if "--apps" in flags:
            return refresh_apps(repo)
        return capture_machine(repo) if "--machine" in flags else bootstrap(repo, "--write" in flags)
    except (OSError, ValueError, RuntimeError, SecretError, store.SecretError, subprocess.CalledProcessError) as error:
        prefix = {"--machine": "RULESYNC_CAPTURE", "--apps": "RULESYNC_APPS"}.get(next(iter(flags), ""), "BOOTSTRAP")
        print(f"{prefix}=failed: {type(error).__name__}: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
