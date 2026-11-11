#!/usr/bin/env python3
"""Local-first Harness telemetry.

Writers append one JSON line per event to this machine's state directory. Sync
publishes those files into the agents repository under telemetry/<host>/ after it
has ingested the remote, so live writes never leave the repository dirty.

  telemetry.py record-result --result JSON [--attempted JSON] [--operation OP] [--consumer NAME]
      [--context CONTEXT]
  telemetry.py record-review --consumer NAME --target TEXT --model NAME --provider NAME
      --round N --limit N --findings JSON --diff-lines N [--extension-approved]
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

STREAMS = ("Results", "Shim_Events", "Review_Rounds")
HOME_PATH = re.compile(r"/(?:Users|home)/[A-Za-z0-9._-]+")
STATUSES = {"accepted", "failed", "blocked", "abandoned"}
OUTCOMES = {"proven", "unproven"}
ROUTE_FIELDS = ("requested", "model", "effort", "provider", "executor", "dispatch")
# unique: confirmed findings no other reviewer raised on this target.
# regraded: findings whose severity the parent changed.
FINDING_COUNTS = ("fixed", "disputed", "declined", "open", "unique", "regraded")
# Where harness:delegate ran: the host runtime, and whether it was the top-level session.
CONTEXTS = ("", "claude-main", "claude-worker", "codex-main", "codex-worker")
# executor: for missing_executor and unsuitable_executor, the executor the candidate's
# row names ("" for none).
ATTEMPT_FIELDS = ("candidate", "reason", "executor")
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


def require_one_reviewer(model: str, provider: str) -> None:
    # A combined row cannot be attributed, so it would corrupt per-model counts.
    if "+" in model or "+" in provider:
        raise ValueError("record one row per model and provider, not a combined one")


def require_count(name: str, value: object, minimum: int = 0) -> int:
    # bool is an int subclass; a true flag is not a count.
    if type(value) is not int or value < minimum:
        raise ValueError(f"{name} must be an integer of at least {minimum}")
    return value


def review_record(
    consumer: str,
    target: str,
    model: str,
    provider: str,
    round_number: int,
    limit: int,
    extension_approved: bool,
    findings: object,
    diff_lines: int,
) -> dict:
    for name, value in (("consumer", consumer), ("target", target), ("model", model), ("provider", provider)):
        if not value.strip():
            raise ValueError(f"{name} must not be empty")
    require_one_reviewer(model, provider)
    if not isinstance(findings, dict) or set(findings) - set(FINDING_COUNTS):
        raise ValueError(f"findings must be an object with only {', '.join(FINDING_COUNTS)}")
    return {
        "consumer": consumer[:MAX_TEXT],
        "target": target[:MAX_TEXT],
        "model": model[:MAX_TEXT],
        "provider": provider[:MAX_TEXT],
        "round": require_count("round", round_number),
        "limit": require_count("limit", limit, 1),
        "extension_approved": extension_approved,
        "findings": {name: require_count(name, findings.get(name, 0)) for name in FINDING_COUNTS},
        "diff_lines": require_count("diff-lines", diff_lines),
    }


def attempt_record(entry: object) -> dict:
    if not isinstance(entry, dict) or not all(isinstance(entry.get(field), str) for field in ("candidate", "reason")):
        raise ValueError("each attempted entry must be an object with candidate and reason strings")
    return {field: str(entry[field])[:MAX_TEXT] for field in ATTEMPT_FIELDS if field in entry}


def result_record(result: object, attempted: object, operation: str, consumer: str, context: str = "") -> dict:
    if not isinstance(result, dict):
        raise ValueError("result must be a JSON object")
    status = result.get("status")
    if status not in STATUSES:
        raise ValueError(f"status must be one of {sorted(STATUSES)}")
    route = result.get("route")
    if not isinstance(route, dict) or any(field not in route for field in ROUTE_FIELDS):
        raise ValueError(f"route must carry {', '.join(ROUTE_FIELDS)}")
    require_one_reviewer(str(route.get("model") or ""), str(route.get("provider") or ""))
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
        "context": context,
        "status": status,
        "route": {field: str(route.get(field) or "") for field in ROUTE_FIELDS},
        "outcome": evidence["outcome"],
        "checks": len(checks),
        "blockers": [str(item)[:MAX_TEXT] for item in blockers[:MAX_ITEMS]],
        "attempted": [attempt_record(entry) for entry in attempted[:MAX_ITEMS]],
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    commands = parser.add_subparsers(dest="command", required=True)
    record = commands.add_parser("record-result")
    record.add_argument("--result", required=True, help="complete HarnessResult as JSON")
    record.add_argument("--attempted", default="[]", help="resolver candidates tried before the terminal one")
    record.add_argument("--operation", default="", choices=("", "execute", "review", "computer-use"))
    record.add_argument("--consumer", default="", help="calling skill, e.g. pm:dev-task")
    record.add_argument("--context", default="", choices=CONTEXTS, help="runtime and level that ran harness:delegate")
    review = commands.add_parser("record-review")
    review.add_argument("--consumer", required=True, help="workflow that owns the review loop")
    review.add_argument("--target", required=True, help="stable name for the reviewed work, e.g. a PR number")
    review.add_argument("--model", required=True)
    review.add_argument("--provider", required=True)
    review.add_argument("--round", required=True, type=int, help="0 is the initial review; 1 and up are fix/review rounds")
    review.add_argument("--limit", required=True, type=int, help="fix/review rounds the workflow allows")
    review.add_argument("--extension-approved", action="store_true", help="the user approved rounds past the limit")
    review.add_argument("--findings", required=True, help=f"JSON counts: {', '.join(FINDING_COUNTS)}")
    review.add_argument("--diff-lines", required=True, type=int, help="insertions plus deletions against the base")
    published = commands.add_parser("publish")
    published.add_argument("--repo", required=True, type=Path)
    args = parser.parse_args(argv)

    if args.command == "publish":
        print(json.dumps({"status": "published", "added": publish(args.repo)}))
        return 0
    try:
        if args.command == "record-review":
            stream = "Review_Rounds"
            entry = review_record(
                args.consumer,
                args.target,
                args.model,
                args.provider,
                args.round,
                args.limit,
                args.extension_approved,
                json.loads(args.findings),
                args.diff_lines,
            )
        else:
            stream = "Results"
            entry = result_record(
                json.loads(args.result), json.loads(args.attempted), args.operation, args.consumer, args.context
            )
    except ValueError as error:
        print(json.dumps({"status": "invalid", "reason": str(error)}))
        return 2
    print(json.dumps({"status": "recorded", "id": append(stream, entry)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
