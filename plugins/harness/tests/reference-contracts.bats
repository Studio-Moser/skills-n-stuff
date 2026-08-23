#!/usr/bin/env bats

setup() { REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"; }

@test "references define the provider-neutral Harness contract" {
  run python3 - "$REPO/plugins/harness/references" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
required = {
    "harness-contract.md",
    "routing.md",
    "handoff.md",
    "verification.md",
    "context.md",
    "shelby-integration.md",
}
missing = sorted(name for name in required if not (root / name).is_file())
assert not missing, f"missing references: {', '.join(missing)}"

docs = {name: (root / name).read_text() for name in required}
contract = docs["harness-contract.md"]
routing = docs["routing.md"]
handoff = docs["handoff.md"]
verification = docs["verification.md"]
context = docs["context.md"]
shelby = docs["shelby-integration.md"]

request_fields = ["operation", "route", "outcome", "context", "authority", "constraints", "verification"]
result_fields = ["status", "route", "artifacts", "evidence", "telemetry", "shelby", "blockers"]
routes = ["bulk", "quick", "default", "taste", "batch", "review", "independent"]
statuses = ["accepted", "failed", "blocked", "abandoned"]
context_modes = ["fresh", "fork", "hybrid"]

def schema_after(heading):
    section = contract.split(heading, 1)[1]
    return section.split("```yaml", 1)[1].split("```", 1)[0]

def top_level_fields(schema):
    return [line.split(":", 1)[0] for line in schema.splitlines() if line and not line[0].isspace()]

request_schema = schema_after("## HarnessRequest")
result_schema = schema_after("## HarnessResult")
assert top_level_fields(request_schema) == request_fields
assert top_level_fields(result_schema) == result_fields
assert "operation: execute | review | computer-use" in request_schema
assert f"route: {' | '.join(routes)}" in request_schema
assert f"status: {' | '.join(statuses)}" in result_schema
assert f"mode: {' | '.join(context_modes)}" in request_schema
for value in context_modes:
    assert value in contract and value in context, f"context mode missing: {value}"

assert "accepted" in verification and "evidence.outcome: proven" in verification
assert "independent" in context and "fresh" in context
assert "independent" in routing and "explicit cost approval" in " ".join(routing.split())
assert "missing Shelby is not blocking" in shelby
assert all(value in routing for value in ["resolved", "fallback", "blocked"])
assert "fallback" in routing and "authorized" in routing
assert "required capability" in routing and "otherwise `blocked`" in routing
assert "secrets" in handoff.lower() and "unbounded logs" in handoff.lower()
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
