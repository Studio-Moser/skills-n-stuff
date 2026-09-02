#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  REFERENCES="${HARNESS_REFERENCES_ROOT:-$REPO/plugins/harness/references}"
}

@test "references define the provider-neutral Harness contract" {
  run python3 - "$REFERENCES" <<'PY'
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

def schema_after(heading):
    section = contract.split(heading, 1)[1]
    return section.split("```yaml", 1)[1].split("```", 1)[0]

def parse_schema(schema):
    parsed = []
    parents = []
    for line in schema.strip().splitlines():
        indent = len(line) - len(line.lstrip())
        assert indent % 2 == 0, f"schema indentation must use two spaces: {line!r}"
        depth = indent // 2
        content = line.strip()
        if content.startswith("- "):
            assert depth == len(parents), f"orphaned list item: {line!r}"
            parsed.append((".".join(parents) + "[]", content[2:]))
            continue
        key, separator, value = content.partition(":")
        assert separator and key, f"malformed schema line: {line!r}"
        parents = parents[:depth]
        path = ".".join([*parents, key])
        parsed.append((path, value.strip() or None))
        if not value.strip():
            parents.append(key)
    return parsed

def normalized(text):
    return " ".join(text.split())

def require_clause(document, clause):
    assert clause in normalized(document), f"missing contract clause: {clause}"

request_schema = schema_after("## HarnessRequest")
result_schema = schema_after("## HarnessResult")
assert parse_schema(request_schema) == [
    ("operation", "execute | review | computer-use"),
    ("route", "bulk | quick | default | taste | batch | review | independent"),
    ("outcome", "bounded observable result"),
    ("context", None),
    ("context.project", "canonical project identifier when known"),
    ("context.mode", "fresh | fork | hybrid"),
    ("context.state", "concise current state"),
    ("context.files", "relevant repository-relative paths"),
    ("context.memory", None),
    ("context.memory.enabled", "true | false"),
    ("context.memory.recall", "optional domain-owned lookup intents"),
    ("context.memory.capture", "optional durable facts to record only after acceptance"),
    ("authority", None),
    ("authority.working_directory", "repository root or worktree"),
    ("authority.allowed_paths", "explicit write/read scope when narrower than the repository"),
    ("authority.tools", "required capabilities"),
    ("authority.approvals", "actions that still require the user"),
    ("constraints", None),
    ("constraints[]", "explicit task constraints"),
    ("verification", None),
    ("verification.seam", "highest stable observable check"),
    ("verification.expected", "expected result"),
    ("verification.fixed_target", "commit or immutable snapshot when reviewing"),
]
assert parse_schema(result_schema) == [
    ("status", "accepted | failed | blocked | abandoned"),
    ("route", None),
    ("route.requested", "semantic route"),
    ("route.actual_model", "resolved model"),
    ("route.effort", "resolved effort"),
    ("route.provider", "resolved provider"),
    ("route.executor", "native agent or external CLI"),
    ("route.resolution", "primary | fallback"),
    ("route.attempted", "ordered model-effort dispatches"),
    ("route.fallback_reason", "typed availability reason or empty"),
    ("artifacts", None),
    ("artifacts.files", "changed or created paths"),
    ("artifacts.report", "optional report path"),
    ("evidence", None),
    ("evidence.fixed_target", "commit or immutable snapshot"),
    ("evidence.checks", "commands or procedures with actual results"),
    ("evidence.outcome", "proven | unproven"),
    ("telemetry", None),
    ("telemetry.attempts", "count"),
    ("telemetry.elapsed", "duration when available"),
    ("telemetry.verification_failures", "count"),
    ("telemetry.token_or_quota_usage", "value when available"),
    ("shelby", None),
    ("shelby.project_id", "optional"),
    ("shelby.run_id", "optional"),
    ("shelby.checkpoint_ids", "optional"),
    ("blockers", "explicit unresolved items"),
]

require_clause(
    verification,
    "`accepted` requires both the delivered outcome and `evidence.outcome: proven`.",
)
require_clause(
    context,
    "An independent review uses `fresh` so the review is not primed by the implementer's reasoning.",
)
require_clause(
    routing,
    "`independent`: a context-independent adversarial review. "
    "It requires explicit cost approval from the user before dispatch.",
)
require_clause(
    routing,
    "`taste` resolves through the exact `routing.taste` value.",
)
require_clause(
    routing,
    "`routing.taste_min` is an input to rubric setup, not a runtime route value.",
)
require_clause(
    routing,
    "`orchestrator` selects the preferred model for the top-level session; it is not a delegated HarnessRequest route.",
)
require_clause(
    routing,
    "A running agent never replaces itself to satisfy `routing.orchestrator`.",
)
require_clause(
    routing,
    "Candidate order is exactly `routing.<route>` followed by `fallbacks.<route>` in listed order.",
)
require_clause(
    routing,
    "`fallbacks.<route>` is the only standing authorization for automatic fallback; `routing.fallback` grants none.",
)
require_clause(
    contract,
    "The top-level orchestrator owns the user conversation, scope, approvals, delegation graph, and final acceptance decision.",
)
for clause in (
    "For a typed pre-dispatch block, copy the returned `reason` to `route.fallback_reason`.",
    "When no dispatch occurred, set unresolved route fields to `null`, `route.attempted` to `[]`, and `telemetry.attempts` to `0`.",
    "Encode a checked absolute path as `path:<absolute-path>` in `evidence.fixed_target`.",
    "Begin each `evidence.checks` entry with the exact decisive result",
    "Begin each blocker with `<reason>:` and follow it with the concrete recovery condition or setup action.",
):
    require_clause(contract, clause)
require_clause(shelby, "The missing Shelby does not block execution.")
require_clause(
    routing,
    "Automatic provider switching is limited to `quota`, `authentication`, `rate_limit`, `provider_unavailable`, and preflight `missing_executor`.",
)
require_clause(
    routing,
    "When a candidate's provider matches the native provider, use native execution even if its model row declares `via`.",
)
require_clause(
    routing,
    "Every attempt preserves the original HarnessRequest's operation, tools, approvals, working directory, allowed paths, fixed target, sandbox, and verification seam.",
)
require_clause(
    routing,
    "Timed availability failures open a local circuit for 24 hours for `quota` and `authentication`, and for 15 minutes, 1 hour, 6 hours, then 24 hours for repeated `rate_limit` or `provider_unavailable` failures.",
)
require_clause(
    routing,
    "After a cooldown expires, exactly one selector may claim the half-open probe for 15 minutes.",
)
require_clause(
    routing,
    "External Codex availability is classified only from `turn/completed.turn.error.codexErrorInfo`.",
)
require_clause(
    routing,
    "A missing or incompatible Codex App Server is preflight `missing_executor` and never creates a timed circuit or dispatch attempt.",
)
require_clause(
    routing,
    "Every `independent` candidate differs from the persistent `routing.orchestrator` provider and every request-supplied authoring provider.",
)
require_clause(handoff, "Secrets and unbounded logs are forbidden;")
PY
  if [ "$status" -ne 0 ]; then
    printf '%s\n' "$output" >&2
  fi
  [ "$status" -eq 0 ]
}
