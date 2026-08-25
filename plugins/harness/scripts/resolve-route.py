#!/usr/bin/env python3
"""Resolve one Harness semantic route from a validated model rubric."""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Iterator


AVAILABILITY_REASONS = {
    "quota",
    "authentication",
    "rate_limit",
    "provider_unavailable",
    "missing_executor",
}
TIMED_AVAILABILITY_REASONS = AVAILABILITY_REASONS - {"missing_executor"}
OUTAGE_DELAYS = (900, 3600, 21600, 86400)
DAY_SECONDS = 86400
PROBE_LEASE_SECONDS = 900
EXIT_BLOCKED = 4


class Blocked(ValueError):
    """The rubric cannot produce an authorized route resolution."""


class Arguments(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise argparse.ArgumentError(None, message)


@dataclass(frozen=True)
class Candidate:
    ref: str
    model: str
    effort: str
    provider: str
    executor: str
    taste: int | None


def split_ref(value: str) -> tuple[str, str]:
    model, separator, effort = value.rpartition("@")
    if not separator or not model or not effort:
        raise ValueError(f"invalid model-effort reference: {value}")
    return model, effort


def resolve_executor(
    row: dict, native_provider: str, executors: set[str]
) -> tuple[str | None, str | None]:
    if row["provider"] == native_provider:
        return "native", None
    via = row.get("via")
    return (via, None) if via in executors else (None, "missing_executor")


def compact_json(value: dict) -> None:
    print(json.dumps(value, separators=(",", ":")))


def circuit_key(provider: str, executor: str) -> str:
    return f"{provider}|{executor}"


def cooldown_seconds(reason: str, failure_count: int) -> int:
    if reason in {"quota", "authentication"}:
        return DAY_SECONDS
    if reason in {"rate_limit", "provider_unavailable"}:
        index = min(max(failure_count, 1) - 1, len(OUTAGE_DELAYS) - 1)
        return OUTAGE_DELAYS[index]
    raise ValueError(f"not a timed availability failure: {reason}")


def default_state_path() -> Path:
    root = Path(os.environ.get("XDG_STATE_HOME") or Path.home() / ".local/state")
    return root / "studio-moser/harness/provider-health.json"


def state_path(value: str | None) -> Path:
    return Path(value) if value else default_state_path()


def decode_timestamp(value: object) -> datetime:
    if not isinstance(value, str) or not value:
        raise ValueError("timestamp must be a non-empty string")
    normalized = f"{value[:-1]}+00:00" if value.endswith("Z") else value
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def parse_timestamp(value: str | None, field: str) -> datetime:
    if value is None:
        return datetime.now(timezone.utc)
    try:
        return decode_timestamp(value)
    except ValueError as error:
        raise argparse.ArgumentError(None, f"{field} must be an ISO 8601 timestamp") from error


def format_timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="seconds").replace(
        "+00:00", "Z"
    )


def malformed_state() -> Blocked:
    return Blocked("provider health state is malformed")


def validate_state(document: object) -> dict:
    if not isinstance(document, dict) or set(document) != {"version", "circuits"}:
        raise malformed_state()
    if (
        isinstance(document["version"], bool)
        or document["version"] != 1
        or not isinstance(document["circuits"], dict)
    ):
        raise malformed_state()

    fields = {
        "state",
        "reason",
        "failure_count",
        "last_failure_at",
        "unavailable_until",
        "probe_claimed_at",
    }
    for key, circuit in document["circuits"].items():
        if (
            not isinstance(key, str)
            or key.count("|") != 1
            or not all(key.split("|"))
            or not isinstance(circuit, dict)
            or set(circuit) != fields
            or circuit["state"] != "open"
            or not isinstance(circuit["reason"], str)
            or circuit["reason"] not in TIMED_AVAILABILITY_REASONS
            or isinstance(circuit["failure_count"], bool)
            or not isinstance(circuit["failure_count"], int)
            or circuit["failure_count"] < 1
        ):
            raise malformed_state()
        try:
            decode_timestamp(circuit["last_failure_at"])
            decode_timestamp(circuit["unavailable_until"])
            if circuit["probe_claimed_at"] is not None:
                decode_timestamp(circuit["probe_claimed_at"])
        except (TypeError, ValueError) as error:
            raise malformed_state() from error
    return document


def load_state(path: Path) -> dict:
    if not path.exists():
        return {"version": 1, "circuits": {}}
    try:
        with path.open(encoding="utf-8") as handle:
            document = json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise malformed_state() from error
    return validate_state(document)


def write_state(path: Path, state: dict) -> None:
    descriptor = -1
    temporary = ""
    try:
        descriptor, temporary = tempfile.mkstemp(
            prefix=f".{path.name}.", dir=path.parent
        )
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            descriptor = -1
            json.dump(state, handle, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except OSError as error:
        raise Blocked("provider health state could not be written") from error
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary:
            try:
                os.unlink(temporary)
            except FileNotFoundError:
                pass


def state_lock_path(path: Path) -> Path:
    return path.with_name(f"{path.name}.lock")


@contextmanager
def locked_state(path: Path) -> Iterator[dict]:
    try:
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        descriptor = os.open(state_lock_path(path), os.O_RDWR | os.O_CREAT, 0o600)
        os.fchmod(descriptor, 0o600)
    except OSError as error:
        raise Blocked("provider health state could not be locked") from error
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX)
        except OSError as error:
            raise Blocked("provider health state could not be locked") from error
        yield load_state(path)
    finally:
        os.close(descriptor)


@contextmanager
def state_for_selection(path: Path) -> Iterator[dict]:
    with locked_state(path) as health:
        yield health


def blocked(message: str, attempted: list[str] | None = None,
            skipped: list[str] | None = None) -> None:
    result: dict[str, object] = {"status": "blocked", "blockers": [message]}
    if attempted is not None:
        result["attempted"] = attempted
    if skipped:
        result["skipped"] = skipped
    compact_json(result)


def load_rubric(path: str) -> dict:
    try:
        process = subprocess.run(
            ["yq", "-o=json", path],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except FileNotFoundError as error:
        raise Blocked("yq is required to load the rubric") from error
    if process.returncode:
        raise Blocked("rubric could not be loaded")
    try:
        document = json.loads(process.stdout)
    except json.JSONDecodeError as error:
        raise Blocked("rubric is not valid YAML") from error
    if not isinstance(document, dict):
        raise Blocked("rubric must be a mapping")
    return document


def require_string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value:
        raise Blocked(f"{field} must be a non-empty string")
    return value


def require_circuit_component(value: object, field: str) -> str:
    component = require_string(value, field)
    if "|" in component:
        raise Blocked(f"{field} must not contain '|'")
    return component


def require_argument_string(value: object, field: str) -> str:
    if not isinstance(value, str) or not value or "|" in value:
        raise argparse.ArgumentError(
            None, f"{field} must be a non-empty string without '|'"
        )
    return value


def model_rows(document: dict) -> dict[tuple[str, str], dict]:
    rows = document.get("models")
    if not isinstance(rows, list) or not rows:
        raise Blocked("rubric.models must be a non-empty list")

    indexed: dict[tuple[str, str], dict] = {}
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise Blocked(f"models[{index}] must be a mapping")
        name = require_string(row.get("name"), f"models[{index}].name")
        effort = require_string(row.get("effort"), f"models[{index}].effort")
        require_circuit_component(row.get("provider"), f"models[{index}].provider")
        if "via" in row and row["via"] is not None:
            require_circuit_component(row["via"], f"models[{index}].via")
        if "taste" in row and (
            isinstance(row["taste"], bool) or not isinstance(row["taste"], int)
        ):
            raise Blocked(f"models[{index}].taste must be an integer")
        key = (name, effort)
        if key in indexed:
            raise Blocked(f"duplicate model row: {name}@{effort}")
        indexed[key] = row
    return indexed


def parse_routes(document: dict, rows: dict[tuple[str, str], dict]) -> dict[str, list[str]]:
    routing = document.get("routing")
    if not isinstance(routing, dict):
        raise Blocked("rubric.routing must be a mapping")
    fallbacks = document.get("fallbacks", {})
    if not isinstance(fallbacks, dict):
        raise Blocked("rubric.fallbacks must be a mapping")

    route_names = [name for name in routing if name not in {"taste_min", "fallback"}]
    if not route_names:
        raise Blocked("rubric.routing must contain a semantic route")

    for route, values in fallbacks.items():
        if not isinstance(route, str) or route not in route_names:
            raise Blocked(f"fallbacks.{route} has no primary route")
        if not isinstance(values, list):
            raise Blocked(f"fallbacks.{route} must be a list")

    chains: dict[str, list[str]] = {}
    for route in route_names:
        primary = require_string(routing[route], f"routing.{route}")
        extras = fallbacks.get(route, [])
        if not isinstance(extras, list):
            raise Blocked(f"fallbacks.{route} must be a list")
        refs = [primary, *extras]
        providers: set[str] = set()
        for ref in refs:
            try:
                name, effort = split_ref(require_string(ref, f"fallbacks.{route}"))
            except ValueError as error:
                raise Blocked(str(error)) from error
            row = rows.get((name, effort))
            if row is None:
                raise Blocked(f"route {route} references an unknown row: {ref}")
            provider = row["provider"]
            if provider in providers:
                raise Blocked(f"route {route} has duplicate provider: {provider}")
            providers.add(provider)
        chains[route] = refs

    if "taste" in chains:
        taste_min = routing.get("taste_min")
        if isinstance(taste_min, bool) or not isinstance(taste_min, int):
            raise Blocked("routing.taste_min must be an integer when routing.taste exists")
        for ref in chains["taste"]:
            row = rows[split_ref(ref)]
            taste = row.get("taste")
            if isinstance(taste, bool) or not isinstance(taste, int) or taste < taste_min:
                raise Blocked(f"taste candidate {ref} is below routing.taste_min")

    return chains


def parse_csv(value: str, field: str) -> list[str]:
    if not value:
        return []
    if value.lstrip().startswith("["):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as error:
            raise argparse.ArgumentError(None, f"{field} must be a list or comma-separated") from error
        if not isinstance(parsed, list) or not all(isinstance(item, str) and item for item in parsed):
            raise argparse.ArgumentError(None, f"{field} must contain non-empty strings")
        return parsed
    return [item.strip() for item in value.split(",") if item.strip()]


def parse_attempted(value: str) -> list[str]:
    attempted = parse_csv(value, "--attempted")
    for ref in attempted:
        try:
            split_ref(ref)
        except ValueError as error:
            raise argparse.ArgumentError(None, str(error)) from error
    return attempted


def validate_reachable_routes(chains: dict[str, list[str]], rows: dict[tuple[str, str], dict],
                              native_provider: str, executors: set[str]) -> None:
    for route, refs in chains.items():
        for ref in refs:
            if resolve_executor(rows[split_ref(ref)], native_provider, executors)[0] is None:
                raise Blocked(f"route {route} candidate {ref} has no reachable executor")


def validate_independent_routes(
    chains: dict[str, list[str]],
    rows: dict[tuple[str, str], dict],
    authoring_providers: set[str],
) -> None:
    if "independent" not in chains:
        return
    if "orchestrator" not in chains:
        raise Blocked(
            "routing.independent requires routing.orchestrator provider boundary"
        )
    orchestrator_provider = rows[split_ref(chains["orchestrator"][0])]["provider"]
    for ref in chains["independent"]:
        provider = rows[split_ref(ref)]["provider"]
        if provider == orchestrator_provider:
            raise Blocked(f"independent candidate {ref} uses the orchestrator provider")
        if provider in authoring_providers:
            raise Blocked(f"independent candidate {ref} uses an authoring provider")


def candidate_for(ref: str, row: dict, executor: str) -> Candidate:
    model, effort = split_ref(ref)
    taste = row.get("taste")
    return Candidate(ref, model, effort, row["provider"], executor, taste)


def configured_executor(row: dict, native_provider: str) -> str | None:
    if row["provider"] == native_provider:
        return "native"
    via = row.get("via")
    return via if isinstance(via, str) else None


def validate_attempted(
    attempted: list[str],
    chain: list[str],
    rows: dict[tuple[str, str], dict],
    circuits: dict,
    native_provider: str,
) -> None:
    authorized = set(chain)
    for ref in attempted:
        if ref not in authorized:
            raise Blocked(f"attempted candidate {ref} is not authorized for this route")
        row = rows[split_ref(ref)]
        executor = configured_executor(row, native_provider)
        circuit = (
            circuits.get(circuit_key(row["provider"], executor))
            if executor is not None
            else None
        )
        if circuit is None:
            raise Blocked(
                f"attempted candidate {ref} has no recorded availability failure"
            )


def select(args: argparse.Namespace) -> int:
    attempted = parse_attempted(args.attempted)
    attempted_set = set(attempted)
    authoring_providers = set(parse_csv(args.authoring_providers, "--authoring-providers"))
    executors = set(parse_csv(args.executors, "--executors"))
    now = parse_timestamp(args.now, "--now")
    document = load_rubric(args.rubric)
    rows = model_rows(document)
    chains = parse_routes(document, rows)
    validate_independent_routes(chains, rows, authoring_providers)
    if args.route not in chains:
        raise Blocked(f"routing.{args.route} is not configured")

    skipped: list[str] = []
    fallback_reason: str | None = None

    path = state_path(args.state)
    with state_for_selection(path) as health:
        circuits = health["circuits"]
        validate_attempted(
            attempted,
            chains[args.route],
            rows,
            circuits,
            args.native_provider,
        )
        for index, ref in enumerate(chains[args.route]):
            row = rows[split_ref(ref)]
            executor, reason = resolve_executor(row, args.native_provider, executors)
            endpoint_executor = configured_executor(row, args.native_provider)
            circuit = (
                circuits.get(circuit_key(row["provider"], endpoint_executor))
                if endpoint_executor
                else None
            )
            if ref in attempted_set:
                skipped.append(ref)
                if circuit:
                    fallback_reason = fallback_reason or circuit["reason"]
                continue
            if executor is None:
                skipped.append(ref)
                fallback_reason = fallback_reason or reason
                continue

            probe = False
            if circuit:
                unavailable_until = decode_timestamp(circuit["unavailable_until"])
                claimed_at = circuit["probe_claimed_at"]
                lease_is_fresh = claimed_at is not None and (
                    now - decode_timestamp(claimed_at)
                ).total_seconds() < PROBE_LEASE_SECONDS
                if now < unavailable_until or lease_is_fresh:
                    skipped.append(ref)
                    fallback_reason = fallback_reason or circuit["reason"]
                    continue
                circuit["probe_claimed_at"] = format_timestamp(now)
                write_state(path, health)
                probe = True

            candidate = candidate_for(ref, row, executor)
            result: dict[str, object] = {
                "status": "resolved" if index == 0 else "fallback",
                "resolution": "primary" if index == 0 else "fallback",
                "candidate": candidate.ref,
                "model": candidate.model,
                "effort": candidate.effort,
                "provider": candidate.provider,
                "executor": candidate.executor,
            }
            if index > 0 and fallback_reason:
                result["reason"] = fallback_reason
            if skipped:
                result["skipped"] = skipped
            if probe:
                result["probe"] = True
            compact_json(result)
            return 0

    blocked(f"no eligible {args.route} candidate remains", attempted, skipped)
    return EXIT_BLOCKED


def record_failure(args: argparse.Namespace) -> int:
    provider = require_argument_string(args.provider, "--provider")
    executor = require_argument_string(args.executor, "--executor")
    now = parse_timestamp(args.now, "--now")
    retry_at = parse_timestamp(args.retry_at, "--retry-at") if args.retry_at else None
    if retry_at is not None and args.reason != "quota":
        raise argparse.ArgumentError(None, "--retry-at is only valid for quota")

    path = state_path(args.state)
    key = circuit_key(provider, executor)
    with locked_state(path) as health:
        previous = health["circuits"].get(key)
        failure_count = (
            previous["failure_count"] + 1
            if previous and previous["reason"] == args.reason
            else 1
        )
        unavailable_until = now + timedelta(
            seconds=cooldown_seconds(args.reason, failure_count)
        )
        if args.reason == "quota" and retry_at is not None and retry_at > now:
            unavailable_until = retry_at
        circuit = {
            "state": "open",
            "reason": args.reason,
            "failure_count": failure_count,
            "last_failure_at": format_timestamp(now),
            "unavailable_until": format_timestamp(unavailable_until),
            "probe_claimed_at": None,
        }
        health["circuits"][key] = circuit
        write_state(path, health)

    compact_json(
        {
            "status": "recorded",
            "provider": provider,
            "executor": executor,
            "reason": args.reason,
            "failure_count": failure_count,
            "unavailable_until": circuit["unavailable_until"],
        }
    )
    return 0


def record_success(args: argparse.Namespace) -> int:
    provider = require_argument_string(args.provider, "--provider")
    executor = require_argument_string(args.executor, "--executor")
    parse_timestamp(args.now, "--now")
    path = state_path(args.state)
    key = circuit_key(provider, executor)
    with locked_state(path) as health:
        if key in health["circuits"]:
            del health["circuits"][key]
            write_state(path, health)
    compact_json({"status": "cleared", "provider": provider, "executor": executor})
    return 0


def validate(args: argparse.Namespace) -> int:
    executors = set(parse_csv(args.executors, "--executors"))
    authoring_providers = set(
        parse_csv(args.authoring_providers, "--authoring-providers")
    )
    document = load_rubric(args.rubric)
    rows = model_rows(document)
    chains = parse_routes(document, rows)
    validate_independent_routes(chains, rows, authoring_providers)
    validate_reachable_routes(chains, rows, args.native_provider, executors)
    compact_json({"status": "valid"})
    return 0


def build_parser() -> Arguments:
    parser = Arguments(prog="resolve-route.py", add_help=True)
    subcommands = parser.add_subparsers(dest="operation", required=True)
    for operation in ("validate", "select"):
        command = subcommands.add_parser(operation)
        command.add_argument("--rubric", required=True)
        command.add_argument("--native-provider", required=True)
        command.add_argument("--executors", required=True)
        command.add_argument("--authoring-providers", default="")
        if operation == "select":
            command.add_argument("--state")
            command.add_argument("--route", required=True)
            command.add_argument("--attempted", default="")
            command.add_argument("--now")
    failure = subcommands.add_parser("record-failure")
    failure.add_argument("--state")
    failure.add_argument("--provider", required=True)
    failure.add_argument("--executor", required=True)
    failure.add_argument(
        "--reason", required=True, choices=sorted(TIMED_AVAILABILITY_REASONS)
    )
    failure.add_argument("--retry-at")
    failure.add_argument("--now")

    success = subcommands.add_parser("record-success")
    success.add_argument("--state")
    success.add_argument("--provider", required=True)
    success.add_argument("--executor", required=True)
    success.add_argument("--now")
    return parser


def main(argv: list[str]) -> int:
    try:
        args = build_parser().parse_args(argv)
        if args.operation == "validate":
            return validate(args)
        if args.operation == "select":
            return select(args)
        if args.operation == "record-failure":
            return record_failure(args)
        return record_success(args)
    except argparse.ArgumentError as error:
        compact_json({"status": "error", "blockers": [str(error)]})
        return 2
    except Blocked as error:
        blocked(str(error))
        return EXIT_BLOCKED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
