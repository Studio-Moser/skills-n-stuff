#!/usr/bin/env python3
"""Local-first Harness telemetry.

Writers append one JSON line per event to this machine's state directory. Sync
publishes those files into the agents repository under telemetry/<host>/ after it
has ingested the remote, so live writes never leave the repository dirty.

  telemetry.py record-result --result JSON [--attempted JSON] [--operation OP] [--consumer NAME]
  telemetry.py publish --repo PATH

Records hold typed fields only: no prompts, raw errors, or secrets. Every string is
redacted to `~` for home paths so published files pass the portability lint.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import socket
import sys
import tempfile
import uuid
from datetime import datetime, timezone
from typing import Iterator

STREAMS = ("Results", "Shim_Events")
HOME_PATH = re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+")
STATUSES = {"accepted", "failed", "blocked", "abandoned"}
OUTCOMES = {"proven", "unproven"}
ROUTE_FIELDS = ("requested", "model", "effort", "provider", "executor", "dispatch")
MAX_ITEMS = 10
MAX_TEXT = 200


def state_dir() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
    return Path(base) / "studio-moser/harness/telemetry"


def host() -> str:
    # Same short name sync uses in its commit message.
    return socket.gethostname().split(".")[0]


def redact(value: object) -> object:
    if isinstance(value, str):
        home = str(Path.home())
        text = value.replace(home, "~") if home not in ("", "/") else value
        return HOME_PATH.sub("~", text)
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, dict):
        return {key: redact(item) for key, item in value.items()}
    return value


def append(stream: str, record: dict) -> str:
    assert stream in STREAMS, stream
    now = datetime.now(timezone.utc)
    entry = {"id": uuid.uuid4().hex, "ts": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "host": host()}
    entry.update(redact(record))
    directory = state_dir()
    directory.mkdir(parents=True, exist_ok=True)
    line = json.dumps(entry, sort_keys=True, ensure_ascii=False) + "\n"
    # One O_APPEND write per event keeps concurrent writers from interleaving lines.
    fd = os.open(directory / f"{stream}-{now:%Y-%m}.jsonl", os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, line.encode())
    finally:
        os.close(fd)
    return entry["id"]


def read_lines(path: Path) -> Iterator[dict]:
    try:
        handle = path.open(encoding="utf-8")
    except OSError:
        return
    with handle:
        for line in handle:
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if isinstance(record, dict) and isinstance(record.get("id"), str):
                yield record


def events(stream: str, repo: Path | None = None, *, local_only: bool = False) -> list[dict]:
    """Union of this machine's unpublished events and every host's published ones."""
    files = sorted(state_dir().glob(f"{stream}-*.jsonl"))
    if repo is not None and not local_only:
        files += sorted((repo / "telemetry").glob(f"*/{stream}-*.jsonl"))
    seen: dict[str, dict] = {}
    for path in files:
        for record in read_lines(path):
            seen.setdefault(record["id"], record)
    return sorted(seen.values(), key=lambda record: str(record.get("ts", "")))


def write_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        handle.write(text)
    os.replace(temporary, path)


def publish(repo: Path) -> int:
    """Merge local event files into telemetry/<host>/ by id. Returns new lines added.

    A union, never an overwrite: a reinstalled machine with an empty local state keeps
    the history already published under its host name.
    """
    added = 0
    target_dir = repo / "telemetry" / host()
    for source in sorted(state_dir().glob("*.jsonl")):
        if not source.name.startswith(tuple(f"{stream}-" for stream in STREAMS)):
            continue
        target = target_dir / source.name
        merged = {record["id"]: record for record in read_lines(target)}
        before = len(merged)
        for record in read_lines(source):
            merged.setdefault(record["id"], redact(record))
        if len(merged) == before and target.exists():
            continue
        added += len(merged) - before
        ordered = sorted(merged.values(), key=lambda record: str(record.get("ts", "")))
        write_atomic(target, "".join(json.dumps(r, sort_keys=True, ensure_ascii=False) + "\n" for r in ordered))
    return added


def result_record(result: object, attempted: object, operation: str, consumer: str) -> dict:
    if not isinstance(result, dict):
        raise ValueError("result must be a JSON object")
    status = result.get("status")
    if status not in STATUSES:
        raise ValueError(f"status must be one of {sorted(STATUSES)}")
    route = result.get("route")
    if not isinstance(route, dict) or any(field not in route for field in ROUTE_FIELDS):
        raise ValueError(f"route must carry {', '.join(ROUTE_FIELDS)}")
    evidence = result.get("evidence")
    if not isinstance(evidence, dict) or evidence.get("outcome") not in OUTCOMES:
        raise ValueError("evidence.outcome must be proven or unproven")
    blockers = result.get("blockers") or []
    checks = evidence.get("checks") or []
    if not isinstance(blockers, list) or not isinstance(checks, list):
        raise ValueError("blockers and evidence.checks must be lists")
    if attempted is None:
        attempted = []
    if not isinstance(attempted, list):
        raise ValueError("attempted must be a JSON list")
    return {
        "operation": operation,
        "consumer": consumer,
        "status": status,
        "route": {field: str(route.get(field) or "") for field in ROUTE_FIELDS},
        "outcome": evidence["outcome"],
        "checks": len(checks),
        "blockers": [str(item)[:MAX_TEXT] for item in blockers[:MAX_ITEMS]],
        "attempted": attempted[:MAX_ITEMS],
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    record = commands.add_parser("record-result")
    record.add_argument("--result", required=True, help="complete HarnessResult as JSON")
    record.add_argument("--attempted", default="[]", help="resolver candidates tried before the terminal one")
    record.add_argument("--operation", default="", choices=("", "execute", "review", "computer-use"))
    record.add_argument("--consumer", default="", help="calling skill, e.g. pm:dev-task")
    published = commands.add_parser("publish")
    published.add_argument("--repo", required=True, type=Path)
    args = parser.parse_args(argv)

    if args.command == "publish":
        print(json.dumps({"status": "published", "added": publish(args.repo)}))
        return 0
    try:
        entry = result_record(json.loads(args.result), json.loads(args.attempted), args.operation, args.consumer)
    except ValueError as error:
        print(json.dumps({"status": "invalid", "reason": str(error)}))
        return 2
    print(json.dumps({"status": "recorded", "id": append("Results", entry)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
