#!/usr/bin/env python3
"""Keep agent secrets in this machine's secret store and hand them only to the
process that needs them. Values are never printed, logged, or put on a command line.

  agent-secrets.py set NAME                 value from stdin (or a hidden prompt)
  agent-secrets.py exec [--optional] --env NAME [--env NAME ...] -- CMD [ARGS...]
                                            start CMD with each NAME exported; a name
                                            already set in the environment is kept
  agent-secrets.py check [NAME ...]         report present/missing; exit 1 if missing
  agent-secrets.py copy-to HOST [NAME ...]  copy values over fleet SSH into HOST's store

Names default to ${AGENTS_REPO:-~/.agents}/secrets.names (one per line, # comments).

Backend, chosen by HARNESS_SECRETS_BACKEND or the platform:
  keychain   macOS login Keychain via `security` (service agent-secrets, account NAME)
  libsecret  Linux desktop keyring via `secret-tool`
  file       ${XDG_CONFIG_HOME:-~/.config}/agent-secrets/secrets.env, mode 0600
copy-to runs `set` on the remote machine, so each machine keeps its own backend.
"""

from __future__ import annotations

import getpass
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
SERVICE = os.environ.get("HARNESS_SECRETS_SERVICE", "agent-secrets")
MISSING_EXIT = 78  # EX_CONFIG: the command cannot start without its configuration
KEYCHAIN_MAX = 3500
# Resolves the remote Harness root the same way skills do, across Claude and Codex caches.
REMOTE_ROOT = (
    'h=$(ls -d "$HOME"/.claude/plugins/cache/*/harness/*/ "$HOME"/.codex/plugins/cache/*/harness/*/ '
    "2>/dev/null | awk -F/ '{print $(NF-1)\"\\t\"$0}' | sort -V | tail -1 | cut -f2)"
)


class SecretError(Exception):
    pass


def backend_name() -> str:
    chosen = os.environ.get("HARNESS_SECRETS_BACKEND")
    if chosen:
        if chosen not in ("keychain", "libsecret", "file"):
            raise SecretError(f"unknown HARNESS_SECRETS_BACKEND {chosen!r}")
        return chosen
    if sys.platform == "darwin" and shutil.which("security"):
        return "keychain"
    if sys.platform.startswith("linux") and shutil.which("secret-tool"):
        return "libsecret"
    return "file"


def secrets_file() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "agent-secrets" / "secrets.env"


def read_file_store() -> dict[str, str]:
    path = secrets_file()
    values: dict[str, str] = {}
    if path.is_file():
        for line in path.read_text(encoding="utf-8").splitlines():
            key, sep, value = line.partition("=")
            if sep and NAME.match(key):
                values[key] = value
    return values


def get(name: str) -> str | None:
    backend = backend_name()
    if backend == "file":
        return read_file_store().get(name)
    if backend == "keychain":
        command = ["security", "find-generic-password", "-s", SERVICE, "-a", name, "-w"]
        if os.environ.get("HARNESS_KEYCHAIN"):
            command.append(os.environ["HARNESS_KEYCHAIN"])
    else:
        command = ["secret-tool", "lookup", "service", SERVICE, "account", name]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        return None
    return result.stdout[:-1] if result.stdout.endswith("\n") else result.stdout


def put(name: str, value: str) -> None:
    if "\n" in value or "\0" in value:
        raise SecretError("a secret value must be a single line")
    backend = backend_name()
    if backend == "file":
        values = read_file_store()
        values[name] = value
        path = secrets_file()
        path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=".secrets.")
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write("".join(f"{key}={values[key]}\n" for key in sorted(values)))
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
        return
    if backend == "keychain":
        # `security -i` reads the command from stdin, so the value stays off argv.
        escaped = value.replace("\\", "\\\\").replace('"', '\\"')
        if len(escaped.encode()) > KEYCHAIN_MAX:
            # `security -i` splits longer input lines and would store a truncated value.
            raise SecretError(f"a Keychain value is limited to {KEYCHAIN_MAX} bytes")
        keychain = os.environ.get("HARNESS_KEYCHAIN")
        line = f'add-generic-password -U -s "{SERVICE}" -a "{name}" -w "{escaped}"'
        line += f' "{keychain}"\n' if keychain else "\n"
        result = subprocess.run(["security", "-i"], input=line, capture_output=True, text=True)
    else:
        result = subprocess.run(
            ["secret-tool", "store", "--label", f"{SERVICE} {name}", "service", SERVICE, "account", name],
            input=value, capture_output=True, text=True,
        )
    if result.returncode != 0 or get(name) != value:
        raise SecretError(f"could not store {name} in the {backend} backend")


def names_file() -> Path:
    repo = os.environ.get("AGENTS_REPO") or str(Path.home() / ".agents")
    return Path(repo).expanduser() / "secrets.names"


def default_names() -> list[str]:
    path = names_file()
    if not path.is_file():
        return []
    names = []
    for line in path.read_text(encoding="utf-8").splitlines():
        name = line.split("#", 1)[0].strip()
        if name:
            names.append(name)
    return names


def checked(names: list[str]) -> list[str]:
    for name in names:
        if not NAME.match(name):
            raise SecretError(f"invalid secret name {name!r}")
    return names


def cmd_set(args: list[str]) -> int:
    if len(args) != 1:
        raise SecretError("usage: set NAME")
    name = checked(args)[0]
    if sys.stdin.isatty():
        value = getpass.getpass(f"{name}: ")
    else:
        value = sys.stdin.read()
        value = value[:-1] if value.endswith("\n") else value
    if not value:
        raise SecretError("refusing to store an empty value")
    put(name, value)
    print(f"{name} stored ({backend_name()})")
    return 0


def cmd_exec(args: list[str]) -> int:
    if "--" not in args:
        raise SecretError("usage: exec [--optional] --env NAME ... -- CMD [ARGS...]")
    split = args.index("--")
    options, command = args[:split], args[split + 1 :]
    if not command:
        raise SecretError("exec needs a command after --")
    optional = "--optional" in options
    names = [options[i + 1] for i, item in enumerate(options[:-1]) if item == "--env"]
    environment = dict(os.environ)
    for name in checked(names):
        if environment.get(name):
            continue
        value = get(name)
        if value is None:
            if optional:
                continue
            print(f"agent-secrets: {name} is not stored on this machine; "
                  f"run: agent-secrets.py set {name}", file=sys.stderr)
            return MISSING_EXIT
        environment[name] = value
    os.execvpe(command[0], command, environment)
    return 0  # unreachable


def cmd_check(args: list[str]) -> int:
    names = checked(args or default_names())
    missing = 0
    for name in names:
        present = get(name) is not None
        missing += not present
        print(f"{name}\t{'present' if present else 'missing'}")
    print(f"backend\t{backend_name()}")
    return 1 if missing else 0


def cmd_copy_to(args: list[str]) -> int:
    if not args:
        raise SecretError("usage: copy-to HOST [NAME ...]")
    host, names = args[0], checked(args[1:] or default_names())
    if not re.match(r"^[A-Za-z0-9._-]+$", host):
        raise SecretError(f"invalid host alias {host!r}")
    failed = 0
    for name in names:
        value = get(name)
        if value is None:
            print(f"{name}\tmissing locally")
            failed += 1
            continue
        remote = f'{REMOTE_ROOT}; exec python3 "$h/scripts/agent-secrets.py" set {name}'
        # ssh hands one string to the remote login shell; quote it as a single word.
        result = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", host, "sh -lc " + shlex.quote(remote)],
            input=value + "\n", capture_output=True, text=True,
        )
        ok = result.returncode == 0
        failed += not ok
        print(f"{name}\t{'copied' if ok else 'failed: ' + (result.stderr.strip().splitlines() or ['ssh error'])[-1]}")
    return 1 if failed else 0


def main(argv: list[str]) -> int:
    commands = {"set": cmd_set, "exec": cmd_exec, "check": cmd_check, "copy-to": cmd_copy_to}
    if not argv or argv[0] not in commands:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        return commands[argv[0]](argv[1:])
    except SecretError as error:
        print(f"agent-secrets: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
