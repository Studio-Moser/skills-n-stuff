#!/usr/bin/env python3
"""Resolve one Harness semantic route from a validated model rubric."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass


AVAILABILITY_REASONS = {
    "quota",
    "authentication",
    "rate_limit",
    "provider_unavailable",
    "missing_executor",
}
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
        require_string(row.get("provider"), f"models[{index}].provider")
        if "via" in row and row["via"] is not None:
            require_string(row["via"], f"models[{index}].via")
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
        if not any(resolve_executor(rows[split_ref(ref)], native_provider, executors)[0] for ref in refs):
            raise Blocked(f"route {route} has no reachable executor")


def candidate_for(ref: str, row: dict, executor: str) -> Candidate:
    model, effort = split_ref(ref)
    taste = row.get("taste")
    return Candidate(ref, model, effort, row["provider"], executor, taste)


def select(args: argparse.Namespace) -> int:
    attempted = parse_attempted(args.attempted)
    attempted_set = set(attempted)
    authoring_providers = set(parse_csv(args.authoring_providers, "--authoring-providers"))
    executors = set(parse_csv(args.executors, "--executors"))
    document = load_rubric(args.rubric)
    rows = model_rows(document)
    chains = parse_routes(document, rows)
    if args.route not in chains:
        raise Blocked(f"routing.{args.route} is not configured")

    skipped: list[str] = []
    fallback_reason: str | None = None

    for index, ref in enumerate(chains[args.route]):
        row = rows[split_ref(ref)]
        if ref in attempted_set:
            skipped.append(ref)
            continue
        if args.route == "independent" and row["provider"] in authoring_providers:
            blocked(f"independent candidate {ref} uses an authoring provider", attempted, skipped)
            return EXIT_BLOCKED
        executor, reason = resolve_executor(row, args.native_provider, executors)
        if executor is None:
            skipped.append(ref)
            fallback_reason = fallback_reason or reason
            continue

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
        compact_json(result)
        return 0

    blocked(f"no eligible {args.route} candidate remains", attempted, skipped)
    return EXIT_BLOCKED


def validate(args: argparse.Namespace) -> int:
    executors = set(parse_csv(args.executors, "--executors"))
    document = load_rubric(args.rubric)
    rows = model_rows(document)
    chains = parse_routes(document, rows)
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
        if operation == "select":
            command.add_argument("--state")
            command.add_argument("--route", required=True)
            command.add_argument("--authoring-providers", default="")
            command.add_argument("--attempted", default="")
            command.add_argument("--now")
    return parser


def main(argv: list[str]) -> int:
    try:
        args = build_parser().parse_args(argv)
        if args.operation == "validate":
            return validate(args)
        return select(args)
    except argparse.ArgumentError as error:
        compact_json({"status": "error", "blockers": [str(error)]})
        return 2
    except Blocked as error:
        blocked(str(error))
        return EXIT_BLOCKED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
