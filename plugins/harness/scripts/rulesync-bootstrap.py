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
  hooks   each tool keeps its own hooks; entries with home-folder paths stay local.
  skills  skills.manifest + .skill-lock.json entries become rulesync `sources`;
          other committed folders under skills/ are yours and move to .rulesync/skills.

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

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("rulesync_generate", HERE / "rulesync-generate.py")
gen = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gen)

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
        env = dict(os.environ, HOME=str(home), npm_config_yes="true")
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


class Secrets:
    """Secret values found while composing; stored in the OS store only on --write."""

    def __init__(self) -> None:
        self.values: dict[str, str] = {}

    def claim(self, name: str, value: str, server: str) -> str:
        if self.values.get(name, value) != value:
            name = env_name(server, name)
        self.values[name] = value
        return name


def launcher(repo_rel: str, names: list[str], command: list[str]) -> str:
    return f'exec "$HOME/{repo_rel}/bin/with-secrets" {" ".join(names)} -- {shlex.join(command)}'


def convert(server: str, spec: dict, secrets: Secrets, repo_rel: str) -> tuple[dict, dict | None]:
    """(definition for every tool, Claude-only variant or None), secrets moved out."""
    spec = json.loads(json.dumps(spec))
    env = spec.get("env") or {}
    secret_env = [k for k, v in env.items() if isinstance(v, str) and v and not v.startswith("${") and SECRET_NAME.search(k)]
    headers = spec.get("headers") or {}
    secret_headers = [h for h, v in headers.items() if isinstance(v, str) and v and "${" not in v
                      and (h.lower() == "authorization" or SECRET_NAME.search(h))]
    if not secret_env and not secret_headers:
        return spec, None
    if secret_env and spec.get("command"):
        pairs = [(k, secrets.claim(k, env.pop(k), server)) for k in secret_env]
        names = [name for _k, name in pairs]
        command = [spec["command"], *spec.get("args", [])]
        renamed = [(k, name) for k, name in pairs if k != name]
        if renamed:
            # A stored name differs from what the server reads: assign in the shell,
            # so the value still never appears on a command line.
            assign = " ".join(f'{k}="${name}"' for k, name in renamed)
            command = ["sh", "-c", f'{assign} exec "$@"', "sh", *command]
        spec.update({"type": "stdio", "command": "sh", "args": ["-c", launcher(repo_rel, names, command)]})
        if not env:
            spec.pop("env", None)
    if secret_headers and spec.get("url"):
        parts, helper_fields, names = [], [], []
        for header in secret_headers:
            value = headers.pop(header)
            scheme, _, token = value.partition(" ") if " " in value else ("", "", value)
            name = secrets.claim(env_name(server, "token" if header.lower() == "authorization" else header), token, server)
            names.append(name)
            prefix = f"{scheme} " if scheme else ""
            parts += ["--header", f"{header}:{prefix}${{{name}}}"]
            helper_fields.append((header, prefix))
        plain = [arg for h, v in headers.items() for arg in ("--header", f"{h}:{v}")]
        command = ["npx", "-y", MCP_REMOTE, spec["url"], *parts, *plain]
        shared = {"type": "stdio", "command": "sh", "args": ["-c", launcher(repo_rel, names, command)]}
        fmt = ", ".join(f'\\"{h}\\": \\"{p}%s\\"' for h, p in helper_fields)
        printf = f"printf \"{{{fmt}}}\" " + " ".join(f'"${n}"' for n in names)
        claude = {"type": "http", "url": spec["url"],
                  "headersHelper": f'"$HOME/{repo_rel}/bin/with-secrets" {" ".join(names)} -- sh -c {shlex.quote(printf)}'}
        if headers:
            claude["headers"] = headers
        return shared, claude
    return spec, None


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


def compose(imports: dict[str, tuple[dict, dict]], secrets: Secrets, repo_rel: str) -> tuple[dict, dict, dict, dict]:
    """Return (source mcp, local mcp, source hooks, local hooks)."""
    local_path = home_paths()
    variants: dict[str, dict[str, dict]] = {}
    claude_only: dict[str, dict] = {}
    for tool, (servers, _hooks) in imports.items():
        for name, spec in servers.items():
            converted, claude_variant = convert(name, spec, secrets, repo_rel)
            variants.setdefault(name, {})[tool] = converted
            if claude_variant and tool == "claudecode":
                claude_only[name] = claude_variant
    source_mcp: dict = {"mcpServers": {}}
    local_mcp: dict = {}
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
                target = local_hooks if local_path.search(json.dumps(entry)) else source_hooks
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


def store_secrets(repo: Path, secrets: Secrets) -> None:
    tool = HERE / "agent-secrets.py"
    for name, value in secrets.values.items():
        result = subprocess.run([sys.executable, str(tool), "set", name], input=value, text=True, capture_output=True)
        if result.returncode:
            raise RuntimeError(f"could not store {name}: {result.stderr.strip()}")
    names_file = repo / "secrets.names"
    existing = names_file.read_text().split() if names_file.is_file() else []
    new = [n for n in secrets.values if n not in existing]
    if new:
        with names_file.open("a") as handle:
            if not names_file.stat().st_size:
                handle.write("# Secret names this repo's agents need; values live in each machine's secret store.\n")
            handle.write("".join(f"{n}\n" for n in new))


def count(block: dict, key: str) -> int:
    total = 0
    for name, value in block.items():
        if name == key and isinstance(value, dict):
            total += sum(len(v) if isinstance(v, list) else 1 for v in value.values())
        elif isinstance(value, dict) and isinstance(value.get(key), dict):
            total += sum(len(v) if isinstance(v, list) else 1 for v in value[key].values())
    return total


def bootstrap(repo: Path, write: bool) -> int:
    if (repo / "rulesync.jsonc").exists():
        print(f"BOOTSTRAP=skipped: {repo} already has rulesync.jsonc")
        return 0
    try:
        repo_rel = str(repo.relative_to(Path.home().resolve()))
    except ValueError:
        print("BOOTSTRAP=failed: the agents repo must live under your home folder")
        return 1
    tools = installed_tools()
    imports = {tool: import_tool(tool) for tool in tools}
    secrets = Secrets()
    source_mcp, local_mcp, source_hooks, local_hooks = compose(imports, secrets, repo_rel)
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
    store_secrets(repo, secrets)
    write_json(repo / ".rulesync" / "mcp.jsonc", source_mcp)
    write_json(repo / ".rulesync" / "hooks.jsonc", source_hooks)
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
    try:
        repo_rel = str(repo.relative_to(Path.home().resolve()))
    except ValueError:
        repo_rel = ".agents"
    settings = gen.load_jsonc(repo / "rulesync.jsonc")
    tools = [t for t in installed_tools() if t in (settings.get("targets") or list(TOOLS))]
    imports = {tool: import_tool(tool) for tool in tools}
    secrets = Secrets()
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
        for event, entries in hooks.items():
            commands = {e.get("command") for e in defined.get(event, [])}
            for entry in entries:
                if entry.get("command") not in commands:
                    local_hooks.setdefault(tool, {"hooks": {}})["hooks"].setdefault(event, []).append(entry)
    store_secrets(repo, secrets)
    write_json(local_dir / "mcp.jsonc", local_mcp)
    write_json(local_dir / "hooks.jsonc", local_hooks)
    servers, hooks_count = count(local_mcp, "mcpServers"), count(local_hooks, "hooks")
    note = " (move them into .rulesync/ to share them)" if servers or hooks_count else ""
    print(f"RULESYNC_CAPTURE=kept on this machine only: {servers} server(s), {hooks_count} hook(s){note}")
    return 0


def main(argv: list[str]) -> int:
    flags = {a for a in argv if a.startswith("--")}
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 1 or flags - {"--write", "--machine"} or {"--write", "--machine"} <= flags:
        print(__doc__, file=sys.stderr)
        return 2
    repo = Path(args[0]).expanduser().resolve()
    try:
        return capture_machine(repo) if "--machine" in flags else bootstrap(repo, "--write" in flags)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        prefix = "RULESYNC_CAPTURE" if "--machine" in flags else "BOOTSTRAP"
        print(f"{prefix}=failed: {type(error).__name__}: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
